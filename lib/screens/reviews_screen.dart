import 'package:flutter/material.dart';
import '../models/faculty_review.dart';
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
        onPressed: () => _showSubmitUnavailable(context),
        backgroundColor: AppTheme.surface,
        foregroundColor: AppTheme.textSecondary,
        icon: const Icon(Icons.rate_review_outlined),
        label: const Text('Write a Review',
            style: TextStyle(fontWeight: FontWeight.w700)),
      ),
    );
  }

  /// Submitting is not wired up yet.
  ///
  /// Reviews in the shared corpus are written only by the Cloudflare Worker,
  /// which computes the pseudonymous document id server-side; clients are
  /// denied create by the rules. Saying so is better than a form that silently
  /// fails, which is what shipped before.
  void _showSubmitUnavailable(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('Not available yet',
            style: TextStyle(color: AppTheme.textPrimary, fontSize: 17)),
        content: const Text(
          'Writing reviews from the app is still being built. Reviews are '
          'submitted anonymously through the Shohoj web app for now — they '
          'show up here as soon as they are posted.',
          style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK', style: TextStyle(color: AppTheme.green)),
          ),
        ],
      ),
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
      body: StreamBuilder<List<FacultyReview>>(
        stream: fs.reviewsForDept(deptCode),
        builder: (ctx, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: AppTheme.green));
          }
          final docs = snap.data ?? const <FacultyReview>[];
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
          final byCourse = <String, List<FacultyReview>>{};
          for (final r in docs) {
            byCourse.putIfAbsent(r.courseCode, () => []).add(r);
          }
          final codes = byCourse.keys.toList()..sort();
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
            itemCount: codes.length,
            itemBuilder: (ctx2, i) {
              final code = codes[i];
              final revs = byCourse[code]!;
              // Teaching quality stands in for the old single rating.
              final avgRating = revs
                      .map((r) => (r.ratings['teaching'] ?? 0).toDouble())
                      .fold(0.0, (a, b) => a + b) /
                  revs.length;
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
      body: StreamBuilder<List<FacultyReview>>(
        stream: fs.reviewsForCourse(courseCode),
        builder: (ctx, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: AppTheme.green));
          }
          final docs = snap.data ?? const <FacultyReview>[];
          if (docs.isEmpty) {
            return const Center(
              child: Text('No reviews yet.', style: TextStyle(color: AppTheme.textSecondary)),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
            itemCount: docs.length,
            itemBuilder: (ctx2, i) {
              return _ReviewCard(review: docs[i], showFacultyLink: true);
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
    return StreamBuilder<List<FacultyReview>>(
      stream: fs.reviewsForCourse(courseQuery.toUpperCase()),
      builder: (ctx, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: AppTheme.green));
        }
        final docs = snap.data ?? const <FacultyReview>[];
        if (docs.isEmpty) {
          return const Center(
            child: Text('No reviews yet for this course.', style: TextStyle(color: AppTheme.textSecondary)),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
          itemCount: docs.length,
          itemBuilder: (ctx, i) {
            return _ReviewCard(review: docs[i], showFacultyLink: true);
          },
        );
      },
    );
  }
}

// ── Review Card ────────────────────────────────────────────────────────────────

class _ReviewCard extends StatelessWidget {
  final FacultyReview review;
  final bool showFacultyLink;
  const _ReviewCard({required this.review, this.showFacultyLink = false});

  @override
  Widget build(BuildContext context) {
    final rating = review.ratings['teaching'] ?? 0;
    final difficulty = review.ratings['difficulty'] ?? 0;
    // Faculty are keyed by initials in the shared corpus. Resolving them to a
    // full name needs facultyProfiles, which the detail screen loads.
    final initials = review.facultyInitials;
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
                      review.courseCode,
                      style: const TextStyle(color: AppTheme.green, fontWeight: FontWeight.w700, fontSize: 13),
                    ),
                    if (initials.isNotEmpty)
                      GestureDetector(
                        onTap: showFacultyLink
                            ? () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => FacultyDetailScreen(
                                      initials: initials,
                                      displayName: initials,
                                    ),
                                  ),
                                )
                            : null,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              initials,
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
          if (review.text.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(review.text,
                style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14)),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              if (difficulty > 0) _DifficultyChip(difficulty),
              const Spacer(),
              // No author: review documents carry no uid, email or name.
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

// ── Submit Sheet ───────────────────────────────────────────────────────────────
