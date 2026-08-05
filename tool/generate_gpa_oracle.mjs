// Regenerates test/oracle_fixture.json from the web app's real CGPA
// implementation, so the Dart port is pinned to the reference rather than to
// someone's reading of it.
//
//   node tool/generate_gpa_oracle.mjs > test/oracle_fixture.json
//
// Requires the Shohoj web repo checked out alongside this one. Rerun whenever
// the web's gpa-core.js changes; a diff in the parity test means the two
// clients would show different CGPAs for the same transcript.

import { calculateCgpaTotals } from '../../Shohoj/js/core/gpa-core.js';

const S = (id, courses, extra = {}) => ({ id, name: `S${id}`, courses, running: false, ...extra });
const C = (name, credits, grade) => ({ name, credits, grade });

const cases = {
  retake_latest: [S(0, [C('X (CSE111)', 3, 'F')]), S(1, [C('X (CSE111)', 3, 'A')])],
  retake_best:   [S(0, [C('X (CSE111)', 3, 'A')]), S(1, [C('X (CSE111)', 3, 'C')])],
  fnt_retaken:   [S(0, [C('Programming Language I (CSE110)', 3, 'C-')]),
                  S(1, [C('Programming Language II (CSE111)', 3, 'F(NT)')]),
                  S(2, [C('Programming Language II (CSE111)', 3, 'B')])],
  withdrawal:    [S(0, [C('X (CSE111)', 3, 'A'), C('Y (CSE112)', 3, 'W')])],
  w_no_supersede:[S(0, [C('X (CSE111)', 3, 'A')]), S(1, [C('X (CSE111)', 3, 'W')])],
  running:       [S(0, [C('A (X100)', 3, 'C')]), S(1, [C('B (X101)', 3, 'A')], { running: true })],
  summary:       [{ id: 0, summary: true, summaryCGPA: 3.0, summaryCredits: 30, summaryAttempted: 30, courses: [], running: false },
                  S(1, [C('A (X100)', 3, 'A')])],
  summary_att:   [{ id: 0, summary: true, summaryCGPA: 3.0, summaryCredits: 30, summaryAttempted: 36, courses: [], running: false }],
  pass_incomplete:[S(0, [C('A (X100)', 3, 'A'), C('B (X101)', 0, 'P'), C('C (X102)', 3, 'I')])],
  three_attempts:[S(0, [C('X (CSE111)', 3, 'F')]), S(1, [C('X (CSE111)', 3, 'C')]), S(2, [C('X (CSE111)', 3, 'A')])],
  fail_only:     [S(0, [C('A (X100)', 3, 'A'), C('B (X101)', 3, 'F')])],
};

const policies = { fall2024: { startSeason: 'Fall', startYear: '2024' },
                   spring2023: { startSeason: 'Spring', startYear: '2023' } };

const out = {};
for (const [name, sems] of Object.entries(cases)) {
  for (const [pname, opts] of Object.entries(policies)) {
    const t = calculateCgpaTotals(sems, opts);
    out[`${name}|${pname}`] = {
      cgpa: t.cgpa === null ? null : +t.cgpa.toFixed(6),
      cgpaCredits: t.cgpaCredits, attempted: t.attemptedCredits, earned: t.earnedCredits,
    };
  }
}
console.log(JSON.stringify(out, null, 0));
