import 'package:flutter_test/flutter_test.dart';
import 'package:shohoj/core/gpa.dart';
import 'package:shohoj/models/course.dart';
import 'package:shohoj/models/semester.dart';

Course c(String name, double credits, String grade) =>
    Course(name: name, credits: credits, grade: grade);

Semester sem(int id, List<Course> courses, {bool running = false}) =>
    Semester(id: id, name: 'S$id', courses: courses, running: running);

Semester summary(
  int id, {
  required double cgpa,
  required double credits,
  double? attempted,
}) =>
    Semester(
      id: id,
      courses: const [],
      summary: true,
      summaryCGPA: cgpa,
      summaryCredits: credits,
      summaryAttempted: attempted ?? credits,
    );

void main() {
  group('intake policy', () {
    test('best grade applies up to Summer 2024', () {
      expect(usesBestGradePolicy(startSeason: 'Spring', startYear: '2023'), isTrue);
      expect(usesBestGradePolicy(startSeason: 'Fall', startYear: '2023'), isTrue);
      expect(usesBestGradePolicy(startSeason: 'Spring', startYear: '2024'), isTrue);
      expect(usesBestGradePolicy(startSeason: 'Summer', startYear: '2024'), isTrue);
    });

    test('latest grade applies from Fall 2024', () {
      expect(usesBestGradePolicy(startSeason: 'Fall', startYear: '2024'), isFalse);
      expect(usesBestGradePolicy(startSeason: 'Spring', startYear: '2025'), isFalse);
    });

    test('defaults to the latest-grade policy when intake is unknown', () {
      // Safer default: it never silently upgrades a CGPA by discarding a
      // later, worse attempt the student actually has to live with.
      expect(usesBestGradePolicy(), isFalse);
      expect(usesBestGradePolicy(startSeason: '', startYear: ''), isFalse);
      expect(usesBestGradePolicy(startSeason: 'Fall', startYear: 'rubbish'), isFalse);
    });
  });

  group('course identity', () {
    test('groups by the bracketed course code', () {
      expect(courseIdentity('Programming Language I (CSE110)'), 'CSE110');
      expect(courseIdentity('Something Else Entirely (CSE110)'), 'CSE110');
    });

    test('falls back to the name without a trailing parenthetical', () {
      expect(courseIdentity('Free Typed Course'), 'free typed course');
      expect(courseIdentity('Free Typed Course (section 2)'), 'free typed course');
    });
  });

  group('retake detection', () {
    test('supersedes the worse attempt under the best-grade policy', () {
      final semesters = [
        sem(0, [c('Programming Language II (CSE111)', 3, 'F')]),
        sem(1, [c('Programming Language II (CSE111)', 3, 'B')]),
      ];
      expect(
        retakenKeys(semesters, startSeason: 'Spring', startYear: '2023'),
        {'0-0'},
      );
    });

    test('supersedes the earlier attempt under the latest-grade policy', () {
      // Even when the later grade is worse — that is the point of the policy.
      final semesters = [
        sem(0, [c('Programming Language II (CSE111)', 3, 'A')]),
        sem(1, [c('Programming Language II (CSE111)', 3, 'C')]),
      ];
      expect(
        retakenKeys(semesters, startSeason: 'Fall', startYear: '2024'),
        {'0-0'},
      );
    });

    test('treats F(NT) as worse than every real grade', () {
      final semesters = [
        sem(0, [c('X (CSE111)', 3, 'F(NT)')]),
        sem(1, [c('X (CSE111)', 3, 'D-')]),
      ];
      expect(retakenKeys(semesters, startSeason: 'Spring', startYear: '2023'), {'0-0'});
    });

    test('never supersedes anything with a withdrawal', () {
      // A W is not an outcome. Under the latest-grade policy, letting it into
      // the group would drop the real grade in favour of it.
      final semesters = [
        sem(0, [c('X (CSE111)', 3, 'A')]),
        sem(1, [c('X (CSE111)', 3, 'W')]),
      ];
      expect(
        retakenKeys(semesters, startSeason: 'Fall', startYear: '2024'),
        isEmpty,
        reason: 'the A must survive',
      );
    });

    test('ignores running and summary semesters', () {
      final semesters = [
        sem(0, [c('X (CSE111)', 3, 'F')]),
        sem(1, [c('X (CSE111)', 3, 'A')], running: true),
      ];
      expect(retakenKeys(semesters), isEmpty);
    });

    test('ignores unnamed course rows', () {
      final semesters = [
        sem(0, [c('', 3, 'A')]),
        sem(1, [c('', 3, 'B')]),
      ];
      expect(retakenKeys(semesters), isEmpty);
    });

    test('handles three attempts', () {
      final semesters = [
        sem(0, [c('X (CSE111)', 3, 'F')]),
        sem(1, [c('X (CSE111)', 3, 'C')]),
        sem(2, [c('X (CSE111)', 3, 'A')]),
      ];
      expect(retakenKeys(semesters, startSeason: 'Fall', startYear: '2024'),
          {'0-0', '1-0'});
      expect(retakenKeys(semesters, startSeason: 'Spring', startYear: '2023'),
          {'0-0', '1-0'});
    });
  });

  group('semester GPA', () {
    test('excludes pass and incomplete', () {
      final s = sem(0, [
        c('A (X100)', 3, 'A'),
        c('B (X101)', 0, 'P'),
        c('C (X102)', 3, 'I'),
      ]);
      expect(semesterGpa(s), 4.0);
    });

    test('F(NT) adds credits but no points', () {
      final s = sem(0, [
        c('A (X100)', 3, 'A'),
        c('B (X101)', 3, 'F(NT)'),
      ]);
      expect(semesterGpa(s), 2.0, reason: '12 points over 6 credits');
    });

    test('is null for a summary block', () {
      expect(semesterGpa(summary(0, cgpa: 3.0, credits: 30)), isNull);
    });
  });

  group('cumulative totals', () {
    test('excludes superseded attempts from the CGPA', () {
      final semesters = [
        sem(0, [c('X (CSE111)', 3, 'F')]),
        sem(1, [c('X (CSE111)', 3, 'A')]),
      ];
      final t = calculateCgpaTotals(semesters,
          startSeason: 'Fall', startYear: '2024');

      expect(t.cgpa, 4.0, reason: 'only the surviving attempt counts');
      expect(t.cgpaCredits, 3);
      expect(t.attemptedCredits, 6, reason: 'both attempts were sat');
      expect(t.earnedCredits, 3);
    });

    test('a naive sum would disagree — this is the reported bug', () {
      // Exactly the shape of the reported mismatch: a failed no-transfer
      // attempt that was later retaken.
      final semesters = [
        sem(0, [c('Programming Language I (CSE110)', 3, 'C-')]),
        sem(1, [c('Programming Language II (CSE111)', 3, 'F(NT)')]),
        sem(2, [c('Programming Language II (CSE111)', 3, 'B')]),
      ];

      final correct = calculateCgpaTotals(semesters,
          startSeason: 'Fall', startYear: '2024');

      // 1.7*3 + 3.0*3 = 14.1 over 6 credits
      expect(correct.cgpa, closeTo(2.35, 0.001));

      // What the app used to do: count the F(NT) as 0.0 over 3 more credits.
      const naive = (1.7 * 3 + 0.0 * 3 + 3.0 * 3) / 9;
      expect(naive, closeTo(1.567, 0.001));
      expect(correct.cgpa, greaterThan(naive),
          reason: 'counting the superseded failure drags the average down');
    });

    test('folds a summary block into the total', () {
      final semesters = [
        summary(0, cgpa: 3.0, credits: 30),
        sem(1, [c('A (X100)', 3, 'A')]),
      ];
      final t = calculateCgpaTotals(semesters);

      // 3.0*30 + 4.0*3 = 102 over 33
      expect(t.cgpa, closeTo(102 / 33, 0.0001));
      expect(t.cgpaCredits, 33);
      expect(t.earnedCredits, 33);
    });

    test('dropping the summary block changes the answer', () {
      final semesters = [
        summary(0, cgpa: 3.0, credits: 30),
        sem(1, [c('A (X100)', 3, 'A')]),
      ];
      expect(
        calculateCgpaTotals(semesters, includeSummary: false).cgpa,
        4.0,
        reason: 'ignoring history is what the app used to do',
      );
    });

    test('uses summaryAttempted for attempted credits when it differs', () {
      final semesters = [summary(0, cgpa: 3.0, credits: 30, attempted: 36)];
      final t = calculateCgpaTotals(semesters);
      expect(t.attemptedCredits, 36);
      expect(t.earnedCredits, 30);
    });

    test('includes running semesters by default', () {
      final semesters = [
        sem(0, [c('A (X100)', 3, 'C')]),
        sem(1, [c('B (X101)', 3, 'A')], running: true),
      ];
      expect(calculateCgpaTotals(semesters).cgpa, closeTo(3.0, 0.0001));
      expect(
        calculateCgpaTotals(semesters, includeRunning: false).cgpa,
        closeTo(2.0, 0.0001),
      );
    });

    test('a running semester adds no attempted or earned credits', () {
      final semesters = [
        sem(0, [c('A (X100)', 3, 'C')]),
        sem(1, [c('B (X101)', 3, 'A')], running: true),
      ];
      final t = calculateCgpaTotals(semesters);
      expect(t.attemptedCredits, 3);
      expect(t.earnedCredits, 3);
    });

    test('a withdrawal is attempted but neither earned nor graded', () {
      final semesters = [
        sem(0, [c('A (X100)', 3, 'A'), c('B (X101)', 3, 'W')]),
      ];
      final t = calculateCgpaTotals(semesters);
      expect(t.cgpa, 4.0);
      expect(t.cgpaCredits, 3);
      expect(t.attemptedCredits, 6);
      expect(t.earnedCredits, 3);
    });

    test('a failure is attempted but not earned', () {
      final semesters = [
        sem(0, [c('A (X100)', 3, 'A'), c('B (X101)', 3, 'F')]),
      ];
      final t = calculateCgpaTotals(semesters);
      expect(t.cgpa, 2.0);
      expect(t.attemptedCredits, 6);
      expect(t.earnedCredits, 3);
    });

    test('is null with nothing graded', () {
      expect(calculateCgpaTotals(const []).cgpa, isNull);
      expect(calculateCgpaTotals([sem(0, [c('A (X100)', 3, '')])]).cgpa, isNull);
    });
  });

  group('improvement strategy', () {
    test('failures take a retake', () {
      expect(improvementStrategy('F'), 'retake');
      expect(improvementStrategy('F(NT)'), 'retake');
    });

    test('below B takes a repeat', () {
      expect(improvementStrategy('B-'), 'repeat');
      expect(improvementStrategy('C'), 'repeat');
      expect(improvementStrategy('D-'), 'repeat');
    });

    test('B and above cannot be improved', () {
      expect(improvementStrategy('B'), isNull);
      expect(improvementStrategy('A'), isNull);
    });

    test('pass, incomplete and blank cannot be improved', () {
      expect(improvementStrategy('P'), isNull);
      expect(improvementStrategy('I'), isNull);
      expect(improvementStrategy(''), isNull);
    });
  });

  group('credit load policy', () {
    CreditWarning? warn(double credits) =>
        semesterCreditWarning(sem(0, [c('A (X100)', credits, 'A')]));

    test('flags below the 9-credit minimum', () {
      expect(warn(6)!.type, CreditWarningType.error);
      expect(warn(6)!.message, contains('below 9-credit minimum'));
    });

    test('accepts a normal load', () {
      expect(warn(12), isNull);
      expect(warn(9), isNull);
    });

    test("flags the chairman's-permission band", () {
      expect(warn(13)!.type, CreditWarningType.warn);
      expect(warn(15)!.type, CreditWarningType.warn);
    });

    test('flags above the 15-credit maximum', () {
      expect(warn(18)!.type, CreditWarningType.error);
      expect(warn(18)!.message, contains('exceeds 15-credit maximum'));
    });

    test('an empty semester is not a warning', () {
      expect(semesterCreditWarning(sem(0, const [])), isNull);
    });

    test('excludes pass and F(NT) from the load', () {
      final s = sem(0, [
        c('A (X100)', 12, 'A'),
        c('B (X101)', 3, 'P'),
        c('C (X102)', 3, 'F(NT)'),
      ]);
      expect(semesterCreditWarning(s), isNull, reason: '12 counted, not 18');
    });
  });
}
