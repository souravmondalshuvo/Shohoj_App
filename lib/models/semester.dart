import 'course.dart';

class Semester {
  final String id;
  String label;
  List<Course> courses;
  bool isRunning;

  Semester({
    required this.id,
    this.label = '',
    List<Course>? courses,
    this.isRunning = false,
  }) : courses = courses ?? [Course()];

  double? get gpa {
    double pts = 0;
    double creds = 0;
    for (final c in courses) {
      if (!c.countsTowardGPA) continue;
      final gp = c.gradePoint;
      if (gp == null) continue;
      pts += gp * c.credits;
      creds += c.credits;
    }
    return creds > 0 ? pts / creds : null;
  }

  double get totalCredits {
    double creds = 0;
    for (final c in courses) {
      if (!c.countsCredits) continue;
      if (c.grade == 'F' || c.grade == 'F(NT)') continue;
      creds += c.credits;
    }
    return creds;
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'label': label,
    'courses': courses.map((c) => c.toMap()).toList(),
    'isRunning': isRunning,
  };

  factory Semester.fromMap(Map<String, dynamic> m) => Semester(
    id: m['id'] ?? '',
    label: m['label'] ?? '',
    courses: (m['courses'] as List?)
        ?.map((c) => Course.fromMap(c as Map<String, dynamic>))
        .toList() ??
        [Course()],
    isRunning: m['isRunning'] ?? false,
  );
}
