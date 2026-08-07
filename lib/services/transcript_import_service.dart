import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:pdfrx/pdfrx.dart';

import '../core/transcript.dart';

/// Why an import did not produce a transcript.
enum ImportFailure {
  /// The picker was dismissed.
  cancelled,

  /// The picker itself failed — the plugin threw rather than returning a file.
  pickerUnavailable,

  /// The file could not be opened as a PDF.
  unreadable,

  /// A PDF, but no text — almost always a scan rather than a generated sheet.
  noText,

  /// Text, but nothing resembling a BRACU grade sheet.
  notATranscript,

  /// Recognisable, but in a layout this parser does not handle.
  unsupportedLayout,
}

class ImportOutcome {
  final TranscriptParseResult? result;
  final ImportFailure? failure;
  final String? fileName;

  const ImportOutcome._({this.result, this.failure, this.fileName});

  const ImportOutcome.success(TranscriptParseResult result, String fileName)
      : this._(result: result, fileName: fileName);

  const ImportOutcome.failed(ImportFailure failure, {String? fileName})
      : this._(failure: failure, fileName: fileName);

  bool get isSuccess => result != null;

  /// A message that says what to do next, not just what went wrong.
  String get message => switch (failure) {
        ImportFailure.cancelled => 'No file selected.',
        ImportFailure.pickerUnavailable =>
          'The file picker could not be opened. Check that Shohoj is allowed '
              'to access your files, then try again.',
        ImportFailure.unreadable =>
          'That file could not be opened as a PDF. Make sure it is the grade '
              'sheet downloaded from CONNECT.',
        ImportFailure.noText =>
          'This PDF has no readable text — it looks like a scan or a photo. '
              'Download the grade sheet directly from CONNECT rather than '
              'scanning a printout.',
        ImportFailure.notATranscript =>
          'No semesters found. This does not look like a BRACU grade sheet.',
        ImportFailure.unsupportedLayout =>
          'This grade sheet uses a layout the app cannot read yet. Import it '
              'on the Shohoj website instead — it will sync here afterwards.',
        null => '',
      };
}

/// Picks a grade-sheet PDF, extracts its text, and parses it.
///
/// Every failure is a value. An import that half-works would write a wrong
/// transcript, and a wrong transcript is a wrong CGPA — so anything short of a
/// confident parse comes back as a typed failure with an actionable message.
class TranscriptImportService {
  TranscriptImportService({this.pickFile, this.extractText});

  /// Injectable for tests; defaults to the real picker.
  final Future<PlatformFile?> Function()? pickFile;

  /// Injectable for tests; defaults to pdfrx.
  final Future<String> Function(Uint8List bytes)? extractText;

  Future<ImportOutcome> importTranscript() async {
    final PlatformFile? file;
    try {
      file = await (pickFile ?? _pickPdf)();
    } catch (_) {
      // A throwing picker must still come back as a value — the caller resets
      // its spinner on the outcome, not in a finally.
      return const ImportOutcome.failed(ImportFailure.pickerUnavailable);
    }

    if (file == null) {
      return const ImportOutcome.failed(ImportFailure.cancelled);
    }

    final bytes = file.bytes;
    if (bytes == null || bytes.isEmpty) {
      return ImportOutcome.failed(ImportFailure.unreadable, fileName: file.name);
    }

    String text;
    try {
      text = await (extractText ?? _extractPdfText)(bytes);
    } catch (_) {
      return ImportOutcome.failed(ImportFailure.unreadable, fileName: file.name);
    }

    if (text.trim().isEmpty) {
      return ImportOutcome.failed(ImportFailure.noText, fileName: file.name);
    }

    final parsed = parseTranscriptText(text);
    return switch (parsed.status) {
      TranscriptParseStatus.ok => ImportOutcome.success(parsed, file.name),
      TranscriptParseStatus.unsupportedLayout =>
        ImportOutcome.failed(ImportFailure.unsupportedLayout, fileName: file.name),
      TranscriptParseStatus.empty =>
        ImportOutcome.failed(ImportFailure.notATranscript, fileName: file.name),
    };
  }

  static Future<PlatformFile?> _pickPdf() async {
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      // Bytes rather than a path: on Android the picker hands back a content
      // URI that is not a readable filesystem path.
      withData: true,
    );
    return picked?.files.singleOrNull;
  }

  static Future<String> _extractPdfText(Uint8List bytes) async {
    final doc = await PdfDocument.openData(bytes);
    try {
      final buffer = StringBuffer();
      for (var i = 1; i <= doc.pages.length; i++) {
        final pageText = await doc.pages[i - 1].loadText();
        if (pageText != null) buffer.writeln(pageText.fullText);
      }
      return buffer.toString();
    } finally {
      doc.dispose();
    }
  }
}
