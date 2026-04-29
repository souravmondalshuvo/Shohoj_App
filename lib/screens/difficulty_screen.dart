import 'package:flutter/material.dart';
import '../services/firestore_service.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_card.dart';

enum _SortMode { difficulty, rating, reviews, code }

class DifficultyScreen extends StatefulWidget {
  const DifficultyScreen({super.key});

  @override
  State<DifficultyScreen> createState() => _DifficultyScreenState();
}

class _DifficultyScreenState extends State<DifficultyScreen> {
  final _fs = FirestoreService();
  List<DifficultyEntry>? _all;
  String _error = '';
  _SortMode _sort = _SortMode.difficulty;
  String _filterDept = '';
  final _searchCtrl = TextEditingController();
  String _search = '';

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
    try {
      final data = await _fs.loadDifficultyMap(minReviews: 3);
      if (mounted) setState(() => _all = data);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  List<DifficultyEntry> get _filtered {
    var list = _all ?? [];
    if (_filterDept.isNotEmpty) {
      list = list.where((e) => e.courseCode.startsWith(_filterDept)).toList();
    }
    if (_search.isNotEmpty) {
      final q = _search.toUpperCase();
      list = list
          .where((e) =>
              e.courseCode.contains(q) ||
              e.courseName.toUpperCase().contains(q))
          .toList();
    }
    switch (_sort) {
      case _SortMode.difficulty:
        list.sort((a, b) => b.avgDifficulty.compareTo(a.avgDifficulty));
      case _SortMode.rating:
        list.sort((a, b) => b.avgRating.compareTo(a.avgRating));
      case _SortMode.reviews:
        list.sort((a, b) => b.reviewCount.compareTo(a.reviewCount));
      case _SortMode.code:
        list.sort((a, b) => a.courseCode.compareTo(b.courseCode));
    }
    return list;
  }

  Set<String> get _deptPrefixes {
    final all = _all ?? [];
    final prefixes = <String>{};
    for (final e in all) {
      final match = RegExp(r'^([A-Za-z]+)').firstMatch(e.courseCode);
      if (match != null) prefixes.add(match.group(1)!);
    }
    return prefixes;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Difficulty Map'),
        actions: [
          PopupMenuButton<_SortMode>(
            icon: const Icon(Icons.sort_rounded, color: AppTheme.textSecondary),
            color: AppTheme.surface,
            onSelected: (m) => setState(() => _sort = m),
            itemBuilder: (_) => const [
              PopupMenuItem(value: _SortMode.difficulty, child: Text('Sort: Hardest first')),
              PopupMenuItem(value: _SortMode.rating,     child: Text('Sort: Highest rated')),
              PopupMenuItem(value: _SortMode.reviews,    child: Text('Sort: Most reviewed')),
              PopupMenuItem(value: _SortMode.code,       child: Text('Sort: Course code')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (v) => setState(() => _search = v.trim()),
              style: const TextStyle(color: AppTheme.textPrimary),
              decoration: InputDecoration(
                hintText: 'Search course…',
                prefixIcon: const Icon(Icons.search_rounded, color: AppTheme.textSecondary),
                suffixIcon: _search.isNotEmpty
                    ? GestureDetector(
                        onTap: () {
                          _searchCtrl.clear();
                          setState(() => _search = '');
                        },
                        child: const Icon(Icons.close_rounded, color: AppTheme.textSecondary),
                      )
                    : null,
              ),
            ),
          ),
          // Dept filter chips
          if (_all != null && _deptPrefixes.isNotEmpty)
            SizedBox(
              height: 44,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                scrollDirection: Axis.horizontal,
                children: [
                  _FilterChip(
                    label: 'All',
                    selected: _filterDept.isEmpty,
                    onTap: () => setState(() => _filterDept = ''),
                  ),
                  ...(_deptPrefixes.toList()..sort()).map((d) => _FilterChip(
                        label: d,
                        selected: _filterDept == d,
                        onTap: () =>
                            setState(() => _filterDept = _filterDept == d ? '' : d),
                      )),
                ],
              ),
            ),
          const SizedBox(height: 8),
          // Content
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_error.isNotEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 36),
            const SizedBox(height: 8),
            Text('Failed to load', style: const TextStyle(color: AppTheme.textSecondary)),
            TextButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      );
    }

    if (_all == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: AppTheme.green),
            const SizedBox(height: 16),
            const Text('Aggregating reviews…', style: TextStyle(color: AppTheme.textSecondary)),
          ],
        ),
      );
    }

    final entries = _filtered;

    if (entries.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.map_outlined, size: 48, color: AppTheme.textMuted),
            SizedBox(height: 12),
            Text('No courses found', style: TextStyle(color: AppTheme.textSecondary)),
            SizedBox(height: 4),
            Text('Courses need ≥3 reviews to appear here', style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 80),
      itemCount: entries.length,
      itemBuilder: (ctx, i) => _DifficultyCard(entry: entries[i]),
    );
  }
}

// ── Difficulty card ────────────────────────────────────────────────────────────

class _DifficultyCard extends StatelessWidget {
  final DifficultyEntry entry;
  const _DifficultyCard({required this.entry});

  Color _diffColor(double v) {
    if (v <= 1.5) return AppTheme.green;
    if (v <= 2.5) return const Color(0xFFA8D820);
    if (v <= 3.2) return AppTheme.gold;
    if (v <= 4.0) return Colors.orange;
    return Colors.redAccent;
  }

  String _diffLabel(double v) {
    if (v <= 1.5) return 'Easy';
    if (v <= 2.5) return 'Moderate';
    if (v <= 3.2) return 'Challenging';
    if (v <= 4.0) return 'Hard';
    return 'Brutal';
  }

  @override
  Widget build(BuildContext context) {
    final diffColor = _diffColor(entry.avgDifficulty);
    return GlassCard(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          // Difficulty badge
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: diffColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: diffColor.withValues(alpha: 0.35)),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  entry.avgDifficulty.toStringAsFixed(1),
                  style: TextStyle(
                    color: diffColor,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    height: 1,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '/5',
                  style: TextStyle(color: diffColor.withValues(alpha: 0.7), fontSize: 10),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.courseCode,
                  style: const TextStyle(
                    color: AppTheme.green,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  entry.courseName,
                  style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: diffColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: diffColor.withValues(alpha: 0.4)),
                      ),
                      child: Text(
                        _diffLabel(entry.avgDifficulty),
                        style: TextStyle(color: diffColor, fontSize: 11, fontWeight: FontWeight.w600),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(Icons.star_rounded, size: 13, color: AppTheme.gold),
                    const SizedBox(width: 2),
                    Text(
                      entry.avgRating.toStringAsFixed(1),
                      style: const TextStyle(color: AppTheme.gold, fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                    const Spacer(),
                    Text(
                      '${entry.reviewCount} reviews',
                      style: const TextStyle(color: AppTheme.textMuted, fontSize: 11),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Filter chip ───────────────────────────────────────────────────────────────

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _FilterChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: selected ? AppTheme.greenGlow : AppTheme.glass,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? AppTheme.green : AppTheme.border2,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? AppTheme.green : AppTheme.textSecondary,
            fontSize: 12,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
