import '../models/course.dart';
import '../models/semester.dart';

/// CGPA calculation, ported from the web app's `js/core/gpa-core.js`.
///
/// Both clients read the same document, so a student checking their phone must
/// see the number the website shows. Any change here needs a matching change
/// there — the web is the reference implementation.

const List<String> kGpaSeasonOrder = ['Spring', 'Summer', 'Fall'];

/// Whether the best-grade retake policy applies to this intake.
///
/// BRACU switched at Fall 2024: students who started Spring or Summer 2024 or
/// earlier keep their best attempt; Fall 2024 onwards, the latest attempt
/// counts regardless of whether it is better.
bool usesBestGradePolicy({String? startSeason, String? startYear}) {
  final season = (startSeason == null || startSeason.isEmpty) ? 'Fall' : startSeason;
  final year = int.tryParse((startYear ?? '').trim().isEmpty ? '2024' : startYear!.trim());
  if (year == null) return false;

  final seasonIndex = kGpaSeasonOrder.indexOf(season);
  if (year < 2024) return true;
  if (year == 2024 && seasonIndex == 0) return true; // Spring
  if (year == 2024 && seasonIndex == 1) return true; // Summer
  return false;
}

final RegExp _courseCodeSuffix = RegExp(r'\(([A-Z]{2,4}\d{3}[A-Z]?)\)$');
final RegExp _trailingParenthetical = RegExp(r'\s*\([^)]+\)$');

/// The key two attempts at the same course share.
///
/// Prefers the bracketed course code — "Programming Language I (CSE110)" — and
/// falls back to the name with any trailing parenthetical stripped, so a
/// free-typed course still groups with itself.
String courseIdentity(String courseName) {
  final match = _courseCodeSuffix.firstMatch(courseName);
  if (match != null) return match.group(1)!;
  return courseName.replaceFirst(_trailingParenthetical, '').trim().toLowerCase();
}

/// Identifies one course slot across the transcript.
String _attemptKey(int semesterId, int index) => '$semesterId-$index';

/// The attempts superseded by a later or better one, as `semesterId-index` keys.
///
/// Withdrawals are skipped entirely. A `W` is not an outcome, so it must
/// neither supersede an earlier attempt nor be superseded by a later one —
/// otherwise the latest-attempt policy would drop a real grade in favour of it
/// and a passing grade would vanish.
Set<String> retakenKeys(
  List<Semester> semesters, {
  String? startSeason,
  String? startYear,
  bool? bestGrade,
}) {
  final useBest = bestGrade ??
      usesBestGradePolicy(startSeason: startSeason, startYear: startYear);

  final attempts = <({String key, String groupKey, double gradePoint})>[];

  for (final semester in semesters) {
    if (semester.running || semester.summary) continue;
    for (var index = 0; index < semester.courses.length; index++) {
      final course = semester.courses[index];
      if (course.name.trim().isEmpty) continue;
      if (course.grade == 'W') continue;

      // A failed no-transfer attempt sorts below every real grade under the
      // best-grade policy, so -1 rather than its 0.0 grade point.
      final gp = (course.grade.isNotEmpty && course.grade != 'F(NT)')
          ? (kGrades[course.grade] ?? -1.0)
          : -1.0;

      attempts.add((
        key: _attemptKey(semester.id, index),
        groupKey: courseIdentity(course.name),
        gradePoint: gp,
      ));
    }
  }

  final groups = <String, List<({String key, String groupKey, double gradePoint})>>{};
  for (final attempt in attempts) {
    groups.putIfAbsent(attempt.groupKey, () => []).add(attempt);
  }

  final superseded = <String>{};
  for (final group in groups.values) {
    if (group.length < 2) continue;

    if (useBest) {
      var best = group.first;
      for (final attempt in group) {
        if (attempt.gradePoint >= best.gradePoint) best = attempt;
      }
      for (final attempt in group) {
        if (attempt.key != best.key) superseded.add(attempt.key);
      }
      continue;
    }

    // Latest-grade policy: everything but the final attempt is superseded.
    for (final attempt in group.take(group.length - 1)) {
      superseded.add(attempt.key);
    }
  }

  return superseded;
}

/// One semester's GPA.
///
/// `P` and `I` are excluded outright. `F(NT)` contributes credits but no
/// points, which is what makes a failed no-transfer course drag the average.
double? semesterGpa(Semester semester) {
  if (semester.summary) return null;

  var points = 0.0;
  var credits = 0.0;

  for (final course in semester.courses) {
    if (!kGrades.containsKey(course.grade)) continue;
    if (course.credits == 0) continue;
    if (course.grade == 'P' || course.grade == 'I') continue;

    if (course.grade == 'F(NT)') {
      credits += course.credits;
      continue;
    }

    final gp = kGrades[course.grade];
    if (gp == null) continue;

    points += gp * course.credits;
    credits += course.credits;
  }

  return credits > 0 ? points / credits : null;
}

/// The totals behind the CGPA display.
class CgpaTotals {
  final double points;

  /// Every credit sat, including failures and superseded attempts.
  final double attemptedCredits;

  /// Credits that counted toward the degree — passed, and not superseded.
  final double earnedCredits;

  /// The denominator of [cgpa].
  final double cgpaCredits;

  final double? cgpa;

  const CgpaTotals({
    required this.points,
    required this.attemptedCredits,
    required this.earnedCredits,
    required this.cgpaCredits,
    required this.cgpa,
  });
}

/// Cumulative totals across the transcript.
///
/// Mirrors `calculateCgpaTotals`. The defaults match the web's: running
/// semesters and summary blocks both count.
CgpaTotals calculateCgpaTotals(
  List<Semester> semesters, {
  String? startSeason,
  String? startYear,
  bool? bestGrade,
  bool includeRunning = true,
  bool includeSummary = true,
}) {
  final superseded = retakenKeys(
    semesters,
    startSeason: startSeason,
    startYear: startYear,
    bestGrade: bestGrade,
  );

  var points = 0.0;
  var attemptedCredits = 0.0;
  var earnedCredits = 0.0;
  var cgpaCredits = 0.0;

  if (includeSummary) {
    // Only the first summary block counts, matching the web's `find`.
    Semester? summary;
    for (final s in semesters) {
      if (s.summary) {
        summary = s;
        break;
      }
    }
    if (summary != null) {
      points += summary.summaryCGPA * summary.summaryCredits;
      cgpaCredits += summary.summaryCredits;
      attemptedCredits += summary.summaryAttempted;
      earnedCredits += summary.summaryCredits;
    }
  }

  for (final semester in semesters) {
    if (semester.summary) continue;
    if (semester.running && !includeRunning) continue;

    for (var index = 0; index < semester.courses.length; index++) {
      final course = semester.courses[index];
      if (!kGrades.containsKey(course.grade)) continue;
      if (course.credits == 0) continue;
      if (course.grade == 'P' || course.grade == 'I') continue;

      final gp = kGrades[course.grade];
      final isRetaken = superseded.contains(_attemptKey(semester.id, index));

      if (!semester.running) attemptedCredits += course.credits;

      if (!isRetaken && gp != null) {
        points += gp * course.credits;
        cgpaCredits += course.credits;
      }

      if (gp != null && gp > 0 && !semester.running && !isRetaken) {
        earnedCredits += course.credits;
      }
    }
  }

  return CgpaTotals(
    points: points,
    attemptedCredits: attemptedCredits,
    earnedCredits: earnedCredits,
    cgpaCredits: cgpaCredits,
    cgpa: cgpaCredits > 0 ? points / cgpaCredits : null,
  );
}

/// Whether a grade can be improved by sitting the one-off repeat exam.
///
/// Failures take the full retake instead, and P/I are not improvable.
bool isRepeatEligible(String grade) {
  if (grade == 'F' || grade == 'F(NT)') return false;
  if (grade == 'P' || grade == 'I' || grade.isEmpty) return false;
  final gp = kGrades[grade];
  if (gp == null) return false;
  return gp < 3.0;
}

/// `retake`, `repeat`, or null when the grade cannot be improved.
String? improvementStrategy(String grade) {
  if (grade == 'F' || grade == 'F(NT)') return 'retake';
  if (isRepeatEligible(grade)) return 'repeat';
  return null;
}

enum CreditWarningType { warn, error }

class CreditWarning {
  final CreditWarningType type;
  final String message;
  const CreditWarning(this.type, this.message);
}

/// BRACU's 9/12/15-credit load policy for one semester.
CreditWarning? semesterCreditWarning(Semester semester) {
  var total = 0.0;
  for (final course in semester.courses) {
    if (course.name.trim().isEmpty || course.credits == 0) continue;
    if (course.grade == 'P' || course.grade == 'F(NT)') continue;
    total += course.credits;
  }

  if (total == 0) return null;

  final label = total == total.roundToDouble()
      ? total.toInt().toString()
      : total.toString();

  if (total < 9) {
    return CreditWarning(
      CreditWarningType.error,
      '⚠ $label credits — below 9-credit minimum',
    );
  }
  if (total > 15) {
    return CreditWarning(
      CreditWarningType.error,
      '⛔ $label credits — exceeds 15-credit maximum',
    );
  }
  if (total > 12) {
    return CreditWarning(
      CreditWarningType.warn,
      "⚠ $label credits — requires chairman's permission",
    );
  }
  return null;
}
