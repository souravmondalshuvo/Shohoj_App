import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/semester.dart';

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

class FirestoreService {
  final _db = FirebaseFirestore.instance;

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  DocumentReference? get _userDoc =>
      _uid != null ? _db.collection('users').doc(_uid) : null;

  // ── Semesters (CGPA data) ──────────────────────────────────────────────────

  Future<List<Semester>> loadSemesters() async {
    final doc = await _userDoc?.get();
    if (doc == null || !doc.exists) return [];
    final data = doc.data() as Map<String, dynamic>?;
    final raw = data?['semesters'] as List?;
    return raw
            ?.map((s) => Semester.fromMap(s as Map<String, dynamic>))
            .toList() ??
        [];
  }

  Future<void> saveSemesters(List<Semester> semesters) async {
    await _userDoc?.set({
      'semesters': semesters.map((s) => s.toMap()).toList(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
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
