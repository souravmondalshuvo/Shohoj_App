import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shohoj/core/playground.dart';
import 'package:shohoj/models/course.dart';
import 'package:shohoj/models/semester.dart';

Course c(String name, double credits, String grade) =>
    Course(name: name, credits: credits, grade: grade);

Semester s(int id, List<Course> courses, {bool running = false}) =>
    Semester(id: id, name: 'S$id', courses: courses, running: running);

/// The same transcript the oracle generator uses.
final transcript = <Semester>[
  s(0, [
    c('Programming Language I (CSE110)', 3, 'C-'),
    c('Fundamentals of English (ENG101)', 3, 'B+'),
    c('Remedial Course in Mathematics (MAT092)', 0, 'P'),
    c('Principles of Physics I (PHY111)', 3, 'B-'),
  ]),
  s(1, [
    c('Programming Language II (CSE111)', 3, 'F(NT)'),
    c('Calculus (MAT110)', 3, 'C'),
  ]),
  s(2, [
    c('Programming Language II (CSE111)', 3, 'B'),
    c('Discrete Math (CSE221)', 3, 'A-'),
    c('Dropped (CSE230)', 3, 'W'),
  ]),
];

final withSummary = <Semester>[
  Semester(
    id: 9,
    courses: const [],
    summary: true,
    summaryCGPA: 3.0,
    summaryCredits: 30,
    summaryAttempted: 33,
  ),
  ...transcript,
];

const season = 'Fall';
const year = '2024';

PlaygroundTotals totalsFor(List<Semester> sems) =>
    playgroundTotals(sems, startSeason: season, startYear: year);

List<GradedCourse> coursesFor(List<Semester> sems) =>
    gradedCourses(sems, startSeason: season, startYear: year);

GradedCourse? byKey(List<GradedCourse> list, String key) {
  for (final c in list) {
    if (c.key == key) return c;
  }
  return null;
}

void main() {
  late Map<String, dynamic> oracle;

  setUpAll(() {
    oracle = jsonDecode(
      File('test/playground_oracle_fixture.json').readAsStringSync(),
    ) as Map<String, dynamic>;
  });

  group('parity with the web', () {
    test('baseline totals match', () {
      final t = totalsFor(transcript);
      final want = oracle['totals'] as Map<String, dynamic>;
      expect(t.points, closeTo((want['pts'] as num).toDouble(), 0.000001));
      expect(t.credits, (want['cr'] as num).toDouble());
      expect(t.cgpa, closeTo((want['cgpa'] as num).toDouble(), 0.000001));
    });

    test('baseline totals match with a summary block', () {
      final t = totalsFor(withSummary);
      final want = oracle['totals_summary'] as Map<String, dynamic>;
      expect(t.points, closeTo((want['pts'] as num).toDouble(), 0.000001));
      expect(t.credits, (want['cr'] as num).toDouble());
      expect(t.cgpa, closeTo((want['cgpa'] as num).toDouble(), 0.000001));
    });

    test('the eligible course set matches', () {
      expect(
        coursesFor(transcript).map((c) => c.key).toList(),
        (oracle['eligible'] as List).cast<String>(),
      );
      expect(
        coursesFor(withSummary).map((c) => c.key).toList(),
        (oracle['eligible_summary'] as List).cast<String>(),
      );
    });

    void expectSolve(String fixtureKey, String courseKey, double target) {
      final want = oracle[fixtureKey] as Map<String, dynamic>;
      final courses = coursesFor(transcript);
      final got = solveForGrade(
        course: byKey(courses, courseKey),
        totals: totalsFor(transcript),
        targetCgpa: target,
      );

      expect(got.outcome.name, want['outcome'], reason: fixtureKey);
      if (want['grade'] != null) expect(got.requiredGrade, want['grade']);
      if (want['needed'] != null) {
        expect(got.neededGradePoint,
            closeTo((want['needed'] as num).toDouble(), 0.000001));
      }
      if (want['resulting'] != null) {
        expect(got.resultingCgpa,
            closeTo((want['resulting'] as num).toDouble(), 0.000001));
      }
    }

    test('solver: a reachable target matches', () =>
        expectSolve('solve_reachable', '0-0', 3.0));

    test('solver: an impossible target matches', () =>
        expectSolve('solve_impossible', '0-0', 4.0));

    test('solver: an already-met target matches', () =>
        expectSolve('solve_met2', '0-0', 1.0));

    test('solver: an out-of-range target matches', () =>
        expectSolve('solve_badtarget', '0-0', 5.0));

    void expectChanges(String fixtureKey, Map<String, String> changes) {
      final want = oracle[fixtureKey] as Map<String, dynamic>;
      final courses = coursesFor(transcript);
      final got = applyGradeChanges(
        courses: courses,
        totals: totalsFor(transcript),
        changes: changes,
      );

      expect(got.projectedCgpa,
          closeTo((want['projected'] as num).toDouble(), 0.000001),
          reason: fixtureKey);

      final wantImpacts = (want['impacts'] as List).cast<Map<String, dynamic>>();
      expect(got.impacts, hasLength(wantImpacts.length));
      for (var i = 0; i < wantImpacts.length; i++) {
        expect(got.impacts[i].key, wantImpacts[i]['key']);
        expect(got.impacts[i].delta,
            closeTo((wantImpacts[i]['delta'] as num).toDouble(), 0.000001));
        expect(got.impacts[i].impact,
            closeTo((wantImpacts[i]['impact'] as num).toDouble(), 0.000001));
      }
    }

    test('changer: one change matches', () =>
        expectChanges('change_one', {'0-0': 'A'}));

    test('changer: stacked changes match', () =>
        expectChanges('change_many', {'0-0': 'A', '1-1': 'A'}));

    test('changer: a worse grade matches', () =>
        expectChanges('change_worse', {'2-1': 'D'}));
  });

  group('eligible courses', () {
    test('excludes pass, incomplete, withdrawal and F(NT)', () {
      final keys = coursesFor(transcript).map((c) => c.key);
      expect(keys, isNot(contains('0-2')), reason: 'P');
      expect(keys, isNot(contains('1-0')), reason: 'F(NT)');
      expect(keys, isNot(contains('2-2')), reason: 'W');
    });

    test('excludes superseded retake attempts', () {
      // CSE111 was failed in S1 and retaken in S2; only the surviving attempt
      // is actionable. Changing a grade that does not count would imply an
      // impact it cannot have.
      final keys = coursesFor(transcript).map((c) => c.key).toList();
      expect(keys, contains('2-0'));
      expect(keys, isNot(contains('1-0')));
    });

    test('carries the semester label with any parenthetical stripped', () {
      final sem = s(0, [c('X (CSE110)', 3, 'A')]);
      sem.name = 'Fall 2024 (running)';
      expect(gradedCourses([sem]).single.semesterLabel, 'Fall 2024');
    });
  });

  group('grade changer', () {
    test('an empty change set leaves the CGPA alone', () {
      final t = totalsFor(transcript);
      final r = applyGradeChanges(
        courses: coursesFor(transcript),
        totals: t,
        changes: const {},
      );
      expect(r.projectedCgpa, t.cgpa);
      expect(r.shift, 0);
      expect(r.impacts, isEmpty);
    });

    test('ignores a change to a course that is not eligible', () {
      final r = applyGradeChanges(
        courses: coursesFor(transcript),
        totals: totalsFor(transcript),
        changes: const {'1-0': 'A'}, // the superseded F(NT)
      );
      expect(r.impacts, isEmpty);
      expect(r.projectedCgpa, totalsFor(transcript).cgpa);
    });

    test('ignores a grade with no point value', () {
      final r = applyGradeChanges(
        courses: coursesFor(transcript),
        totals: totalsFor(transcript),
        changes: const {'0-0': 'P'},
      );
      expect(r.impacts, isEmpty);
    });

    test('a worse grade moves the CGPA down', () {
      final r = applyGradeChanges(
        courses: coursesFor(transcript),
        totals: totalsFor(transcript),
        changes: const {'2-1': 'D'},
      );
      expect(r.shift, lessThan(0));
      expect(r.impacts.single.delta, lessThan(0));
    });

    test('impacts sum to the total shift', () {
      final r = applyGradeChanges(
        courses: coursesFor(transcript),
        totals: totalsFor(transcript),
        changes: const {'0-0': 'A', '1-1': 'A'},
      );
      final summed = r.impacts.fold<double>(0, (a, i) => a + i.impact);
      expect(summed, closeTo(r.shift!, 0.000001),
          reason: 'credits do not move, so per-change impacts are additive');
    });
  });

  group('reverse solver', () {
    test('is invalid with no course selected', () {
      expect(
        solveForGrade(
          course: null,
          totals: totalsFor(transcript),
          targetCgpa: 3.0,
        ).outcome,
        SolverOutcome.invalid,
      );
    });

    test('is invalid for a target outside 0 to 4', () {
      final course = coursesFor(transcript).first;
      for (final t in [-0.5, 4.5]) {
        expect(
          solveForGrade(
            course: course,
            totals: totalsFor(transcript),
            targetCgpa: t,
          ).outcome,
          SolverOutcome.invalid,
        );
      }
    });

    test('is invalid with no credits to divide by', () {
      expect(
        solveForGrade(
          course: coursesFor(transcript).first,
          totals: const PlaygroundTotals(points: 0, credits: 0, cgpa: null),
          targetCgpa: 3.0,
        ).outcome,
        SolverOutcome.invalid,
      );
    });

    test('returns the lowest sufficient grade, not an overshoot', () {
      final courses = coursesFor(transcript);
      final r = solveForGrade(
        course: byKey(courses, '0-0'),
        totals: totalsFor(transcript),
        targetCgpa: 3.0,
      );
      expect(r.outcome, SolverOutcome.reachable);
      expect(r.requiredGradePoint, greaterThanOrEqualTo(r.neededGradePoint!));

      // No cheaper grade would have cleared it.
      final cheaper = kGrades.entries
          .where((e) => e.value != null && e.value! < r.requiredGradePoint!)
          .where((e) => e.value! >= r.neededGradePoint!);
      expect(cheaper, isEmpty);
    });

    test('reports the best achievable CGPA when out of reach', () {
      final courses = coursesFor(transcript);
      final r = solveForGrade(
        course: byKey(courses, '0-0'),
        totals: totalsFor(transcript),
        targetCgpa: 4.0,
      );
      expect(r.outcome, SolverOutcome.impossible);
      expect(r.resultingCgpa, lessThan(4.0));
      expect(r.neededGradePoint, greaterThan(4.0));
    });

    test('reports a target already met', () {
      final courses = coursesFor(transcript);
      final r = solveForGrade(
        course: byKey(courses, '0-0'),
        totals: totalsFor(transcript),
        targetCgpa: 1.0,
      );
      expect(r.outcome, SolverOutcome.alreadyMet);
    });
  });
}
