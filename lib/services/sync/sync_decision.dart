import 'dart:convert';

import '../../core/js_json.dart';

/// How long after a local write incoming snapshots are treated as that write
/// echoing back rather than a change from another device.
///
/// Matches `LOCAL_WRITE_GRACE_MS` in the web app's `js/auth/firebase.js`.
const Duration kLocalWriteGrace = Duration(milliseconds: 5000);

/// How long edits are batched before being written.
///
/// Matches `CLOUD_SAVE_DEBOUNCE_MS` in the web app.
const Duration kCloudSaveDebounce = Duration(milliseconds: 700);

/// Metadata keys stripped before comparing content, so a differing write
/// timestamp is not mistaken for a differing document.
const Set<String> _fingerprintIgnoredKeys = {'updatedAt', '_serverTimestamp'};

/// What to do with an incoming snapshot.
enum RemoteAction {
  /// The first snapshot on a subscription is the state already loaded.
  ignoreFirstSnapshot,

  /// This client wrote moments ago; the snapshot is that write echoing back.
  ignoreOwnWrite,

  /// A local save is queued, so local is ahead. Applying would clobber it.
  ignorePendingSave,

  /// No usable payload on the document.
  ignoreEmpty,

  /// Content is byte-identical after normalisation.
  ignoreIdentical,

  /// A genuine change from another device.
  apply,
}

/// Content-only identity for a stored payload.
///
/// Port of `getDataFingerprint` in the web's `js/auth/user-sync-service.js`:
/// parse, drop the metadata keys, re-serialise. Falls back to the raw string
/// when the payload will not parse, matching the web, so two equally-malformed
/// payloads still compare equal.
String getDataFingerprint(String? raw) {
  if (raw == null || raw.isEmpty) return '';
  try {
    final parsed = jsonDecode(raw);
    if (parsed is! Map) return jsCompatJsonEncode(parsed);
    final withoutMeta = Map<String, dynamic>.fromEntries(
      parsed.entries
          .where((e) => !_fingerprintIgnoredKeys.contains(e.key))
          .map((e) => MapEntry(e.key as String, e.value)),
    );
    return jsCompatJsonEncode(withoutMeta);
  } on FormatException {
    return raw;
  }
}

/// Decides what to do with a snapshot, in the web's guard order.
///
/// Ordering is deliberate and mirrors `startRealtimeSync` in
/// `js/auth/firebase.js`. The cheap structural guards run before the parse-and-
/// compare, and the pending-save guard runs before the content check so an
/// in-progress edit is never weighed against a stale cloud copy.
RemoteAction decideRemoteSnapshot({
  required bool isFirstSnapshot,
  required Duration sinceLocalWrite,
  required bool hasPendingSave,
  required String? localRaw,
  required String? remoteRaw,
}) {
  if (isFirstSnapshot) return RemoteAction.ignoreFirstSnapshot;
  if (sinceLocalWrite < kLocalWriteGrace) return RemoteAction.ignoreOwnWrite;
  if (hasPendingSave) return RemoteAction.ignorePendingSave;
  if (remoteRaw == null || remoteRaw.isEmpty) return RemoteAction.ignoreEmpty;

  return getDataFingerprint(localRaw) == getDataFingerprint(remoteRaw)
      ? RemoteAction.ignoreIdentical
      : RemoteAction.apply;
}
