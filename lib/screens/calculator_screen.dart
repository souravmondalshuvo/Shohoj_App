import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../data/departments.dart';
import '../models/course.dart';
import '../models/semester.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_card.dart';
import '../widgets/gpa_chart.dart';

class CalculatorScreen extends StatefulWidget {
  const CalculatorScreen({super.key});

  @override
  State<CalculatorScreen> createState() => _CalculatorScreenState();
}

class _CalculatorScreenState extends State<CalculatorScreen> {
  final _fs = FirestoreService();
  List<Semester> _semesters = [];
  bool _loading = true;
  int _semCounter = 0;
  String? _selectedDept;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final loaded = await _fs.loadSemesters();
    setState(() {
      _semesters = loaded.isEmpty ? [_newSem()] : loaded;
      _semCounter = _semesters.length;
      _loading = false;
    });
  }

  Semester _newSem() => Semester(
        id: 'sem_${DateTime.now().millisecondsSinceEpoch}_$_semCounter',
        label: 'Semester ${_semCounter + 1}',
      );

  void _addSemester() {
    setState(() {
      _semCounter++;
      _semesters.add(_newSem());
    });
    _save();
  }

  void _removeSemester(int idx) {
    setState(() => _semesters.removeAt(idx));
    _save();
  }

  void _addCourse(int semIdx) {
    setState(() => _semesters[semIdx].courses.add(Course()));
    _save();
  }

  void _removeCourse(int semIdx, int courseIdx) {
    setState(() => _semesters[semIdx].courses.removeAt(courseIdx));
    _save();
  }

  void _updateCourse(int semIdx, int courseIdx, Course updated) {
    setState(() => _semesters[semIdx].courses[courseIdx] = updated);
    _save();
  }

  Future<void> _save() async {
    await _fs.saveSemesters(_semesters);
  }

  double? get _cgpa {
    double pts = 0, creds = 0;
    for (final sem in _semesters) {
      if (sem.isRunning) continue;
      for (final c in sem.courses) {
        if (!c.countsTowardGPA) continue;
        final gp = c.gradePoint;
        if (gp == null) continue;
        pts += gp * c.credits;
        creds += c.credits;
      }
    }
    return creds > 0 ? pts / creds : null;
  }

  double get _totalCredits {
    double total = 0;
    for (final sem in _semesters) {
      total += sem.totalCredits;
    }
    return total;
  }

  List<GpaDataPoint> get _chartPoints {
    return _semesters
        .where((s) => !s.isRunning && s.gpa != null)
        .map((s) => GpaDataPoint(s.label.replaceAll('Semester ', 'S'), s.gpa!))
        .toList();
  }

  void _showDeptPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _DeptPicker(
        current: _selectedDept,
        onSelected: (code) {
          setState(() => _selectedDept = code);
          Navigator.pop(context);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: AppTheme.green));
    }

    final cgpa = _cgpa;
    final user = context.watch<AuthService>().user;
    final chartPoints = _chartPoints;
    final dept = _selectedDept != null ? kDeptMap[_selectedDept] : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('CGPA Calculator'),
        actions: [
          if (user != null)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: CircleAvatar(
                radius: 16,
                backgroundImage: user.photoURL != null ? NetworkImage(user.photoURL!) : null,
                backgroundColor: AppTheme.greenDim,
                child: user.photoURL == null
                    ? Text(user.displayName?[0] ?? '?',
                        style: const TextStyle(color: Colors.white, fontSize: 12))
                    : null,
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          // CGPA + credits banner
          _CgpaBanner(cgpa: cgpa, totalCredits: _totalCredits),
          // GPA chart (≥2 semesters with grades)
          if (chartPoints.length >= 2) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: GlassCard(
                padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(left: 8, bottom: 4),
                      child: Text('GPA Trend', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12, fontWeight: FontWeight.w600)),
                    ),
                    GpaLineChart(data: chartPoints),
                  ],
                ),
              ),
            ),
          ],
          // Degree tracker
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: GlassCard(
              padding: const EdgeInsets.all(14),
              child: _DegreeTracker(
                totalCredits: _totalCredits,
                dept: dept,
                onPickDept: _showDeptPicker,
              ),
            ),
          ),
          // Semester list
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
              itemCount: _semesters.length,
              itemBuilder: (ctx, i) => _SemesterCard(
                semester: _semesters[i],
                onAddCourse: () => _addCourse(i),
                onRemoveCourse: (ci) => _removeCourse(i, ci),
                onUpdateCourse: (ci, c) => _updateCourse(i, ci, c),
                onRemoveSemester: _semesters.length > 1 ? () => _removeSemester(i) : null,
                onLabelChanged: (label) {
                  setState(() => _semesters[i].label = label);
                  _save();
                },
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addSemester,
        backgroundColor: AppTheme.green,
        foregroundColor: Colors.black,
        icon: const Icon(Icons.add),
        label: const Text('Add Semester', style: TextStyle(fontWeight: FontWeight.w700)),
      ),
    );
  }
}

// ── CGPA Banner ───────────────────────────────────────────────────────────────

class _CgpaBanner extends StatelessWidget {
  final double? cgpa;
  final double totalCredits;
  const _CgpaBanner({required this.cgpa, required this.totalCredits});

  Color _cgpaColor(double v) {
    if (v >= 3.70) return AppTheme.green;
    if (v >= 3.00) return const Color(0xFF3498DB);
    if (v >= 2.00) return AppTheme.gold;
    return Colors.redAccent;
  }

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      borderColor: AppTheme.border,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('CGPA', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                const SizedBox(height: 4),
                Text(
                  cgpa != null ? cgpa!.toStringAsFixed(2) : '–',
                  style: TextStyle(
                    fontSize: 40,
                    fontWeight: FontWeight.w800,
                    color: cgpa != null ? _cgpaColor(cgpa!) : AppTheme.textMuted,
                    height: 1,
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Text('Credits Earned', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
              const SizedBox(height: 4),
              Text(
                totalCredits.toStringAsFixed(
                    totalCredits == totalCredits.roundToDouble() ? 0 : 2),
                style: const TextStyle(
                    fontSize: 28, fontWeight: FontWeight.w700, color: AppTheme.textPrimary),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Degree Tracker ─────────────────────────────────────────────────────────────

class _DegreeTracker extends StatelessWidget {
  final double totalCredits;
  final DeptInfo? dept;
  final VoidCallback onPickDept;
  const _DegreeTracker({required this.totalCredits, required this.dept, required this.onPickDept});

  @override
  Widget build(BuildContext context) {
    if (dept == null) {
      return GestureDetector(
        onTap: onPickDept,
        child: Row(
          children: [
            const Icon(Icons.school_outlined, color: AppTheme.textMuted, size: 18),
            const SizedBox(width: 8),
            const Expanded(
              child: Text('Select your department to track degree progress',
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppTheme.textMuted, size: 18),
          ],
        ),
      );
    }

    final required = dept!.totalCredits.toDouble();
    final progress = (totalCredits / required).clamp(0.0, 1.0);
    final remaining = (required - totalCredits).clamp(0.0, required);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.school_outlined, color: AppTheme.green, size: 16),
            const SizedBox(width: 6),
            Expanded(
              child: Text(dept!.label,
                  style: const TextStyle(color: AppTheme.textPrimary, fontSize: 12, fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ),
            GestureDetector(
              onTap: onPickDept,
              child: const Text('Change', style: TextStyle(color: AppTheme.green, fontSize: 12)),
            ),
          ],
        ),
        const SizedBox(height: 10),
        // Progress bar
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: progress,
            backgroundColor: AppTheme.border2,
            valueColor: AlwaysStoppedAnimation<Color>(
              progress >= 1.0 ? AppTheme.green : AppTheme.green.withValues(alpha: 0.8),
            ),
            minHeight: 6,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Text('${totalCredits.toInt()} / ${required.toInt()} credits',
                style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
            const Spacer(),
            if (progress < 1.0)
              Text('${remaining.toInt()} remaining',
                  style: const TextStyle(color: AppTheme.textMuted, fontSize: 12))
            else
              const Text('Complete!',
                  style: TextStyle(color: AppTheme.green, fontSize: 12, fontWeight: FontWeight.w600)),
          ],
        ),
      ],
    );
  }
}

// ── Dept Picker ───────────────────────────────────────────────────────────────

class _DeptPicker extends StatelessWidget {
  final String? current;
  final void Function(String?) onSelected;
  const _DeptPicker({required this.current, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 20, 20, 8),
          child: Text('Select Department',
              style: TextStyle(color: AppTheme.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
        ),
        if (current != null)
          ListTile(
            leading: const Icon(Icons.clear_rounded, color: AppTheme.textMuted),
            title: const Text('Clear selection', style: TextStyle(color: AppTheme.textSecondary)),
            onTap: () => onSelected(null),
          ),
        Flexible(
          child: ListView.builder(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(0, 0, 0, 20),
            itemCount: kDepartments.length,
            itemBuilder: (_, i) {
              final dept = kDepartments[i];
              final sel = current == dept.code;
              return ListTile(
                selected: sel,
                selectedColor: AppTheme.green,
                title: Text(dept.label, style: TextStyle(color: sel ? AppTheme.green : AppTheme.textPrimary, fontSize: 14)),
                subtitle: Text('${dept.totalCredits} credits',
                    style: const TextStyle(color: AppTheme.textMuted, fontSize: 12)),
                onTap: () => onSelected(dept.code),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ── Semester Card ─────────────────────────────────────────────────────────────

class _SemesterCard extends StatelessWidget {
  final Semester semester;
  final VoidCallback onAddCourse;
  final void Function(int) onRemoveCourse;
  final void Function(int, Course) onUpdateCourse;
  final VoidCallback? onRemoveSemester;
  final void Function(String) onLabelChanged;

  const _SemesterCard({
    required this.semester,
    required this.onAddCourse,
    required this.onRemoveCourse,
    required this.onUpdateCourse,
    required this.onRemoveSemester,
    required this.onLabelChanged,
  });

  @override
  Widget build(BuildContext context) {
    final gpa = semester.gpa;
    return GlassCard(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: TextEditingController(text: semester.label)
                    ..selection = TextSelection.collapsed(offset: semester.label.length),
                  onChanged: onLabelChanged,
                  style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600, fontSize: 15),
                  decoration: const InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ),
              if (gpa != null) GreenBadge('GPA: ${gpa.toStringAsFixed(2)}'),
              const SizedBox(width: 8),
              if (onRemoveSemester != null)
                GestureDetector(
                  onTap: onRemoveSemester,
                  child: const Icon(Icons.close_rounded, size: 18, color: AppTheme.textMuted),
                ),
            ],
          ),
          const SizedBox(height: 10),
          ...List.generate(
            semester.courses.length,
            (i) => _CourseRow(
              course: semester.courses[i],
              onChanged: (c) => onUpdateCourse(i, c),
              onRemove: semester.courses.length > 1 ? () => onRemoveCourse(i) : null,
            ),
          ),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: onAddCourse,
            child: const Row(
              children: [
                Icon(Icons.add_circle_outline_rounded, size: 16, color: AppTheme.green),
                SizedBox(width: 6),
                Text('Add course', style: TextStyle(color: AppTheme.green, fontSize: 13, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Course Row ────────────────────────────────────────────────────────────────

class _CourseRow extends StatelessWidget {
  final Course course;
  final void Function(Course) onChanged;
  final VoidCallback? onRemove;

  const _CourseRow({required this.course, required this.onChanged, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: TextField(
              controller: TextEditingController(text: course.name)
                ..selection = TextSelection.collapsed(offset: course.name.length),
              onChanged: (v) => onChanged(course.copyWith(name: v)),
              style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Course name',
                hintStyle: const TextStyle(color: AppTheme.textMuted, fontSize: 13),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                filled: true,
                fillColor: AppTheme.glass,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppTheme.border2)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppTheme.border2)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppTheme.green)),
              ),
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 64,
            child: DropdownButtonFormField<double>(
              isExpanded: true,
              initialValue: kCreditOptions.contains(course.credits) ? course.credits : 3.0,
              onChanged: (v) => onChanged(course.copyWith(credits: v)),
              dropdownColor: AppTheme.surface,
              style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13),
              decoration: InputDecoration(
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                filled: true,
                fillColor: AppTheme.glass,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppTheme.border2)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppTheme.border2)),
              ),
              items: kCreditOptions.map((c) => DropdownMenuItem(value: c, child: Text(c.toString()))).toList(),
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 72,
            child: DropdownButtonFormField<String>(
              isExpanded: true,
              initialValue: kGradeOptions.contains(course.grade) ? course.grade : '',
              onChanged: (v) => onChanged(course.copyWith(grade: v ?? '')),
              dropdownColor: AppTheme.surface,
              style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13),
              decoration: InputDecoration(
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                filled: true,
                fillColor: AppTheme.glass,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppTheme.border2)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppTheme.border2)),
              ),
              items: kGradeOptions.map((g) => DropdownMenuItem(value: g, child: Text(g.isEmpty ? '–' : g))).toList(),
            ),
          ),
          const SizedBox(width: 4),
          if (onRemove != null)
            GestureDetector(
              onTap: onRemove,
              child: const Icon(Icons.remove_circle_outline_rounded, size: 18, color: AppTheme.textMuted),
            )
          else
            const SizedBox(width: 18),
        ],
      ),
    );
  }
}
