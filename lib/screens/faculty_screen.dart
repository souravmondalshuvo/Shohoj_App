import 'package:flutter/material.dart';
import '../core/review_aggregation.dart';
import '../models/faculty_review.dart';
import '../services/firestore_service.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_card.dart';

class FacultyScreen extends StatefulWidget {
  const FacultyScreen({super.key});

  @override
  State<FacultyScreen> createState() => _FacultyScreenState();
}

class _FacultyScreenState extends State<FacultyScreen> {
  final _fs = FirestoreService();
  final _searchCtrl = TextEditingController();
  String _search = '';
  List<FacultyStats>? _allFaculty;
  Map<String, FacultyProfile> _profiles = const {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    // Profiles are a display concern only — the corpus is keyed by initials, so
    // a missing profile degrades to showing the initials rather than failing.
    final results = await Future.wait([
      _fs.knownFaculty(),
      _fs.facultyProfiles(),
    ]);
    if (!mounted) return;
    setState(() {
      _allFaculty = results[0] as List<FacultyStats>;
      _profiles = results[1] as Map<String, FacultyProfile>;
      _loading = false;
    });
  }

  String _nameFor(String initials) =>
      _profiles[initials]?.displayName ?? initials;

  List<FacultyStats> get _filtered {
    final all = _allFaculty ?? [];
    if (_search.isEmpty) return all;
    final q = _search.toLowerCase();
    return all
        .where((f) =>
            f.initials.toLowerCase().contains(q) ||
            _nameFor(f.initials).toLowerCase().contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Faculty')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (v) => setState(() => _search = v.trim()),
              style: const TextStyle(color: AppTheme.textPrimary),
              decoration: InputDecoration(
                hintText: 'Search faculty by name…',
                prefixIcon: const Icon(Icons.search_rounded, color: AppTheme.textSecondary),
                suffixIcon: _search.isNotEmpty
                    ? GestureDetector(
                        onTap: () { _searchCtrl.clear(); setState(() => _search = ''); },
                        child: const Icon(Icons.close_rounded, color: AppTheme.textSecondary),
                      )
                    : null,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: AppTheme.green));
    }
    final faculty = _filtered;
    if (faculty.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.person_search_rounded, size: 48, color: AppTheme.textMuted),
            const SizedBox(height: 12),
            Text(
              _search.isNotEmpty ? 'No faculty found for "$_search"' : 'No faculty data yet',
              style: const TextStyle(color: AppTheme.textSecondary),
            ),
          ],
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 80),
      itemCount: faculty.length,
      itemBuilder: (ctx, i) => _FacultyListTile(
        initials: faculty[i].initials,
        name: _nameFor(faculty[i].initials),
        reviewCount: faculty[i].reviewCount,
        onTap: () => Navigator.push(
          ctx,
          MaterialPageRoute(
            builder: (_) => FacultyDetailScreen(
              initials: faculty[i].initials,
              displayName: _nameFor(faculty[i].initials),
            ),
          ),
        ),
      ),
    );
  }
}

class _FacultyListTile extends StatelessWidget {
  final String initials;
  final String name;
  final int reviewCount;
  final VoidCallback onTap;
  const _FacultyListTile({
    required this.initials,
    required this.name,
    required this.reviewCount,
    required this.onTap,
  });

  String get _initials => initials;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      onTap: onTap,
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: AppTheme.greenGlow,
            child: Text(
              _initials,
              style: const TextStyle(color: AppTheme.green, fontWeight: FontWeight.w700, fontSize: 14),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              name,
              style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w500),
            ),
          ),
          const Icon(Icons.chevron_right_rounded, color: AppTheme.textMuted, size: 20),
        ],
      ),
    );
  }
}

// ── Faculty Detail Screen ────────────────────────────────────────────────────

class FacultyDetailScreen extends StatefulWidget {
  final String initials;
  final String displayName;
  const FacultyDetailScreen({
    super.key,
    required this.initials,
    required this.displayName,
  });

  @override
  State<FacultyDetailScreen> createState() => _FacultyDetailScreenState();
}

class _FacultyDetailScreenState extends State<FacultyDetailScreen> {
  final _fs = FirestoreService();
  FacultyStats? _stats;
  List<FacultyReview> _reviews = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final reviews = await _fs.reviewsForFaculty(widget.initials);
    if (!mounted) return;
    setState(() {
      _reviews = reviews;
      _stats = reviews.isEmpty
          ? null
          : aggregateFaculty(widget.initials.toUpperCase(), reviews);
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.displayName, maxLines: 1, overflow: TextOverflow.ellipsis)),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.green))
          : _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_stats == null) {
      return const Center(
        child: Text('No reviews found.', style: TextStyle(color: AppTheme.textSecondary)),
      );
    }

    final totalReviews = _stats!.reviewCount;
    final avgRating = _stats!.avgQuality;
    final avgDiff = _stats!.avgDifficulty;

    // Review counts per course taught, for the chips below.
    final courses = <String, int>{};
    for (final r in _reviews) {
      if (r.courseCode.isEmpty) continue;
      courses[r.courseCode] = (courses[r.courseCode] ?? 0) + 1;
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
      children: [
        // Stats banner
        GlassCard(
          borderColor: AppTheme.border,
          child: Row(
            children: [
              _StatCell(label: 'Reviews', value: '$totalReviews'),
              const _Divider(),
              _StatCell(
                label: 'Teaching',
                value: avgRating != null ? avgRating.toStringAsFixed(2) : '—',
                color: AppTheme.gold,
              ),
              const _Divider(),
              _StatCell(
                label: 'Avg Difficulty',
                value: avgDiff != null ? avgDiff.toStringAsFixed(2) : '—',
                color: _diffColor(avgDiff ?? 0),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // Courses taught
        if (courses.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text('Courses', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12, fontWeight: FontWeight.w600)),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: courses.keys.map((code) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: AppTheme.glass,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppTheme.border2),
              ),
              child: Text(
                '$code (${courses[code]})',
                style: const TextStyle(color: AppTheme.green, fontSize: 12, fontWeight: FontWeight.w600),
              ),
            )).toList(),
          ),
          const SizedBox(height: 16),
        ],
        // Recent reviews
        const Padding(
          padding: EdgeInsets.only(bottom: 8),
          child: Text('Reviews', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12, fontWeight: FontWeight.w600)),
        ),
        ..._reviews.map((r) => _ReviewCard(review: r)),
      ],
    );
  }

  Color _diffColor(double v) {
    if (v <= 1.5) return AppTheme.green;
    if (v <= 2.5) return const Color(0xFFA8D820);
    if (v <= 3.2) return AppTheme.gold;
    if (v <= 4.0) return Colors.orange;
    return Colors.redAccent;
  }
}

class _StatCell extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _StatCell({required this.label, required this.value, this.color = AppTheme.textPrimary});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(label, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
          const SizedBox(height: 4),
          Text(value, style: TextStyle(color: color, fontSize: 20, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) {
    return Container(width: 1, height: 36, color: AppTheme.border2);
  }
}

class _ReviewCard extends StatelessWidget {
  final FacultyReview review;
  const _ReviewCard({required this.review});

  @override
  Widget build(BuildContext context) {
    // The star row shows teaching quality — the closest single number to what
    // the old one-dimensional rating meant.
    final rating = review.ratings['teaching'] ?? 0;
    final difficulty = review.ratings['difficulty'] ?? 0;
    final comment = review.text;
    final code = review.courseCode;
    return GlassCard(
      margin: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (code.isNotEmpty)
                Text(code, style: const TextStyle(color: AppTheme.green, fontWeight: FontWeight.w700, fontSize: 13)),
              const Spacer(),
              Row(
                children: List.generate(
                  5,
                  (i) => Icon(
                    i < rating ? Icons.star_rounded : Icons.star_outline_rounded,
                    size: 14,
                    color: AppTheme.gold,
                  ),
                ),
              ),
            ],
          ),
          if (comment.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(comment, style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13)),
          ],
          const SizedBox(height: 6),
          Row(
            children: [
              if (difficulty > 0) _DifficultyChip(difficulty),
              const Spacer(),
              // No author is shown because none exists: review documents in
              // the shared corpus carry no uid, email or display name.
              Text(
                review.semester.isNotEmpty ? review.semester : 'Anonymous',
                style: const TextStyle(color: AppTheme.textMuted, fontSize: 11),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DifficultyChip extends StatelessWidget {
  final int level;
  const _DifficultyChip(this.level);

  String get _label => ['', 'Easy', 'Medium', 'Hard', 'Very Hard', 'Brutal'][level.clamp(0, 5)];
  Color get _color => [
    Colors.transparent,
    AppTheme.green,
    const Color(0xFF3498DB),
    AppTheme.gold,
    Colors.orange,
    Colors.redAccent,
  ][level.clamp(0, 5)];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: _color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _color.withValues(alpha: 0.4)),
      ),
      child: Text(_label, style: TextStyle(color: _color, fontSize: 11, fontWeight: FontWeight.w600)),
    );
  }
}
