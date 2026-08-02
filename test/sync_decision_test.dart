import 'package:flutter_test/flutter_test.dart';
import 'package:shohoj/core/js_json.dart';
import 'package:shohoj/models/app_state.dart';
import 'package:shohoj/services/sync/sync_decision.dart';

/// Convenience wrapper so each test states only the guard it cares about.
RemoteAction decide({
  bool isFirstSnapshot = false,
  Duration sinceLocalWrite = const Duration(days: 1),
  bool hasPendingSave = false,
  String? localRaw = '{"a":1}',
  String? remoteRaw = '{"a":2}',
}) =>
    decideRemoteSnapshot(
      isFirstSnapshot: isFirstSnapshot,
      sinceLocalWrite: sinceLocalWrite,
      hasPendingSave: hasPendingSave,
      localRaw: localRaw,
      remoteRaw: remoteRaw,
    );

void main() {
  group('JavaScript-compatible encoding', () {
    test('narrows whole doubles to integers', () {
      expect(jsCompatJsonEncode({'credits': 3.0}), '{"credits":3}');
      expect(jsCompatJsonEncode({'n': -0.0}), '{"n":0}');
    });

    test('leaves fractional values alone', () {
      expect(jsCompatJsonEncode({'cgpa': 3.42}), '{"cgpa":3.42}');
      expect(jsCompatJsonEncode({'gp': 3.7}), '{"gp":3.7}');
    });

    test('recurses through maps and lists', () {
      expect(
        jsCompatJsonEncode({
          'semesters': [
            {'id': 0.0, 'courses': [
              {'credits': 3.0, 'gradePoint': 3.7}
            ]}
          ]
        }),
        '{"semesters":[{"id":0,"courses":[{"credits":3,"gradePoint":3.7}]}]}',
      );
    });

    test('leaves very large doubles alone', () {
      // JavaScript switches to exponential notation past 1e21, so narrowing
      // would not make the two encoders agree.
      expect(normaliseForJs(1e21), 1e21);
    });
  });

  group('fingerprint', () {
    test('ignores the metadata keys the web strips', () {
      expect(
        getDataFingerprint('{"a":1,"updatedAt":111}'),
        getDataFingerprint('{"a":1,"updatedAt":999}'),
      );
      expect(
        getDataFingerprint('{"a":1,"_serverTimestamp":111}'),
        getDataFingerprint('{"a":1}'),
      );
    });

    test('still distinguishes real content changes', () {
      expect(
        getDataFingerprint('{"a":1}') == getDataFingerprint('{"a":2}'),
        isFalse,
      );
    });

    test('treats JS and Dart number formatting as equal', () {
      expect(
        getDataFingerprint('{"credits":3}'),
        getDataFingerprint('{"credits":3.0}'),
        reason: 'otherwise every cross-client write looks like a change',
      );
    });

    test('is empty for absent or blank input', () {
      expect(getDataFingerprint(null), '');
      expect(getDataFingerprint(''), '');
    });

    test('falls back to the raw string for unparseable input', () {
      expect(getDataFingerprint('{not json'), '{not json');
      expect(
        getDataFingerprint('{not json'),
        getDataFingerprint('{not json'),
        reason: 'two equally-malformed payloads must not read as a change',
      );
    });
  });

  group('snapshot guards', () {
    test('ignores the first snapshot even when content differs', () {
      expect(decide(isFirstSnapshot: true), RemoteAction.ignoreFirstSnapshot);
    });

    test('ignores a snapshot echoing this client\'s own write', () {
      expect(
        decide(sinceLocalWrite: const Duration(milliseconds: 100)),
        RemoteAction.ignoreOwnWrite,
      );
    });

    test('applies once the own-write grace window has passed', () {
      expect(
        decide(sinceLocalWrite: kLocalWriteGrace + const Duration(milliseconds: 1)),
        RemoteAction.apply,
      );
    });

    test('ignores a snapshot while a local save is queued', () {
      expect(decide(hasPendingSave: true), RemoteAction.ignorePendingSave);
    });

    test('ignores an empty or absent payload', () {
      expect(decide(remoteRaw: null), RemoteAction.ignoreEmpty);
      expect(decide(remoteRaw: ''), RemoteAction.ignoreEmpty);
    });

    test('ignores identical content', () {
      expect(
        decide(localRaw: '{"a":1}', remoteRaw: '{"a":1}'),
        RemoteAction.ignoreIdentical,
      );
    });

    test('applies a genuine change from another device', () {
      expect(decide(), RemoteAction.apply);
    });

    test('applies when there is no local baseline yet', () {
      expect(decide(localRaw: null), RemoteAction.apply);
    });
  });

  group('guard precedence', () {
    // Ordering is load-bearing: a cheaper guard firing first is what stops an
    // in-progress edit being weighed against a stale cloud copy.

    test('first-snapshot beats every other guard', () {
      expect(
        decide(
          isFirstSnapshot: true,
          sinceLocalWrite: const Duration(milliseconds: 1),
          hasPendingSave: true,
          remoteRaw: null,
        ),
        RemoteAction.ignoreFirstSnapshot,
      );
    });

    test('own-write beats the pending-save guard', () {
      expect(
        decide(
          sinceLocalWrite: const Duration(milliseconds: 1),
          hasPendingSave: true,
        ),
        RemoteAction.ignoreOwnWrite,
      );
    });

    test('pending-save beats the content comparison', () {
      expect(
        decide(hasPendingSave: true, localRaw: '{"a":1}', remoteRaw: '{"a":1}'),
        RemoteAction.ignorePendingSave,
        reason: 'a queued edit must win before content is even compared',
      );
    });
  });

  group('cross-client byte compatibility', () {
    test('app encoding of a web payload is byte-identical', () {
      // Exactly what the web writes: integral values with no decimal point.
      const webRaw = '{"currentDept":"CSE","semesterCounter":1,'
          '"semesters":[{"id":0,"name":"Spring 2024","courses":['
          '{"name":"CSE110","credits":3,"grade":"A","gradePoint":4,"faculty":"MMR"}'
          '],"running":false}],'
          '"startSeason":"Spring","startYear":"2023","planCourses":["CSE220"]}';

      expect(
        AppState.decode(webRaw)!.encode(),
        webRaw,
        reason: 'a byte difference would make each client see the other\'s '
            'writes as a change and reload in a loop',
      );
    });

    test('fractional values survive the round-trip', () {
      const webRaw = '{"currentDept":"","semesterCounter":1,'
          '"semesters":[{"id":0,"summary":true,"summaryCGPA":3.42,'
          '"summaryCredits":36,"summaryAttempted":39,"summarySemesters":4,'
          '"courses":[],"running":false}],'
          '"startSeason":"","startYear":"","planCourses":[]}';

      expect(AppState.decode(webRaw)!.encode(), webRaw);
    });

    test('a decoded and re-encoded payload has an unchanged fingerprint', () {
      const webRaw = '{"currentDept":"CSE","semesterCounter":0,'
          '"semesters":[],"startSeason":"","startYear":"","planCourses":[]}';

      expect(
        getDataFingerprint(AppState.decode(webRaw)!.encode()),
        getDataFingerprint(webRaw),
      );
    });
  });
}
