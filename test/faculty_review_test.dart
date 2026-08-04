import 'package:flutter_test/flutter_test.dart';
import 'package:shohoj/core/review_aggregation.dart';
import 'package:shohoj/models/faculty_review.dart';

/// Builds a review in the shape the Worker writes to `facultyReviews`.
FacultyReview review({
  String initials = 'MMR',
  String course = 'CSE110',
  int teaching = 4,
  int marking = 4,
  int behavior = 4,
  int difficulty = 3,
  int workload = 3,
  String text = '',
  String semester = '',
}) {
  return FacultyReview.fromMap('${initials}_${course}_abc', {
    'facultyInitials': initials,
    'courseCode': course,
    'semester': semester,
    'text': text,
    'ratings': {
      'teaching': teaching,
      'marking': marking,
      'behavior': behavior,
      'difficulty': difficulty,
      'workload': workload,
    },
  });
}

void main() {
  group('parsing the shared document shape', () {
    test('reads all five rating dimensions', () {
      final r = review(teaching: 5, marking: 4, behavior: 3, difficulty: 2, workload: 1);
      expect(r.ratings['teaching'], 5);
      expect(r.ratings['marking'], 4);
      expect(r.ratings['behavior'], 3);
      expect(r.ratings['difficulty'], 2);
      expect(r.ratings['workload'], 1);
    });

    test('uppercases initials and course code', () {
      final r = FacultyReview.fromMap('x', {
        'facultyInitials': 'mmr',
        'courseCode': 'cse110',
        'ratings': const {},
      });
      expect(r.facultyInitials, 'MMR');
      expect(r.courseCode, 'CSE110');
    });

    test('drops ratings outside 1-5', () {
      final r = FacultyReview.fromMap('x', {
        'ratings': {'teaching': 9, 'marking': 0, 'behavior': 3},
      });
      expect(r.ratings['teaching'], isNull);
      expect(r.ratings['marking'], isNull);
      expect(r.ratings['behavior'], 3);
    });

    test('tolerates a missing or malformed ratings map', () {
      expect(FacultyReview.fromMap('x', {}).ratings.values, isEmpty);
      expect(FacultyReview.fromMap('x', {'ratings': 'nope'}).ratings.values, isEmpty);
    });

    test('carries no author field', () {
      // The corpus is pseudonymous: the Worker strips identity before writing.
      // Nothing in the model can surface one even if a document had it.
      final r = FacultyReview.fromMap('x', {
        'facultyInitials': 'MMR',
        'courseCode': 'CSE110',
        'uid': 'should-not-be-readable',
        'displayName': 'Someone',
        'ratings': const {},
      });
      expect(r.text, '');
      expect(r.semester, '');
      // No API exposes the stray fields.
      expect(r.toString(), isNot(contains('should-not-be-readable')));
    });
  });

  group('quality mean', () {
    test('averages teaching, marking and behaviour only', () {
      // Difficulty and workload are descriptive, not good-or-bad. Folding them
      // in would mark down a professor for teaching a hard course.
      final r = review(teaching: 5, marking: 5, behavior: 5, difficulty: 1, workload: 1);
      expect(r.ratings.qualityMean, 5.0);
    });

    test('is null when no quality dimension is present', () {
      final r = FacultyReview.fromMap('x', {
        'ratings': {'difficulty': 4, 'workload': 4},
      });
      expect(r.ratings.qualityMean, isNull);
    });
  });

  group('difficulty map', () {
    test('omits courses below the review threshold', () {
      final out = aggregateDifficulty([
        review(course: 'CSE110'),
        review(course: 'CSE110'),
        review(course: 'CSE220'),
        review(course: 'CSE220'),
        review(course: 'CSE220'),
      ]);
      expect(out.map((c) => c.courseCode), ['CSE220']);
    });

    test('averages difficulty and workload per course', () {
      final out = aggregateDifficulty([
        review(course: 'CSE110', difficulty: 2, workload: 1),
        review(course: 'CSE110', difficulty: 4, workload: 3),
        review(course: 'CSE110', difficulty: 3, workload: 2),
      ]);
      expect(out.single.avgDifficulty, closeTo(3.0, 0.001));
      expect(out.single.avgWorkload, closeTo(2.0, 0.001));
      expect(out.single.reviewCount, 3);
    });

    test('sorts hardest first', () {
      final out = aggregateDifficulty([
        ...List.generate(3, (_) => review(course: 'EASY101', difficulty: 1)),
        ...List.generate(3, (_) => review(course: 'HARD401', difficulty: 5)),
      ]);
      expect(out.map((c) => c.courseCode), ['HARD401', 'EASY101']);
    });

    test('bands scores the way the web does', () {
      CourseDifficulty band(int d) => aggregateDifficulty(
            List.generate(3, (_) => review(course: 'X100', difficulty: d)),
          ).single;

      expect(band(2).band, 'Moderate');
      expect(band(3).band, 'Challenging');
      expect(band(4).band, 'Hard');
    });

    test('respects a caller-supplied threshold', () {
      final out = aggregateDifficulty(
        [review(course: 'CSE110')],
        minReviews: 1,
      );
      expect(out, hasLength(1));
    });
  });

  group('faculty aggregation', () {
    test('summarises quality, difficulty and courses taught', () {
      final stats = aggregateFaculty('MMR', [
        review(course: 'CSE110', teaching: 5, marking: 5, behavior: 5, difficulty: 2),
        review(course: 'CSE220', teaching: 3, marking: 3, behavior: 3, difficulty: 4),
      ]);

      expect(stats.reviewCount, 2);
      expect(stats.avgQuality, closeTo(4.0, 0.001));
      expect(stats.avgDifficulty, closeTo(3.0, 0.001));
      expect(stats.courses, ['CSE110', 'CSE220']);
    });

    test('is empty rather than null for a faculty with no reviews', () {
      final stats = aggregateFaculty('XYZ', const []);
      expect(stats.reviewCount, 0);
      expect(stats.avgQuality, isNull);
    });

    test('groups a course by faculty, most-reviewed first', () {
      final out = facultyForCourse([
        review(initials: 'AAA', course: 'CSE110'),
        review(initials: 'BBB', course: 'CSE110'),
        review(initials: 'BBB', course: 'CSE110'),
      ]);
      expect(out.map((f) => f.initials), ['BBB', 'AAA']);
      expect(out.first.reviewCount, 2);
    });
  });

  group('faculty profile', () {
    test('falls back to initials when the seed has no name', () {
      // The seed is explicitly partial, so this is the ordinary case.
      expect(const FacultyProfile(initials: 'MMR').displayName, 'MMR');
    });

    test('uses the seeded name when present', () {
      final p = FacultyProfile.fromMap('MSI', {
        'initials': 'MSI',
        'name': 'Md. Saiful Islam',
        'dept': 'CSE',
        'courses': ['CSE110'],
      });
      expect(p.displayName, 'Md. Saiful Islam');
      expect(p.dept, 'CSE');
      expect(p.courses, ['CSE110']);
    });

    test('derives initials from the doc id when the field is absent', () {
      expect(FacultyProfile.fromMap('abc', {}).initials, 'ABC');
    });
  });
}
