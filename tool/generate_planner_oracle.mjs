// Regenerates test/planner_oracle_fixture.json from the web's planner-core.js.
//
//   node tool/generate_planner_oracle.mjs > test/planner_oracle_fixture.json
//
// Requires the Shohoj web repo checked out alongside this one.

import {
  getCompletedCodes, getInProgressCodes, getScheduledCodes, checkPrereqs,
  buildUnlockCountMap, isRelevantToDept, getAvailableCourses, validatePlan,
  getPrereqChain, projectCgpa,
} from '../../Shohoj/js/core/planner-core.js';
import { PREREQS } from '../../Shohoj/js/core/catalog.js';
import { getRetakenKeys } from '../../Shohoj/js/core/gpa-core.js';

const S = (id, courses, extra = {}) => ({ id, name: `S${id}`, courses, running: false, ...extra });
const C = (name, credits, grade) => ({ name, credits, grade });

const semesters = [
  S(0, [C('Programming Language I (CSE110)', 3, 'B'), C('Principles of Physics I (PHY111)', 3, 'B-')]),
  S(1, [C('Programming Language II (CSE111)', 3, 'F'), C('Calculus (MAT110)', 3, 'C')]),
  S(2, [C('Programming Language II (CSE111)', 3, 'A'), C('Data Structures (CSE220)', 3, '')]),
  S(3, [C('Algorithms (CSE221)', 3, '')], { running: true }),
];

const opts = { startSeason: 'Fall', startYear: '2024' };
const rk = getRetakenKeys(semesters, opts);

const catalog = {
  CSE110: { code: 'CSE110', name: 'Programming Language I', credits: 3 },
  CSE111: { code: 'CSE111', name: 'Programming Language II', credits: 3 },
  CSE220: { code: 'CSE220', name: 'Data Structures', credits: 3 },
  CSE221: { code: 'CSE221', name: 'Algorithms', credits: 3 },
  CSE230: { code: 'CSE230', name: 'Discrete Mathematics', credits: 3 },
  CSE250: { code: 'CSE250', name: 'Circuits and Electronics', credits: 3 },
  CSE310: { code: 'CSE310', name: 'Object Oriented Programming', credits: 3 },
  CSE320: { code: 'CSE320', name: 'Data Communications', credits: 3 },
  CSE331: { code: 'CSE331', name: 'Automata', credits: 3 },
  PHY111: { code: 'PHY111', name: 'Principles of Physics I', credits: 3 },
  MAT110: { code: 'MAT110', name: 'Calculus', credits: 3 },
  MAT120: { code: 'MAT120', name: 'Calculus II', credits: 3 },
  ENG101: { code: 'ENG101', name: 'Fundamentals of English', credits: 3 },
  BUS102: { code: 'BUS102', name: 'Business Basics', credits: 3 },
};
const allCourses = Object.values(catalog);

const completed = getCompletedCodes(semesters, rk);
const planCourses = ['CSE310', 'CSE331'];

const avail = (options) => getAvailableCourses(
  { semesters, retakenKeys: rk, prerequisites: PREREQS, allCourses, planCourses: [], currentDept: 'CSE' },
  options,
).map(c => ({ code: c.code, canTake: c.canTake, unlockCount: c.unlockCount, isRelevant: c.isRelevant, missingHp: c.missingHp }));

const flatten = (node) => node && ({
  code: node.code, completed: node.completed, isSoft: !!node.isSoft,
  children: node.children.map(flatten),
});

console.log(JSON.stringify({
  completed: [...completed].sort(),
  inProgress: [...getInProgressCodes(semesters)].sort(),
  scheduled: [...getScheduledCodes(semesters)].sort(),
  unlock_CSE110: buildUnlockCountMap(PREREQS)['CSE110'] ?? 0,
  unlock_CSE220: buildUnlockCountMap(PREREQS)['CSE220'] ?? 0,
  relevant_CSE_cse: isRelevantToDept('CSE310', 'CSE'),
  relevant_CSE_bus: isRelevantToDept('BUS102', 'CSE'),
  relevant_CSE_mat: isRelevantToDept('MAT120', 'CSE'),
  relevant_nodept: isRelevantToDept('BUS102', ''),
  check_CSE221: checkPrereqs('CSE221', completed, PREREQS),
  check_CSE310: checkPrereqs('CSE310', completed, PREREQS),
  check_unknown: checkPrereqs('ZZZ999', completed, PREREQS),
  available_all: avail({}),
  available_unlocked: avail({ filterMode: 'unlocked' }),
  available_locked: avail({ filterMode: 'locked' }),
  available_search: avail({ searchQuery: 'program' }),
  available_limit: avail({ limit: 3 }),
  validate: validatePlan({ semesters, retakenKeys: rk, prerequisites: PREREQS, courseCatalog: catalog, planCourses }),
  validate_overload: validatePlan({ semesters, retakenKeys: rk, prerequisites: PREREQS, courseCatalog: catalog,
    planCourses: ['CSE310','CSE331','CSE320','CSE250','MAT120','ENG101'] }),
  validate_dupe: validatePlan({ semesters, retakenKeys: rk, prerequisites: PREREQS, courseCatalog: catalog,
    planCourses: ['CSE110','CSE220','CSE221'] }),
  chain_CSE331: flatten(getPrereqChain('CSE331', completed, catalog, PREREQS)),
  project_A: projectCgpa(100, 40, 12, 'A'),
  project_bad: projectCgpa(100, 40, 12, 'P'),
}, null, 0));
