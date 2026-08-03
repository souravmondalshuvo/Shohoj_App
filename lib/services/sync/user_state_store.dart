import '../../models/app_state.dart';

/// The persistence surface [UserStateSync] needs.
///
/// Narrow on purpose. `FirestoreService` carries reviews, faculty lookups and
/// the difficulty map alongside user state; depending on all of it would make
/// the sync coordinator untestable without Firebase, when the only two
/// operations it performs are these.
abstract interface class UserStateStore {
  /// Streams the raw `data` payload, or `null` when absent.
  ///
  /// Raw rather than decoded: the sync layer compares payloads by fingerprint
  /// before applying anything, and decoding first discards the bytes that
  /// comparison needs.
  Stream<String?> watchRawState();

  /// Persists the state document.
  Future<void> saveState(AppState state);
}
