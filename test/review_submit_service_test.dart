import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shohoj/models/faculty_review.dart';
import 'package:shohoj/services/review_submit_service.dart';

const validRatings = {
  'teaching': 5,
  'marking': 4,
  'behavior': 4,
  'difficulty': 3,
  'workload': 3,
};

/// Builds a service whose HTTP layer returns a canned response, capturing the
/// request so tests can assert on what was actually sent.
({ReviewSubmitService service, List<http.Request> sent}) serviceReturning(
  int status, {
  String body = '{}',
  String? token = 'test-token',
}) {
  final sent = <http.Request>[];
  final client = MockClient((req) async {
    sent.add(req);
    return http.Response(body, status);
  });
  return (
    service: ReviewSubmitService(
      client: client,
      idToken: () async => token,
      baseUrl: 'https://worker.test',
    ),
    sent: sent,
  );
}

Future<SubmitResult> submitWith(
  ReviewSubmitService s, {
  String initials = 'MMR',
  String course = 'CSE110',
  Map<String, int> ratings = validRatings,
  String semester = '',
  String text = '',
}) =>
    s.submit(
      facultyInitials: initials,
      courseCode: course,
      ratings: ratings,
      semester: semester,
      text: text,
    );

void main() {
  group('the request', () {
    test('posts to /reviews with a bearer token', () async {
      final h = serviceReturning(201);
      await submitWith(h.service);

      expect(h.sent, hasLength(1));
      expect(h.sent.single.url.toString(), 'https://worker.test/reviews');
      expect(h.sent.single.headers['Authorization'], 'Bearer test-token');
    });

    test('sends the five dimensions and uppercased identifiers', () async {
      final h = serviceReturning(201);
      await submitWith(h.service, initials: 'mmr', course: 'cse110');

      final body = jsonDecode(h.sent.single.body) as Map<String, dynamic>;
      expect(body['facultyInitials'], 'MMR');
      expect(body['courseCode'], 'CSE110');
      expect(body['ratings'], validRatings);
    });

    test('never sends a document id', () async {
      // The Worker derives the id from the verified uid. A client-supplied id
      // would hand control of the pseudonymity hash to the caller.
      final h = serviceReturning(201);
      await submitWith(h.service);

      final body = jsonDecode(h.sent.single.body) as Map<String, dynamic>;
      expect(body.keys, isNot(contains('id')));
      expect(body.keys, isNot(contains('uid')));
      expect(body.keys,
          unorderedEquals(['facultyInitials', 'courseCode', 'ratings', 'semester', 'text']));
    });

    test('trims semester and text', () async {
      final h = serviceReturning(201);
      await submitWith(h.service, semester: '  Spring 2024  ', text: '  good  ');

      final body = jsonDecode(h.sent.single.body) as Map<String, dynamic>;
      expect(body['semester'], 'Spring 2024');
      expect(body['text'], 'good');
    });
  });

  group('local validation', () {
    Future<SubmitResult> reject(Future<SubmitResult> Function(ReviewSubmitService) f) async {
      final h = serviceReturning(201);
      final r = await f(h.service);
      expect(h.sent, isEmpty, reason: 'invalid input must not reach the network');
      return r;
    }

    test('rejects malformed initials', () async {
      final r = await reject((s) => submitWith(s, initials: 'M'));
      expect(r.outcome, SubmitOutcome.invalid);
      expect(r.message, contains('2–6 letters'));
    });

    test('rejects a malformed course code', () async {
      final r = await reject((s) => submitWith(s, course: 'NOPE'));
      expect(r.outcome, SubmitOutcome.invalid);
      expect(r.message, contains('course code'));
    });

    test('rejects a missing rating and names the dimension', () async {
      final ratings = Map<String, int>.from(validRatings)..remove('workload');
      final r = await reject((s) => submitWith(s, ratings: ratings));
      expect(r.outcome, SubmitOutcome.invalid);
      expect(r.message, contains('workload'));
    });

    test('rejects an out-of-range rating', () async {
      final ratings = Map<String, int>.from(validRatings)..['teaching'] = 9;
      final r = await reject((s) => submitWith(s, ratings: ratings));
      expect(r.outcome, SubmitOutcome.invalid);
    });

    test('refuses over-long text rather than truncating it', () async {
      // Storing a different review than the one written is worse than saying
      // it is too long. The Worker takes the same position.
      final r = await reject((s) => submitWith(s, text: 'x' * (kMaxReviewTextChars + 1)));
      expect(r.outcome, SubmitOutcome.invalid);
      expect(r.message, contains('$kMaxReviewTextChars characters'));
    });

    test('accepts text exactly at the cap', () async {
      final h = serviceReturning(201);
      final r = await submitWith(h.service, text: 'x' * kMaxReviewTextChars);
      expect(r.isSuccess, isTrue);
    });

    test('rejects an over-long semester', () async {
      final r = await reject(
          (s) => submitWith(s, semester: 'x' * (kMaxReviewSemesterChars + 1)));
      expect(r.outcome, SubmitOutcome.invalid);
    });

    test('accepts every rating key the Worker requires', () async {
      expect(validRatings.keys, unorderedEquals(kRatingKeys));
    });
  });

  group('response handling', () {
    test('201 is success', () async {
      final r = await submitWith(serviceReturning(201).service);
      expect(r.outcome, SubmitOutcome.success);
    });

    test('409 reports the duplicate specifically', () async {
      final h = serviceReturning(409,
          body: '{"error":"You have already reviewed this faculty for this course"}');
      final r = await submitWith(h.service);
      expect(r.outcome, SubmitOutcome.duplicate);
      expect(r.message, contains('already reviewed'));
    });

    test('400 surfaces the Worker reason', () async {
      final h = serviceReturning(400, body: '{"error":"Unknown course code"}');
      final r = await submitWith(h.service);
      expect(r.outcome, SubmitOutcome.rejected);
      expect(r.message, 'Unknown course code',
          reason: 'the specific reason beats a generic failure');
    });

    test('400 with an unparseable body still gives a usable message', () async {
      final h = serviceReturning(400, body: '<html>gateway</html>');
      final r = await submitWith(h.service);
      expect(r.outcome, SubmitOutcome.rejected);
      expect(r.message, isNotEmpty);
    });

    test('401 asks the user to sign in again', () async {
      final r = await submitWith(serviceReturning(401).service);
      expect(r.outcome, SubmitOutcome.unauthenticated);
    });

    test('403 is reported as not permitted', () async {
      final r = await submitWith(serviceReturning(403).service);
      expect(r.outcome, SubmitOutcome.rejected);
    });

    test('429 is reported as rate limiting', () async {
      final r = await submitWith(serviceReturning(429).service);
      expect(r.outcome, SubmitOutcome.rateLimited);
    });

    test('502 and 503 are server errors', () async {
      expect((await submitWith(serviceReturning(502).service)).outcome,
          SubmitOutcome.serverError);
      expect((await submitWith(serviceReturning(503).service)).outcome,
          SubmitOutcome.serverError);
    });

    test('every outcome carries a non-empty message', () async {
      for (final status in [201, 400, 401, 403, 409, 429, 502]) {
        final r = await submitWith(serviceReturning(status).service);
        expect(r.message, isNotEmpty, reason: 'status $status');
      }
    });
  });

  group('preconditions', () {
    test('no token means unauthenticated, with nothing sent', () async {
      final h = serviceReturning(201, token: null);
      final r = await submitWith(h.service);
      expect(r.outcome, SubmitOutcome.unauthenticated);
      expect(h.sent, isEmpty);
    });

    test('no configured Worker URL disables submission', () async {
      final service = ReviewSubmitService(
        client: MockClient((_) async => http.Response('{}', 201)),
        idToken: () async => 'token',
        baseUrl: '',
      );
      final r = await submitWith(service);
      expect(r.outcome, SubmitOutcome.notConfigured);
    });

    test('a network failure is a result, not an exception', () async {
      final service = ReviewSubmitService(
        client: MockClient((_) async => throw const SocketExceptionStub()),
        idToken: () async => 'token',
        baseUrl: 'https://worker.test',
      );
      final r = await submitWith(service);
      expect(r.outcome, SubmitOutcome.networkError);
    });
  });
}

/// Stands in for a transport failure without importing dart:io, which is
/// unavailable on some test platforms.
class SocketExceptionStub implements Exception {
  const SocketExceptionStub();
}
