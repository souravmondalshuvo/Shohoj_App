import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/semester.dart';

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

  // ── Faculty ────────────────────────────────────────────────────────────────

  Future<QuerySnapshot> searchFaculty(String query) {
    return _db
        .collection('faculty')
        .where('nameLower', isGreaterThanOrEqualTo: query.toLowerCase())
        .where('nameLower', isLessThanOrEqualTo: '${query.toLowerCase()}')
        .limit(20)
        .get();
  }
}
