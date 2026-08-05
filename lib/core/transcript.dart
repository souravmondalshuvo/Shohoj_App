library;

/// BRACU grade-sheet parsing, ported from the web's `js/import/transcript-core.js`.
///
/// A divergence here does not fail — it silently produces a wrong transcript,
/// and therefore a wrong CGPA. The parser is differential-tested against the
/// web; keep the two in step.

const Map<String, String> kDepartmentLabels = {
  'CSE': 'B.Sc. in Computer Science and Engineering (CSE)',
  'EEE': 'BSc EEE — Electrical & Electronic Engineering',
  'BBA': 'Bachelor of Business Administration (BBA)',
  'ECO': 'B.S.S. in Economics (ECO)',
  'ENG': 'B.A. in English (ENG)',
  'ARC': 'B.Arch. in Architecture (ARC)',
  'PHR': 'B.Sc. in Pharmacy (PHR)',
  'LAW': 'Bachelor of Laws (LLB)',
  'CS': 'B.Sc. in Computer Science (CS)',
  'ECE': 'B.Sc. in Electronic & Communication Engineering (ECE)',
  'ANT': 'B.S.S. in Anthropology (ANT)',
  'PHY': 'B.Sc. in Physics (PHY)',
  'APE': 'B.Sc. in Applied Physics & Electronics (APE)',
  'MAT': 'B.Sc. in Mathematics (MAT)',
  'MIC': 'B.Sc. in Microbiology (MIC)',
  'BIO': 'B.Sc. in Biotechnology (BIO)',
};

String _label(String key) => kDepartmentLabels[key]!;

/// Ordered — the first match wins, so narrower patterns come first. CS must be
/// tested after CSE, and PHY after APE, or the broader name swallows them.
final List<(String, RegExp)> _programDetectors = [
  (_label('CSE'), RegExp(r'COMPUTER\s+SCIENCE\s+AND\s+ENGINEERING|\bCSE\b', caseSensitive: false)),
  (_label('CS'), RegExp(r'COMPUTER\s+SCIENCE(?!\s+AND\s+ENGINEERING)|\bCS\b', caseSensitive: false)),
  (_label('EEE'), RegExp(r'ELECTRICAL\s*(?:&|AND)\s*ELECTRONIC\s+ENGINEERING|\bBSC\s*EEE\b|\bEEE\b', caseSensitive: false)),
  (_label('ECE'), RegExp(r'ELECTRONIC\s*(?:&|AND)\s*COMMUNICATION\s+ENGINEERING|\bECE\b', caseSensitive: false)),
  (_label('BBA'), RegExp(r'BUSINESS\s+ADMINISTRATION|\bBBA\b', caseSensitive: false)),
  (_label('ECO'), RegExp(r'ECONOMICS|\bECO\b', caseSensitive: false)),
  (_label('ENG'), RegExp(r'ENGLISH|\bENG\b', caseSensitive: false)),
  (_label('ARC'), RegExp(r'ARCHITECTURE|\bARCH\b|\bARC\b', caseSensitive: false)),
  (_label('PHR'), RegExp(r'PHARMACY|\bPHR\b', caseSensitive: false)),
  (_label('LAW'), RegExp(r'BACHELOR\s+OF\s+LAWS|\bLL\.?B\b|\bLAW\b', caseSensitive: false)),
  (_label('ANT'), RegExp(r'ANTHROPOLOGY|\bANT\b', caseSensitive: false)),
  (_label('APE'), RegExp(r'APPLIED\s+PHYSICS\s*(?:&|AND)\s*ELECTRONICS|\bAPE\b', caseSensitive: false)),
  (_label('PHY'), RegExp(r'PHYSICS(?!\s*(?:&|AND)\s*ELECTRONICS)|\bPHY\b', caseSensitive: false)),
  (_label('MAT'), RegExp(r'MATHEMATICS|\bMAT\b', caseSensitive: false)),
  (_label('MIC'), RegExp(r'MICROBIOLOGY|\bMIC\b', caseSensitive: false)),
  (_label('BIO'), RegExp(r'BIOTECHNOLOGY|\bBIO\b', caseSensitive: false)),
];

final List<(String, RegExp)> _textDetectors = [
  (_label('CSE'), RegExp(r'\bB\.?\s*SC\.?\s+IN\s+COMPUTER\s+SCIENCE\s+AND\s+ENGINEERING\b|COMPUTER\s+SCIENCE\s+AND\s+ENGINEERING|\bCSE\b', caseSensitive: false)),
  (_label('EEE'), RegExp(r'\bBSC\s*EEE\b|\bELECTRICAL\s*(?:&|AND)\s*ELECTRONIC\s+ENGINEERING\b', caseSensitive: false)),
  (_label('BBA'), RegExp(r'\bBACHELOR\s+OF\s+BUSINESS\s+ADMINISTRATION\b|\bBBA\b', caseSensitive: false)),
  (_label('ECO'), RegExp(r'\bB\.?\s*S\.?\s*S\.?\s+IN\s+ECONOMICS\b|\bSOCIAL\s+SCIENCE.*ECONOMICS\b', caseSensitive: false)),
  (_label('ENG'), RegExp(r'\bB\.?\s*A\.?\s+IN\s+ENGLISH\b|\bBACHELOR\s+OF\s+ARTS\s+IN\s+ENGLISH\b', caseSensitive: false)),
  (_label('ARC'), RegExp(r'\bB\.?\s*ARCH\.?\b|\bBACHELOR\s+OF\s+ARCHITECTURE\b', caseSensitive: false)),
  (_label('PHR'), RegExp(r'\bB\.?\s*SC\.?\s+IN\s+PHARMACY\b|\bBACHELOR\s+OF\s+SCIENCE\s+IN\s+PHARMACY\b', caseSensitive: false)),
  (_label('LAW'), RegExp(r'\bBACHELOR\s+OF\s+LAWS\b|\bLL\.?B\b', caseSensitive: false)),
  (_label('CS'), RegExp(r'\bB\.?\s*SC\.?\s+IN\s+COMPUTER\s+SCIENCE\b(?!\s+AND\s+ENGINEERING)|\bBACHELOR\s+OF\s+SCIENCE\s+IN\s+COMPUTER\s+SCIENCE\b(?!\s+AND\s+ENGINEERING)', caseSensitive: false)),
  (_label('ECE'), RegExp(r'\bB\.?\s*SC\.?\s+IN\s+ELECTRONIC\s*(?:&|AND)\s*COMMUNICATION\s+ENGINEERING\b|\bELECTRONIC\s*(?:&|AND)\s*COMMUNICATION\s+ENGINEERING\b', caseSensitive: false)),
  (_label('ANT'), RegExp(r'\bB\.?\s*S\.?\s*S\.?\s+IN\s+ANTHROPOLOGY\b|\bBACHELOR\s+OF\s+SOCIAL\s+SCIENCE\s+IN\s+ANTHROPOLOGY\b', caseSensitive: false)),
  (_label('APE'), RegExp(r'\bB\.?\s*SC\.?\s+IN\s+APPLIED\s+PHYSICS\s*(?:&|AND)\s*ELECTRONICS\b|\bAPPLIED\s+PHYSICS\s*(?:&|AND)\s*ELECTRONICS\b', caseSensitive: false)),
  (_label('PHY'), RegExp(r'\bB\.?\s*SC\.?\s+IN\s+PHYSICS\b|\bBACHELOR\s+OF\s+SCIENCE\s+IN\s+PHYSICS\b', caseSensitive: false)),
  (_label('MAT'), RegExp(r'\bB\.?\s*SC\.?\s+IN\s+MATHEMATICS\b|\bBACHELOR\s+OF\s+SCIENCE\s+IN\s+MATHEMATICS\b', caseSensitive: false)),
  (_label('MIC'), RegExp(r'\bB\.?\s*SC\.?\s+IN\s+MICROBIOLOGY\b|\bBACHELOR\s+OF\s+SCIENCE\s+IN\s+MICROBIOLOGY\b', caseSensitive: false)),
  (_label('BIO'), RegExp(r'\bB\.?\s*SC\.?\s+IN\s+BIOTECHNOLOGY\b|\bBACHELOR\s+OF\s+SCIENCE\s+IN\s+BIOTECHNOLOGY\b', caseSensitive: false)),
];

const Map<String, String> _seasonNames = {
  'SPRING': 'Spring',
  'SUMMER': 'Summer',
  'FALL': 'Fall',
};

/// The degree programme named in the transcript, or null.
///
/// The `PROGRAM:` line is preferred; only if that yields nothing does the whole
/// document get searched, which is looser and more prone to a stray match.
String? detectDepartment(String? text) {
  final compact = (text ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
  if (compact.isEmpty) return null;

  final programMatch = RegExp(
    r'PROGRAM:\s*(.+?)(?=SEMESTER:|COURSE\s+NO|COURSE\s+TITLE|CREDITS\s+EARNED|GRADE\s+POINTS|GRADE\s+SHEET|STUDENT\s+ID|NAME\b|$)',
    caseSensitive: false,
  ).firstMatch(compact);

  final programText = programMatch?.group(1)?.trim() ?? '';
  if (programText.isNotEmpty) {
    for (final (label, pattern) in _programDetectors) {
      if (pattern.hasMatch(programText)) return label;
    }
  }

  for (final (label, pattern) in _textDetectors) {
    if (pattern.hasMatch(compact)) return label;
  }
  return null;
}

class StudentIdentity {
  final String? studentId;
  final String? studentName;
  const StudentIdentity({this.studentId, this.studentName});
}

StudentIdentity detectStudentIdentity(String? text) {
  final compact = (text ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
  if (compact.isEmpty) return const StudentIdentity();

  String? studentId;
  final idMatch =
      RegExp(r'STUDENT\s*ID\s*:?\s*(\d{7,8})\b', caseSensitive: false).firstMatch(compact) ??
          RegExp(r'\bID\s*:?\s*(\d{8})\b', caseSensitive: false).firstMatch(compact);
  if (idMatch != null) studentId = idMatch.group(1);

  String? studentName;
  final nameMatch = RegExp(
    r"\bNAME\s*:?\s*([A-Za-z][A-Za-z.\s'-]{1,58}?)\s*(?=\b(?:PROGRAM|STUDENT\s*ID|SEMESTER|ID|DATE|GRADE\s+SHEET|COURSE|CREDITS|UNDERGRADUATE|UNDERGRAD|POSTGRADUATE|GRADUATE)\b|$)",
    caseSensitive: false,
  ).firstMatch(compact);
  if (nameMatch != null) {
    final cleaned = nameMatch.group(1)!.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (cleaned.isNotEmpty && !RegExp(r'^\d+$').hasMatch(cleaned)) {
      studentName = cleaned;
    }
  }

  return StudentIdentity(studentId: studentId, studentName: studentName);
}

/// Repairs a single line of PDF-extracted text.
///
/// Extraction runs tokens together — `CSE110Programming`, `3.00A-` — so this
/// reinserts the spaces the layout implied before anything tries to parse it.
String normalizeTranscriptLine(String? line) {
  var s = (line ?? '').replaceAll(' ', ' ').trim();
  if (s.isEmpty) return '';

  s = s.replaceAll(RegExp(r'\s+'), ' ');
  s = s.replaceAllMapped(
      RegExp(r'^(SEMESTER|PROGRAM)\s*:\s*', caseSensitive: false),
      (m) => '${m.group(1)}: ');
  s = s.replaceAllMapped(
      RegExp(r'\b(SPRING|SUMMER|FALL)(\d{4})\b', caseSensitive: false),
      (m) => '${m.group(1)} ${m.group(2)}');
  s = s.replaceFirstMapped(
      RegExp(r'^([A-Z]{2,4}\d{3}[A-Z]?)(?=[A-Z])'), (m) => '${m.group(1)} ');
  s = s.replaceAllMapped(
      RegExp(r'([A-Za-z)])(?=\d+\.\d+)'), (m) => '${m.group(1)} ');
  s = s.replaceAllMapped(
      RegExp(r'(\d+\.\d+)(?=F\s*\(\s*NT\s*\)|[A-Z][+-]?)'), (m) => '${m.group(1)} ');
  s = s.replaceAllMapped(
      RegExp(r'(F\s*\(\s*NT\s*\)|[A-Z][+-]?)(?=\d+\.\d+)'), (m) => '${m.group(1)} ');
  s = s.replaceAll(RegExp(r'F\s*\(\s*NT\s*\)', caseSensitive: false), 'F(NT)');
  s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
  return s;
}

String normalizeTranscriptText(String? text) => (text ?? '')
    .split(RegExp(r'\r?\n'))
    .map(normalizeTranscriptLine)
    .join('\n');

class SemesterTerm {
  final String season;
  final int year;
  const SemesterTerm(this.season, this.year);
}

SemesterTerm? parseSemesterName(String name) {
  final m = RegExp(r'(Spring|Summer|Fall)\s+(\d{4})').firstMatch(name);
  if (m == null) return null;
  return SemesterTerm(m.group(1)!, int.parse(m.group(2)!));
}

/// Strips retake and no-transfer markers, collapsing `F (NT)` to `F(NT)`.
String normalizeGradeToken(String raw) {
  if (RegExp(r'F.*NT', caseSensitive: false).hasMatch(raw)) return 'F(NT)';
  return raw
      .trim()
      .replaceAll(RegExp(r'\s+'), '')
      .replaceAll('(RT)', '')
      .replaceAll('(NT)', '')
      .trim();
}

/// One parsed course, before it becomes a `Course`.
class ParsedCourse {
  final String name;
  final double credits;
  final String grade;

  /// A `double`, the string `'NT'`, or `''` — matching what the web stores.
  final Object gradePoint;

  const ParsedCourse({
    required this.name,
    required this.credits,
    required this.grade,
    required this.gradePoint,
  });
}

class ParsedSemester {
  final String name;
  final List<ParsedCourse> courses;
  const ParsedSemester({required this.name, required this.courses});
}

enum TranscriptParseStatus {
  ok,

  /// Nothing recognisable — not a BRACU grade sheet, or not text at all.
  empty,

  /// Semesters were found but the layout is one only the web's legacy parser
  /// handles. Deliberately not guessed at.
  unsupportedLayout,
}

class TranscriptParseResult {
  final TranscriptParseStatus status;
  final List<ParsedSemester> semesters;
  final String? detectedDept;

  const TranscriptParseResult({
    required this.status,
    this.semesters = const [],
    this.detectedDept,
  });

  bool get isOk => status == TranscriptParseStatus.ok;
}

/// Zips a flat column of values back onto per-semester course counts.
///
/// The two extra positions skipped after each semester are its GPA and
/// cumulative-CGPA rows, which sit in the same column as the course values.
List<Object?> _extractCourseValues(List<Object?> raw, List<int> counts) {
  final out = <Object?>[];
  var position = 0;
  for (final count in counts) {
    for (var i = 0; i < count; i++) {
      out.add(position < raw.length ? raw[position] : null);
      position++;
    }
    position += 2;
  }
  return out;
}

/// Last-resort parse for text with no usable line structure.
///
/// Treats the whole document as one blob and pulls out
/// `CODE … credits grade gradePoint` runs between semester headers.
TranscriptParseResult parseBlobFallback(String text) {
  final normalizedText = normalizeTranscriptText(text);
  final blob = normalizedText.replaceAll(RegExp(r'\s+'), ' ');

  final semMatches = RegExp(r'SEMESTER[:\s]+([A-Z]+)\s*(\d{4})', caseSensitive: false)
      .allMatches(blob)
      .toList();
  if (semMatches.isEmpty) {
    return const TranscriptParseResult(status: TranscriptParseStatus.empty);
  }

  final courseRe = RegExp(
      r'\b([A-Z]{2,4}\d{3}[A-Z]?)\b(.{1,120}?)\b(\d+\.\d+)\s+((?:[A-Z][+-]?)(?:\((?:NT|RT)\))|[A-Z][+-]?)\s+(\d+\.\d+)');

  final semesters = <ParsedSemester>[];
  for (var i = 0; i < semMatches.length; i++) {
    final m = semMatches[i];
    final season = m.group(1)!.toUpperCase();
    final name = '${_seasonNames[season] ?? m.group(1)} ${m.group(2)}';
    final sliceEnd = i + 1 < semMatches.length ? semMatches[i + 1].start : blob.length;
    final slice = blob.substring(m.start, sliceEnd);

    final courses = <ParsedCourse>[];
    for (final cm in courseRe.allMatches(slice)) {
      final code = cm.group(1)!;
      final title = (cm.group(2) ?? '').trim().replaceAll(RegExp(r'\s{2,}'), ' ');
      final credits = double.tryParse(cm.group(3)!);
      final grade = cm.group(4)!.replaceFirst('(RT)', '').trim();
      final gradePoint = double.tryParse(cm.group(5)!);
      if (credits != null && credits > 0) {
        courses.add(ParsedCourse(
          name: '$code $title'.trim(),
          credits: credits,
          grade: grade,
          gradePoint: gradePoint ?? '',
        ));
      }
    }

    if (courses.isNotEmpty) {
      semesters.add(ParsedSemester(name: name, courses: courses));
    }
  }

  return TranscriptParseResult(
    status: semesters.isEmpty
        ? TranscriptParseStatus.empty
        : TranscriptParseStatus.ok,
    semesters: semesters,
    detectedDept: detectDepartment(normalizedText),
  );
}

class _WorkingSemester {
  final String name;
  final List<String> codes = [];
  final List<String> titles = [];
  _WorkingSemester(this.name);
}

/// Parses a BRACU grade sheet.
///
/// The PDF emits course codes and titles first, then credits, grades and grade
/// points as separate later columns, so the courses are collected in order and
/// the value columns zipped back on afterwards.
///
/// Layouts that the web would hand to its legacy parser return
/// [TranscriptParseStatus.unsupportedLayout] rather than a guess — a wrong
/// transcript is worse than a refused one.
TranscriptParseResult parseTranscriptText(String text) {
  final normalizedText = normalizeTranscriptText(text);
  final lines = normalizedText
      .split('\n')
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .toList();
  final detectedDept = detectDepartment(normalizedText);

  final semRe = RegExp(r'^SEMESTER:\s*([A-Z]+)\s*(\d{4})\b', caseSensitive: false);
  final codeRe = RegExp(r'^([A-Z]{2,4}\d{3}[A-Z]?)$');
  final codeStartRe = RegExp(r'^([A-Z]{2,4}\d{3}[A-Z]?)(?:\s*(?:\d|\.\d))');
  final numberRe = RegExp(r'^\d+\.\d+$');
  final gradeRe = RegExp(r'^([A-Z][+-]?(?:\s*\((?:NT|RT)\))?)$');
  final skipRe = RegExp(
      r'^(SEMESTER\b(?!:)|CUMULATIVE\s+Credits|Credits\s+(Attempted|Earned)|GPA$|CGPA$|BRAC\s+University|Kha\s+224|Merul|GRADE\s+SHEET|UNOFFICIAL|Student\s+ID|^Name$|Course\s+No|Course\s+Title|UNDERGRADUATE|PROGRAM:|Page\s+\d|Credits\s+Earned\s+Grade|Grade\s+Points)',
      caseSensitive: false);

  final working = <_WorkingSemester>[];
  _WorkingSemester? current;
  String? lastExtText;
  var lastExtIndex = -1;
  var lastExtOrigLen = 0;

  for (final line in lines) {
    if (skipRe.hasMatch(line)) continue;
    if (numberRe.hasMatch(line)) continue;
    if (gradeRe.hasMatch(line)) continue;

    final semesterMatch = semRe.firstMatch(line);
    if (semesterMatch != null) {
      final season = semesterMatch.group(1)!.toUpperCase();
      current = _WorkingSemester(
          '${_seasonNames[season] ?? semesterMatch.group(1)} ${semesterMatch.group(2)}');
      working.add(current);
      lastExtText = null;
      lastExtIndex = -1;
      continue;
    }

    if (current == null) continue;

    final codeMatch = codeRe.firstMatch(line);
    if (codeMatch != null) {
      current.codes.add(codeMatch.group(1)!);
      lastExtText = null;
      lastExtIndex = -1;
      continue;
    }

    final compactCodeMatch = codeStartRe.firstMatch(line);
    if (compactCodeMatch != null) {
      current.codes.add(compactCodeMatch.group(1)!);
      // A title line that looked like a continuation turned out to belong to
      // the next course; undo the append and re-file it.
      if (lastExtText != null &&
          lastExtIndex >= 0 &&
          lastExtIndex < current.titles.length) {
        current.titles[lastExtIndex] =
            current.titles[lastExtIndex].substring(0, lastExtOrigLen);
        current.titles.add(lastExtText);
      }
      lastExtText = null;
      lastExtIndex = -1;
      continue;
    }

    if (!RegExp(r'\d').hasMatch(line[0])) {
      if (current.titles.length < current.codes.length) {
        current.titles.add(line);
        lastExtText = null;
        lastExtIndex = -1;
      } else if (current.titles.isNotEmpty) {
        lastExtOrigLen = current.titles.last.length;
        lastExtText = line;
        lastExtIndex = current.titles.length - 1;
        current.titles[current.titles.length - 1] = '${current.titles.last} $line';
      }
    }
  }

  final counts = working.map((s) => s.codes.length).toList();
  final totalCourses = counts.fold<int>(0, (a, b) => a + b);
  if (totalCourses == 0) {
    return TranscriptParseResult(
      status: TranscriptParseStatus.unsupportedLayout,
      detectedDept: detectedDept,
    );
  }

  var creditsBlockStart = -1;
  for (var i = lines.length - 1; i >= 0; i--) {
    if (!RegExp(r'^Credits\s+Earned\b', caseSensitive: false).hasMatch(lines[i])) {
      continue;
    }
    for (var j = i + 1; j <= i + 4 && j < lines.length; j++) {
      if (numberRe.hasMatch(lines[j])) {
        creditsBlockStart = j;
        break;
      }
    }
    if (creditsBlockStart >= 0) break;
  }
  if (creditsBlockStart < 0) {
    return TranscriptParseResult(
      status: TranscriptParseStatus.unsupportedLayout,
      detectedDept: detectedDept,
    );
  }

  final creditsRaw = <Object?>[];
  final gradesRaw = <String>[];
  final gpRaw = <Object?>[];
  var phase = 'credits';

  for (var i = creditsBlockStart; i < lines.length; i++) {
    final line = lines[i];
    if (line == 'GPA' || line == 'CGPA') continue;

    if (phase == 'credits') {
      if (numberRe.hasMatch(line)) {
        creditsRaw.add(double.parse(line));
        continue;
      }
      if (gradeRe.hasMatch(line)) phase = 'grades';
    }

    if (phase == 'grades') {
      if (numberRe.hasMatch(line)) {
        phase = 'gp';
        gpRaw.add(double.parse(line));
        continue;
      }
      if (gradeRe.hasMatch(line)) {
        gradesRaw.add(normalizeGradeToken(line));
        continue;
      }
    }

    if (phase == 'gp' && numberRe.hasMatch(line)) {
      gpRaw.add(double.parse(line));
    }
  }

  final allCredits = _extractCourseValues(creditsRaw, counts);
  final allGradePoints = _extractCourseValues(gpRaw, counts);

  final semesters = <ParsedSemester>[];
  var flatIndex = 0;
  for (final semester in working) {
    final courses = <ParsedCourse>[];
    for (var index = 0; index < semester.codes.length; index++) {
      final code = semester.codes[index];
      final title = index < semester.titles.length ? semester.titles[index] : '';
      courses.add(ParsedCourse(
        name: title.isNotEmpty ? '$title ($code)' : code,
        credits: (allCredits.elementAtOrNull(flatIndex) as double?) ?? 0,
        grade: flatIndex < gradesRaw.length ? gradesRaw[flatIndex] : '',
        gradePoint: allGradePoints.elementAtOrNull(flatIndex) ?? '',
      ));
      flatIndex++;
    }
    if (courses.isNotEmpty) {
      semesters.add(ParsedSemester(name: semester.name, courses: courses));
    }
  }

  if (semesters.isEmpty) {
    return TranscriptParseResult(
      status: TranscriptParseStatus.unsupportedLayout,
      detectedDept: detectedDept,
    );
  }

  return TranscriptParseResult(
    status: TranscriptParseStatus.ok,
    semesters: semesters,
    detectedDept: detectedDept,
  );
}
