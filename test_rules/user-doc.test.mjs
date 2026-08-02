// Does a write from the Flutter app pass the rules the web app deploys?
//
// This is the one claim the Dart test suite cannot check. `cloud_firestore` is
// a plugin behind platform channels, so nothing under `flutter test` reaches
// real rule evaluation. These tests run the web's actual rules against the
// payload shapes `FirestoreService.saveState` produces.

import { readFile } from 'node:fs/promises';
import { after, before, beforeEach, describe, it } from 'node:test';

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import { doc, getDoc, setDoc, serverTimestamp } from 'firebase/firestore';

const UID = 'student-uid';
const OTHER_UID = 'someone-else';

/// A token matching what Firebase issues for a BRACU Google sign-in. The rules
/// check the email pattern, email_verified, and sign_in_provider — all three.
const bracuToken = {
  email: 'student@g.bracu.ac.bd',
  email_verified: true,
  firebase: { sign_in_provider: 'google.com' },
};

/// Exactly what `AppState.encode()` produces for a minimal state.
const appPayload = JSON.stringify({
  currentDept: 'CSE',
  semesterCounter: 1,
  semesters: [{ id: 0, name: 'Spring 2024', courses: [], running: false }],
  startSeason: 'Spring',
  startYear: '2023',
  planCourses: [],
});

let testEnv;

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: 'shohoj-rules-test',
    firestore: {
      rules: await readFile(new URL('./.web-firestore.rules', import.meta.url), 'utf8'),
      host: '127.0.0.1',
      port: 8080,
    },
  });
});

after(async () => {
  await testEnv?.cleanup();
});

beforeEach(async () => {
  await testEnv.clearFirestore();
});

const asBracu = () => testEnv.authenticatedContext(UID, bracuToken).firestore();

describe('the app write shape', () => {
  it('is accepted from a verified BRACU Google account', async () => {
    await assertSucceeds(
      setDoc(doc(asBracu(), 'users', UID), {
        data: appPayload,
        updatedAt: serverTimestamp(),
      }),
    );
  });

  it('round-trips the payload back out', async () => {
    const ref = doc(asBracu(), 'users', UID);
    await setDoc(ref, { data: appPayload, updatedAt: serverTimestamp() });
    const snap = await assertSucceeds(getDoc(ref));
    if (snap.data().data !== appPayload) {
      throw new Error('payload did not survive the write');
    }
  });

  it('is accepted without an updatedAt field', async () => {
    // The rule only constrains updatedAt when present.
    await assertSucceeds(setDoc(doc(asBracu(), 'users', UID), { data: appPayload }));
  });
});

describe('the legacy semesters field', () => {
  // The whole reason saveState issues a FieldValue.delete(). hasOnly() is
  // evaluated against the *merged* result, so a leftover field from a
  // pre-contract app build would poison every subsequent write.

  it('is rejected when present alongside data', async () => {
    await assertFails(
      setDoc(doc(asBracu(), 'users', UID), {
        data: appPayload,
        updatedAt: serverTimestamp(),
        semesters: [{ id: 'sem_1' }],
      }),
    );
  });

  it('is rejected when a merge write leaves it in place', async () => {
    // Seed a pre-contract document with rules bypassed, the way a real
    // legacy account would already look.
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'users', UID), {
        semesters: [{ id: 'sem_1', label: 'Old' }],
      });
    });

    await assertFails(
      setDoc(
        doc(asBracu(), 'users', UID),
        { data: appPayload, updatedAt: serverTimestamp() },
        { merge: true },
      ),
    );
  });
});

describe('payload constraints', () => {
  it('rejects a non-string data field', async () => {
    await assertFails(
      setDoc(doc(asBracu(), 'users', UID), {
        data: { not: 'a string' },
        updatedAt: serverTimestamp(),
      }),
    );
  });

  it('rejects a payload over the 500 KB cap', async () => {
    await assertFails(
      setDoc(doc(asBracu(), 'users', UID), {
        data: 'x'.repeat(500_001),
        updatedAt: serverTimestamp(),
      }),
    );
  });

  it('accepts a payload just under the cap', async () => {
    await assertSucceeds(
      setDoc(doc(asBracu(), 'users', UID), {
        data: 'x'.repeat(500_000),
        updatedAt: serverTimestamp(),
      }),
    );
  });

  it('rejects a client-supplied updatedAt that is not the server time', async () => {
    await assertFails(
      setDoc(doc(asBracu(), 'users', UID), {
        data: appPayload,
        updatedAt: new Date('2020-01-01'),
      }),
    );
  });
});

describe('authentication', () => {
  const write = (db) =>
    setDoc(doc(db, 'users', UID), { data: appPayload, updatedAt: serverTimestamp() });

  it('rejects an unauthenticated write', async () => {
    await assertFails(write(testEnv.unauthenticatedContext().firestore()));
  });

  it('rejects a non-BRACU email', async () => {
    const db = testEnv
      .authenticatedContext(UID, { ...bracuToken, email: 'someone@gmail.com' })
      .firestore();
    await assertFails(write(db));
  });

  it('rejects an unverified email', async () => {
    const db = testEnv
      .authenticatedContext(UID, { ...bracuToken, email_verified: false })
      .firestore();
    await assertFails(write(db));
  });

  it('rejects a non-Google sign-in provider', async () => {
    const db = testEnv
      .authenticatedContext(UID, {
        ...bracuToken,
        firebase: { sign_in_provider: 'password' },
      })
      .firestore();
    await assertFails(write(db));
  });

  it("rejects writing another student's document", async () => {
    await assertFails(
      setDoc(doc(asBracu(), 'users', OTHER_UID), {
        data: appPayload,
        updatedAt: serverTimestamp(),
      }),
    );
  });

  it("rejects reading another student's document", async () => {
    await assertFails(getDoc(doc(asBracu(), 'users', OTHER_UID)));
  });
});
