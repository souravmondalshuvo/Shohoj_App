class DeptInfo {
  final String code;
  final String label;
  final int totalCredits;
  final List<String> seasons;
  const DeptInfo({
    required this.code,
    required this.label,
    required this.totalCredits,
    required this.seasons,
  });
}

const List<DeptInfo> kDepartments = [
  DeptInfo(code: 'CSE', label: 'Computer Science & Engineering (CSE)', totalCredits: 136, seasons: ['Spring', 'Summer', 'Fall']),
  DeptInfo(code: 'CS',  label: 'Computer Science (CS)',                totalCredits: 124, seasons: ['Spring', 'Summer', 'Fall']),
  DeptInfo(code: 'EEE', label: 'Electrical & Electronic Engineering (EEE)', totalCredits: 136, seasons: ['Spring', 'Summer', 'Fall']),
  DeptInfo(code: 'ECE', label: 'Electronic & Communication Eng. (ECE)', totalCredits: 136, seasons: ['Spring', 'Summer', 'Fall']),
  DeptInfo(code: 'BBA', label: 'Business Administration (BBA)',        totalCredits: 130, seasons: ['Spring', 'Summer', 'Fall']),
  DeptInfo(code: 'ECO', label: 'Economics (ECO)',                      totalCredits: 120, seasons: ['Spring', 'Summer', 'Fall']),
  DeptInfo(code: 'ENG', label: 'English (ENG)',                        totalCredits: 120, seasons: ['Spring', 'Summer', 'Fall']),
  DeptInfo(code: 'ANT', label: 'Anthropology (ANT)',                   totalCredits: 120, seasons: ['Spring', 'Summer', 'Fall']),
  DeptInfo(code: 'ARC', label: 'Architecture (ARC)',                   totalCredits: 207, seasons: ['Spring', 'Summer', 'Fall']),
  DeptInfo(code: 'PHR', label: 'Pharmacy (PHR)',                       totalCredits: 164, seasons: ['Spring', 'Summer', 'Fall']),
  DeptInfo(code: 'LLB', label: 'Law (LLB)',                            totalCredits: 135, seasons: ['Spring', 'Summer', 'Fall']),
  DeptInfo(code: 'PHY', label: 'Physics (PHY)',                        totalCredits: 132, seasons: ['Spring', 'Summer', 'Fall']),
  DeptInfo(code: 'APE', label: 'Applied Physics & Electronics (APE)',  totalCredits: 130, seasons: ['Spring', 'Summer', 'Fall']),
  DeptInfo(code: 'MAT', label: 'Mathematics (MAT)',                    totalCredits: 127, seasons: ['Spring', 'Summer', 'Fall']),
  DeptInfo(code: 'MIC', label: 'Microbiology (MIC)',                   totalCredits: 136, seasons: ['Spring', 'Summer', 'Fall']),
  DeptInfo(code: 'BIO', label: 'Biotechnology (BIO)',                  totalCredits: 136, seasons: ['Spring', 'Summer', 'Fall']),
];

final Map<String, DeptInfo> kDeptMap = {
  for (final d in kDepartments) d.code: d,
};
