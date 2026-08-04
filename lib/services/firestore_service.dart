import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/app_state.dart';
import '../models/semester.dart';
import '../core/review_aggregation.dart';
import '../models/faculty_review.dart';
import 'sync/user_state_store.dart';

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

  // ── Faculty reviews (shared with the web app) ──────────────────────────────
  //
  // The corpus lives in `facultyReviews`, written only by the Cloudflare Worker
  // and readable by any BRACU account. Clients are denied create and update by
  // the rules, so nothing here writes.
  //
  // Every query below is backed by an index the web repo already deploys
  // (facultyInitials+createdAt, facultyInitials+courseCode+createdAt,
  // courseCode+createdAt). This repo cannot deploy indexes, so a query outside
  // that set would fail at runtime rather than at build time.

  static const _reviewsCollection = 'facultyReviews';

  List<FacultyReview> _toReviews(QuerySnapshot snap) => snap.docs
      .map((d) => FacultyReview.fromMap(d.id, d.data() as Map<String, dynamic>))
      .toList();

  /// Reviews for one course, newest first.
  Stream<List<FacultyReview>> reviewsForCourse(String courseCode) {
    return _db
        .collection(_reviewsCollection)
        .where('courseCode', isEqualTo: courseCode.toUpperCase())
        .orderBy('createdAt', descending: true)
        .limit(100)
        .snapshots()
        .map(_toReviews);
  }

  /// Reviews for one faculty member, newest first.
  Future<List<FacultyReview>> reviewsForFaculty(String initials) async {
    final snap = await _db
        .collection(_reviewsCollection)
        .where('facultyInitials', isEqualTo: initials.toUpperCase())
        .orderBy('createdAt', descending: true)
        .limit(200)
        .get();
    return _toReviews(snap);
  }

  /// Reviews for a whole department, by course-code prefix.
  ///
  /// A range filter and ordering on the same field needs only the automatic
  /// single-field index, so this works without a composite.
  Stream<List<FacultyReview>> reviewsForDept(String deptPrefix) {
    final prefix = deptPrefix.toUpperCase();
    return _db
        .collection(_reviewsCollection)
        .where('courseCode', isGreaterThanOrEqualTo: prefix)
        .where('courseCode', isLessThan: '${prefix}Z')
        .orderBy('courseCode')
        .limit(300)
        .snapshots()
        .map(_toReviews);
  }

  /// The whole corpus, for the difficulty map.
  Future<List<FacultyReview>> allReviews({int limit = 3000}) async {
    final snap = await _db.collection(_reviewsCollection).limit(limit).get();
    return _toReviews(snap);
  }

  /// The difficulty map: the whole corpus rolled up per course, hardest first.
  Future<List<CourseDifficulty>> loadDifficultyMap({
    int minReviews = kMinReviewsForDifficulty,
  }) async {
    return aggregateDifficulty(await allReviews(), minReviews: minReviews);
  }

  /// Every faculty member who appears in the corpus, with their aggregates.
  Future<List<FacultyStats>> knownFaculty() async {
    final reviews = await allReviews();
    final byFaculty = <String, List<FacultyReview>>{};
    for (final r in reviews) {
      if (r.facultyInitials.isEmpty) continue;
      byFaculty.putIfAbsent(r.facultyInitials, () => []).add(r);
    }
    final out = byFaculty.entries
        .map((e) => aggregateFaculty(e.key, e.value))
        .toList()
      ..sort((a, b) => a.initials.compareTo(b.initials));
    return out;
  }

  /// One faculty member's aggregate, or null when they have no reviews.
  Future<FacultyStats?> facultyStats(String initials) async {
    final reviews = await reviewsForFaculty(initials);
    if (reviews.isEmpty) return null;
    return aggregateFaculty(initials.toUpperCase(), reviews);
  }

  // ── Faculty profiles ───────────────────────────────────────────────────────
  //
  // Admin-seeded and read-only. The seed is explicitly partial, so a lookup
  // miss is ordinary — callers fall back to showing the initials.

  Future<Map<String, FacultyProfile>> facultyProfiles({int limit = 500}) async {
    final snap = await _db.collection('facultyProfiles').limit(limit).get();
    return {
      for (final d in snap.docs)
        d.id.toUpperCase(): FacultyProfile.fromMap(d.id, d.data()),
    };
  }

  Future<FacultyProfile?> facultyProfile(String initials) async {
    final doc =
        await _db.collection('facultyProfiles').doc(initials.toUpperCase()).get();
    if (!doc.exists) return null;
    return FacultyProfile.fromMap(doc.id, doc.data() as Map<String, dynamic>);
  }
}
