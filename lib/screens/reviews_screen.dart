import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../services/firestore_service.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_card.dart';
import 'faculty_screen.dart';

// Top-level departments shown in browse tab (ordered by popularity)
const _kBrowseDepts = [
  ('CSE', 'Computer Science & Eng.'),
  ('EEE', 'Electrical & Electronic Eng.'),
  ('BBA', 'Business Administration'),
  ('ECO', 'Economics'),
  ('ENG', 'English'),
  ('ECE', 'Electronic & Communication Eng.'),
  ('ANT', 'Anthropology'),
  ('ARC', 'Architecture'),
  ('PHR', 'Pharmacy'),
  ('LLB', 'Law'),
  ('PHY', 'Physics'),
  ('MAT', 'Mathematics'),
  ('MIC', 'Microbiology'),
  ('BIO', 'Biotechnology'),
  ('CS',  'Computer Science'),
  ('APE', 'Applied Physics & Electronics'),
];

class ReviewsScreen extends StatefulWidget {
  const ReviewsScreen({super.key});

  @override
  State<ReviewsScreen> createState() => _ReviewsScreenState();
}

class _ReviewsScreenState extends State<ReviewsScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  final _searchController = TextEditingController();
  String _search = '';

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Course Reviews'),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_search_rounded),
            color: AppTheme.textSecondary,
            tooltip: 'Browse Faculty',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const FacultyScreen()),
            ),
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: AppTheme.green,
          labelColor: AppTheme.green,
          unselectedLabelColor: AppTheme.textSecondary,
          tabs: const [
            Tab(text: 'Search'),
            Tab(text: 'Browse'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _SearchTab(
            searchController: _searchController,
            search: _search,
            onSearchChanged: (v) => setState(() => _search = v.trim()),
          ),
          const _BrowseTab(),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showSubmitSheet(context),
        backgroundColor: AppTheme.green,
        foregroundColor: Colors.black,
        icon: const Icon(Icons.rate_review_rounded),
        label: const Text('Write a Review', style: TextStyle(fontWeight: FontWeight.w700)),
      ),
    );
  }

  void _showSubmitSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const _ReviewSubmitSheet(),
    );
  }
}

// ── Search Tab ─────────────────────────────────────────────────────────────────

class _SearchTab extends StatelessWidget {
  final TextEditingController searchController;
  final String search;
  final void Function(String) onSearchChanged;

  const _SearchTab({
    required this.searchController,
    required this.search,
    required this.onSearchChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: TextField(
            controller: searchController,
            onChanged: onSearchChanged,
            style: const TextStyle(color: AppTheme.textPrimary),
            decoration: InputDecoration(
              hintText: 'Search by course code or name…',
              prefixIcon: const Icon(Icons.search_rounded, color: AppTheme.textSecondary),
              suffixIcon: search.isNotEmpty
                  ? GestureDetector(
                      onTap: () => onSearchChanged(''),
                      child: const Icon(Icons.close_rounded, color: AppTheme.textSecondary),
                    )
                  : null,
            ),
          ),
        ),
        const SizedBox(height: 8),
        if (search.length >= 2)
          Expanded(child: _ReviewList(courseQuery: search))
        else
          const Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.search_rounded, size: 48, color: AppTheme.textMuted),
                  SizedBox(height: 12),
                  Text('Search for a course to see reviews', style: TextStyle(color: AppTheme.textSecondary)),
                  SizedBox(height: 4),
                  Text('e.g. CSE110, MAT110, ENG101', style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

// ── Browse Tab ─────────────────────────────────────────────────────────────────

class _BrowseTab extends StatelessWidget {
  const _BrowseTab();

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
      itemCount: _kBrowseDepts.length,
      itemBuilder: (ctx, i) {
        final (code, label) = _kBrowseDepts[i];
        return GlassCard(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          onTap: () => Navigator.push(
            ctx,
            MaterialPageRoute(
              builder: (_) => _DeptReviewsScreen(deptCode: code, deptLabel: label),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppTheme.greenGlow,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppTheme.border),
                ),
                child: Center(
                  child: Text(
                    code,
                    style: const TextStyle(
                      color: AppTheme.green,
                      fontWeight: FontWeight.w800,
                      fontSize: 11,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(label, style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w500)),
              ),
              const Icon(Icons.chevron_right_rounded, color: AppTheme.textMuted, size: 20),
            ],
          ),
        );
      },
    );
  }
}

// ── Dept Reviews Screen ────────────────────────────────────────────────────────

class _DeptReviewsScreen extends StatelessWidget {
  final String deptCode;
  final String deptLabel;
  const _DeptReviewsScreen({required this.deptCode, required this.deptLabel});

  @override
  Widget build(BuildContext context) {
    final fs = FirestoreService();
    return Scaffold(
      appBar: AppBar(title: Text(deptCode)),
      body: StreamBuilder<QuerySnapshot>(
        stream: fs.reviewsForDept(deptCode),
        builder: (ctx, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: AppTheme.green));
          }
          final docs = snap.data?.docs ?? [];
          if (docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.rate_review_outlined, size: 48, color: AppTheme.textMuted),
                  const SizedBox(height: 12),
                  Text('No reviews for $deptCode yet',
                      style: const TextStyle(color: AppTheme.textSecondary)),
                ],
              ),
            );
          }
          // Group by course
          final byCourse = <String, List<Map<String, dynamic>>>{};
          for (final doc in docs) {
            final d = doc.data() as Map<String, dynamic>;
            final code = d['courseCode'] as String? ?? '';
            byCourse.putIfAbsent(code, () => []).add(d);
          }
          final codes = byCourse.keys.toList()..sort();
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
            itemCount: codes.length,
            itemBuilder: (ctx2, i) {
              final code = codes[i];
              final revs = byCourse[code]!;
              final avgRating = revs.map((r) => (r['rating'] as num?)?.toDouble() ?? 0).fold(0.0, (a, b) => a + b) / revs.length;
              return GlassCard(
                margin: const EdgeInsets.only(bottom: 10),
                onTap: () => Navigator.push(
                  ctx2,
                  MaterialPageRoute(builder: (_) => _CourseReviewsScreen(courseCode: code)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(code,
                              style: const TextStyle(color: AppTheme.green, fontWeight: FontWeight.w700, fontSize: 14)),
                          Text('${revs.length} review${revs.length == 1 ? '' : 's'}',
                              style: const TextStyle(color: AppTheme.textMuted, fontSize: 12)),
                        ],
                      ),
                    ),
                    Row(
                      children: List.generate(5, (j) => Icon(
                        j < avgRating.round() ? Icons.star_rounded : Icons.star_outline_rounded,
                        size: 14,
                        color: AppTheme.gold,
                      )),
                    ),
                    const SizedBox(width: 8),
                    const Icon(Icons.chevron_right_rounded, color: AppTheme.textMuted, size: 18),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

// ── Course Reviews Screen ──────────────────────────────────────────────────────

class _CourseReviewsScreen extends StatelessWidget {
  final String courseCode;
  const _CourseReviewsScreen({required this.courseCode});

  @override
  Widget build(BuildContext context) {
    final fs = FirestoreService();
    return Scaffold(
      appBar: AppBar(title: Text(courseCode)),
      body: StreamBuilder<QuerySnapshot>(
        stream: fs.reviewsForCourse(courseCode),
        builder: (ctx, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: AppTheme.green));
          }
          final docs = snap.data?.docs ?? [];
          if (docs.isEmpty) {
            return const Center(
              child: Text('No reviews yet.', style: TextStyle(color: AppTheme.textSecondary)),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
            itemCount: docs.length,
            itemBuilder: (ctx2, i) {
              final d = docs[i].data() as Map<String, dynamic>;
              return _ReviewCard(data: d, showFacultyLink: true);
            },
          );
        },
      ),
    );
  }
}

// ── Review List (search) ───────────────────────────────────────────────────────

class _ReviewList extends StatelessWidget {
  final String courseQuery;
  const _ReviewList({required this.courseQuery});

  @override
  Widget build(BuildContext context) {
    final fs = FirestoreService();
    return StreamBuilder<QuerySnapshot>(
      stream: fs.reviewsForCourse(courseQuery.toUpperCase()),
      builder: (ctx, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: AppTheme.green));
        }
        final docs = snap.data?.docs ?? [];
        if (docs.isEmpty) {
          return const Center(
            child: Text('No reviews yet for this course.', style: TextStyle(color: AppTheme.textSecondary)),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
          itemCount: docs.length,
          itemBuilder: (ctx, i) {
            final d = docs[i].data() as Map<String, dynamic>;
            return _ReviewCard(data: d, showFacultyLink: true);
          },
        );
      },
    );
  }
}

// ── Review Card ────────────────────────────────────────────────────────────────

class _ReviewCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final bool showFacultyLink;
  const _ReviewCard({required this.data, this.showFacultyLink = false});

  @override
  Widget build(BuildContext context) {
    final rating = (data['rating'] as num?)?.toInt() ?? 0;
    final difficulty = (data['difficulty'] as num?)?.toInt() ?? 0;
    final facultyName = data['facultyName'] as String? ?? '';
    return GlassCard(
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      data['courseCode'] ?? '',
                      style: const TextStyle(color: AppTheme.green, fontWeight: FontWeight.w700, fontSize: 13),
                    ),
                    if (facultyName.isNotEmpty)
                      GestureDetector(
                        onTap: showFacultyLink
                            ? () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => FacultyDetailScreen(facultyName: facultyName),
                                  ),
                                )
                            : null,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              facultyName,
                              style: TextStyle(
                                color: showFacultyLink ? AppTheme.green.withValues(alpha: 0.7) : AppTheme.textSecondary,
                                fontSize: 12,
                                decoration: showFacultyLink ? TextDecoration.underline : null,
                                decorationColor: AppTheme.green.withValues(alpha: 0.5),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              Row(
                children: List.generate(5, (i) => Icon(
                  i < rating ? Icons.star_rounded : Icons.star_outline_rounded,
                  size: 16,
                  color: AppTheme.gold,
                )),
              ),
            ],
          ),
          if (data['comment'] != null && (data['comment'] as String).isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(data['comment'], style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14)),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              if (difficulty > 0) _DifficultyChip(difficulty),
              const Spacer(),
              Text(
                data['displayName'] ?? 'Anonymous',
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

// ── Submit Sheet ───────────────────────────────────────────────────────────────

class _ReviewSubmitSheet extends StatefulWidget {
  const _ReviewSubmitSheet();

  @override
  State<_ReviewSubmitSheet> createState() => _ReviewSubmitSheetState();
}

class _ReviewSubmitSheetState extends State<_ReviewSubmitSheet> {
  final _fs = FirestoreService();
  final _codeCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _facultyCtrl = TextEditingController();
  final _commentCtrl = TextEditingController();
  int _rating = 0;
  int _difficulty = 0;
  bool _submitting = false;

  @override
  void dispose() {
    _codeCtrl.dispose();
    _nameCtrl.dispose();
    _facultyCtrl.dispose();
    _commentCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_codeCtrl.text.trim().isEmpty || _rating == 0) return;
    setState(() => _submitting = true);
    await _fs.submitReview(
      courseCode: _codeCtrl.text.trim().toUpperCase(),
      courseName: _nameCtrl.text.trim(),
      facultyName: _facultyCtrl.text.trim(),
      rating: _rating,
      comment: _commentCtrl.text.trim(),
      difficulty: _difficulty,
    );
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20, right: 20, top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Write a Review',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
            const SizedBox(height: 16),
            TextField(
              controller: _codeCtrl,
              textCapitalization: TextCapitalization.characters,
              style: const TextStyle(color: AppTheme.textPrimary),
              decoration: const InputDecoration(labelText: 'Course Code *', hintText: 'e.g. CSE110'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _nameCtrl,
              style: const TextStyle(color: AppTheme.textPrimary),
              decoration: const InputDecoration(labelText: 'Course Name', hintText: 'e.g. Programming Language I'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _facultyCtrl,
              style: const TextStyle(color: AppTheme.textPrimary),
              decoration: const InputDecoration(labelText: 'Faculty Name', hintText: 'e.g. Md. John Doe'),
            ),
            const SizedBox(height: 16),
            const Text('Rating *', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
            const SizedBox(height: 6),
            Row(
              children: List.generate(5, (i) => GestureDetector(
                onTap: () => setState(() => _rating = i + 1),
                child: Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Icon(
                    i < _rating ? Icons.star_rounded : Icons.star_outline_rounded,
                    color: AppTheme.gold,
                    size: 32,
                  ),
                ),
              )),
            ),
            const SizedBox(height: 16),
            const Text('Difficulty', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              children: List.generate(5, (i) {
                final labels = ['Easy', 'Medium', 'Hard', 'Very Hard', 'Brutal'];
                final selected = _difficulty == i + 1;
                return ChoiceChip(
                  label: Text(labels[i]),
                  selected: selected,
                  onSelected: (_) => setState(() => _difficulty = i + 1),
                  selectedColor: AppTheme.greenGlow,
                  labelStyle: TextStyle(
                    color: selected ? AppTheme.green : AppTheme.textSecondary,
                    fontSize: 12,
                  ),
                );
              }),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _commentCtrl,
              maxLines: 3,
              style: const TextStyle(color: AppTheme.textPrimary),
              decoration: const InputDecoration(labelText: 'Comment', hintText: 'Share your experience…'),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _submitting ? null : _submit,
                child: _submitting
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2))
                    : const Text('Submit Review'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
