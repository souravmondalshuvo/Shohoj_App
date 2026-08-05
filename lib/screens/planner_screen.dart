import 'package:flutter/material.dart';

import '../core/gpa.dart';
import '../core/planner.dart';
import '../data/catalog.dart';
import '../models/app_state.dart';
import '../services/firestore_service.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_card.dart';

/// Prerequisite-aware semester planning over the student's real transcript.
///
/// The plan lives in `planCourses` on the shared state document, so it survives
/// a restart and shows up on the website. It previously lived in a local list
/// and was lost the moment the screen closed.
class PlannerScreen extends StatefulWidget {
  const PlannerScreen({super.key});

  @override
  State<PlannerScreen> createState() => _PlannerScreenState();
}

class _PlannerScreenState extends State<PlannerScreen> {
  final _fs = FirestoreService();
  final _searchCtrl = TextEditingController();

  AppState? _state;
  bool _loading = true;
  bool _saving = false;
  String _search = '';
  PlannerFilter _filter = PlannerFilter.all;

  /// Grade assumed across the whole plan for the projection.
  String _assumedGrade = 'B';

  static final List<CatalogCourse> _catalog = [
    for (final c in kAllCourses)
      CatalogCourse(c.code, c.name, c.credits.toDouble()),
  ];
  static final Map<String, CatalogCourse> _catalogMap = {
    for (final c in _catalog) c.code: c,
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final loaded = await _fs.loadState();
    if (!mounted) return;
    setState(() {
      _state = loaded ?? AppState();
      _loading = false;
    });
  }

  Future<void> _persist() async {
    final state = _state;
    if (state == null) return;
    setState(() => _saving = true);
    try {
      await _fs.saveState(state);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _add(String code) {
    setState(() => _state!.planCourses.add(code));
    _persist();
  }

  void _remove(String code) {
    setState(() => _state!.planCourses.remove(code));
    _persist();
  }

  Set<String> get _superseded => retakenKeys(
        _state!.semesters,
        startSeason: _state!.startSeason,
        startYear: _state!.startYear,
      );

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: AppTheme.green)),
      );
    }

    final state = _state!;
    final plan = state.planCourses;
    final validation = validatePlan(
      planCourses: plan,
      catalog: _catalogMap,
      semesters: state.semesters,
      superseded: _superseded,
    );

    final totals = calculateCgpaTotals(
      state.semesters,
      startSeason: state.startSeason,
      startYear: state.startYear,
    );
    final projection = projectCgpa(
      currentPoints: totals.points,
      currentCredits: totals.cgpaCredits,
      plannedCredits: validation.totalCredits,
      assumedGrade: _assumedGrade,
    );

    final available = availableCourses(
      catalog: _catalog,
      semesters: state.semesters,
      planCourses: plan,
      currentDept: state.currentDept,
      superseded: _superseded,
      searchQuery: _search,
      filter: _filter,
      limit: 60,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Semester Planner'),
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: Center(
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: AppTheme.green),
                ),
              ),
            )
          else if (plan.isNotEmpty)
            TextButton(
              onPressed: () {
                setState(plan.clear);
                _persist();
              },
              child: const Text('Clear',
                  style: TextStyle(color: AppTheme.textSecondary)),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
        children: [
          _PlanSummary(
            validation: validation,
            projection: projection,
            assumedGrade: _assumedGrade,
            onGradeChanged: (g) => setState(() => _assumedGrade = g),
          ),
          const SizedBox(height: 12),
          if (plan.isNotEmpty) ...[
            const _SectionLabel('Your plan'),
            for (final code in plan)
              _PlannedRow(
                code: code,
                name: _catalogMap[code]?.name ?? code,
                credits: _catalogMap[code]?.credits ?? 0,
                onRemove: () => _remove(code),
              ),
            const SizedBox(height: 12),
          ],
          const _SectionLabel('Add courses'),
          TextField(
            controller: _searchCtrl,
            onChanged: (v) => setState(() => _search = v),
            style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
            decoration: const InputDecoration(
              hintText: 'Search by code or name',
              hintStyle: TextStyle(color: AppTheme.textMuted),
              prefixIcon:
                  Icon(Icons.search, color: AppTheme.textMuted, size: 20),
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              for (final f in PlannerFilter.values)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(switch (f) {
                      PlannerFilter.all => 'All',
                      PlannerFilter.unlocked => 'Available now',
                      PlannerFilter.locked => 'Blocked',
                    }),
                    selected: _filter == f,
                    onSelected: (_) => setState(() => _filter = f),
                    selectedColor: AppTheme.greenDim,
                    labelStyle: TextStyle(
                      fontSize: 12,
                      color:
                          _filter == f ? AppTheme.green : AppTheme.textSecondary,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (available.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text('Nothing matches',
                    style: TextStyle(color: AppTheme.textSecondary)),
              ),
            ),
          for (final course in available)
            _AvailableRow(course: course, onAdd: () => _add(course.code)),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          text,
          style: const TextStyle(
            color: AppTheme.textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
}

class _PlanSummary extends StatelessWidget {
  final PlanValidation validation;
  final CgpaProjection projection;
  final String assumedGrade;
  final ValueChanged<String> onGradeChanged;

  const _PlanSummary({
    required this.validation,
    required this.projection,
    required this.assumedGrade,
    required this.onGradeChanged,
  });

  @override
  Widget build(BuildContext context) {
    final credits = validation.totalCredits;
    final label = credits == credits.roundToDouble()
        ? credits.toInt().toString()
        : credits.toString();

    return GlassCard(
      borderColor:
          validation.issues.isNotEmpty ? Colors.redAccent : AppTheme.border,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Planned credits',
                      style: TextStyle(
                          color: AppTheme.textSecondary, fontSize: 12)),
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              if (projection.projected != null)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text('Projected CGPA',
                        style: TextStyle(
                            color: AppTheme.textSecondary, fontSize: 12)),
                    Text(
                      projection.projected!.toStringAsFixed(2),
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.green,
                      ),
                    ),
                    if (projection.delta != null)
                      Text(
                        '${projection.delta! >= 0 ? '+' : ''}'
                        '${projection.delta!.toStringAsFixed(2)} if all $assumedGrade',
                        style: const TextStyle(
                            color: AppTheme.textMuted, fontSize: 11),
                      ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Text('Assume ',
                  style:
                      TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
              DropdownButton<String>(
                value: assumedGrade,
                isDense: true,
                dropdownColor: AppTheme.surface,
                underline: const SizedBox.shrink(),
                style: const TextStyle(color: AppTheme.green, fontSize: 13),
                items: [
                  for (final g in ['A', 'A-', 'B+', 'B', 'B-', 'C+', 'C'])
                    DropdownMenuItem(value: g, child: Text(g)),
                ],
                onChanged: (v) => onGradeChanged(v ?? assumedGrade),
              ),
              const Text(' in every planned course',
                  style:
                      TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
            ],
          ),
          for (final issue in validation.issues)
            _Note(
                text: issue, color: Colors.redAccent, icon: Icons.error_outline),
          for (final warning in validation.warnings)
            _Note(
                text: warning,
                color: AppTheme.gold,
                icon: Icons.warning_amber_rounded),
        ],
      ),
    );
  }
}

class _Note extends StatelessWidget {
  final String text;
  final Color color;
  final IconData icon;
  const _Note({required this.text, required this.color, required this.icon});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 6),
            Expanded(
              child: Text(text, style: TextStyle(color: color, fontSize: 12)),
            ),
          ],
        ),
      );
}

class _PlannedRow extends StatelessWidget {
  final String code;
  final String name;
  final double credits;
  final VoidCallback onRemove;

  const _PlannedRow({
    required this.code,
    required this.name,
    required this.credits,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      margin: const EdgeInsets.only(bottom: 8),
      borderColor: AppTheme.green,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(code,
                    style: const TextStyle(
                        color: AppTheme.green,
                        fontWeight: FontWeight.w700,
                        fontSize: 13)),
                Text(name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: AppTheme.textPrimary, fontSize: 13)),
                Text('${credits.toStringAsFixed(0)} cr',
                    style: const TextStyle(
                        color: AppTheme.textMuted, fontSize: 11)),
              ],
            ),
          ),
          IconButton(
            onPressed: onRemove,
            icon: const Icon(Icons.remove_circle_outline,
                color: AppTheme.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _AvailableRow extends StatelessWidget {
  final AvailableCourse course;
  final VoidCallback onAdd;

  const _AvailableRow({required this.course, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      margin: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(course.code,
                        style: TextStyle(
                          color: course.canTake
                              ? AppTheme.green
                              : AppTheme.textSecondary,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        )),
                    if (course.unlockCount > 0) ...[
                      const SizedBox(width: 8),
                      Text('unlocks ${course.unlockCount}',
                          style: const TextStyle(
                              color: AppTheme.textMuted, fontSize: 11)),
                    ],
                  ],
                ),
                Text(course.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: AppTheme.textPrimary, fontSize: 13)),
                Text('${course.credits.toStringAsFixed(0)} cr',
                    style: const TextStyle(
                        color: AppTheme.textMuted, fontSize: 11)),
                if (course.missingHard.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text('Needs ${course.missingHard.join(', ')}',
                        style: const TextStyle(
                            color: Colors.redAccent, fontSize: 11)),
                  )
                else if (course.missingSoft.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                        'Recommended first: ${course.missingSoft.join(', ')}',
                        style: const TextStyle(
                            color: AppTheme.gold, fontSize: 11)),
                  ),
              ],
            ),
          ),
          IconButton(
            onPressed: onAdd,
            icon: Icon(
              Icons.add_circle_outline,
              color: course.canTake ? AppTheme.green : AppTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
