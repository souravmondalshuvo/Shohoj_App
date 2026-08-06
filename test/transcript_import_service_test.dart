import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shohoj/core/transcript.dart';
import 'package:shohoj/screens/transcript_import_sheet.dart';
import 'package:shohoj/services/transcript_import_service.dart';

/// A grade sheet the parser handles, in the column layout pdf.js produces.
const sheetText = '''
PROGRAM: B.Sc. in Computer Science and Engineering (CSE)
SEMESTER: FALL 2024
CSE110
Programming Language I
ENG101
Fundamentals of English
Credits Earned Grade Grade Points
3.00
3.00
6.00
6.00
A
B+
4.00
3.30
3.65
3.65
''';

PlatformFile fakeFile({String name = 'grades.pdf', Uint8List? bytes}) =>
    PlatformFile(
      name: name,
      size: bytes?.length ?? 4,
      bytes: bytes ?? Uint8List.fromList([1, 2, 3, 4]),
    );

TranscriptImportService serviceThat({
  PlatformFile? picks,
  String? extracts,
  Object? throwsOnExtract,
}) =>
    TranscriptImportService(
      pickFile: () async => picks,
      extractText: (_) async {
        if (throwsOnExtract != null) throw throwsOnExtract;
        return extracts ?? '';
      },
    );

void main() {
  group('failure paths', () {
    test('a dismissed picker is cancelled, not an error', () async {
      final r = await serviceThat(picks: null).importTranscript();
      expect(r.failure, ImportFailure.cancelled);
      expect(r.isSuccess, isFalse);
    });

    test('an empty file is unreadable', () async {
      final r = await serviceThat(
        picks: fakeFile(bytes: Uint8List(0)),
        extracts: sheetText,
      ).importTranscript();
      expect(r.failure, ImportFailure.unreadable);
    });

    test('an extraction failure is reported, not thrown', () async {
      final r = await serviceThat(
        picks: fakeFile(),
        throwsOnExtract: StateError('not a pdf'),
      ).importTranscript();
      expect(r.failure, ImportFailure.unreadable);
    });

    test('a PDF with no text is called out as a scan', () async {
      final r = await serviceThat(picks: fakeFile(), extracts: '   ')
          .importTranscript();
      expect(r.failure, ImportFailure.noText);
      expect(r.message, contains('scan'));
    });

    test('text that is not a grade sheet is rejected', () async {
      final r = await serviceThat(
        picks: fakeFile(),
        extracts: 'Dear student, your enrolment is confirmed.',
      ).importTranscript();
      expect(r.failure, ImportFailure.notATranscript);
    });

    test('a layout the parser cannot handle is refused, not guessed', () async {
      final r = await serviceThat(
        picks: fakeFile(),
        extracts: 'SEMESTER: FALL 2024\nsome prose but no courses',
      ).importTranscript();
      expect(r.failure, ImportFailure.unsupportedLayout);
      expect(r.message, contains('website'),
          reason: 'the message should point somewhere that works');
    });

    test('every failure carries an actionable message', () async {
      for (final f in ImportFailure.values) {
        final o = ImportOutcome.failed(f);
        expect(o.message, isNotEmpty, reason: f.name);
      }
    });

    test('the file name is kept for the error message', () async {
      final r = await serviceThat(
        picks: fakeFile(name: 'my grades.pdf', bytes: Uint8List(0)),
        extracts: '',
      ).importTranscript();
      expect(r.fileName, 'my grades.pdf');
    });
  });

  group('success path', () {
    test('parses a grade sheet and reports the file name', () async {
      final r = await serviceThat(picks: fakeFile(), extracts: sheetText)
          .importTranscript();

      expect(r.isSuccess, isTrue);
      expect(r.fileName, 'grades.pdf');
      expect(r.result!.status, TranscriptParseStatus.ok);
      expect(r.result!.semesters, hasLength(1));
      expect(r.result!.detectedDept, contains('Computer Science'));
    });
  });

  group('converting to semesters', () {
    test('ids are ints, allocated in order', () {
      // The web discards any semester whose id is not a number.
      final parsed = parseTranscriptText(sheetText);
      final semesters = semestersFromParsed(parsed.semesters);
      expect(semesters.map((s) => s.id), [0]);
      expect(semesters.first.id, isA<int>());
    });

    test('honours a starting id so ids stay unique', () {
      final parsed = parseTranscriptText(sheetText);
      expect(semestersFromParsed(parsed.semesters, startingId: 7).first.id, 7);
    });

    test('carries grade, credits and the stored grade point across', () {
      final parsed = parseTranscriptText(sheetText);
      final course = semestersFromParsed(parsed.semesters).first.courses.first;
      expect(course.name, contains('CSE110'));
      expect(course.credits, 3.0);
      expect(course.grade, 'A');
      expect(course.storedGradePoint, 4.0);
    });

    test('an empty parse yields no semesters', () {
      expect(semestersFromParsed(const []), isEmpty);
    });
  });
}
