import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../services/firestore_service.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_card.dart';

class ReviewsScreen extends StatefulWidget {
  const ReviewsScreen({super.key});

  @override
  State<ReviewsScreen> createState() => _ReviewsScreenState();
}

class _ReviewsScreenState extends State<ReviewsScreen> {
  final _searchController = TextEditingController();
  String _search = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Course Reviews')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: TextField(
              controller: _searchController,
              onChanged: (v) => setState(() => _search = v.trim()),
              style: const TextStyle(color: AppTheme.textPrimary),
              decoration: InputDecoration(
                hintText: 'Search by course code or name…',
                prefixIcon: const Icon(Icons.search_rounded, color: AppTheme.textSecondary),
                suffixIcon: _search.isNotEmpty
                    ? GestureDetector(
                        onTap: () {
                          _searchController.clear();
                          setState(() => _search = '');
                        },
                        child: const Icon(Icons.close_rounded, color: AppTheme.textSecondary),
                      )
                    : null,
              ),
            ),
          ),
          const SizedBox(height: 8),
          if (_search.length >= 2)
            Expanded(child: _ReviewList(courseQuery: _search))
          else
            const Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.search_rounded, size: 48, color: AppTheme.textMuted),
                    SizedBox(height: 12),
                    Text(
                      'Search for a course to see reviews',
                      style: TextStyle(color: AppTheme.textSecondary),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'e.g. CSE110, MAT110, ENG101',
                      style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
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
            return _ReviewCard(data: d);
          },
        );
      },
    );
  }
}

class _ReviewCard extends StatelessWidget {
  final Map<String, dynamic> data;
  const _ReviewCard({required this.data});

  @override
  Widget build(BuildContext context) {
    final rating = (data['rating'] as num?)?.toInt() ?? 0;
    final difficulty = (data['difficulty'] as num?)?.toInt() ?? 0;
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
                    Text(
                      data['facultyName'] ?? 'Unknown Faculty',
                      style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                    ),
                  ],
                ),
              ),
              // Stars
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
              _DifficultyChip(difficulty),
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
            const Text('Write a Review', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
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
