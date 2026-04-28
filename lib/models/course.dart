const Map<String, double?> kGrades = {
  'A+': 4.00, 'A': 4.00, 'A-': 3.70,
  'B+': 3.30, 'B': 3.00, 'B-': 2.70,
  'C+': 2.30, 'C': 2.00, 'C-': 1.70,
  'D+': 1.30, 'D': 1.00, 'D-': 0.70,
  'F': 0.00, 'F(NT)': 0.00,
  'P': null, 'I': null,
};

const List<String> kGradeOptions = [
  '', 'A+', 'A', 'A-', 'B+', 'B', 'B-',
  'C+', 'C', 'C-', 'D+', 'D', 'D-',
  'F', 'F(NT)', 'P', 'I',
];

const List<double> kCreditOptions = [0.75, 1.0, 1.5, 2.0, 3.0, 4.0];

class Course {
  String name;
  double credits;
  String grade;

  Course({this.name = '', this.credits = 3.0, this.grade = ''});

  double? get gradePoint => kGrades[grade];

  bool get countsTowardGPA {
    if (grade.isEmpty) return false;
    if (grade == 'P' || grade == 'I') return false;
    return true;
  }

  bool get countsCredits {
    if (grade.isEmpty) return false;
    if (grade == 'P' || grade == 'I') return false;
    return true;
  }

  Map<String, dynamic> toMap() => {
    'name': name,
    'credits': credits,
    'grade': grade,
  };

  factory Course.fromMap(Map<String, dynamic> m) => Course(
    name: m['name'] ?? '',
    credits: (m['credits'] as num?)?.toDouble() ?? 3.0,
    grade: m['grade'] ?? '',
  );

  Course copyWith({String? name, double? credits, String? grade}) => Course(
    name: name ?? this.name,
    credits: credits ?? this.credits,
    grade: grade ?? this.grade,
  );
}
