// Generates lib/data/prerequisites.dart from the web app's catalog and planner
// core, so the two stay in step without hand-transcribing 286 prerequisite
// entries.
//
//   node tool/generate_prereq_data.mjs > lib/data/prerequisites.dart
//
// Requires the Shohoj web repo checked out alongside this one.

import { readFileSync } from 'node:fs';
import { PREREQS } from '../../Shohoj/js/core/catalog.js';

// DEPT_PREFIXES and COMMON_PREFIXES are module-private in planner-core.js, so
// they are read out of the source rather than imported.
const src = readFileSync(new URL('../../Shohoj/js/core/planner-core.js', import.meta.url), 'utf8');
const grab = (name) => {
  const start = src.indexOf(`const ${name} =`);
  if (start < 0) throw new Error(`${name} not found in planner-core.js`);
  const open = src.indexOf(name.endsWith('PREFIXES') && src[src.indexOf('=', start) + 2] === '[' ? '[' : '{', start);
  let depth = 0;
  for (let i = open; i < src.length; i++) {
    if (src[i] === '{' || src[i] === '[') depth++;
    if (src[i] === '}' || src[i] === ']') { depth--; if (depth === 0) return src.slice(open, i + 1); }
  }
  throw new Error(`unterminated ${name}`);
};

const deptPrefixes = eval(`(${grab('DEPT_PREFIXES')})`);
const commonPrefixes = eval(`(${grab('COMMON_PREFIXES')})`);

const q = (s) => `'${String(s).replace(/\\/g, '\\\\').replace(/'/g, "\\'")}'`;
const list = (xs) => `[${xs.map(q).join(', ')}]`;

const prereqEntries = Object.entries(PREREQS).sort(([a], [b]) => a.localeCompare(b));

console.log(`// GENERATED — do not edit by hand.
//
// Regenerate with:
//   node tool/generate_prereq_data.mjs > lib/data/prerequisites.dart
//
// Source of truth is the Shohoj web repo: PREREQS in js/core/catalog.js and the
// prefix maps in js/core/planner-core.js. Editing this file directly means the
// app and the website disagree about what unlocks what.

/// Hard and soft prerequisites per course code.
///
/// \`hp\` must be completed before the course can be taken. \`sp\` is recommended
/// and surfaces as a warning rather than a blocker.
class Prereq {
  final List<String> hp;
  final List<String> sp;
  const Prereq({this.hp = const [], this.sp = const []});
}

const Map<String, Prereq> kPrereqs = {`);

for (const [code, p] of prereqEntries) {
  const parts = [];
  if (p.hp?.length) parts.push(`hp: ${list(p.hp)}`);
  if (p.sp?.length) parts.push(`sp: ${list(p.sp)}`);
  console.log(`  ${q(code)}: Prereq(${parts.join(', ')}),`);
}

console.log(`};

/// Course-code prefixes each department treats as its own.
const Map<String, List<String>> kDeptPrefixes = {`);
for (const [dept, prefixes] of Object.entries(deptPrefixes)) {
  console.log(`  ${q(dept)}: ${list(prefixes)},`);
}
console.log(`};

/// Prefixes every department counts as relevant.
const List<String> kCommonPrefixes = ${list(commonPrefixes)};`);
