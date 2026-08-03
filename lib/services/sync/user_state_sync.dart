import 'dart:async';

import 'package:clock/clock.dart';

import '../../models/app_state.dart';
import 'sync_decision.dart';
import 'user_state_store.dart';

/// Keeps `users/{uid}` in step with the Shohoj web app in both directions.
///
/// Writes are debounced and serialised; incoming snapshots are filtered through
/// [decideRemoteSnapshot] before anything is applied. The guards matter as much
/// as the listener — see the ordering notes on that function.
///
/// Depends on the narrow [UserStateStore] rather than `FirestoreService` so the
/// coordination — debounce, guard wiring, write ordering — is testable without
/// Firebase. Time comes from `package:clock` for the same reason: `fakeAsync`
/// can drive the 5 s own-write window without the tests waiting 5 s.
class UserStateSync {
  UserStateSync({required UserStateStore store}) : _fs = store;

  final UserStateStore _fs;

  final _remoteChanges = StreamController<AppState>.broadcast();

  /// Genuine changes from another device. Does not emit for this client's own
  /// writes, for identical content, or for the initial snapshot.
  Stream<AppState> get remoteChanges => _remoteChanges.stream;

  StreamSubscription<String?>? _subscription;
  bool _isFirstSnapshot = true;

  /// When this client last wrote. Snapshots arriving inside [kLocalWriteGrace]
  /// of it are that write echoing back.
  ///
  /// Defence in depth rather than load-bearing here. [_write] sets [_localRaw]
  /// to the payload being written, so an echo already compares equal by
  /// fingerprint and is dropped as [RemoteAction.ignoreIdentical] even with
  /// this guard removed — verified by mutation testing, where deleting the
  /// guard failed no coordinator test.
  ///
  /// Kept because it short-circuits before a parse-and-re-serialise, because it
  /// keeps this implementation comparable to the web's, and because it is
  /// genuinely load-bearing there: the web's baseline comes from localStorage,
  /// which can diverge from what was actually written.
  DateTime? _localWriteAt;

  /// The payload this client believes is current, used as the comparison side
  /// of the fingerprint check. The web reads localStorage for this; the app
  /// tracks it in memory.
  String? _localRaw;

  Timer? _saveTimer;
  AppState? _queuedState;
  Future<bool> _activeSave = Future.value(false);
  final List<Completer<bool>> _queuedSaveWaiters = [];

  bool get _hasPendingSave => _saveTimer != null || _queuedState != null;

  /// Begins listening. Safe to call repeatedly; a second call is a no-op.
  void start() {
    if (_subscription != null) return;
    _isFirstSnapshot = true;
    _subscription = _fs.watchRawState().listen(
      _onSnapshot,
      onError: (Object e) {
        // A dropped listener must not take the app down. Firestore retries on
        // its own, and local edits still persist through save().
        _remoteChanges.addError(e);
      },
    );
  }

  /// Stops listening and drops any queued write. Call on sign-out.
  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
    _saveTimer?.cancel();
    _saveTimer = null;
    _queuedState = null;
    _localRaw = null;
    _localWriteAt = null;
    _isFirstSnapshot = true;
    for (final waiter in _queuedSaveWaiters) {
      if (!waiter.isCompleted) waiter.complete(false);
    }
    _queuedSaveWaiters.clear();
  }

  Future<void> dispose() async {
    await stop();
    await _remoteChanges.close();
  }

  /// Seeds the comparison baseline from an initial read, so the first genuine
  /// remote change is measured against what the app actually loaded.
  void seed(AppState state) => _localRaw = state.encode();

  void _onSnapshot(String? remoteRaw) {
    final action = decideRemoteSnapshot(
      isFirstSnapshot: _isFirstSnapshot,
      sinceLocalWrite: _localWriteAt == null
          ? const Duration(days: 1)
          : clock.now().difference(_localWriteAt!),
      hasPendingSave: _hasPendingSave,
      localRaw: _localRaw,
      remoteRaw: remoteRaw,
    );

    if (_isFirstSnapshot) _isFirstSnapshot = false;
    if (action != RemoteAction.apply) return;

    final incoming = AppState.decode(remoteRaw);
    if (incoming == null) return;

    _localRaw = remoteRaw;
    _remoteChanges.add(incoming);
  }

  /// Queues a write.
  ///
  /// Edits are batched for [kCloudSaveDebounce] so a burst of keystrokes is one
  /// write. Pass `immediate: true` for writes that must not be lost to a
  /// backgrounded app — sign-out, or an explicit upload.
  ///
  /// Resolves true when the write lands.
  Future<bool> save(AppState state, {bool immediate = false}) {
    if (immediate) {
      _saveTimer?.cancel();
      _saveTimer = null;
      _queuedState = null;
      final waiters = List<Completer<bool>>.from(_queuedSaveWaiters);
      _queuedSaveWaiters.clear();
      final result = _enqueueWrite(state);
      result.then((ok) {
        for (final w in waiters) {
          if (!w.isCompleted) w.complete(ok);
        }
      });
      return result;
    }

    _queuedState = state;
    final waiter = Completer<bool>();
    _queuedSaveWaiters.add(waiter);

    _saveTimer?.cancel();
    _saveTimer = Timer(kCloudSaveDebounce, () {
      final pending = _queuedState;
      final waiters = List<Completer<bool>>.from(_queuedSaveWaiters);
      _queuedSaveWaiters.clear();
      _queuedState = null;
      _saveTimer = null;
      if (pending == null) {
        for (final w in waiters) {
          if (!w.isCompleted) w.complete(false);
        }
        return;
      }
      _enqueueWrite(pending).then((ok) {
        for (final w in waiters) {
          if (!w.isCompleted) w.complete(ok);
        }
      });
    });

    return waiter.future;
  }

  /// Chains onto the previous write so a queued save cannot overtake an
  /// in-flight one and land an older payload last.
  Future<bool> _enqueueWrite(AppState state) {
    _activeSave = _activeSave.then((_) => _write(state));
    return _activeSave;
  }

  Future<bool> _write(AppState state) async {
    // Recorded before the write so the echoing snapshot is inside the grace
    // window however fast Firestore turns it around.
    _localWriteAt = clock.now();
    _localRaw = state.encode();
    try {
      await _fs.saveState(state);
      return true;
    } catch (_) {
      // Reset the guard so a later genuine remote change is not mistaken for
      // this failed write echoing back.
      _localWriteAt = null;
      return false;
    }
  }
}
