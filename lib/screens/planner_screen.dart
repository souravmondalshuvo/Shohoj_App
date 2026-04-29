import 'package:flutter/material.dart';
import '../data/catalog.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_card.dart';

class PlannerScreen extends StatefulWidget {
  const PlannerScreen({super.key});

  @override
  State<PlannerScreen> createState() => _PlannerScreenState();
}

class _PlannerScreenState extends State<PlannerScreen> {
  final List<_PlanEntry> _plan = [];

  double get _totalCredits => _plan.fold(0, (s, e) => s + e.credits);

  void _addCourse(String code, String name, double credits) {
    setState(() => _plan.add(_PlanEntry(code: code, name: name, credits: credits)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Semester Planner'),
        actions: [
          if (_plan.isNotEmpty)
            TextButton(
              onPressed: () => setState(() => _plan.clear()),
              child: const Text('Clear', style: TextStyle(color: AppTheme.textSecondary)),
            ),
        ],
      ),
      body: Column(
        children: [
          // Credit summary
          GlassCard(
            margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            borderColor: AppTheme.border,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Planned Credits', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                    Text(
                      _totalCredits.toStringAsFixed(1),
                      style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w800, color: AppTheme.green),
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text('Courses', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                    Text(
                      '${_plan.length}',
                      style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w700, color: AppTheme.textPrimary),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Course search & add
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: _CourseSearchField(onAdd: _addCourse),
          ),
          // Plan list
          Expanded(
            child: _plan.isEmpty
                ? const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.calendar_month_outlined, size: 48, color: AppTheme.textMuted),
                        SizedBox(height: 12),
                        Text('Your plan is empty', style: TextStyle(color: AppTheme.textSecondary)),
                        SizedBox(height: 4),
                        Text('Search and add courses above', style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
                      ],
                    ),
                  )
                : ReorderableListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
                    itemCount: _plan.length,
                    onReorder: (oldIdx, newIdx) {
                      setState(() {
                        if (newIdx > oldIdx) newIdx--;
                        final item = _plan.removeAt(oldIdx);
                        _plan.insert(newIdx, item);
                      });
                    },
                    itemBuilder: (ctx, i) {
                      final entry = _plan[i];
                      return GlassCard(
                        key: ValueKey(Object.hashAll([entry.code, entry.name, i])),
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        child: Row(
                          children: [
                            const Icon(Icons.drag_handle_rounded, color: AppTheme.textMuted, size: 18),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    entry.code,
                                    style: const TextStyle(fontWeight: FontWeight.w700, color: AppTheme.green, fontSize: 13),
                                  ),
                                  if (entry.name.isNotEmpty && entry.name != entry.code)
                                    Text(
                                      entry.name,
                                      style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                ],
                              ),
                            ),
                            Text(
                              '${entry.credits % 1 == 0 ? entry.credits.toInt() : entry.credits} cr',
                              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                            ),
                            const SizedBox(width: 10),
                            GestureDetector(
                              onTap: () => setState(() => _plan.removeAt(i)),
                              child: const Icon(Icons.close_rounded, size: 18, color: AppTheme.textMuted),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// ── Course Search Field with autocomplete ─────────────────────────────────────

class _CourseSearchField extends StatefulWidget {
  final void Function(String code, String name, double credits) onAdd;
  const _CourseSearchField({required this.onAdd});

  @override
  State<_CourseSearchField> createState() => _CourseSearchFieldState();
}

class _CourseSearchFieldState extends State<_CourseSearchField> {
  final _ctrl = TextEditingController();
  final _credCtrl = TextEditingController(text: '3');
  final _layerLink = LayerLink();
  OverlayEntry? _overlay;
  List<CourseInfo> _suggestions = [];
  CourseInfo? _selected;

  @override
  void dispose() {
    _ctrl.dispose();
    _credCtrl.dispose();
    _closeOverlay();
    super.dispose();
  }

  void _onChanged(String v) {
    _selected = null;
    final results = searchCourses(v);
    setState(() => _suggestions = results.take(8).toList());
    if (results.isNotEmpty && v.length >= 2) {
      _showOverlay();
    } else {
      _closeOverlay();
    }
  }

  void _pick(CourseInfo info) {
    _selected = info;
    _ctrl.text = info.code;
    _credCtrl.text = info.credits.toInt().toString();
    setState(() => _suggestions = []);
    _closeOverlay();
  }

  void _add() {
    final raw = _ctrl.text.trim().toUpperCase();
    if (raw.isEmpty) return;
    final credits = double.tryParse(_credCtrl.text.trim()) ?? 3.0;
    final info = _selected ?? kCourseDB[raw];
    widget.onAdd(raw, info?.name ?? '', credits);
    _ctrl.clear();
    _credCtrl.text = '3';
    _selected = null;
    setState(() => _suggestions = []);
    _closeOverlay();
  }

  void _showOverlay() {
    _closeOverlay();
    _overlay = OverlayEntry(
      builder: (_) => Positioned(
        width: 280,
        child: CompositedTransformFollower(
          link: _layerLink,
          showWhenUnlinked: false,
          offset: const Offset(0, 48),
          child: Material(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(12),
            elevation: 8,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: _suggestions.map((c) => InkWell(
                  onTap: () => _pick(c),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    child: Row(
                      children: [
                        Text(c.code,
                            style: const TextStyle(color: AppTheme.green, fontWeight: FontWeight.w700, fontSize: 13)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(c.name,
                              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                        ),
                        Text('${c.credits.toInt()} cr',
                            style: const TextStyle(color: AppTheme.textMuted, fontSize: 12)),
                      ],
                    ),
                  ),
                )).toList(),
              ),
            ),
          ),
        ),
      ),
    );
    Overlay.of(context).insert(_overlay!);
  }

  void _closeOverlay() {
    _overlay?.remove();
    _overlay = null;
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          flex: 3,
          child: CompositedTransformTarget(
            link: _layerLink,
            child: TextField(
              controller: _ctrl,
              textCapitalization: TextCapitalization.characters,
              onChanged: _onChanged,
              style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
              decoration: const InputDecoration(
                hintText: 'Course code (e.g. CSE110)',
                isDense: true,
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 64,
          child: TextField(
            controller: _credCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
            decoration: const InputDecoration(
              hintText: 'Cr.',
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            ),
          ),
        ),
        const SizedBox(width: 8),
        ElevatedButton(
          onPressed: _add,
          style: ElevatedButton.styleFrom(minimumSize: const Size(48, 44), padding: EdgeInsets.zero),
          child: const Icon(Icons.add_rounded, color: Colors.black),
        ),
      ],
    );
  }
}

class _PlanEntry {
  final String code;
  final String name;
  final double credits;
  _PlanEntry({required this.code, required this.name, this.credits = 3.0});
}
