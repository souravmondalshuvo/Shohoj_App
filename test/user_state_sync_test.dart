import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shohoj/models/app_state.dart';
import 'package:shohoj/models/semester.dart';
import 'package:shohoj/services/sync/sync_decision.dart';
import 'package:shohoj/services/sync/user_state_sync.dart';
import 'package:shohoj/services/sync/user_state_store.dart';

/// An in-memory [UserStateStore] that records writes and lets a test push
/// snapshots as if they came from another device.
class FakeStore implements UserStateStore {
  final _controller = StreamController<String?>.broadcast();

  /// Every payload written, in the order it reached the store.
  final List<String> writes = [];

  /// Completers for in-flight writes, so a test can hold one open and check
  /// that a later write does not overtake it.
  final List<Completer<void>> pending = [];

  /// When true, writes block until the test completes them by hand.
  bool holdWrites = false;

  /// When true, writes throw — standing in for an offline device or a rules
  /// rejection.
  bool failWrites = false;

  int startedWrites = 0;

  @override
  Stream<String?> watchRawState() => _controller.stream;

  @override
  Future<void> saveState(AppState state) async {
    startedWrites++;
    if (holdWrites) {
      final gate = Completer<void>();
      pending.add(gate);
      await gate.future;
    }
    if (failWrites) throw StateError('write failed');
    writes.add(state.encode());
  }

  /// Simulates a snapshot arriving from Firestore.
  void emit(String? raw) => _controller.add(raw);

  Future<void> dispose() => _controller.close();
}

AppState stateNamed(String name) =>
    AppState(semesters: [Semester(id: 0, name: name, courses: [])]);

void main() {
  group('write debounce', () {
    test('collapses a burst into a single write', () {
      fakeAsync((async) {
        final store = FakeStore();
        final sync = UserStateSync(store: store);

        sync.save(stateNamed('a'));
        sync.save(stateNamed('b'));
        sync.save(stateNamed('c'));

        async.elapse(kCloudSaveDebounce - const Duration(milliseconds: 1));
        expect(store.writes, isEmpty, reason: 'still inside the debounce window');

        async.elapse(const Duration(milliseconds: 2));
        async.flushMicrotasks();

        expect(store.writes, hasLength(1));
        expect(store.writes.single, contains('"name":"c"'),
            reason: 'the newest state should win, not the first');
      });
    });

    test('a later burst writes again', () {
      fakeAsync((async) {
        final store = FakeStore();
        final sync = UserStateSync(store: store);

        sync.save(stateNamed('first'));
        async.elapse(kCloudSaveDebounce * 2);
        async.flushMicrotasks();

        sync.save(stateNamed('second'));
        async.elapse(kCloudSaveDebounce * 2);
        async.flushMicrotasks();

        expect(store.writes, hasLength(2));
        expect(store.writes.last, contains('"name":"second"'));
      });
    });

    test('resolves the futures of every collapsed save', () {
      fakeAsync((async) {
        final store = FakeStore();
        final sync = UserStateSync(store: store);

        final results = <bool>[];
        sync.save(stateNamed('a')).then(results.add);
        sync.save(stateNamed('b')).then(results.add);

        async.elapse(kCloudSaveDebounce * 2);
        async.flushMicrotasks();

        expect(results, [true, true],
            reason: 'a caller awaiting a collapsed save must not hang');
      });
    });
  });

  group('immediate writes', () {
    test('bypass the debounce', () {
      fakeAsync((async) {
        final store = FakeStore();
        final sync = UserStateSync(store: store);

        sync.save(stateNamed('now'), immediate: true);
        async.flushMicrotasks();

        expect(store.writes, hasLength(1));
        expect(store.writes.single, contains('"name":"now"'));
      });
    });

    test('cancel a queued debounced save and complete its waiter', () {
      fakeAsync((async) {
        final store = FakeStore();
        final sync = UserStateSync(store: store);

        var queuedResolved = false;
        sync.save(stateNamed('queued')).then((_) => queuedResolved = true);
        sync.save(stateNamed('urgent'), immediate: true);

        async.elapse(kCloudSaveDebounce * 2);
        async.flushMicrotasks();

        expect(store.writes, hasLength(1),
            reason: 'the queued save was superseded, not written separately');
        expect(store.writes.single, contains('"name":"urgent"'));
        expect(queuedResolved, isTrue, reason: 'its caller must not hang');
      });
    });
  });

  group('write ordering', () {
    test('a queued write cannot overtake one in flight', () {
      fakeAsync((async) {
        final store = FakeStore()..holdWrites = true;
        final sync = UserStateSync(store: store);

        sync.save(stateNamed('first'), immediate: true);
        async.flushMicrotasks();
        expect(store.startedWrites, 1);

        // Second write requested while the first is still in flight.
        sync.save(stateNamed('second'), immediate: true);
        async.flushMicrotasks();

        expect(store.startedWrites, 1,
            reason: 'the second write must wait for the first to finish');

        store.pending.first.complete();
        async.flushMicrotasks();
        expect(store.startedWrites, 2);

        store.pending[1].complete();
        async.flushMicrotasks();

        expect(store.writes.map((w) => w.contains('"name":"first"')).toList(),
            [true, false],
            reason: 'writes must land in request order, oldest first');
      });
    });
  });

  group('remote changes', () {
    test('ignores the first snapshot', () {
      fakeAsync((async) {
        final store = FakeStore();
        final sync = UserStateSync(store: store);
        final applied = <AppState>[];
        sync.remoteChanges.listen(applied.add);

        sync.start();
        store.emit(stateNamed('from-cloud').encode());
        async.flushMicrotasks();

        expect(applied, isEmpty,
            reason: 'the first snapshot is the state already loaded');
      });
    });

    test('applies a genuine change from another device', () {
      fakeAsync((async) {
        final store = FakeStore();
        final sync = UserStateSync(store: store)..seed(stateNamed('local'));
        final applied = <AppState>[];
        sync.remoteChanges.listen(applied.add);

        sync.start();
        store.emit(stateNamed('local').encode()); // first snapshot, ignored
        store.emit(stateNamed('remote').encode());
        async.flushMicrotasks();

        expect(applied, hasLength(1));
        expect(applied.single.semesters.single.name, 'remote');
      });
    });

    test('ignores a snapshot identical to local state', () {
      fakeAsync((async) {
        final store = FakeStore();
        final sync = UserStateSync(store: store)..seed(stateNamed('same'));
        final applied = <AppState>[];
        sync.remoteChanges.listen(applied.add);

        sync.start();
        store.emit(null); // first snapshot
        store.emit(stateNamed('same').encode());
        async.flushMicrotasks();

        expect(applied, isEmpty);
      });
    });

    test("suppresses this client's own write echoing back", () {
      fakeAsync((async) {
        final store = FakeStore();
        final sync = UserStateSync(store: store)..seed(stateNamed('local'));
        final applied = <AppState>[];
        sync.remoteChanges.listen(applied.add);

        sync.start();
        store.emit(null); // first snapshot

        sync.save(stateNamed('mine'), immediate: true);
        async.flushMicrotasks();

        // Firestore delivers our own write straight back.
        store.emit(stateNamed('mine').encode());
        async.flushMicrotasks();

        expect(applied, isEmpty, reason: 'inside the own-write grace window');
      });
    });

    test('suppresses an echo that arrives while the write is still in flight', () {
      // Firestore can deliver a local write back before saveState's future
      // resolves. This pins that the echo is suppressed in that window.
      //
      // It does not isolate *which* guard does the suppressing: mutation
      // testing showed the own-write timestamp is shadowed by the fingerprint
      // check, because _write sets _localRaw to the payload it is writing. Both
      // orderings of _localWriteAt therefore pass. The behaviour is worth
      // pinning regardless — see the note on _localWriteAt.
      fakeAsync((async) {
        final store = FakeStore()..holdWrites = true;
        final sync = UserStateSync(store: store)..seed(stateNamed('local'));
        final applied = <AppState>[];
        sync.remoteChanges.listen(applied.add);

        sync.start();
        store.emit(null); // first snapshot
        async.flushMicrotasks();

        sync.save(stateNamed('mine'), immediate: true);
        async.flushMicrotasks();
        expect(store.startedWrites, 1, reason: 'write is in flight');

        store.emit(stateNamed('mine').encode());
        async.flushMicrotasks();

        expect(applied, isEmpty,
            reason: 'the echo arrived before the write resolved, so the guard '
                'must already be armed');

        store.pending.first.complete();
        async.flushMicrotasks();
      });
    });

    test('applies a change arriving after the grace window', () {
      fakeAsync((async) {
        final store = FakeStore();
        final sync = UserStateSync(store: store)..seed(stateNamed('local'));
        final applied = <AppState>[];
        sync.remoteChanges.listen(applied.add);

        sync.start();
        store.emit(null);

        sync.save(stateNamed('mine'), immediate: true);
        async.flushMicrotasks();

        async.elapse(kLocalWriteGrace + const Duration(seconds: 1));
        store.emit(stateNamed('theirs').encode());
        async.flushMicrotasks();

        expect(applied, hasLength(1));
        expect(applied.single.semesters.single.name, 'theirs');
      });
    });

    test('ignores a snapshot while a local save is queued', () {
      fakeAsync((async) {
        final store = FakeStore();
        final sync = UserStateSync(store: store)..seed(stateNamed('local'));
        final applied = <AppState>[];
        sync.remoteChanges.listen(applied.add);

        sync.start();
        store.emit(null);

        // A debounced edit is pending, so local is ahead of the cloud.
        sync.save(stateNamed('in-progress'));
        store.emit(stateNamed('stale-cloud').encode());
        async.flushMicrotasks();

        expect(applied, isEmpty,
            reason: 'applying here would clobber the in-progress edit');
      });
    });

    test('ignores an unparseable payload', () {
      fakeAsync((async) {
        final store = FakeStore();
        final sync = UserStateSync(store: store)..seed(stateNamed('local'));
        final applied = <AppState>[];
        sync.remoteChanges.listen(applied.add);

        sync.start();
        store.emit(null);
        store.emit('{not json');
        async.flushMicrotasks();

        expect(applied, isEmpty);
      });
    });
  });

  group('write failure', () {
    test('reports false without throwing', () {
      fakeAsync((async) {
        final store = FakeStore()..failWrites = true;
        final sync = UserStateSync(store: store);

        bool? result;
        sync.save(stateNamed('doomed'), immediate: true).then((r) => result = r);
        async.flushMicrotasks();

        expect(result, isFalse);
      });
    });

    test('clears the own-write guard so a later change is not swallowed', () {
      fakeAsync((async) {
        final store = FakeStore()..failWrites = true;
        final sync = UserStateSync(store: store)..seed(stateNamed('local'));
        final applied = <AppState>[];
        sync.remoteChanges.listen(applied.add);

        sync.start();
        store.emit(null);

        sync.save(stateNamed('doomed'), immediate: true);
        async.flushMicrotasks();

        // Immediately after the failure — well inside what would have been the
        // grace window had the write succeeded.
        store.emit(stateNamed('theirs').encode());
        async.flushMicrotasks();

        expect(applied, hasLength(1),
            reason: 'a failed write must not suppress a real remote change');
      });
    });
  });

  group('lifecycle', () {
    test('stop() drops a queued write and completes its waiter', () {
      fakeAsync((async) {
        final store = FakeStore();
        final sync = UserStateSync(store: store);

        bool? result;
        sync.save(stateNamed('abandoned')).then((r) => result = r);
        sync.stop();

        async.elapse(kCloudSaveDebounce * 2);
        async.flushMicrotasks();

        expect(store.writes, isEmpty);
        expect(result, isFalse, reason: 'the caller must not hang after stop()');
      });
    });

    test('start() is idempotent', () {
      fakeAsync((async) {
        final store = FakeStore();
        final sync = UserStateSync(store: store)..seed(stateNamed('local'));
        final applied = <AppState>[];
        sync.remoteChanges.listen(applied.add);

        sync.start();
        sync.start();

        store.emit(null);
        store.emit(stateNamed('remote').encode());
        async.flushMicrotasks();

        expect(applied, hasLength(1),
            reason: 'a second start() must not double-subscribe');
      });
    });

    test('stops applying changes after stop()', () {
      fakeAsync((async) {
        final store = FakeStore();
        final sync = UserStateSync(store: store)..seed(stateNamed('local'));
        final applied = <AppState>[];
        sync.remoteChanges.listen(applied.add);

        sync.start();
        store.emit(null);
        sync.stop();
        async.flushMicrotasks();

        store.emit(stateNamed('remote').encode());
        async.flushMicrotasks();

        expect(applied, isEmpty);
      });
    });
  });
}
