import '../models/course.dart';
import '../models/semester.dart';
import 'gpa.dart';

/// Grade Changer and Reverse Solver, ported from the web's `js/ui/playground.js`.
///
/// Both operate on the student's real transcript. Keep in step with the web —
/// a student comparing the two should get the same answer.

/// A course the Playground can act on, identified the way the web identifies
/// one: `semesterId-index`.
class GradedCourse {
  final String key;
  final String name;
  final double credits;
  final String grade;
  final double gradePoint;
  final String semesterLabel;
  final bool running;

  const GradedCourse({
    required this.key,
    required this.name,
    required this.credits,
    required this.grade,
    required this.gradePoint,
    required this.semesterLabel,
    required this.running,
  });
}

final RegExp _trailingParen = RegExp(r'\s*\(.*\)$');

/// Courses eligible for what-if analysis.
///
/// Excludes anything without a numeric grade point — `P`, `I`, `W` — and
/// `F(NT)`, which the web's Playground leaves out of its baseline too.
/// Superseded retake attempts are excluded: changing a grade that does not
/// count would imply an impact it cannot have.
List<GradedCourse> gradedCourses(
  List<Semester> semesters, {
  String? startSeason,
  String? startYear,
}) {
  final superseded = retakenKeys(
    semesters,
    startSeason: startSeason,
    startYear: startYear,
  );

  final out = <GradedCourse>[];
  for (final semester in semesters) {
    if (semester.summary) continue;
    for (var i = 0; i < semester.courses.length; i++) {
      final c = semester.courses[i];
      if (c.name.trim().isEmpty || c.grade.isEmpty) continue;
      if (c.grade == 'P' || c.grade == 'I' || c.grade == 'F(NT)' || c.grade == 'W') {
        continue;
      }
      final gp = kGrades[c.grade];
      if (gp == null) continue;

      final key = '${semester.id}-$i';
      if (superseded.contains(key)) continue;

      out.add(GradedCourse(
        key: key,
        name: c.name,
        credits: c.credits,
        grade: c.grade,
        gradePoint: gp,
        semesterLabel: semester.name.replaceFirst(_trailingParen, ''),
        running: semester.running,
      ));
    }
  }
  return out;
}

/// The Playground's baseline points and credits.
class PlaygroundTotals {
  final double points;
  final double credits;
  final double? cgpa;

  const PlaygroundTotals({
    required this.points,
    required this.credits,
    required this.cgpa,
  });
}

/// The baseline the what-if tools work from.
///
/// Mirrors the web's `getCurrentTotals`, which differs from
/// [calculateCgpaTotals] in one respect: it **excludes** `F(NT)` rather than
/// counting it as zero points plus credits. The two web functions disagree, so
/// a student with an unretaken `F(NT)` sees a slightly different baseline here
/// than in the header. Matched deliberately — diverging would be a second bug
/// rather than a fix.
PlaygroundTotals playgroundTotals(
  List<Semester> semesters, {
  String? startSeason,
  String? startYear,
}) {
  final superseded = retakenKeys(
    semesters,
    startSeason: startSeason,
    startYear: startYear,
  );

  var points = 0.0;
  var credits = 0.0;

  for (final s in semesters) {
    if (s.summary) {
      points += s.summaryCGPA * s.summaryCredits;
      credits += s.summaryCredits;
      break; // only the first summary block, matching the web's `find`
    }
  }

  for (final semester in semesters) {
    if (semester.summary) continue;
    for (var i = 0; i < semester.courses.length; i++) {
      final c = semester.courses[i];
      final gp = kGrades[c.grade];
      if (gp == null || c.credits == 0) continue;
      if (c.grade == 'P' || c.grade == 'I' || c.grade == 'F(NT)') continue;
      if (superseded.contains('${semester.id}-$i')) continue;
      points += gp * c.credits;
      credits += c.credits;
    }
  }

  return PlaygroundTotals(
    points: points,
    credits: credits,
    cgpa: credits > 0 ? points / credits : null,
  );
}

/// The effect of one hypothetical grade change.
class GradeChangeImpact {
  final String key;
  final String newGrade;

  /// Points added or removed by this change alone.
  final double delta;

  /// This change's own contribution to the CGPA shift.
  final double impact;

  const GradeChangeImpact({
    required this.key,
    required this.newGrade,
    required this.delta,
    required this.impact,
  });
}

class GradeChangeResult {
  final double? projectedCgpa;
  final double? baselineCgpa;
  final List<GradeChangeImpact> impacts;

  const GradeChangeResult({
    required this.projectedCgpa,
    required this.baselineCgpa,
    required this.impacts,
  });

  /// Total CGPA movement, or null when there is no baseline to move from.
  double? get shift => (projectedCgpa == null || baselineCgpa == null)
      ? null
      : projectedCgpa! - baselineCgpa!;
}

/// Applies a set of hypothetical grade changes, keyed by `semesterId-index`.
///
/// Credits do not move — swapping a grade on a course already counted changes
/// only the points — so the denominator stays fixed and each change's impact is
/// independent of the others.
GradeChangeResult applyGradeChanges({
  required List<GradedCourse> courses,
  required PlaygroundTotals totals,
  required Map<String, String> changes,
}) {
  var points = totals.points;
  final credits = totals.credits;
  final impacts = <GradeChangeImpact>[];

  for (final entry in changes.entries) {
    GradedCourse? course;
    for (final c in courses) {
      if (c.key == entry.key) {
        course = c;
        break;
      }
    }
    if (course == null) continue;

    final newGp = kGrades[entry.value];
    if (newGp == null) continue;

    final delta = course.credits * (newGp - course.gradePoint);
    points += delta;

    impacts.add(GradeChangeImpact(
      key: entry.key,
      newGrade: entry.value,
      delta: delta,
      impact: credits > 0 ? delta / credits : 0,
    ));
  }

  return GradeChangeResult(
    projectedCgpa: credits > 0 ? points / credits : null,
    baselineCgpa: totals.cgpa,
    impacts: impacts,
  );
}

enum SolverOutcome {
  /// A grade exists that reaches the target.
  reachable,

  /// The target is already met whatever happens in this course.
  alreadyMet,

  /// Even an A in this course falls short.
  impossible,

  /// No course selected, or the target is outside 0–4.
  invalid,
}

class SolverResult {
  final SolverOutcome outcome;

  /// The lowest sufficient grade, when [outcome] is reachable.
  final String? requiredGrade;
  final double? requiredGradePoint;

  /// The raw grade point needed, before rounding up to a real grade.
  final double? neededGradePoint;

  /// CGPA after achieving [requiredGrade], or the best achievable when
  /// the target is out of reach.
  final double? resultingCgpa;

  const SolverResult({
    required this.outcome,
    this.requiredGrade,
    this.requiredGradePoint,
    this.neededGradePoint,
    this.resultingCgpa,
  });
}

/// Grades that can be aimed for, lowest point value first.
List<MapEntry<String, double>> _targetableGrades() {
  final out = <MapEntry<String, double>>[];
  for (final entry in kGrades.entries) {
    final gp = entry.value;
    if (gp == null) continue;
    out.add(MapEntry(entry.key, gp));
  }
  out.sort((a, b) => a.value.compareTo(b.value));
  return out;
}

/// "What grade do I need in this course to reach this CGPA?"
///
/// Solves `target = (points - credits*current + credits*needed) / credits`
/// for the course's grade point, then rounds up to the lowest real grade that
/// clears it.
SolverResult solveForGrade({
  required GradedCourse? course,
  required PlaygroundTotals totals,
  required double? targetCgpa,
}) {
  if (course == null || targetCgpa == null) {
    return const SolverResult(outcome: SolverOutcome.invalid);
  }
  if (targetCgpa < 0 || targetCgpa > 4.0 || totals.credits <= 0) {
    return const SolverResult(outcome: SolverOutcome.invalid);
  }

  final needed = (targetCgpa * totals.credits -
          totals.points +
          course.credits * course.gradePoint) /
      course.credits;

  if (needed > 4.0) {
    final best = (totals.points -
            course.credits * course.gradePoint +
            course.credits * 4.0) /
        totals.credits;
    return SolverResult(
      outcome: SolverOutcome.impossible,
      neededGradePoint: needed,
      resultingCgpa: best,
    );
  }

  if (needed <= 0) {
    return SolverResult(
      outcome: SolverOutcome.alreadyMet,
      neededGradePoint: needed,
      resultingCgpa: totals.cgpa,
    );
  }

  for (final candidate in _targetableGrades()) {
    if (candidate.value >= needed) {
      final resulting = (totals.points -
              course.credits * course.gradePoint +
              course.credits * candidate.value) /
          totals.credits;
      return SolverResult(
        outcome: SolverOutcome.reachable,
        requiredGrade: candidate.key,
        requiredGradePoint: candidate.value,
        neededGradePoint: needed,
        resultingCgpa: resulting,
      );
    }
  }

  return SolverResult(outcome: SolverOutcome.invalid, neededGradePoint: needed);
}
