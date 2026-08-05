// Regenerates test/playground_oracle_fixture.json.
//
//   node tool/generate_playground_oracle.mjs > test/playground_oracle_fixture.json
//
// Requires the Shohoj web repo checked out alongside this one.
// Mirrors getCurrentTotals / getGradedCourses / computeSolverResult from
// js/ui/playground.js. Those live inside a DOM-bound module, so the pure parts
// are transcribed here and cross-checked against getRetakenKeys from gpa-core.
import { GRADES } from '../../Shohoj/js/core/grades.js';
import { getRetakenKeys } from '../../Shohoj/js/core/gpa-core.js';

function currentTotals(semesters, opts) {
  const rk = getRetakenKeys(semesters, opts);
  let pts = 0, cr = 0;
  const summaryBlock = semesters.find(s => s.summary);
  if (summaryBlock) { pts += summaryBlock.summaryCGPA * summaryBlock.summaryCredits; cr += summaryBlock.summaryCredits; }
  semesters.forEach(sem => {
    if (sem.summary) return;
    sem.courses.forEach((c, i) => {
      const gp = GRADES[c.grade];
      if (gp === undefined || gp === null || !c.credits) return;
      if (c.grade === 'P' || c.grade === 'I' || c.grade === 'F(NT)') return;
      if (rk.has(`${sem.id}-${i}`)) return;
      pts += gp * c.credits; cr += c.credits;
    });
  });
  return { pts, cr, cgpa: cr > 0 ? pts / cr : null };
}

function gradedCourses(semesters, opts) {
  const rk = getRetakenKeys(semesters, opts);
  const out = [];
  semesters.forEach(sem => {
    if (sem.summary) return;
    sem.courses.forEach((c, i) => {
      if (!c.name.trim() || !c.grade) return;
      if (['P','I','F(NT)','W'].includes(c.grade)) return;
      const gp = GRADES[c.grade];
      if (gp === undefined || gp === null) return;
      if (rk.has(`${sem.id}-${i}`)) return;
      out.push({ key: `${sem.id}-${i}`, credits: c.credits, grade: c.grade, gp });
    });
  });
  return out;
}

function solve(courses, totals, key, target) {
  const c = courses.find(x => x.key === key);
  if (!c || isNaN(target) || target < 0 || target > 4.0) return { outcome: 'invalid' };
  const neededGp = (target * totals.cr - totals.pts + c.credits * c.gp) / c.credits;
  const sorted = Object.entries(GRADES).filter(([, gp]) => gp !== null && gp !== undefined)
    .map(([g, gp]) => ({ g, gp })).sort((a, b) => a.gp - b.gp);
  if (neededGp > 4.0) {
    return { outcome: 'impossible', needed: +neededGp.toFixed(6),
             resulting: +((totals.pts - c.credits * c.gp + c.credits * 4.0) / totals.cr).toFixed(6) };
  }
  if (neededGp <= 0) return { outcome: 'alreadyMet', needed: +neededGp.toFixed(6), resulting: +totals.cgpa.toFixed(6) };
  const min = sorted.find(x => x.gp >= neededGp);
  if (!min) return { outcome: 'invalid' };
  return { outcome: 'reachable', grade: min.g, gp: min.gp, needed: +neededGp.toFixed(6),
           resulting: +((totals.pts - c.credits * c.gp + c.credits * min.gp) / totals.cr).toFixed(6) };
}

function changes(courses, totals, map) {
  let pts = totals.pts; const cr = totals.cr; const impacts = [];
  for (const [key, ng] of Object.entries(map)) {
    const c = courses.find(x => x.key === key); if (!c) continue;
    const newGp = GRADES[ng]; if (newGp === null || newGp === undefined) continue;
    const delta = c.credits * (newGp - c.gp); pts += delta;
    impacts.push({ key, delta: +delta.toFixed(6), impact: +(cr > 0 ? delta / cr : 0).toFixed(6) });
  }
  return { projected: cr > 0 ? +(pts / cr).toFixed(6) : null, impacts };
}

const S = (id, courses, extra = {}) => ({ id, name: `S${id}`, courses, running: false, ...extra });
const C = (name, credits, grade) => ({ name, credits, grade });

const transcript = [
  S(0, [C('Programming Language I (CSE110)', 3, 'C-'), C('Fundamentals of English (ENG101)', 3, 'B+'),
        C('Remedial Course in Mathematics (MAT092)', 0, 'P'), C('Principles of Physics I (PHY111)', 3, 'B-')]),
  S(1, [C('Programming Language II (CSE111)', 3, 'F(NT)'), C('Calculus (MAT110)', 3, 'C')]),
  S(2, [C('Programming Language II (CSE111)', 3, 'B'), C('Discrete Math (CSE221)', 3, 'A-'), C('Dropped (CSE230)', 3, 'W')]),
];
const withSummary = [{ id: 9, summary: true, summaryCGPA: 3.0, summaryCredits: 30, summaryAttempted: 33, courses: [], running: false }, ...transcript];
const opts = { startSeason: 'Fall', startYear: '2024' };

const t = currentTotals(transcript, opts), gc = gradedCourses(transcript, opts);
const ts = currentTotals(withSummary, opts), gcs = gradedCourses(withSummary, opts);

console.log(JSON.stringify({
  totals: { pts: +t.pts.toFixed(6), cr: t.cr, cgpa: +t.cgpa.toFixed(6) },
  totals_summary: { pts: +ts.pts.toFixed(6), cr: ts.cr, cgpa: +ts.cgpa.toFixed(6) },
  eligible: gc.map(c => c.key),
  eligible_summary: gcs.map(c => c.key),
  solve_reachable: solve(gc, t, '0-0', 3.0),
  solve_impossible: solve(gc, t, '0-0', 4.0),
  solve_alreadymet: solve(gc, t, 1.0),
  solve_met2: solve(gc, t, '0-0', 1.0),
  solve_badtarget: solve(gc, t, '0-0', 5.0),
  change_one: changes(gc, t, { '0-0': 'A' }),
  change_many: changes(gc, t, { '0-0': 'A', '1-1': 'A' }),
  change_worse: changes(gc, t, { '2-1': 'D' }),
}, null, 0));
