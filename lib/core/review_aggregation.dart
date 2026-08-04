import '../models/faculty_review.dart';

/// Minimum reviews before a course appears on the difficulty map.
///
/// Matches the web's threshold. It is a privacy floor as much as a statistical
/// one: with one or two reviews for a small section, an aggregate is close to
/// republishing an individual's rating.
const int kMinReviewsForDifficulty = 3;

/// Rolls the review corpus up per course, hardest first.
///
/// Courses below [minReviews] are omitted entirely rather than shown with a
/// low-confidence score.
List<CourseDifficulty> aggregateDifficulty(
  Iterable<FacultyReview> reviews, {
  int minReviews = kMinReviewsForDifficulty,
}) {
  final byCourse = <String, List<FacultyReview>>{};
  for (final r in reviews) {
    if (r.courseCode.isEmpty) continue;
    byCourse.putIfAbsent(r.courseCode, () => []).add(r);
  }

  final out = <CourseDifficulty>[];
  byCourse.forEach((code, rs) {
    if (rs.length < minReviews) return;

    final difficulties = rs.map((r) => r.ratings['difficulty']).whereType<int>();
    final workloads = rs.map((r) => r.ratings['workload']).whereType<int>();
    if (difficulties.isEmpty) return;

    out.add(CourseDifficulty(
      courseCode: code,
      avgDifficulty: difficulties.reduce((a, b) => a + b) / difficulties.length,
      avgWorkload: workloads.isEmpty
          ? 0
          : workloads.reduce((a, b) => a + b) / workloads.length,
      reviewCount: rs.length,
    ));
  });

  out.sort((a, b) => b.avgDifficulty.compareTo(a.avgDifficulty));
  return out;
}

/// Rolls up one faculty member's reviews.
///
/// Quality deliberately excludes difficulty and workload — a hard course is not
/// a badly taught one, and averaging them together would punish rigour.
FacultyStats aggregateFaculty(String initials, Iterable<FacultyReview> reviews) {
  final rs = reviews.toList();
  if (rs.isEmpty) return FacultyStats(initials: initials);

  final qualities = rs.map((r) => r.ratings.qualityMean).whereType<double>();
  final difficulties = rs.map((r) => r.ratings['difficulty']).whereType<int>();

  final courses = rs.map((r) => r.courseCode).where((c) => c.isNotEmpty).toSet().toList()
    ..sort();

  return FacultyStats(
    initials: initials,
    avgQuality: qualities.isEmpty
        ? null
        : qualities.reduce((a, b) => a + b) / qualities.length,
    avgDifficulty: difficulties.isEmpty
        ? null
        : difficulties.reduce((a, b) => a + b) / difficulties.length,
    reviewCount: rs.length,
    courses: courses,
  );
}

/// Groups a course's reviews by the faculty who taught it, most-reviewed first.
///
/// This is the per-course panel the web shows: which professors teach this, and
/// how each is rated.
List<FacultyStats> facultyForCourse(Iterable<FacultyReview> reviews) {
  final byFaculty = <String, List<FacultyReview>>{};
  for (final r in reviews) {
    if (r.facultyInitials.isEmpty) continue;
    byFaculty.putIfAbsent(r.facultyInitials, () => []).add(r);
  }

  final out = byFaculty.entries
      .map((e) => aggregateFaculty(e.key, e.value))
      .toList()
    ..sort((a, b) => b.reviewCount.compareTo(a.reviewCount));
  return out;
}
