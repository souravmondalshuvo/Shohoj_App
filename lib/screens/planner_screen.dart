import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_card.dart';

// Lightweight planner — add courses to a semester plan and track credits.
// Full prereq logic requires the catalog data (to be ported from catalog.js).

class PlannerScreen extends StatefulWidget {
  const PlannerScreen({super.key});

  @override
  State<PlannerScreen> createState() => _PlannerScreenState();
}

class _PlannerScreenState extends State<PlannerScreen> {
  final List<_PlanEntry> _plan = [];
  final _codeCtrl = TextEditingController();
  final _credCtrl = TextEditingController();

  double get _totalCredits => _plan.fold(0, (s, e) => s + e.credits);

  void _addCourse() {
    final code = _codeCtrl.text.trim().toUpperCase();
    final credits = double.tryParse(_credCtrl.text.trim()) ?? 3.0;
    if (code.isEmpty) return;
    setState(() => _plan.add(_PlanEntry(code: code, credits: credits)));
    _codeCtrl.clear();
    _credCtrl.clear();
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    _credCtrl.dispose();
    super.dispose();
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
          // Add course row
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: _codeCtrl,
                    textCapitalization: TextCapitalization.characters,
                    style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
                    decoration: const InputDecoration(
                      hintText: 'Course code (e.g. CSE110)',
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
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
                  onPressed: _addCourse,
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(48, 44),
                    padding: EdgeInsets.zero,
                  ),
                  child: const Icon(Icons.add_rounded, color: Colors.black),
                ),
              ],
            ),
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
                        Text('Add courses above to start planning', style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
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
                        key: ValueKey(entry),
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        child: Row(
                          children: [
                            const Icon(Icons.drag_handle_rounded, color: AppTheme.textMuted, size: 18),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                entry.code,
                                style: const TextStyle(fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
                              ),
                            ),
                            Text(
                              '${entry.credits} cr',
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

class _PlanEntry {
  final String code;
  final double credits;
  _PlanEntry({required this.code, required this.credits});
}
