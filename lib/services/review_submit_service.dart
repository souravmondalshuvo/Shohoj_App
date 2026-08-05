import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import '../models/faculty_review.dart';

/// Shape rules mirrored from the Worker's `validateReviewPayload`.
///
/// Checked client-side so an obvious mistake gets an instant, specific message
/// instead of a round trip. The Worker re-checks everything — this is a
/// convenience, never the enforcement point.
final RegExp kInitialsPattern = RegExp(r'^[A-Z]{2,6}$');
final RegExp kCourseCodePattern = RegExp(r'^[A-Z]{2,4}[0-9]{3}[A-Z]?$');

const int kMaxReviewTextChars = 500;
const int kMaxReviewSemesterChars = 40;

enum SubmitOutcome {
  success,

  /// Failed our own checks; never sent.
  invalid,

  /// The Worker rejected the payload.
  rejected,

  /// One review per user per faculty-course pair already exists.
  duplicate,

  /// Token missing or expired.
  unauthenticated,

  rateLimited,

  /// Worker or Firestore unavailable.
  serverError,

  /// Could not reach the Worker at all.
  networkError,

  /// No Worker URL in this build.
  notConfigured,
}

class SubmitResult {
  final SubmitOutcome outcome;

  /// Safe to show the user verbatim.
  final String message;

  const SubmitResult(this.outcome, this.message);

  bool get isSuccess => outcome == SubmitOutcome.success;
}

/// Submits reviews through the Cloudflare Worker.
///
/// The Worker is the only writer to `facultyReviews`: it derives the document
/// id from the verified uid server-side, which is what makes the corpus
/// pseudonymous. This class must never construct an id or write to Firestore
/// directly — doing so would hand the client control of the hash and defeat the
/// guarantee.
class ReviewSubmitService {
  ReviewSubmitService({
    http.Client? client,
    Future<String?> Function()? idToken,
    String? baseUrl,
  })  : _client = client ?? http.Client(),
        _idToken = idToken ?? _firebaseIdToken,
        _baseUrl = baseUrl ?? AppConfig.workerBase;

  final http.Client _client;
  final Future<String?> Function() _idToken;
  final String _baseUrl;

  static Future<String?> _firebaseIdToken() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    return user.getIdToken();
  }

  /// Validates locally, then posts. Never throws — every failure is a result.
  Future<SubmitResult> submit({
    required String facultyInitials,
    required String courseCode,
    required Map<String, int> ratings,
    String semester = '',
    String text = '',
  }) async {
    if (_baseUrl.isEmpty) {
      return const SubmitResult(
        SubmitOutcome.notConfigured,
        'Review submission is not available in this build.',
      );
    }

    final initials = facultyInitials.trim().toUpperCase();
    final code = courseCode.trim().toUpperCase();

    final localError = _validate(initials, code, ratings, semester, text);
    if (localError != null) {
      return SubmitResult(SubmitOutcome.invalid, localError);
    }

    final token = await _idToken();
    if (token == null || token.isEmpty) {
      return const SubmitResult(
        SubmitOutcome.unauthenticated,
        'Sign in with your BRACU account to post a review.',
      );
    }

    http.Response res;
    try {
      res = await _client.post(
        Uri.parse('$_baseUrl/reviews'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'facultyInitials': initials,
          'courseCode': code,
          'ratings': ratings,
          'semester': semester.trim(),
          'text': text.trim(),
        }),
      );
    } catch (_) {
      return const SubmitResult(
        SubmitOutcome.networkError,
        'Could not reach the server. Check your connection and try again.',
      );
    }

    return _interpret(res);
  }

  String? _validate(
    String initials,
    String code,
    Map<String, int> ratings,
    String semester,
    String text,
  ) {
    if (!kInitialsPattern.hasMatch(initials)) {
      return 'Faculty initials must be 2–6 letters, e.g. MMR.';
    }
    if (!kCourseCodePattern.hasMatch(code)) {
      return 'Enter a valid course code, e.g. CSE110.';
    }
    for (final key in kRatingKeys) {
      final v = ratings[key];
      if (v == null || v < 1 || v > 5) {
        return 'Rate ${kRatingLabels[key]!.toLowerCase()} from 1 to 5.';
      }
    }
    if (semester.trim().length > kMaxReviewSemesterChars) {
      return 'Semester must be $kMaxReviewSemesterChars characters or fewer.';
    }
    // Refused rather than truncated: silently storing a different review than
    // the one written is worse than saying it is too long. The Worker takes the
    // same position.
    if (text.trim().length > kMaxReviewTextChars) {
      return 'Review must be $kMaxReviewTextChars characters or fewer.';
    }
    return null;
  }

  SubmitResult _interpret(http.Response res) {
    if (res.statusCode == 201 || res.statusCode == 200) {
      return const SubmitResult(SubmitOutcome.success, 'Review posted.');
    }

    final serverMessage = _errorFrom(res.body);

    switch (res.statusCode) {
      case 400:
        return SubmitResult(
          SubmitOutcome.rejected,
          serverMessage ?? 'That review was rejected. Check the details and try again.',
        );
      case 401:
        return const SubmitResult(
          SubmitOutcome.unauthenticated,
          'Your session expired. Sign in again and retry.',
        );
      case 403:
        return const SubmitResult(
          SubmitOutcome.rejected,
          'This app is not permitted to post reviews.',
        );
      case 409:
        return SubmitResult(
          SubmitOutcome.duplicate,
          serverMessage ?? 'You have already reviewed this faculty for this course.',
        );
      case 429:
        return const SubmitResult(
          SubmitOutcome.rateLimited,
          'Too many requests. Wait a moment and try again.',
        );
      default:
        return const SubmitResult(
          SubmitOutcome.serverError,
          'The server could not save the review. Try again later.',
        );
    }
  }

  /// Pulls `{"error": "..."}` out of a response body.
  ///
  /// The Worker's 400s carry the specific reason — unknown course code, a
  /// rating out of range — which is more useful than anything generic.
  static String? _errorFrom(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map && decoded['error'] is String) {
        final msg = (decoded['error'] as String).trim();
        return msg.isEmpty ? null : msg;
      }
    } catch (_) {
      // Non-JSON body — fall through to the caller's default.
    }
    return null;
  }
}
