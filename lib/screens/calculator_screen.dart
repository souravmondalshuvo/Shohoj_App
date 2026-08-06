import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../core/gpa.dart';
import '../data/departments.dart';
import '../models/app_state.dart';
import '../models/course.dart';
import '../models/semester.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../services/sync/user_state_sync.dart';
import '../services/transcript_import_service.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_card.dart';
import '../widgets/gpa_chart.dart';
import '../widgets/liquid_glass.dart';
import 'profile_screen.dart';
import 'transcript_import_sheet.dart';

class CalculatorScreen extends StatefulWidget {
  const CalculatorScreen({super.key});

  @override
  State<CalculatorScreen> createState() => _CalculatorScreenState();
}

class _CalculatorScreenState extends State<CalculatorScreen> {
  final _fs = FirestoreService();

  /// The whole shared state document, not just the semester list. Held intact
  /// so fields this screen does not edit — planner selections, intake term,
  /// department — survive a save instead of being dropped.
  AppState _state = AppState();

  late final UserStateSync _sync = UserStateSync(store: _fs);
  StreamSubscription<AppState>? _remoteSub;

  bool _loading = true;
  bool _importing = false;
  String? _selectedDept;

  List<Semester> get _semesters => _state.semesters;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _remoteSub?.cancel();
    _sync.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final loaded = await _fs.loadState();
    if (!mounted) return;

    setState(() {
      _state = loaded ?? AppState();
      if (_state.semesters.isEmpty) {
        _state.semesters.add(_newSem());
        _state.semesterCounter = _state.semesters.length;
      }
      _loading = false;
    });

    // Seed the comparison baseline with what was actually loaded, so the first
    // genuine remote change is measured against it rather than against nothing.
    _sync.seed(_state);
    _remoteSub = _sync.remoteChanges.listen(_applyRemote, onError: (_) {});
    _sync.start();
  }

  /// Applies a change made on another device — the web app, or a second phone.
  void _applyRemote(AppState incoming) {
    if (!mounted) return;
    setState(() => _state = incoming);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Updated from another device'),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 2),
      ),
    );
  }

  /// Allocates the next semester id.
  ///
  /// Ids are ints because the web discards any block whose id is not a number.
  /// `semesterCounter` is the shared allocator, so ids stay unique across both
  /// clients rather than colliding on list length.
  Semester _newSem() => Semester(
        id: _state.semesterCounter,
        name: 'Semester ${_state.semesterCounter + 1}',
      );

  void _addSemester() {
    setState(() {
      _state.semesters.add(_newSem());
      _state.semesterCounter++;
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
    // Debounced and serialised by the sync layer, so a burst of edits is one
    // write and a queued save cannot overtake an in-flight one.
    await _sync.save(_state);
  }

  /// Cumulative totals, computed the way the web computes them.
  ///
  /// Naively summing every graded course disagrees with the website, because it
  /// counts superseded retake attempts and ignores transcript summary blocks —
  /// see lib/core/gpa.dart.
  CgpaTotals get _totals => calculateCgpaTotals(
        _semesters,
        startSeason: _state.startSeason,
        startYear: _state.startYear,
      );

  double? get _cgpa => _totals.cgpa;

  double get _totalCredits => _totals.earnedCredits;

  List<GpaDataPoint> get _chartPoints {
    return _semesters
        .where((s) => !s.running && !s.summary && semesterGpa(s) != null)
        .map((s) =>
            GpaDataPoint(s.name.replaceAll('Semester ', 'S'), semesterGpa(s)!))
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

  /// Reads a BRACU grade sheet and, once confirmed, replaces the transcript.
  ///
  /// Nothing is written until the parsed result has been reviewed — the parser
  /// cannot be validated against every layout, and a bad import would produce a
  /// wrong CGPA rather than an obvious failure.
  Future<void> _importTranscript() async {
    final messenger = ScaffoldMessenger.of(context);

    setState(() => _importing = true);
    final outcome = await TranscriptImportService().importTranscript();
    if (!mounted) return;
    setState(() => _importing = false);

    if (!outcome.isSuccess) {
      // A dismissed picker is not a failure worth reporting.
      if (outcome.failure == ImportFailure.cancelled) return;
      messenger.showSnackBar(SnackBar(
        content: Text(outcome.message),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 6),
      ));
      return;
    }

    final hasExisting = _state.semesters
        .any((s) => s.courses.any((c) => c.grade.isNotEmpty));

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => TranscriptImportSheet(
        result: outcome.result!,
        fileName: outcome.fileName ?? 'transcript.pdf',
        willReplaceExisting: hasExisting,
      ),
    );

    if (confirmed != true || !mounted) return;

    final imported = semestersFromParsed(outcome.result!.semesters);
    setState(() {
      _state.semesters
        ..clear()
        ..addAll(imported);
      _state.semesterCounter = imported.length;
      final dept = outcome.result!.detectedDept;
      if (dept != null) _selectedDept = _deptCodeFor(dept);
    });

    await _sync.save(_state, immediate: true);
    if (!mounted) return;

    messenger.showSnackBar(SnackBar(
      content: Text('Imported ${imported.length} semesters'),
      behavior: SnackBarBehavior.floating,
    ));
  }

  /// Maps the transcript's programme label back to a department code.
  String? _deptCodeFor(String label) {
    for (final entry in kDeptMap.entries) {
      if (label.contains('(${entry.key})')) return entry.key;
    }
    return null;
  }

  void _openProfile() {
    HapticFeedback.selectionClick();
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ProfileScreen()),
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
    final isCupertino = isCupertinoPlatform(context);
    final userInitial = user?.displayName?.trim().isNotEmpty == true
        ? user!.displayName!.trim()[0]
        : '?';

    return Scaffold(
      backgroundColor: isCupertino ? Colors.transparent : null,
      extendBody: isCupertino,
      appBar: AppBar(
        backgroundColor: isCupertino ? Colors.transparent : null,
        surfaceTintColor: Colors.transparent,
        title: const Text('CGPA Calculator'),
        actions: [
          IconButton(
            tooltip: 'Import grade sheet',
            onPressed: _importing ? null : _importTranscript,
            icon: _importing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppTheme.green),
                  )
                : const Icon(Icons.upload_file_outlined,
                    color: AppTheme.textSecondary),
          ),
          if (isCupertino)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: CupertinoButton(
                minimumSize: const Size(34, 34),
                padding: EdgeInsets.zero,
                onPressed: () {
                  HapticFeedback.lightImpact();
                  _addSemester();
                },
                child: const Icon(
                  CupertinoIcons.plus_circle_fill,
                  color: AppTheme.green,
                  size: 25,
                ),
              ),
            ),
          if (user != null)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Tooltip(
                message: 'Profile',
                child: Semantics(
                  button: true,
                  label: 'Open profile',
                  child: GestureDetector(
                    onTap: _openProfile,
                    child: SizedBox(
                      width: 40,
                      height: 40,
                      child: Center(
                        child: CircleAvatar(
                          radius: 16,
                          backgroundImage: user.photoURL != null ? NetworkImage(user.photoURL!) : null,
                          backgroundColor: AppTheme.greenDim,
                          child: user.photoURL == null
                              ? Text(userInitial,
                                  style: const TextStyle(color: Colors.white, fontSize: 12))
                              : null,
                        ),
                      ),
                    ),
                  ),
                ),
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
                  setState(() => _semesters[i].name = label);
                  _save();
                },
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: isCupertino
          ? null
          : FloatingActionButton.extended(
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
        child: const Row(
          children: [
            Icon(Icons.school_outlined, color: AppTheme.textMuted, size: 18),
            SizedBox(width: 8),
            Expanded(
              child: Text('Select your department to track degree progress',
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
            ),
            Icon(Icons.chevron_right_rounded, color: AppTheme.textMuted, size: 18),
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
                  controller: TextEditingController(text: semester.name)
                    ..selection = TextSelection.collapsed(offset: semester.name.length),
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
