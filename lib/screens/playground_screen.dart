import 'package:flutter/material.dart';

import '../core/playground.dart';
import '../models/app_state.dart';
import '../models/course.dart';
import '../services/firestore_service.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_card.dart';

/// What-if tools over the student's real transcript.
///
/// Both tools previously asked the student to type their CGPA in by hand and
/// operated on hypothetical courses. They now work the way the web's do: on
/// courses actually on the transcript. The maths lives in lib/core/playground.dart
/// and is differential-tested against the web.
class PlaygroundScreen extends StatefulWidget {
  const PlaygroundScreen({super.key});

  @override
  State<PlaygroundScreen> createState() => _PlaygroundScreenState();
}

class _PlaygroundScreenState extends State<PlaygroundScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);
  final _fs = FirestoreService();

  AppState? _state;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final loaded = await _fs.loadState();
    if (!mounted) return;
    setState(() {
      _state = loaded;
      _loading = false;
    });
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
            Tab(text: 'Grade Changer'),
            Tab(text: 'Reverse Solver'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.green))
          : _body(),
    );
  }

  Widget _body() {
    final state = _state;
    final courses = state == null
        ? const <GradedCourse>[]
        : gradedCourses(
            state.semesters,
            startSeason: state.startSeason,
            startYear: state.startYear,
          );

    if (courses.isEmpty) return const _NoTranscript();

    final totals = playgroundTotals(
      state!.semesters,
      startSeason: state.startSeason,
      startYear: state.startYear,
    );

    return TabBarView(
      controller: _tabs,
      children: [
        _GradeChanger(courses: courses, totals: totals),
        _ReverseSolver(courses: courses, totals: totals),
      ],
    );
  }
}

class _NoTranscript extends StatelessWidget {
  const _NoTranscript();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.science_outlined, size: 48, color: AppTheme.textMuted),
            SizedBox(height: 12),
            Text(
              'Add some graded courses in the Calculator first',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.textSecondary),
            ),
            SizedBox(height: 6),
            Text(
              'These tools work on courses already on your transcript.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

/// Grades a student can pick as a hypothetical, lowest first.
List<String> _selectableGrades() {
  final entries = kGrades.entries.where((e) => e.value != null).toList()
    ..sort((a, b) => a.value!.compareTo(b.value!));
  return entries.map((e) => e.key).toList();
}

// ── Grade Changer ───────────────────────────────────────────────────────────

class _GradeChanger extends StatefulWidget {
  final List<GradedCourse> courses;
  final PlaygroundTotals totals;

  const _GradeChanger({required this.courses, required this.totals});

  @override
  State<_GradeChanger> createState() => _GradeChangerState();
}

class _GradeChangerState extends State<_GradeChanger> {
  /// course key → hypothetical grade
  final Map<String, String> _changes = {};

  @override
  Widget build(BuildContext context) {
    final result = applyGradeChanges(
      courses: widget.courses,
      totals: widget.totals,
      changes: _changes,
    );
    final impactsByKey = {for (final i in result.impacts) i.key: i};

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
      children: [
        _ProjectionBanner(
          baseline: result.baselineCgpa,
          projected: result.projectedCgpa,
          shift: result.shift,
          onReset: _changes.isEmpty ? null : () => setState(_changes.clear),
        ),
        const SizedBox(height: 12),
        const Text(
          'Change any grade to see what it would do',
          style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
        ),
        const SizedBox(height: 8),
        for (final course in widget.courses)
          _CourseChangeRow(
            course: course,
            selected: _changes[course.key],
            impact: impactsByKey[course.key]?.impact,
            onChanged: (grade) => setState(() {
              if (grade == null || grade == course.grade) {
                _changes.remove(course.key);
              } else {
                _changes[course.key] = grade;
              }
            }),
          ),
      ],
    );
  }
}

class _ProjectionBanner extends StatelessWidget {
  final double? baseline;
  final double? projected;
  final double? shift;
  final VoidCallback? onReset;

  const _ProjectionBanner({
    required this.baseline,
    required this.projected,
    required this.shift,
    required this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    final moved = shift != null && shift!.abs() > 0.0001;
    final up = (shift ?? 0) > 0;

    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('Projected CGPA',
                  style: TextStyle(
                      color: AppTheme.textSecondary, fontSize: 12)),
              const Spacer(),
              if (onReset != null)
                TextButton(
                  onPressed: onReset,
                  child: const Text('Reset',
                      style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                ),
            ],
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                projected?.toStringAsFixed(2) ?? '—',
                style: TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w800,
                  color: moved
                      ? (up ? AppTheme.green : Colors.redAccent)
                      : AppTheme.textPrimary,
                ),
              ),
              const SizedBox(width: 10),
              if (moved)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    '${up ? '+' : ''}${shift!.toStringAsFixed(2)}',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: up ? AppTheme.green : Colors.redAccent,
                    ),
                  ),
                ),
            ],
          ),
          Text(
            'Currently ${baseline?.toStringAsFixed(2) ?? '—'}',
            style: const TextStyle(color: AppTheme.textMuted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _CourseChangeRow extends StatelessWidget {
  final GradedCourse course;
  final String? selected;
  final double? impact;
  final ValueChanged<String?> onChanged;

  const _CourseChangeRow({
    required this.course,
    required this.selected,
    required this.impact,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final changed = selected != null;

    return GlassCard(
      margin: const EdgeInsets.only(bottom: 8),
      borderColor: changed ? AppTheme.green : AppTheme.border,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  course.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: AppTheme.textPrimary, fontSize: 13),
                ),
                const SizedBox(height: 2),
                Text(
                  '${course.semesterLabel} · ${_creditLabel(course.credits)} cr · now ${course.grade}',
                  style: const TextStyle(color: AppTheme.textMuted, fontSize: 11),
                ),
                if (impact != null && impact!.abs() > 0.0001)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      '${impact! > 0 ? '+' : ''}${impact!.toStringAsFixed(3)} CGPA',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: impact! > 0 ? AppTheme.green : Colors.redAccent,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 96,
            child: DropdownButtonFormField<String>(
              initialValue: selected ?? course.grade,
              isDense: true,
              dropdownColor: AppTheme.surface,
              style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13),
              decoration: const InputDecoration(
                isDense: true,
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              ),
              items: [
                for (final g in _selectableGrades())
                  DropdownMenuItem(value: g, child: Text(g)),
              ],
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}

String _creditLabel(double credits) =>
    credits == credits.roundToDouble() ? credits.toInt().toString() : '$credits';

// ── Reverse Solver ──────────────────────────────────────────────────────────

class _ReverseSolver extends StatefulWidget {
  final List<GradedCourse> courses;
  final PlaygroundTotals totals;

  const _ReverseSolver({required this.courses, required this.totals});

  @override
  State<_ReverseSolver> createState() => _ReverseSolverState();
}

class _ReverseSolverState extends State<_ReverseSolver> {
  late String _courseKey = widget.courses.first.key;
  final _targetCtrl = TextEditingController(text: '3.00');

  @override
  void initState() {
    super.initState();
    _targetCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _targetCtrl.dispose();
    super.dispose();
  }

  GradedCourse? get _course {
    for (final c in widget.courses) {
      if (c.key == _courseKey) return c;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final target = double.tryParse(_targetCtrl.text.trim());
    final result = solveForGrade(
      course: _course,
      totals: widget.totals,
      targetCgpa: target,
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
      children: [
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Current CGPA ${widget.totals.cgpa?.toStringAsFixed(2) ?? '—'} '
                'over ${_creditLabel(widget.totals.credits)} credits',
                style: const TextStyle(color: AppTheme.textMuted, fontSize: 12),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _courseKey,
                isExpanded: true,
                dropdownColor: AppTheme.surface,
                style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13),
                decoration: const InputDecoration(
                  labelText: 'Course',
                  labelStyle: TextStyle(color: AppTheme.textSecondary),
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final c in widget.courses)
                    DropdownMenuItem(
                      value: c.key,
                      child: Text('${c.name} (${c.grade})',
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (v) => setState(() => _courseKey = v ?? _courseKey),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _targetCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
                decoration: const InputDecoration(
                  labelText: 'Target CGPA',
                  labelStyle: TextStyle(color: AppTheme.textSecondary),
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _SolverResultCard(result: result, course: _course),
      ],
    );
  }
}

class _SolverResultCard extends StatelessWidget {
  final SolverResult result;
  final GradedCourse? course;

  const _SolverResultCard({required this.result, required this.course});

  @override
  Widget build(BuildContext context) {
    switch (result.outcome) {
      case SolverOutcome.invalid:
        return const _ResultShell(
          icon: '🎯',
          title: 'Enter a target between 0.00 and 4.00',
          detail: null,
          color: AppTheme.textSecondary,
        );

      case SolverOutcome.alreadyMet:
        return _ResultShell(
          icon: '🎉',
          title: "You've already reached that CGPA",
          detail: 'Any grade in ${course?.name ?? 'this course'} keeps you above it.',
          color: AppTheme.green,
        );

      case SolverOutcome.impossible:
        return _ResultShell(
          icon: '⛔',
          title: 'Not possible with this course alone',
          detail: 'Even an A would leave you at '
              '${result.resultingCgpa?.toStringAsFixed(2) ?? '—'}. '
              'You would need to improve more than one course.',
          color: Colors.redAccent,
        );

      case SolverOutcome.reachable:
        return GlassCard(
          borderColor: AppTheme.green,
          child: Column(
            children: [
              const Text('You need at least',
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
              const SizedBox(height: 6),
              Text(
                result.requiredGrade ?? '—',
                style: const TextStyle(
                  fontSize: 40,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.green,
                ),
              ),
              Text(
                '(${result.requiredGradePoint?.toStringAsFixed(1) ?? '—'} GP)',
                style: const TextStyle(color: AppTheme.textMuted, fontSize: 12),
              ),
              const SizedBox(height: 10),
              Text(
                'in ${course?.name ?? ''}'
                '${course == null ? '' : ' — currently ${course!.grade}'}',
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 4),
              Text(
                'That would put you at '
                '${result.resultingCgpa?.toStringAsFixed(2) ?? '—'}',
                style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13),
              ),
            ],
          ),
        );
    }
  }
}

class _ResultShell extends StatelessWidget {
  final String icon;
  final String title;
  final String? detail;
  final Color color;

  const _ResultShell({
    required this.icon,
    required this.title,
    required this.detail,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(icon, style: const TextStyle(fontSize: 22)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        color: color, fontSize: 14, fontWeight: FontWeight.w600)),
                if (detail != null) ...[
                  const SizedBox(height: 4),
                  Text(detail!,
                      style: const TextStyle(
                          color: AppTheme.textSecondary, fontSize: 12)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
