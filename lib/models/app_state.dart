import 'dart:convert';

import '../core/js_json.dart';
import 'semester.dart';

/// Keys this model owns. Anything else is round-tripped untouched via
/// [AppState.extra].
const Set<String> _knownStateKeys = {
  'currentDept',
  'semesterCounter',
  'semesters',
  'startSeason',
  'startYear',
  'planCourses',
};

final RegExp _deptPattern = RegExp(r'^[A-Z]{2,4}$');
final RegExp _courseCodePattern = RegExp(r'^[A-Z]{2,4}\d{3}[A-Z]?$');

/// The full user state shared with the Shohoj web app.
///
/// This is the decoded form of the `data` field on `users/{uid}`. The web
/// stores the whole payload as a single JSON string — see `saveState()` in the
/// web app's `js/core/state.js` and `persistCloudState()` in `js/auth/firebase.js`.
///
/// Both clients write the same document, so this model must round-trip every
/// field the web owns, including ones the app does not yet use. Dropping a
/// field here deletes it from the user's account the next time the app saves.
class AppState {
  String currentDept;
  int semesterCounter;
  List<Semester> semesters;
  String startSeason;
  String startYear;

  /// Course codes selected in the web's Semester Planner. The app does not read
  /// these yet, but must not drop them.
  List<String> planCourses;

  final Map<String, dynamic> extra;

  AppState({
    this.currentDept = '',
    this.semesterCounter = 0,
    List<Semester>? semesters,
    this.startSeason = '',
    this.startYear = '',
    List<String>? planCourses,
    Map<String, dynamic>? extra,
  })  : semesters = semesters ?? <Semester>[],
        planCourses = planCourses ?? <String>[],
        extra = extra ?? <String, dynamic>{};

  /// Key order matches the web's `saveState()` so an unchanged round-trip
  /// re-encodes to the same JSON, keeping the sync fingerprint stable.
  Map<String, dynamic> toMap() => {
    'currentDept': currentDept,
    'semesterCounter': semesterCounter,
    'semesters': semesters.map((s) => s.toMap()).toList(),
    'startSeason': startSeason,
    'startYear': startYear,
    'planCourses': planCourses,
    ...extra,
  };

  /// Applies the same normalisation as the web's `sanitizeRestoredState`, so
  /// both clients agree on which blocks survive a load.
  factory AppState.fromMap(Map<String, dynamic> m) {
    final rawDept = m['currentDept'];
    final dept = rawDept is String && _deptPattern.hasMatch(rawDept) ? rawDept : '';

    final semesters = m['semesters'] is List
        ? (m['semesters'] as List)
            .whereType<Map>()
            .map((s) => Semester.tryFromMap(Map<String, dynamic>.from(s)))
            .whereType<Semester>()
            .toList()
        : <Semester>[];

    return AppState(
      currentDept: dept,
      semesterCounter: m['semesterCounter'] is num
          ? (m['semesterCounter'] as num).toInt()
          : semesters.length,
      semesters: semesters,
      startSeason: m['startSeason'] is String ? m['startSeason'] as String : '',
      startYear: m['startYear'] is String ? m['startYear'] as String : '',
      planCourses: m['planCourses'] is List
          ? (m['planCourses'] as List)
              .whereType<String>()
              .where(_courseCodePattern.hasMatch)
              .toList()
          : <String>[],
      extra: Map<String, dynamic>.fromEntries(
        m.entries.where((e) => !_knownStateKeys.contains(e.key)),
      ),
    );
  }

  /// Decodes the `data` string stored on `users/{uid}`.
  ///
  /// Returns `null` for absent or malformed JSON rather than throwing, matching
  /// the web's `parseStoredState`, which warns and treats bad state as absent.
  static AppState? decode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return AppState.fromMap(Map<String, dynamic>.from(decoded));
    } on FormatException {
      return null;
    }
  }

  /// Encodes to the JSON string stored in the `data` field.
  ///
  /// Uses JavaScript number formatting so the app and the web produce
  /// byte-identical JSON for identical state — see [jsCompatJsonEncode].
  String encode() => jsCompatJsonEncode(toMap());
}
