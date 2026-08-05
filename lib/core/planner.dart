import '../data/prerequisites.dart';
import '../models/semester.dart';
import '../models/course.dart';

/// Semester planning, ported from the web's `js/core/planner-core.js`.
///
/// Prerequisite data is generated from the same source — see
/// `tool/generate_prereq_data.mjs`.

final RegExp _codeFromName = RegExp(r'\(([A-Z]{2,4}\d{3}[A-Z]?)\)$');
final RegExp _leadingLetters = RegExp(r'^[A-Z]+');
final RegExp _fromFirstDigit = RegExp(r'\d.*');

/// The catalogue code embedded in a course name, or null.
String? codeFromCourseName(String name) =>
    _codeFromName.firstMatch(name.trim())?.group(1);

/// Courses the student has passed.
///
/// Failures and incompletes do not count, and neither do superseded retake
/// attempts — a course failed and then retaken is completed on the strength of
/// the surviving attempt, not the failed one.
Set<String> completedCodes(
  List<Semester> semesters, {
  Set<String>? superseded,
}) {
  final skip = superseded ?? const <String>{};
  final out = <String>{};

  for (final semester in semesters) {
    if (semester.summary) continue;
    for (var i = 0; i < semester.courses.length; i++) {
      final course = semester.courses[i];
      if (course.name.trim().isEmpty || course.grade.isEmpty) continue;
      if (course.grade == 'F' || course.grade == 'F(NT)' || course.grade == 'I') {
        continue;
      }
      if (skip.contains('${semester.id}-$i')) continue;
      final code = codeFromCourseName(course.name);
      if (code != null) out.add(code);
    }
  }
  return out;
}

/// Courses in the running semester.
Set<String> inProgressCodes(List<Semester> semesters) {
  final out = <String>{};
  for (final semester in semesters) {
    if (!semester.running) continue;
    for (final course in semester.courses) {
      if (course.name.trim().isEmpty) continue;
      final code = codeFromCourseName(course.name);
      if (code != null) out.add(code);
    }
  }
  return out;
}

/// Courses sitting ungraded in a non-running semester — already slotted in.
Set<String> scheduledCodes(List<Semester> semesters) {
  final out = <String>{};
  for (final semester in semesters) {
    if (semester.summary || semester.running) continue;
    for (final course in semester.courses) {
      if (course.name.trim().isEmpty || course.grade.isNotEmpty) continue;
      final code = codeFromCourseName(course.name);
      if (code != null) out.add(code);
    }
  }
  return out;
}

class PrereqCheck {
  final bool canTake;
  final List<String> missingHard;
  final List<String> missingSoft;

  /// False when the catalogue has no prerequisite entry for the course, which
  /// is different from having none.
  final bool hasData;

  const PrereqCheck({
    required this.canTake,
    required this.missingHard,
    required this.missingSoft,
    required this.hasData,
  });
}

/// Whether a course can be taken given what has been completed.
PrereqCheck checkPrereqs(
  String code,
  Set<String> completed, {
  Map<String, Prereq>? prerequisites,
}) {
  final table = prerequisites ?? kPrereqs;
  final prereq = table[code];
  if (prereq == null) {
    return const PrereqCheck(
      canTake: true,
      missingHard: [],
      missingSoft: [],
      hasData: false,
    );
  }

  final missingHard = prereq.hp.where((c) => !completed.contains(c)).toList();
  final missingSoft = prereq.sp.where((c) => !completed.contains(c)).toList();

  return PrereqCheck(
    canTake: missingHard.isEmpty,
    missingHard: missingHard,
    missingSoft: missingSoft,
    hasData: true,
  );
}

/// How many courses each code unlocks, for ranking what to take next.
Map<String, int> unlockCounts({Map<String, Prereq>? prerequisites}) {
  final table = prerequisites ?? kPrereqs;
  final counts = <String, int>{};
  for (final prereq in table.values) {
    for (final requirement in [...prereq.hp, ...prereq.sp]) {
      counts[requirement] = (counts[requirement] ?? 0) + 1;
    }
  }
  return counts;
}

/// Whether a course belongs to the student's department or is a common course.
bool isRelevantToDept(String code, String? deptCode) {
  if (deptCode == null || deptCode.isEmpty) return true;
  final prefix = code.replaceFirst(_fromFirstDigit, '');
  if ((kDeptPrefixes[deptCode] ?? const []).contains(prefix)) return true;
  return kCommonPrefixes.contains(prefix);
}

/// A catalogue course annotated with everything the planner needs to rank it.
class AvailableCourse {
  final String code;
  final String name;
  final double credits;
  final bool canTake;
  final List<String> missingHard;
  final List<String> missingSoft;
  final bool hasPrereqData;
  final bool isRelevant;
  final int unlockCount;

  const AvailableCourse({
    required this.code,
    required this.name,
    required this.credits,
    required this.canTake,
    required this.missingHard,
    required this.missingSoft,
    required this.hasPrereqData,
    required this.isRelevant,
    required this.unlockCount,
  });
}

/// Minimal catalogue entry, so this module does not depend on the app's
/// catalogue representation.
class CatalogCourse {
  final String code;
  final String name;
  final double credits;
  const CatalogCourse(this.code, this.name, this.credits);
}

enum PlannerFilter { all, unlocked, locked }

/// Courses the student could add next, best candidates first.
///
/// Ordering matches the web: own-department before electives, unlocked before
/// blocked, then by how many courses each unlocks, then by course number.
List<AvailableCourse> availableCourses({
  required List<CatalogCourse> catalog,
  required List<Semester> semesters,
  required List<String> planCourses,
  String? currentDept,
  Set<String>? superseded,
  Map<String, Prereq>? prerequisites,
  String searchQuery = '',
  PlannerFilter filter = PlannerFilter.all,
  int? limit,
}) {
  final completed = completedCodes(semesters, superseded: superseded);
  final inProgress = inProgressCodes(semesters);
  final scheduled = scheduledCodes(semesters);
  final counts = unlockCounts(prerequisites: prerequisites);
  final planned = planCourses.toSet();

  var results = <AvailableCourse>[];
  for (final course in catalog) {
    if (completed.contains(course.code)) continue;
    if (inProgress.contains(course.code)) continue;
    if (scheduled.contains(course.code)) continue;
    if (planned.contains(course.code)) continue;
    if (course.credits == 0) continue;

    final check =
        checkPrereqs(course.code, completed, prerequisites: prerequisites);

    results.add(AvailableCourse(
      code: course.code,
      name: course.name,
      credits: course.credits,
      canTake: check.canTake,
      missingHard: check.missingHard,
      missingSoft: check.missingSoft,
      hasPrereqData: check.hasData,
      isRelevant: isRelevantToDept(course.code, currentDept),
      unlockCount: counts[course.code] ?? 0,
    ));
  }

  results.sort((a, b) {
    if (a.isRelevant != b.isRelevant) return a.isRelevant ? -1 : 1;
    if (a.canTake != b.canTake) return a.canTake ? -1 : 1;
    if (a.unlockCount != b.unlockCount) {
      return b.unlockCount.compareTo(a.unlockCount);
    }
    final aNum = int.tryParse(a.code.replaceFirst(_leadingLetters, '')) ?? 0;
    final bNum = int.tryParse(b.code.replaceFirst(_leadingLetters, '')) ?? 0;
    return aNum.compareTo(bNum);
  });

  final query = searchQuery.trim().toLowerCase();
  if (query.isNotEmpty) {
    results = results
        .where((c) =>
            c.code.toLowerCase().contains(query) ||
            c.name.toLowerCase().contains(query))
        .toList();
  }

  if (filter == PlannerFilter.unlocked) {
    results = results.where((c) => c.canTake).toList();
  } else if (filter == PlannerFilter.locked) {
    results = results.where((c) => !c.canTake).toList();
  }

  if (limit != null && results.length > limit) {
    results = results.sublist(0, limit);
  }
  return results;
}

class PlanValidation {
  final double totalCredits;

  /// Blockers — a missing hard prerequisite, or a credit load outside policy.
  final List<String> issues;

  /// Worth knowing but not disqualifying.
  final List<String> warnings;

  const PlanValidation({
    required this.totalCredits,
    required this.issues,
    required this.warnings,
  });

  bool get isValid => issues.isEmpty;
}

/// Checks a planned set of courses against prerequisites and credit policy.
PlanValidation validatePlan({
  required List<String> planCourses,
  required Map<String, CatalogCourse> catalog,
  required List<Semester> semesters,
  Set<String>? superseded,
  Map<String, Prereq>? prerequisites,
}) {
  final completed = completedCodes(semesters, superseded: superseded);
  final scheduled = scheduledCodes(semesters);
  final inProgress = inProgressCodes(semesters);

  var totalCredits = 0.0;
  for (final code in planCourses) {
    totalCredits += catalog[code]?.credits ?? 0;
  }

  final issues = <String>[];
  final warnings = <String>[];
  final label = totalCredits == totalCredits.roundToDouble()
      ? totalCredits.toInt().toString()
      : totalCredits.toString();

  if (totalCredits > 0 && totalCredits < 9) {
    issues.add('$label credits — below 9-credit minimum');
  }
  if (totalCredits > 15) {
    issues.add('$label credits — exceeds 15-credit maximum');
  }
  if (totalCredits > 12 && totalCredits <= 15) {
    warnings.add('$label credits — requires chairman’s permission');
  }

  for (final code in planCourses) {
    final check = checkPrereqs(code, completed, prerequisites: prerequisites);
    if (!check.canTake) {
      final plural = check.missingHard.length > 1 ? 's' : '';
      issues.add('$code — missing prerequisite$plural: ${check.missingHard.join(', ')}');
    }
    if (check.missingSoft.isNotEmpty) {
      warnings.add('$code — recommended: ${check.missingSoft.join(', ')}');
    }
  }

  for (final code in planCourses) {
    if (completed.contains(code)) {
      warnings.add('$code — you’ve already passed this course');
    } else if (inProgress.contains(code)) {
      warnings.add('$code — already in your running semester');
    } else if (scheduled.contains(code)) {
      warnings.add('$code — already scheduled in another semester');
    }
  }

  return PlanValidation(
    totalCredits: totalCredits,
    issues: issues,
    warnings: warnings,
  );
}

/// A node in the prerequisite tree.
class PrereqNode {
  final String code;
  final String name;
  final bool completed;

  /// True when this course is a recommendation rather than a hard requirement
  /// of its parent.
  final bool isSoft;

  final List<PrereqNode> children;

  const PrereqNode({
    required this.code,
    required this.name,
    required this.completed,
    this.isSoft = false,
    this.children = const [],
  });
}

/// The full dependency tree behind a course.
///
/// Depth is capped at 8, matching the web — the data should be acyclic, but a
/// bad edit should not hang the app.
PrereqNode? prereqChain(
  String code,
  Set<String> completed, {
  required Map<String, CatalogCourse> catalog,
  Map<String, Prereq>? prerequisites,
  int depth = 0,
}) {
  if (depth > 8) return null;
  final table = prerequisites ?? kPrereqs;
  final prereq = table[code];

  final children = <PrereqNode>[];
  if (prereq != null) {
    for (final item in [...prereq.hp, ...prereq.sp]) {
      final child = prereqChain(
        item,
        completed,
        catalog: catalog,
        prerequisites: prerequisites,
        depth: depth + 1,
      );
      if (child == null) continue;
      children.add(PrereqNode(
        code: child.code,
        name: child.name,
        completed: child.completed,
        isSoft: prereq.sp.contains(item),
        children: child.children,
      ));
    }
  }

  return PrereqNode(
    code: code,
    name: catalog[code]?.name ?? code,
    completed: completed.contains(code),
    children: children,
  );
}

class CgpaProjection {
  final double? current;
  final double? projected;
  final double? delta;
  const CgpaProjection({this.current, this.projected, this.delta});
}

/// What the CGPA becomes if every planned credit lands on one grade.
CgpaProjection projectCgpa({
  required double currentPoints,
  required double currentCredits,
  required double plannedCredits,
  required String assumedGrade,
}) {
  final current = currentCredits > 0 ? currentPoints / currentCredits : null;
  final gradePoint = kGrades[assumedGrade];
  if (gradePoint == null) {
    return CgpaProjection(current: current, projected: null, delta: null);
  }

  final newPoints = currentPoints + plannedCredits * gradePoint;
  final newCredits = currentCredits + plannedCredits;
  final projected = newCredits > 0 ? newPoints / newCredits : null;

  return CgpaProjection(
    current: current,
    projected: projected,
    delta: (current != null && projected != null) ? projected - current : null,
  );
}
