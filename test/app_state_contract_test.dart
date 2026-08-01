import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shohoj/models/app_state.dart';
import 'package:shohoj/models/course.dart';
import 'package:shohoj/models/semester.dart';

/// A payload in exactly the shape the web app writes to `users/{uid}.data`.
///
/// Key order matches `saveState()` in the web's `js/core/state.js`; the nested
/// course keys match the output of `sanitizeRestoredState` in
/// `js/core/helpers.js`. Both matter: the web compares sync fingerprints by
/// re-serialising parsed JSON, so a reordered round-trip reads as a change.
const String webPayload = '{'
    '"currentDept":"CSE",'
    '"semesterCounter":3,'
    '"semesters":['
    '{"id":0,"name":"Spring 2024","courses":['
    '{"name":"CSE110","credits":3,"grade":"A","gradePoint":4,"faculty":"MMR"},'
    '{"name":"MAT110","credits":3,"grade":"B+","gradePoint":3.3,"faculty":"ASZ"}'
    '],"running":false},'
    '{"id":1,"summary":true,"summaryCGPA":3.42,"summaryCredits":36,'
    '"summaryAttempted":39,"summarySemesters":4,"courses":[],"running":false},'
    '{"id":2,"name":"Summer 2024","courses":['
    '{"name":"CSE111","credits":3,"grade":"F","gradePoint":"NT","faculty":"TNS"}'
    '],"running":true}'
    '],'
    '"startSeason":"Spring",'
    '"startYear":"2023",'
    '"planCourses":["CSE220","CSE221"]'
    '}';

void main() {
  group('AppState decodes the web payload', () {
    late AppState state;

    setUp(() => state = AppState.decode(webPayload)!);

    test('reads the top-level fields', () {
      expect(state.currentDept, 'CSE');
      expect(state.semesterCounter, 3);
      expect(state.startSeason, 'Spring');
      expect(state.startYear, '2023');
      expect(state.planCourses, ['CSE220', 'CSE221']);
      expect(state.semesters, hasLength(3));
    });

    test('reads a normal semester with int id and web key names', () {
      final sem = state.semesters[0];
      expect(sem.id, 0);
      expect(sem.name, 'Spring 2024');
      expect(sem.running, isFalse);
      expect(sem.courses, hasLength(2));
      expect(sem.courses[0].name, 'CSE110');
      expect(sem.courses[0].faculty, 'MMR');
      expect(sem.courses[0].storedGradePoint, 4.0);
    });

    test('reads a summary block', () {
      final sem = state.semesters[1];
      expect(sem.summary, isTrue);
      expect(sem.summaryCGPA, 3.42);
      expect(sem.summaryCredits, 36);
      expect(sem.summaryAttempted, 39);
      expect(sem.summarySemesters, 4);
      expect(sem.courses, isEmpty);
      expect(sem.totalCredits, 36, reason: 'summary credits stand in for course credits');
      expect(sem.gpa, isNull);
    });

    test('preserves the NT grade-point marker', () {
      expect(state.semesters[2].courses[0].storedGradePoint, 'NT');
    });

    test('reads the running flag', () {
      expect(state.semesters[2].running, isTrue);
    });
  });

  group('round-trip fidelity', () {
    test('re-encodes the web payload without semantic loss', () {
      final reEncoded = AppState.decode(webPayload)!.encode();

      // Compared as parsed structures: the web normalises numeric formatting
      // when it re-serialises, so `3` vs `3.0` is not a real difference, but
      // a missing or renamed key is.
      expect(jsonDecode(reEncoded), jsonDecode(webPayload));
    });

    test('a second round-trip is stable', () {
      final once = AppState.decode(webPayload)!.encode();
      final twice = AppState.decode(once)!.encode();
      expect(twice, once);
    });

    test('preserves state fields the app does not model', () {
      const withUnknown = '{"currentDept":"CSE","semesterCounter":0,'
          '"semesters":[],"startSeason":"","startYear":"","planCourses":[],'
          '"futureFeature":{"nested":true}}';

      final out = jsonDecode(AppState.decode(withUnknown)!.encode()) as Map;
      expect(out['futureFeature'], {'nested': true},
          reason: 'an older app build must not delete a newer web build\'s data');
    });

    test('preserves semester and course fields the app does not model', () {
      const withUnknown = '{"currentDept":"","semesterCounter":1,'
          '"semesters":[{"id":0,"name":"S1","courses":['
          '{"name":"CSE110","credits":3,"grade":"A","gradePoint":4,'
          '"faculty":"MMR","retakeOf":7}'
          '],"running":false,"pinned":true}],'
          '"startSeason":"","startYear":"","planCourses":[]}';

      final out = jsonDecode(AppState.decode(withUnknown)!.encode()) as Map;
      final sem = (out['semesters'] as List).first as Map;
      expect(sem['pinned'], isTrue);
      expect(((sem['courses'] as List).first as Map)['retakeOf'], 7);
    });

    test('does not add a running key the web did not write', () {
      const noRunning = '{"currentDept":"","semesterCounter":1,'
          '"semesters":[{"id":0,"name":"S1","courses":[]}],'
          '"startSeason":"","startYear":"","planCourses":[]}';

      final out = jsonDecode(AppState.decode(noRunning)!.encode()) as Map;
      final sem = (out['semesters'] as List).first as Map;
      expect(sem.containsKey('running'), isFalse,
          reason: 'adding a field would change the sync fingerprint for '
              'semantically identical data and trigger a spurious reload');
    });
  });

  group('matches the web sanitiser', () {
    test('drops a semester whose id is not a number', () {
      const stringId = '{"currentDept":"","semesterCounter":0,'
          '"semesters":[{"id":"sem_123","name":"S1","courses":[]}],'
          '"startSeason":"","startYear":"","planCourses":[]}';

      expect(AppState.decode(stringId)!.semesters, isEmpty,
          reason: 'the web filters on typeof sem.id !== "number"');
    });

    test('drops a summary block with an out-of-range CGPA', () {
      const badCgpa = '{"currentDept":"","semesterCounter":0,'
          '"semesters":[{"id":0,"summary":true,"summaryCGPA":9,'
          '"summaryCredits":12,"courses":[],"running":false}],'
          '"startSeason":"","startYear":"","planCourses":[]}';

      expect(AppState.decode(badCgpa)!.semesters, isEmpty);
    });

    test('defaults summaryAttempted to earned credits when absent', () {
      const noAttempted = '{"currentDept":"","semesterCounter":0,'
          '"semesters":[{"id":0,"summary":true,"summaryCGPA":3.5,'
          '"summaryCredits":30,"courses":[],"running":false}],'
          '"startSeason":"","startYear":"","planCourses":[]}';

      expect(AppState.decode(noAttempted)!.semesters.first.summaryAttempted, 30);
    });

    test('rejects a malformed department code', () {
      const badDept = '{"currentDept":"not-a-dept","semesterCounter":0,'
          '"semesters":[],"startSeason":"","startYear":"","planCourses":[]}';

      expect(AppState.decode(badDept)!.currentDept, '');
    });

    test('filters plan courses to valid course codes', () {
      const mixed = '{"currentDept":"","semesterCounter":0,"semesters":[],'
          '"startSeason":"","startYear":"",'
          '"planCourses":["CSE220","nope","MAT215A","x"]}';

      expect(AppState.decode(mixed)!.planCourses, ['CSE220', 'MAT215A']);
    });

    test('caps faculty initials at six uppercase characters', () {
      expect(sanitizeFaculty('abcdefghij'), 'ABCDEF');
      expect(sanitizeFaculty('mmr'), 'MMR');
      expect(sanitizeFaculty(null), '');
    });

    test('normalises out-of-range grade points', () {
      expect(sanitizeGradePoint(4), 4.0);
      expect(sanitizeGradePoint('NT'), 'NT');
      expect(sanitizeGradePoint(9), '');
      expect(sanitizeGradePoint(-1), '');
      expect(sanitizeGradePoint(null), '');
      expect(sanitizeGradePoint('3.7'), 3.7);
      expect(sanitizeGradePoint('rubbish'), '');
    });
  });

  group('decode failure modes', () {
    test('returns null for absent, empty, or malformed input', () {
      expect(AppState.decode(null), isNull);
      expect(AppState.decode(''), isNull);
      expect(AppState.decode('{not json'), isNull);
      expect(AppState.decode('[1,2,3]'), isNull);
    });

    test('tolerates a payload with no semesters key', () {
      final state = AppState.decode('{"currentDept":"CSE"}')!;
      expect(state.semesters, isEmpty);
      expect(state.semesterCounter, 0);
    });
  });

  group('Semester', () {
    test('computes GPA over graded courses only', () {
      final sem = Semester(id: 0, courses: [
        Course(name: 'A', credits: 3, grade: 'A'),
        Course(name: 'B', credits: 3, grade: 'P'),
        Course(name: 'C', credits: 3, grade: ''),
      ]);
      expect(sem.gpa, 4.0);
    });

    test('excludes failed courses from earned credits', () {
      final sem = Semester(id: 0, courses: [
        Course(name: 'A', credits: 3, grade: 'A'),
        Course(name: 'B', credits: 3, grade: 'F'),
      ]);
      expect(sem.totalCredits, 3);
    });
  });
}
