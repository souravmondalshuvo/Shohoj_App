const Map<String, double?> kGrades = {
  'A+': 4.00, 'A': 4.00, 'A-': 3.70,
  'B+': 3.30, 'B': 3.00, 'B-': 2.70,
  'C+': 2.30, 'C': 2.00, 'C-': 1.70,
  'D+': 1.30, 'D': 1.00, 'D-': 0.70,
  'F': 0.00, 'F(NT)': 0.00,
  'P': null, 'I': null,
  // A withdrawal carries no grade point, but unlike P/I it still consumed an
  // attempt: it counts toward attempted credits and nothing else.
  'W': null,
};

const List<String> kGradeOptions = [
  '', 'A+', 'A', 'A-', 'B+', 'B', 'B-',
  'C+', 'C', 'C-', 'D+', 'D', 'D-',
  'F', 'F(NT)', 'P', 'I', 'W',
];

const List<double> kCreditOptions = [0.75, 1.0, 1.5, 2.0, 3.0, 4.0];

/// Keys this model owns. Anything else on a decoded course map is round-tripped
/// untouched via [Course.extra] so a newer web build is not degraded by an
/// older app build.
const Set<String> _knownCourseKeys = {
  'name',
  'credits',
  'grade',
  'gradePoint',
  'faculty',
};

/// Mirror of `sanitizeGradePointValue` in the web app's `js/core/helpers.js`.
///
/// The persisted value is a number in 0..4, the string `'NT'`, or `''`. Any
/// other input normalises to `''`.
Object sanitizeGradePoint(Object? value) {
  if (value == null) return '';
  if (value is num) {
    final d = value.toDouble();
    return d.isFinite && d >= 0 && d <= 4 ? d : '';
  }
  if (value is! String) return '';

  final trimmed = value.trim();
  if (trimmed.isEmpty) return '';
  if (trimmed.toUpperCase() == 'NT') return 'NT';

  final parsed = double.tryParse(trimmed);
  if (parsed == null) return '';
  return parsed.isFinite && parsed >= 0 && parsed <= 4 ? parsed : '';
}

/// Mirror of the web's faculty normalisation: uppercase, capped at 6 chars.
String sanitizeFaculty(Object? value) {
  if (value is! String) return '';
  final upper = value.toUpperCase();
  return upper.length > 6 ? upper.substring(0, 6) : upper;
}

class Course {
  String name;
  double credits;
  String grade;

  /// BRACU faculty initials. The web uppercases and caps this at 6 characters.
  String faculty;

  /// The persisted grade point as the web stores it: a `double`, `'NT'`, or `''`.
  ///
  /// Kept separate from [gradePoint], which derives the value from [grade] for
  /// GPA maths. Storing it verbatim is what lets an app write round-trip a
  /// transcript-imported NT marker the app has no other way to represent.
  Object storedGradePoint;

  /// Fields present on the decoded map that this model does not know about.
  final Map<String, dynamic> extra;

  Course({
    this.name = '',
    this.credits = 3.0,
    this.grade = '',
    this.faculty = '',
    Object? storedGradePoint,
    Map<String, dynamic>? extra,
  })  : storedGradePoint = storedGradePoint ?? '',
        extra = extra ?? <String, dynamic>{};

  double? get gradePoint => kGrades[grade];

  bool get countsTowardGPA {
    if (grade.isEmpty) return false;
    if (grade == 'P' || grade == 'I' || grade == 'W') return false;
    return true;
  }

  bool get countsCredits {
    if (grade.isEmpty) return false;
    if (grade == 'P' || grade == 'I' || grade == 'W') return false;
    return true;
  }

  Map<String, dynamic> toMap() => {
    'name': name,
    'credits': credits,
    'grade': grade,
    'gradePoint': storedGradePoint,
    'faculty': faculty,
    ...extra,
  };

  factory Course.fromMap(Map<String, dynamic> m) => Course(
    name: m['name'] is String ? m['name'] as String : '',
    credits: (m['credits'] as num?)?.toDouble() ?? 0.0,
    grade: m['grade'] is String ? m['grade'] as String : '',
    faculty: sanitizeFaculty(m['faculty']),
    storedGradePoint: sanitizeGradePoint(m['gradePoint']),
    extra: Map<String, dynamic>.fromEntries(
      m.entries.where((e) => !_knownCourseKeys.contains(e.key)),
    ),
  );

  Course copyWith({
    String? name,
    double? credits,
    String? grade,
    String? faculty,
    Object? storedGradePoint,
  }) => Course(
    name: name ?? this.name,
    credits: credits ?? this.credits,
    grade: grade ?? this.grade,
    faculty: faculty ?? this.faculty,
    storedGradePoint: storedGradePoint ?? this.storedGradePoint,
    extra: Map<String, dynamic>.from(extra),
  );
}
