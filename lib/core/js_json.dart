import 'dart:convert';

/// Re-encodes decoded JSON the way JavaScript's `JSON.stringify` would.
///
/// JavaScript has a single number type, so it writes `3`. Dart distinguishes
/// int from double and would write `3.0` for the same value. The app and the
/// Shohoj web app write the same Firestore document and compare its content by
/// re-serialising it, so left alone the two clients would produce different
/// bytes for identical state and each read the other's writes as a change — a
/// standing ping-pong of spurious reloads.
///
/// Whole doubles are narrowed to ints to close that gap. Values at or beyond
/// 1e21 are left alone: JavaScript switches to exponential notation there, so
/// narrowing would not help and precision is already lost.
Object? normaliseForJs(Object? value) {
  if (value is double) {
    if (value.isFinite && value == value.roundToDouble() && value.abs() < 1e21) {
      return value.toInt();
    }
    return value;
  }
  if (value is Map) {
    return value.map((k, v) => MapEntry(k, normaliseForJs(v)));
  }
  if (value is List) {
    return value.map(normaliseForJs).toList();
  }
  return value;
}

/// Encodes to JSON using JavaScript's number formatting.
String jsCompatJsonEncode(Object? value) => jsonEncode(normaliseForJs(value));
