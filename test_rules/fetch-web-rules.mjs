// Fetches the Firestore rules from the Shohoj web repo.
//
// The web repo is the single source of truth for rules (both repos deploy to
// the same Firebase project). Fetching rather than vendoring a copy is
// deliberate: a copy would drift, and a drifted copy tests nothing — it would
// go green while production rejected every write from this app.
//
// Failing loudly on a fetch error is also deliberate. Falling back to a stale
// local file would turn a network blip into a false pass.

import { writeFile } from 'node:fs/promises';

const RULES_URL =
  'https://raw.githubusercontent.com/souravmondalshuvo/Shohoj/main/firestore.rules';

const OUT = new URL('./.web-firestore.rules', import.meta.url);

const res = await fetch(RULES_URL);
if (!res.ok) {
  console.error(
    `Could not fetch the web app's firestore.rules (HTTP ${res.status}).\n` +
      `URL: ${RULES_URL}\n` +
      'These tests assert this app writes payloads the web accepts, so a stale ' +
      'or missing rules file would make them meaningless. Refusing to run.',
  );
  process.exit(1);
}

const rules = await res.text();
if (!rules.includes('match /users/{uid}')) {
  console.error(
    'Fetched a rules file with no users/{uid} block. Either the URL is wrong ' +
      'or the web repo restructured its rules.',
  );
  process.exit(1);
}

await writeFile(OUT, rules, 'utf8');
console.log(`Fetched ${rules.length} bytes of rules from the web repo.`);
