import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shohoj/core/transcript.dart';

/// The same grade sheet the oracle generator uses.
final sheet = [
  'BRAC University',
  'GRADE SHEET (UNOFFICIAL)',
  'Name: Test Student',
  'Student ID: 24201402',
  'PROGRAM: B.Sc. in Computer Science and Engineering (CSE)',
  'SEMESTER: FALL 2024',
  'Course No', 'Course Title',
  'CSE110', 'Programming Language I',
  'ENG101', 'Fundamentals of English',
  'PHY111', 'Principles of Physics I',
  'Credits Earned Grade Grade Points',
  '3.00', '3.00', '3.00', '9.00', '9.00',
  'C-', 'B+', 'B-',
  '1.70', '3.30', '2.70', '2.57', '2.57',
  'GPA', 'CGPA',
  'SEMESTER: SPRING 2025',
  'CSE111', 'Programming Language II',
  'MAT110', 'Mathematics I: Differential Calculus',
  'and Coordinate Geometry',
  'Credits Earned Grade Grade Points',
  '3.00', '3.00', '6.00', '6.00',
  'F(NT)', 'B',
  '0.00', '3.00', '1.75', '2.20',
  'GPA', 'CGPA',
].join('\n');

const runOn =
    'SEMESTER: FALL 2024 CSE110 Programming Language I 3.00 A 4.00 '
    'ENG101 Fundamentals of English 3.00 B+ 3.30';

Map<String, dynamic> shape(TranscriptParseResult r) => {
      'detectedDept': r.detectedDept,
      'semesters': r.semesters
          .map((s) => {
                'name': s.name,
                'courses': s.courses
                    .map((c) => {
                          'name': c.name,
                          'credits': c.credits,
                          'grade': c.grade,
                          'gradePoint': c.gradePoint,
                        })
                    .toList(),
              })
          .toList(),
    };

/// The oracle is JSON, so `3.0` arrives as `3`. Compare numerically.
void expectShape(Map<String, dynamic> got, Map<String, dynamic> want, String why) {
  expect(got['detectedDept'], want['detectedDept'], reason: '$why dept');
  final gs = got['semesters'] as List;
  final ws = want['semesters'] as List;
  expect(gs.length, ws.length, reason: '$why semester count');

  for (var i = 0; i < ws.length; i++) {
    final g = gs[i] as Map<String, dynamic>;
    final w = ws[i] as Map<String, dynamic>;
    expect(g['name'], w['name'], reason: '$why semester $i name');

    final gc = g['courses'] as List;
    final wc = w['courses'] as List;
    expect(gc.length, wc.length, reason: '$why semester $i course count');

    for (var j = 0; j < wc.length; j++) {
      final a = gc[j] as Map<String, dynamic>;
      final b = wc[j] as Map<String, dynamic>;
      expect(a['name'], b['name'], reason: '$why course $j name');
      expect((a['credits'] as num).toDouble(),
          (b['credits'] as num).toDouble(), reason: '$why course $j credits');
      expect(a['grade'], b['grade'], reason: '$why course $j grade');

      final ag = a['gradePoint'], bg = b['gradePoint'];
      if (ag is num && bg is num) {
        expect(ag.toDouble(), bg.toDouble(), reason: '$why course $j gp');
      } else {
        expect(ag.toString(), bg.toString(), reason: '$why course $j gp');
      }
    }
  }
}

void main() {
  late Map<String, dynamic> oracle;

  setUpAll(() {
    oracle = jsonDecode(
      File('test/transcript_oracle_fixture.json').readAsStringSync(),
    ) as Map<String, dynamic>;
  });

  group('parity with the web', () {
    test('line normalisation matches', () {
      const inputs = [
        'CSE110Programming Language I',
        '  Fundamentals   of  English  3.00A-',
        'SEMESTER:FALL2024',
        'CSE111 3.00F ( NT )0.00',
        'PROGRAM:  B.Sc. in CSE',
      ];
      expect(inputs.map(normalizeTranscriptLine).toList(),
          (oracle['normalize_lines'] as List).cast<String>());
    });

    test('text normalisation matches', () {
      expect(normalizeTranscriptText('CSE110Intro\nSEMESTER:SPRING2025'),
          oracle['normalize_text']);
    });

    test('department detection matches', () {
      expect(
          detectDepartment(
              'PROGRAM: B.Sc. in Computer Science and Engineering (CSE) SEMESTER: FALL 2024'),
          oracle['dept_cse']);
      expect(detectDepartment('PROGRAM: B.Sc. in Computer Science SEMESTER: FALL 2024'),
          oracle['dept_cs']);
      expect(detectDepartment('PROGRAM: BSC EEE SEMESTER: FALL 2024'), oracle['dept_eee']);
      expect(detectDepartment('nothing here'), oracle['dept_none']);
      expect(detectDepartment(''), oracle['dept_empty']);
    });

    test('identity detection matches', () {
      final want = oracle['identity'] as Map<String, dynamic>;
      final got = detectStudentIdentity(
          'Name: Sourav Mondal Shuvo Student ID: 24201402 PROGRAM: CSE');
      expect(got.studentId, want['studentId']);
      expect(got.studentName, want['studentName']);

      final none = detectStudentIdentity('no identity');
      expect(none.studentId, isNull);
      expect(none.studentName, isNull);
    });

    test('semester name parsing matches', () {
      final want = oracle['semname_ok'] as Map<String, dynamic>;
      final got = parseSemesterName('Fall 2024')!;
      expect(got.season, want['season']);
      expect(got.year, want['year']);
      expect(parseSemesterName('nonsense'), isNull);
      expect(oracle['semname_bad'], isNull);
    });

    test('a full grade sheet parses identically', () {
      expectShape(shape(parseTranscriptText(sheet)),
          oracle['parse_sheet'] as Map<String, dynamic>, 'sheet');
    });

    test('the blob fallback parses identically', () {
      expectShape(shape(parseBlobFallback(runOn)),
          oracle['blob'] as Map<String, dynamic>, 'blob');
    });

    test('an unparseable blob matches', () {
      expectShape(shape(parseBlobFallback('nothing')),
          oracle['blob_empty'] as Map<String, dynamic>, 'blob_empty');
    });
  });

  group('behaviour worth stating directly', () {
    test('run-together tokens are separated before parsing', () {
      // pdf.js emits `CSE110Programming` and `3.00A-`; nothing downstream can
      // parse those, so normalisation has to repair them first.
      expect(normalizeTranscriptLine('CSE110Programming Language I'),
          'CSE110 Programming Language I');
      expect(normalizeTranscriptLine('Intro 3.00A-'), 'Intro 3.00 A-');
    });

    test('F (NT) collapses however it is spaced', () {
      expect(normalizeGradeToken('F (NT)'), 'F(NT)');
      expect(normalizeGradeToken('F(NT)'), 'F(NT)');
      expect(normalizeTranscriptLine('CSE111 3.00F ( NT )0.00'),
          'CSE111 3.00 F(NT) 0.00');
    });

    test('retake markers are stripped from the grade', () {
      expect(normalizeGradeToken('B(RT)'), 'B');
      expect(normalizeGradeToken('A-'), 'A-');
    });

    test('CS is not mistaken for CSE', () {
      expect(detectDepartment('PROGRAM: B.Sc. in Computer Science'),
          kDepartmentLabels['CS']);
      expect(detectDepartment('PROGRAM: B.Sc. in Computer Science and Engineering'),
          kDepartmentLabels['CSE']);
    });

    test('an unsupported layout is refused, not guessed at', () {
      // The web hands these to a legacy parser this port does not implement.
      // Returning a wrong transcript would be worse than returning none.
      final r = parseTranscriptText('SEMESTER: FALL 2024\nsome prose with no courses');
      expect(r.status, TranscriptParseStatus.unsupportedLayout);
      expect(r.semesters, isEmpty);
      expect(r.isOk, isFalse);
    });

    test('empty input is reported as empty, not as a failure to parse', () {
      expect(parseBlobFallback('').status, TranscriptParseStatus.empty);
    });

    test('multi-line course titles are joined', () {
      // "Mathematics I: Differential Calculus" / "and Coordinate Geometry"
      // arrive as two lines and belong to one course.
      final r = parseTranscriptText(sheet);
      final names = r.semesters.expand((s) => s.courses).map((c) => c.name);
      expect(names.any((n) => n.contains('and Coordinate Geometry')), isTrue);
    });
  });
}
