/// The five rating dimensions the web app collects, in display order.
///
/// Keys match the `REVIEW_TYPE_KEYS` the Worker validates against; changing one
/// silently detaches the app from the shared corpus.
const List<String> kRatingKeys = [
  'teaching',
  'marking',
  'behavior',
  'difficulty',
  'workload',
];

const Map<String, String> kRatingLabels = {
  'teaching': 'Teaching quality',
  'marking': 'Marking fairness',
  'behavior': 'Behaviour & attitude',
  'difficulty': 'Course difficulty',
  'workload': 'Workload',
};

/// A five-dimension rating, each value 1–5.
class Ratings {
  final Map<String, int> values;

  const Ratings(this.values);

  int? operator [](String key) => values[key];

  /// Mean across the dimensions present. Null when none are.
  double? get mean {
    if (values.isEmpty) return null;
    final total = values.values.fold<int>(0, (a, b) => a + b);
    return total / values.length;
  }

  /// Mean of the dimensions a student reads as "was this taught well" —
  /// deliberately excludes difficulty and workload, which are descriptive
  /// rather than good-or-bad. A hard course is not a badly taught one.
  double? get qualityMean {
    const qualityKeys = ['teaching', 'marking', 'behavior'];
    final present = qualityKeys.where(values.containsKey).toList();
    if (present.isEmpty) return null;
    return present.map((k) => values[k]!).reduce((a, b) => a + b) / present.length;
  }

  static Ratings fromMap(Object? raw) {
    if (raw is! Map) return const Ratings({});
    final out = <String, int>{};
    for (final key in kRatingKeys) {
      final v = raw[key];
      if (v is num) {
        final i = v.round();
        if (i >= 1 && i <= 5) out[key] = i;
      }
    }
    return Ratings(out);
  }
}

/// One review from the shared `facultyReviews` collection.
///
/// Pseudonymous by design: the document body carries no uid, email or display
/// name. The doc id is `{INITIALS}_{COURSE}_{sha256(uid|initials|course)}`,
/// computed server-side by the Worker, which is the only writer — clients are
/// denied create and update by the rules.
class FacultyReview {
  final String id;
  final String facultyInitials;
  final String courseCode;
  final String semester;
  final String text;
  final Ratings ratings;
  final DateTime? createdAt;

  const FacultyReview({
    required this.id,
    required this.facultyInitials,
    required this.courseCode,
    this.semester = '',
    this.text = '',
    this.ratings = const Ratings({}),
    this.createdAt,
  });

  static FacultyReview fromMap(String id, Map<String, dynamic> m) {
    return FacultyReview(
      id: id,
      facultyInitials: m['facultyInitials'] is String
          ? (m['facultyInitials'] as String).toUpperCase()
          : '',
      courseCode:
          m['courseCode'] is String ? (m['courseCode'] as String).toUpperCase() : '',
      semester: m['semester'] is String ? m['semester'] as String : '',
      text: m['text'] is String ? m['text'] as String : '',
      ratings: Ratings.fromMap(m['ratings']),
      createdAt: _toDate(m['createdAt']),
    );
  }

  /// Firestore hands back a `Timestamp`, but the emulator and any JSON path can
  /// produce a string or millis. Kept loose rather than casting.
  static DateTime? _toDate(Object? v) {
    if (v == null) return null;
    if (v is DateTime) return v;
    if (v is String) return DateTime.tryParse(v);
    if (v is int) return DateTime.fromMillisecondsSinceEpoch(v);
    try {
      // ignore: avoid_dynamic_calls
      final d = (v as dynamic).toDate();
      return d is DateTime ? d : null;
    } catch (_) {
      return null;
    }
  }
}

/// An admin-seeded faculty entry, used to show a name for a set of initials.
class FacultyProfile {
  final String initials;
  final String name;
  final String dept;
  final List<String> courses;

  const FacultyProfile({
    required this.initials,
    this.name = '',
    this.dept = '',
    this.courses = const [],
  });

  static FacultyProfile fromMap(String id, Map<String, dynamic> m) {
    return FacultyProfile(
      initials: m['initials'] is String ? (m['initials'] as String).toUpperCase() : id.toUpperCase(),
      name: m['name'] is String ? m['name'] as String : '',
      dept: m['dept'] is String ? m['dept'] as String : '',
      courses: m['courses'] is List
          ? (m['courses'] as List).whereType<String>().toList()
          : const [],
    );
  }

  /// What to show when the profile seed has no entry for these initials.
  ///
  /// The seed is explicitly partial — the authoritative faculty list is the
  /// live CONNECT feed, which this app does not read — so falling back to the
  /// initials is the normal case, not an error.
  String get displayName => name.isNotEmpty ? name : initials;
}

/// Aggregate of every review for one course, for the difficulty map.
class CourseDifficulty {
  final String courseCode;
  final double avgDifficulty;
  final double avgWorkload;
  final int reviewCount;

  const CourseDifficulty({
    required this.courseCode,
    required this.avgDifficulty,
    required this.avgWorkload,
    required this.reviewCount,
  });

  /// Matches the web's banding.
  String get band {
    if (avgDifficulty >= 4.0) return 'Hard';
    if (avgDifficulty >= 3.0) return 'Challenging';
    return 'Moderate';
  }
}

/// Aggregate of every review for one faculty member.
class FacultyStats {
  final String initials;
  final double? avgQuality;
  final double? avgDifficulty;
  final int reviewCount;
  final List<String> courses;

  const FacultyStats({
    required this.initials,
    this.avgQuality,
    this.avgDifficulty,
    this.reviewCount = 0,
    this.courses = const [],
  });
}
