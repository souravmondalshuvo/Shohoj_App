import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/app_state.dart';
import '../models/semester.dart';
import 'sync/user_state_store.dart';

class DifficultyEntry {
  final String courseCode;
  final String courseName;
  final double avgDifficulty;
  final double avgRating;
  final int reviewCount;
  const DifficultyEntry({
    required this.courseCode,
    required this.courseName,
    required this.avgDifficulty,
    required this.avgRating,
    required this.reviewCount,
  });
}

class FirestoreService implements UserStateStore {
  final _db = FirebaseFirestore.instance;

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  DocumentReference? get _userDoc =>
      _uid != null ? _db.collection('users').doc(_uid) : null;

  // ── User state (shared with the web app) ───────────────────────────────────
  //
  // `users/{uid}` is owned jointly with the Shohoj web app and has exactly two
  // fields: `data` (the whole state as a JSON string) and `updatedAt`. The web's
  // security rules enforce `keys().hasOnly(['data', 'updatedAt'])` on the
  // *resulting* document, so a merge write that leaves any other field in place
  // is rejected — see the legacy cleanup in [saveState].

  /// Reads the shared state document.
  ///
  /// Returns `null` when the user has no cloud state yet. Malformed JSON also
  /// reads as `null` rather than throwing, matching the web's `parseStoredState`.
  Future<AppState?> loadState() async {
    final doc = await _userDoc?.get();
    if (doc == null || !doc.exists) return null;
    final fields = doc.data() as Map<String, dynamic>?;
    if (fields == null) return null;

    final raw = fields['data'];
    if (raw is String) return AppState.decode(raw);

    // Pre-contract app builds stored a top-level `semesters` array instead.
    return _migrateLegacyState(fields);
  }

  /// Streams the raw `data` field of the shared state document.
  ///
  /// Emits the string rather than a decoded [AppState] because the sync layer
  /// compares payloads by fingerprint before deciding to apply anything, and
  /// decoding first would discard the exact bytes that comparison needs.
  ///
  /// Yields `null` while signed out or when the document has no payload.
  @override
  Stream<String?> watchRawState() {
    final ref = _userDoc;
    if (ref == null) return Stream<String?>.value(null);
    return ref.snapshots().map((snap) {
      if (!snap.exists) return null;
      final fields = snap.data() as Map<String, dynamic>?;
      final raw = fields?['data'];
      return raw is String ? raw : null;
    });
  }

  /// Writes the shared state document.
  ///
  /// Also clears the legacy top-level `semesters` field. Without this the merged
  /// document would carry a third key and fail the web's `hasOnly` rule, so every
  /// write from a previously-migrated account would be rejected.
  @override
  Future<void> saveState(AppState state) async {
    await _userDoc?.set({
      'data': state.encode(),
      'updatedAt': FieldValue.serverTimestamp(),
      'semesters': FieldValue.delete(),
    }, SetOptions(merge: true));
  }

  /// Converts a pre-contract document into the shared shape.
  ///
  /// Legacy semester ids were strings, which the web discards. They are
  /// renumbered positionally so the blocks survive rather than being dropped.
  AppState? _migrateLegacyState(Map<String, dynamic> fields) {
    final legacy = fields['semesters'];
    if (legacy is! List) return null;

    final semesters = <Semester>[];
    for (var i = 0; i < legacy.length; i++) {
      final entry = legacy[i];
      if (entry is! Map) continue;
      final m = Map<String, dynamic>.from(entry);
      semesters.add(Semester.tryFromMap({
        ...m,
        'id': i,
        // Legacy builds used `label`/`isRunning`; the shared contract uses
        // `name`/`running`.
        'name': m['name'] ?? m['label'] ?? '',
        'running': m['running'] ?? m['isRunning'] ?? false,
      })!);
    }

    return AppState(
      semesters: semesters,
      semesterCounter: semesters.length,
    );
  }

  // ── Reviews ────────────────────────────────────────────────────────────────

  Stream<QuerySnapshot> reviewsForCourse(String courseCode) {
    return _db
        .collection('reviews')
        .where('courseCode', isEqualTo: courseCode)
        .orderBy('createdAt', descending: true)
        .limit(50)
        .snapshots();
  }

  Future<QuerySnapshot> reviewsForCourseFuture(String courseCode) {
    return _db
        .collection('reviews')
        .where('courseCode', isEqualTo: courseCode)
        .orderBy('createdAt', descending: true)
        .limit(50)
        .get();
  }

  Future<QuerySnapshot> reviewsForFaculty(String facultyName) {
    return _db
        .collection('reviews')
        .where('facultyName', isEqualTo: facultyName)
        .orderBy('createdAt', descending: true)
        .limit(100)
        .get();
  }

  Stream<QuerySnapshot> reviewsForDept(String deptPrefix) {
    final end = '${deptPrefix}Z';
    return _db
        .collection('reviews')
        .where('courseCode', isGreaterThanOrEqualTo: deptPrefix)
        .where('courseCode', isLessThan: end)
        .orderBy('courseCode')
        .limit(200)
        .snapshots();
  }

  Future<void> submitReview({
    required String courseCode,
    required String courseName,
    required String facultyName,
    required int rating,
    required String comment,
    required int difficulty,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    await _db.collection('reviews').add({
      'courseCode': courseCode,
      'courseName': courseName,
      'facultyName': facultyName,
      'rating': rating,
      'comment': comment,
      'difficulty': difficulty,
      'uid': user.uid,
      'displayName': user.displayName,
      'photoURL': user.photoURL,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  // ── Difficulty Map ─────────────────────────────────────────────────────────

  Future<List<DifficultyEntry>> loadDifficultyMap({int minReviews = 3}) async {
    final snap = await _db
        .collection('reviews')
        .where('difficulty', isGreaterThan: 0)
        .limit(5000)
        .get();

    final byCourse = <String, List<Map<String, dynamic>>>{};
    for (final doc in snap.docs) {
      final d = doc.data();
      final code = (d['courseCode'] as String?)?.trim().toUpperCase();
      if (code == null || code.isEmpty) continue;
      byCourse.putIfAbsent(code, () => []).add(d);
    }

    final entries = <DifficultyEntry>[];
    for (final entry in byCourse.entries) {
      final revs = entry.value;
      if (revs.length < minReviews) continue;

      double totalDiff = 0, totalRating = 0;
      int diffCount = 0, ratingCount = 0;
      String courseName = entry.key;

      for (final r in revs) {
        final diff = (r['difficulty'] as num?)?.toDouble();
        final rating = (r['rating'] as num?)?.toDouble();
        final name = r['courseName'] as String?;
        if (name != null && name.isNotEmpty && courseName == entry.key) {
          courseName = name;
        }
        if (diff != null && diff > 0) {
          totalDiff += diff;
          diffCount++;
        }
        if (rating != null && rating > 0) {
          totalRating += rating;
          ratingCount++;
        }
      }

      entries.add(DifficultyEntry(
        courseCode: entry.key,
        courseName: courseName,
        avgDifficulty: diffCount > 0 ? totalDiff / diffCount : 0,
        avgRating: ratingCount > 0 ? totalRating / ratingCount : 0,
        reviewCount: revs.length,
      ));
    }

    entries.sort((a, b) => b.avgDifficulty.compareTo(a.avgDifficulty));
    return entries;
  }

  // ── Faculty ────────────────────────────────────────────────────────────────

  Future<List<String>> searchFacultyNames(String query) async {
    if (query.length < 2) return [];
    final snap = await _db
        .collection('reviews')
        .where('facultyName', isGreaterThanOrEqualTo: query)
        .where('facultyName', isLessThan: '${query}z')
        .limit(50)
        .get();

    final names = <String>{};
    for (final doc in snap.docs) {
      final name = doc.data()['facultyName'] as String?;
      if (name != null && name.isNotEmpty) names.add(name);
    }
    return names.toList()..sort();
  }

  Future<List<String>> getKnownFaculty() async {
    final snap = await _db
        .collection('reviews')
        .limit(2000)
        .get();
    final names = <String>{};
    for (final doc in snap.docs) {
      final name = doc.data()['facultyName'] as String?;
      if (name != null && name.trim().isNotEmpty) names.add(name.trim());
    }
    final sorted = names.toList()..sort();
    return sorted;
  }

  Future<Map<String, dynamic>> getFacultyStats(String facultyName) async {
    final snap = await _db
        .collection('reviews')
        .where('facultyName', isEqualTo: facultyName)
        .limit(200)
        .get();

    if (snap.docs.isEmpty) return {};

    double totalRating = 0, totalDiff = 0;
    int rCount = 0, dCount = 0;
    final courses = <String, List<Map<String, dynamic>>>{};

    for (final doc in snap.docs) {
      final d = doc.data();
      final code = (d['courseCode'] as String?)?.trim().toUpperCase() ?? '';
      final rating = (d['rating'] as num?)?.toDouble();
      final diff = (d['difficulty'] as num?)?.toDouble();
      if (rating != null && rating > 0) { totalRating += rating; rCount++; }
      if (diff != null && diff > 0) { totalDiff += diff; dCount++; }
      courses.putIfAbsent(code, () => []).add(d);
    }

    return {
      'totalReviews': snap.docs.length,
      'avgRating': rCount > 0 ? totalRating / rCount : null,
      'avgDifficulty': dCount > 0 ? totalDiff / dCount : null,
      'courses': courses,
      'docs': snap.docs.map((d) => d.data()).toList(),
    };
  }

  // ── Faculty profile collection ─────────────────────────────────────────────

  Future<QuerySnapshot> searchFaculty(String query) {
    return _db
        .collection('faculty')
        .where('nameLower', isGreaterThanOrEqualTo: query.toLowerCase())
        .where('nameLower', isLessThanOrEqualTo: '${query.toLowerCase()}')
        .limit(20)
        .get();
  }
}
