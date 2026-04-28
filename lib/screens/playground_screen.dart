import 'package:flutter/material.dart';
import '../models/course.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_card.dart';

class PlaygroundScreen extends StatefulWidget {
  const PlaygroundScreen({super.key});

  @override
  State<PlaygroundScreen> createState() => _PlaygroundScreenState();
}

class _PlaygroundScreenState extends State<PlaygroundScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Playground'),
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: AppTheme.green,
          labelColor: AppTheme.green,
          unselectedLabelColor: AppTheme.textSecondary,
          tabs: const [
            Tab(text: 'Grade Simulator'),
            Tab(text: 'Reverse Solver'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: const [
          _GradeSimulator(),
          _ReverseSolver(),
        ],
      ),
    );
  }
}

// ── Grade Simulator ─────────────────────────────────────────────────────────
// "What CGPA will I get if I score X in these upcoming courses?"

class _GradeSimulator extends StatefulWidget {
  const _GradeSimulator();

  @override
  State<_GradeSimulator> createState() => _GradeSimulatorState();
}

class _GradeSimulatorState extends State<_GradeSimulator> {
  double _currentCgpa = 0;
  double _currentCredits = 0;
  final List<_SimCourse> _courses = [_SimCourse()];

  double? get _projectedCgpa {
    double pts = _currentCgpa * _currentCredits;
    double creds = _currentCredits;
    for (final c in _courses) {
      final gp = kGrades[c.grade];
      if (gp == null || c.grade.isEmpty || c.grade == 'P' || c.grade == 'I') continue;
      pts += gp * c.credits;
      creds += c.credits;
    }
    return creds > 0 ? pts / creds : null;
  }

  @override
  Widget build(BuildContext context) {
    final projected = _projectedCgpa;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Current standing inputs
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Current Standing', style: TextStyle(fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _NumberField(
                      label: 'Current CGPA',
                      value: _currentCgpa,
                      min: 0, max: 4,
                      onChanged: (v) => setState(() => _currentCgpa = v),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _NumberField(
                      label: 'Credits Completed',
                      value: _currentCredits,
                      min: 0, max: 160,
                      onChanged: (v) => setState(() => _currentCredits = v),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // Upcoming courses
        ..._courses.asMap().entries.map((e) => _SimCourseRow(
          course: e.value,
          onRemove: _courses.length > 1 ? () => setState(() => _courses.removeAt(e.key)) : null,
        )),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: () => setState(() => _courses.add(_SimCourse())),
          child: Row(
            children: const [
              Icon(Icons.add_circle_outline_rounded, size: 16, color: AppTheme.green),
              SizedBox(width: 6),
              Text('Add course', style: TextStyle(color: AppTheme.green, fontSize: 13, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // Result
        if (projected != null)
          GlassCard(
            borderColor: AppTheme.border,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Column(
                  children: [
                    const Text('Projected CGPA', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
                    const SizedBox(height: 4),
                    Text(
                      projected.toStringAsFixed(2),
                      style: const TextStyle(
                        fontSize: 48,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.green,
                        height: 1,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _SimCourse {
  double credits;
  String grade;
  _SimCourse({this.credits = 3.0, this.grade = 'A'});
}

class _SimCourseRow extends StatelessWidget {
  final _SimCourse course;
  final VoidCallback? onRemove;
  const _SimCourseRow({required this.course, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          const Text('Credits:', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
          const SizedBox(width: 8),
          SizedBox(
            width: 70,
            child: DropdownButtonFormField<double>(
              value: kCreditOptions.contains(course.credits) ? course.credits : 3.0,
              onChanged: (v) => course.credits = v ?? 3.0,
              dropdownColor: AppTheme.surface,
              style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13),
              decoration: const InputDecoration(
                isDense: true,
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(horizontal: 4),
              ),
              items: kCreditOptions.map((c) => DropdownMenuItem(value: c, child: Text(c.toString()))).toList(),
            ),
          ),
          const Spacer(),
          const Text('Grade:', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
          const SizedBox(width: 8),
          SizedBox(
            width: 70,
            child: DropdownButtonFormField<String>(
              value: course.grade,
              onChanged: (v) => course.grade = v ?? 'A',
              dropdownColor: AppTheme.surface,
              style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13),
              decoration: const InputDecoration(
                isDense: true,
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(horizontal: 4),
              ),
              items: kGradeOptions
                  .where((g) => g.isNotEmpty && g != 'P' && g != 'I' && g != 'F(NT)')
                  .map((g) => DropdownMenuItem(value: g, child: Text(g)))
                  .toList(),
            ),
          ),
          if (onRemove != null) ...[
            const SizedBox(width: 8),
            GestureDetector(
              onTap: onRemove,
              child: const Icon(Icons.remove_circle_outline_rounded, size: 18, color: AppTheme.textMuted),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Reverse Solver ───────────────────────────────────────────────────────────
// "What grade do I need in my remaining courses to reach CGPA X?"

class _ReverseSolver extends StatefulWidget {
  const _ReverseSolver();

  @override
  State<_ReverseSolver> createState() => _ReverseSolverState();
}

class _ReverseSolverState extends State<_ReverseSolver> {
  double _currentCgpa = 0;
  double _currentCredits = 0;
  double _targetCgpa = 3.5;
  double _remainingCredits = 12;

  double? get _requiredGpa {
    final needed = (_targetCgpa * (_currentCredits + _remainingCredits)) - (_currentCgpa * _currentCredits);
    if (_remainingCredits <= 0) return null;
    return needed / _remainingCredits;
  }

  @override
  Widget build(BuildContext context) {
    final required = _requiredGpa;
    final feasible = required != null && required <= 4.0 && required >= 0;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Your Situation', style: TextStyle(fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: _NumberField(label: 'Current CGPA', value: _currentCgpa, min: 0, max: 4, onChanged: (v) => setState(() => _currentCgpa = v))),
                  const SizedBox(width: 12),
                  Expanded(child: _NumberField(label: 'Credits Done', value: _currentCredits, min: 0, max: 160, onChanged: (v) => setState(() => _currentCredits = v))),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: _NumberField(label: 'Target CGPA', value: _targetCgpa, min: 0, max: 4, onChanged: (v) => setState(() => _targetCgpa = v))),
                  const SizedBox(width: 12),
                  Expanded(child: _NumberField(label: 'Remaining Credits', value: _remainingCredits, min: 0, max: 160, onChanged: (v) => setState(() => _remainingCredits = v))),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (required != null)
          GlassCard(
            borderColor: feasible ? AppTheme.border : Colors.redAccent.withOpacity(0.4),
            child: Column(
              children: [
                Text(
                  feasible ? 'You need at least' : 'Not achievable',
                  style: TextStyle(color: feasible ? AppTheme.textSecondary : Colors.redAccent, fontSize: 13),
                ),
                const SizedBox(height: 4),
                Text(
                  feasible ? required.toStringAsFixed(2) : '> 4.00',
                  style: TextStyle(
                    fontSize: 48,
                    fontWeight: FontWeight.w800,
                    color: feasible ? AppTheme.green : Colors.redAccent,
                    height: 1,
                  ),
                ),
                if (feasible) ...[
                  const SizedBox(height: 4),
                  const Text('GPA in remaining semesters', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class _NumberField extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final void Function(double) onChanged;

  const _NumberField({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      initialValue: value == value.roundToDouble() ? value.toInt().toString() : value.toStringAsFixed(2),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
      onChanged: (v) {
        final parsed = double.tryParse(v);
        if (parsed != null) onChanged(parsed.clamp(min, max));
      },
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      ),
    );
  }
}
