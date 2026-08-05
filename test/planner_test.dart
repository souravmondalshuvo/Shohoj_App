import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shohoj/core/gpa.dart';
import 'package:shohoj/core/planner.dart';
import 'package:shohoj/data/prerequisites.dart';
import 'package:shohoj/models/course.dart';
import 'package:shohoj/models/semester.dart';

Course c(String name, double credits, String grade) =>
    Course(name: name, credits: credits, grade: grade);

Semester s(int id, List<Course> courses, {bool running = false}) =>
    Semester(id: id, name: 'S$id', courses: courses, running: running);

/// The same transcript the oracle generator uses.
final semesters = <Semester>[
  s(0, [
    c('Programming Language I (CSE110)', 3, 'B'),
    c('Principles of Physics I (PHY111)', 3, 'B-'),
  ]),
  s(1, [
    c('Programming Language II (CSE111)', 3, 'F'),
    c('Calculus (MAT110)', 3, 'C'),
  ]),
  s(2, [
    c('Programming Language II (CSE111)', 3, 'A'),
    c('Data Structures (CSE220)', 3, ''),
  ]),
  s(3, [c('Algorithms (CSE221)', 3, '')], running: true),
];

const catalogList = <CatalogCourse>[
  CatalogCourse('CSE110', 'Programming Language I', 3),
  CatalogCourse('CSE111', 'Programming Language II', 3),
  CatalogCourse('CSE220', 'Data Structures', 3),
  CatalogCourse('CSE221', 'Algorithms', 3),
  CatalogCourse('CSE230', 'Discrete Mathematics', 3),
  CatalogCourse('CSE250', 'Circuits and Electronics', 3),
  CatalogCourse('CSE310', 'Object Oriented Programming', 3),
  CatalogCourse('CSE320', 'Data Communications', 3),
  CatalogCourse('CSE331', 'Automata', 3),
  CatalogCourse('PHY111', 'Principles of Physics I', 3),
  CatalogCourse('MAT110', 'Calculus', 3),
  CatalogCourse('MAT120', 'Calculus II', 3),
  CatalogCourse('ENG101', 'Fundamentals of English', 3),
  CatalogCourse('BUS102', 'Business Basics', 3),
];

final catalogMap = {for (final c in catalogList) c.code: c};

Set<String> get superseded =>
    retakenKeys(semesters, startSeason: 'Fall', startYear: '2024');

List<Map<String, dynamic>> availableAs({
  String search = '',
  PlannerFilter filter = PlannerFilter.all,
  int? limit,
}) =>
    availableCourses(
      catalog: catalogList,
      semesters: semesters,
      planCourses: const [],
      currentDept: 'CSE',
      superseded: superseded,
      searchQuery: search,
      filter: filter,
      limit: limit,
    )
        .map((c) => {
              'code': c.code,
              'canTake': c.canTake,
              'unlockCount': c.unlockCount,
              'isRelevant': c.isRelevant,
              'missingHp': c.missingHard,
            })
        .toList();

void main() {
  late Map<String, dynamic> oracle;

  setUpAll(() {
    oracle = jsonDecode(
      File('test/planner_oracle_fixture.json').readAsStringSync(),
    ) as Map<String, dynamic>;
  });

  group('parity with the web', () {
    test('completed codes match', () {
      final got = completedCodes(semesters, superseded: superseded).toList()..sort();
      expect(got, (oracle['completed'] as List).cast<String>());
    });

    test('in-progress codes match', () {
      final got = inProgressCodes(semesters).toList()..sort();
      expect(got, (oracle['inProgress'] as List).cast<String>());
    });

    test('scheduled codes match', () {
      final got = scheduledCodes(semesters).toList()..sort();
      expect(got, (oracle['scheduled'] as List).cast<String>());
    });

    test('unlock counts match', () {
      final counts = unlockCounts();
      expect(counts['CSE110'] ?? 0, oracle['unlock_CSE110']);
      expect(counts['CSE220'] ?? 0, oracle['unlock_CSE220']);
    });

    test('department relevance matches', () {
      expect(isRelevantToDept('CSE310', 'CSE'), oracle['relevant_CSE_cse']);
      expect(isRelevantToDept('BUS102', 'CSE'), oracle['relevant_CSE_bus']);
      expect(isRelevantToDept('MAT120', 'CSE'), oracle['relevant_CSE_mat']);
      expect(isRelevantToDept('BUS102', ''), oracle['relevant_nodept']);
    });

    void expectCheck(String fixtureKey, String code) {
      final want = oracle[fixtureKey] as Map<String, dynamic>;
      final got = checkPrereqs(
        code,
        completedCodes(semesters, superseded: superseded),
      );
      expect(got.canTake, want['canTake'], reason: fixtureKey);
      expect(got.missingHard, (want['missingHp'] as List).cast<String>());
      expect(got.missingSoft, (want['missingSp'] as List).cast<String>());
      expect(got.hasData, want['hasData']);
    }

    test('prereq check matches for a blocked course',
        () => expectCheck('check_CSE221', 'CSE221'));
    test('prereq check matches for an unlocked course',
        () => expectCheck('check_CSE310', 'CSE310'));
    test('prereq check matches for an unknown course',
        () => expectCheck('check_unknown', 'ZZZ999'));

    void expectAvailable(String fixtureKey, List<Map<String, dynamic>> got) {
      final want = (oracle[fixtureKey] as List).cast<Map<String, dynamic>>();
      expect(got.map((c) => c['code']).toList(),
          want.map((c) => c['code']).toList(),
          reason: '$fixtureKey ordering');
      for (var i = 0; i < want.length; i++) {
        expect(got[i]['canTake'], want[i]['canTake']);
        expect(got[i]['unlockCount'], want[i]['unlockCount']);
        expect(got[i]['isRelevant'], want[i]['isRelevant']);
        expect(got[i]['missingHp'], (want[i]['missingHp'] as List).cast<String>());
      }
    }

    test('available courses and their ranking match',
        () => expectAvailable('available_all', availableAs()));

    test('the unlocked filter matches', () => expectAvailable(
        'available_unlocked', availableAs(filter: PlannerFilter.unlocked)));

    test('the locked filter matches', () => expectAvailable(
        'available_locked', availableAs(filter: PlannerFilter.locked)));

    test('search matches',
        () => expectAvailable('available_search', availableAs(search: 'program')));

    test('the limit matches',
        () => expectAvailable('available_limit', availableAs(limit: 3)));

    void expectValidation(String fixtureKey, List<String> plan) {
      final want = oracle[fixtureKey] as Map<String, dynamic>;
      final got = validatePlan(
        planCourses: plan,
        catalog: catalogMap,
        semesters: semesters,
        superseded: superseded,
      );
      expect(got.totalCredits, (want['totalCredits'] as num).toDouble(),
          reason: fixtureKey);
      expect(got.issues, (want['issues'] as List).cast<String>());
      expect(got.warnings, (want['warnings'] as List).cast<String>());
    }

    test('a valid plan matches',
        () => expectValidation('validate', ['CSE310', 'CSE331']));

    test('an overloaded plan matches', () => expectValidation(
        'validate_overload',
        ['CSE310', 'CSE331', 'CSE320', 'CSE250', 'MAT120', 'ENG101']));

    test('a plan with duplicates matches', () =>
        expectValidation('validate_dupe', ['CSE110', 'CSE220', 'CSE221']));

    test('the prerequisite chain matches', () {
      Map<String, dynamic> flatten(PrereqNode n) => {
            'code': n.code,
            'completed': n.completed,
            'isSoft': n.isSoft,
            'children': n.children.map(flatten).toList(),
          };

      final got = prereqChain(
        'CSE331',
        completedCodes(semesters, superseded: superseded),
        catalog: catalogMap,
      );
      expect(flatten(got!), oracle['chain_CSE331']);
    });

    test('CGPA projection matches', () {
      final want = oracle['project_A'] as Map<String, dynamic>;
      final got = projectCgpa(
        currentPoints: 100,
        currentCredits: 40,
        plannedCredits: 12,
        assumedGrade: 'A',
      );
      expect(got.current, closeTo((want['current'] as num).toDouble(), 0.000001));
      expect(got.projected, closeTo((want['projected'] as num).toDouble(), 0.000001));
      expect(got.delta, closeTo((want['delta'] as num).toDouble(), 0.000001));
    });

    test('a projection with an unusable grade matches', () {
      final want = oracle['project_bad'] as Map<String, dynamic>;
      final got = projectCgpa(
        currentPoints: 100,
        currentCredits: 40,
        plannedCredits: 12,
        assumedGrade: 'P',
      );
      expect(got.projected, isNull);
      expect(want['projected'], isNull);
      expect(got.delta, isNull);
    });
  });

  group('behaviour worth stating directly', () {
    test('a failed attempt does not count as completed', () {
      // CSE111 was failed in S1 and passed in S2. It is completed on the
      // strength of the surviving attempt, and would not be without one.
      final withoutRetake = [semesters[0], semesters[1]];
      expect(completedCodes(withoutRetake), isNot(contains('CSE111')));
      expect(completedCodes(semesters, superseded: superseded), contains('CSE111'));
    });

    test('a course already planned is not offered again', () {
      final offered = availableCourses(
        catalog: catalogList,
        semesters: semesters,
        planCourses: const ['CSE310'],
        currentDept: 'CSE',
        superseded: superseded,
      ).map((c) => c.code);
      expect(offered, isNot(contains('CSE310')));
    });

    test('zero-credit courses are never offered', () {
      final offered = availableCourses(
        catalog: const [CatalogCourse('MAT092', 'Remedial Maths', 0)],
        semesters: semesters,
        planCourses: const [],
      );
      expect(offered, isEmpty);
    });

    test('the prereq chain terminates on a cycle', () {
      const cyclic = {
        'A100': Prereq(hp: ['B100']),
        'B100': Prereq(hp: ['A100']),
      };
      final node = prereqChain(
        'A100',
        <String>{},
        catalog: const {},
        prerequisites: cyclic,
      );
      var depth = 0;
      var cursor = node;
      while (cursor != null && cursor.children.isNotEmpty) {
        cursor = cursor.children.first;
        depth++;
      }
      expect(depth, lessThanOrEqualTo(9), reason: 'depth is capped at 8');
    });

    test('an empty plan raises nothing', () {
      final v = validatePlan(
        planCourses: const [],
        catalog: catalogMap,
        semesters: semesters,
        superseded: superseded,
      );
      expect(v.totalCredits, 0);
      expect(v.issues, isEmpty);
      expect(v.isValid, isTrue);
    });
  });
}
