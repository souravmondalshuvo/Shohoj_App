// Regenerates test/transcript_oracle_fixture.json from the web's parser.
//
//   node tool/generate_transcript_oracle.mjs > test/transcript_oracle_fixture.json
//
// Requires the Shohoj web repo checked out alongside this one.

import {
  parseTranscriptText, parseBlobFallback, detectDepartment,
  detectStudentIdentity, normalizeTranscriptLine, normalizeTranscriptText,
  parseSemesterName,
} from '../../Shohoj/js/import/transcript-core.js';

// A grade sheet in the column layout pdf.js produces: codes and titles first,
// then credits, grades and grade points as separate blocks. The two extra
// numbers after each semester's credits are its GPA and cumulative CGPA.
const sheet = [
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

const runOn = ['SEMESTER: FALL 2024 CSE110 Programming Language I 3.00 A 4.00 ENG101 Fundamentals of English 3.00 B+ 3.30'];

const shape = (r) => ({
  detectedDept: r.detectedDept ?? null,
  semesters: r.semesters.map(s => ({
    name: s.name,
    courses: s.courses.map(c => ({
      name: c.name, credits: c.credits, grade: c.grade,
      gradePoint: typeof c.gradePoint === 'number' ? c.gradePoint : (c.gradePoint ?? ''),
    })),
  })),
});

console.log(JSON.stringify({
  normalize_lines: [
    'CSE110Programming Language I',
    '  Fundamentals   of  English  3.00A-',
    'SEMESTER:FALL2024',
    'CSE111 3.00F ( NT )0.00',
    'PROGRAM:  B.Sc. in CSE',
  ].map(normalizeTranscriptLine),
  normalize_text: normalizeTranscriptText('CSE110Intro\nSEMESTER:SPRING2025'),
  dept_cse: detectDepartment('PROGRAM: B.Sc. in Computer Science and Engineering (CSE) SEMESTER: FALL 2024'),
  dept_cs: detectDepartment('PROGRAM: B.Sc. in Computer Science SEMESTER: FALL 2024'),
  dept_eee: detectDepartment('PROGRAM: BSC EEE SEMESTER: FALL 2024'),
  dept_none: detectDepartment('nothing here'),
  dept_empty: detectDepartment(''),
  identity: detectStudentIdentity('Name: Sourav Mondal Shuvo Student ID: 24201402 PROGRAM: CSE'),
  identity_none: detectStudentIdentity('no identity'),
  semname_ok: parseSemesterName('Fall 2024'),
  semname_bad: parseSemesterName('nonsense'),
  parse_sheet: shape(parseTranscriptText(sheet)),
  parse_empty: shape(parseTranscriptText('')),
  blob: shape(parseBlobFallback(runOn[0])),
  blob_empty: shape(parseBlobFallback('nothing')),
}, null, 0));
