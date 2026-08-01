import 'course.dart';

/// Keys this model owns. Anything else is round-tripped untouched via
/// [Semester.extra].
const Set<String> _knownSemesterKeys = {
  'id',
  'name',
  'courses',
  'running',
  'summary',
  'summaryCGPA',
  'summaryCredits',
  'summaryAttempted',
  'summarySemesters',
};

/// One block in the transcript.
///
/// Two shapes share this type, matching the web app's storage format:
///
/// * a normal semester — `id`, `name`, `courses`, `running`
/// * a **summary block** (`summary: true`) — a pre-computed CGPA/credit roll-up
///   produced by transcript import for terms whose individual courses are not
///   itemised. It carries no courses and never runs.
///
/// The web filters out any block whose `id` is not a number, so [id] is an
/// `int` here. A string id would cause the web to silently discard the
/// semester on its next load.
class Semester {
  final int id;
  String name;
  List<Course> courses;
  bool running;

  final bool summary;
  final double summaryCGPA;
  final double summaryCredits;
  final double summaryAttempted;
  final int summarySemesters;

  /// Whether the decoded map carried an explicit `running` key. Preserved so a
  /// round-trip does not add a field the web did not write, which would
  /// otherwise change the sync fingerprint for semantically identical data.
  final bool _hadRunningKey;

  final Map<String, dynamic> extra;

  Semester({
    required this.id,
    this.name = '',
    List<Course>? courses,
    this.running = false,
    this.summary = false,
    this.summaryCGPA = 0,
    this.summaryCredits = 0,
    this.summaryAttempted = 0,
    this.summarySemesters = 0,
    bool hadRunningKey = true,
    Map<String, dynamic>? extra,
  })  : courses = courses ?? [Course()],
        _hadRunningKey = hadRunningKey,
        extra = extra ?? <String, dynamic>{};

  double? get gpa {
    if (summary) return null;
    double pts = 0;
    double creds = 0;
    for (final c in courses) {
      if (!c.countsTowardGPA) continue;
      final gp = c.gradePoint;
      if (gp == null) continue;
      pts += gp * c.credits;
      creds += c.credits;
    }
    return creds > 0 ? pts / creds : null;
  }

  double get totalCredits {
    if (summary) return summaryCredits;
    double creds = 0;
    for (final c in courses) {
      if (!c.countsCredits) continue;
      if (c.grade == 'F' || c.grade == 'F(NT)') continue;
      creds += c.credits;
    }
    return creds;
  }

  Map<String, dynamic> toMap() {
    if (summary) {
      return {
        'id': id,
        'summary': true,
        'summaryCGPA': summaryCGPA,
        'summaryCredits': summaryCredits,
        'summaryAttempted': summaryAttempted,
        'summarySemesters': summarySemesters,
        'courses': <dynamic>[],
        'running': false,
        ...extra,
      };
    }

    return {
      'id': id,
      'name': name,
      'courses': courses.map((c) => c.toMap()).toList(),
      if (_hadRunningKey || running) 'running': running,
      ...extra,
    };
  }

  /// Decodes one block. Returns `null` for anything the web would itself
  /// discard, so the app and the web agree on which blocks exist.
  static Semester? tryFromMap(Map<String, dynamic> m) {
    final rawId = m['id'];
    if (rawId is! num) return null;
    final id = rawId.toInt();

    final extra = Map<String, dynamic>.fromEntries(
      m.entries.where((e) => !_knownSemesterKeys.contains(e.key)),
    );

    if (m['summary'] == true) {
      final cgpa = _toDouble(m['summaryCGPA']);
      final credits = _toDouble(m['summaryCredits']);
      if (cgpa == null || cgpa < 0 || cgpa > 4.0) return null;
      if (credits == null || credits < 0) return null;

      final attempted = _toDouble(m['summaryAttempted']);
      return Semester(
        id: id,
        // Summary blocks never carry courses. Passed explicitly because the
        // constructor otherwise seeds one blank course row for new semesters.
        courses: <Course>[],
        summary: true,
        summaryCGPA: cgpa,
        summaryCredits: credits,
        summaryAttempted:
            (attempted != null && attempted >= 0) ? attempted : credits,
        summarySemesters: m['summarySemesters'] is num
            ? (m['summarySemesters'] as num).toInt()
            : 0,
        extra: extra,
      );
    }

    return Semester(
      id: id,
      name: m['name'] is String ? m['name'] as String : '',
      courses: m['courses'] is List
          ? (m['courses'] as List)
              .whereType<Map>()
              .map((c) => Course.fromMap(Map<String, dynamic>.from(c)))
              .toList()
          : <Course>[],
      running: m['running'] == true,
      hadRunningKey: m.containsKey('running'),
      extra: extra,
    );
  }

  static double? _toDouble(Object? v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v.trim());
    return null;
  }
}
