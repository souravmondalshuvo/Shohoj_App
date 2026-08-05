import 'package:flutter/material.dart';

import '../models/faculty_review.dart';
import '../services/review_submit_service.dart';
import '../theme/app_theme.dart';

/// The five-dimension review form.
///
/// Faculty are identified by initials, matching the shared corpus. The old form
/// collected a full name and a single rating, neither of which the corpus has.
class ReviewSubmitSheet extends StatefulWidget {
  final String? courseCode;
  final String? facultyInitials;

  /// Injectable so tests and previews can avoid the network.
  final ReviewSubmitService? service;

  const ReviewSubmitSheet({
    super.key,
    this.courseCode,
    this.facultyInitials,
    this.service,
  });

  @override
  State<ReviewSubmitSheet> createState() => _ReviewSubmitSheetState();
}

class _ReviewSubmitSheetState extends State<ReviewSubmitSheet> {
  late final ReviewSubmitService _service = widget.service ?? ReviewSubmitService();

  late final _codeCtrl = TextEditingController(text: widget.courseCode ?? '');
  late final _initialsCtrl = TextEditingController(text: widget.facultyInitials ?? '');
  final _semesterCtrl = TextEditingController();
  final _textCtrl = TextEditingController();

  final Map<String, int> _ratings = {for (final k in kRatingKeys) k: 0};

  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Drives the live character counter.
    _textCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    _initialsCtrl.dispose();
    _semesterCtrl.dispose();
    _textCtrl.dispose();
    super.dispose();
  }

  bool get _complete => _ratings.values.every((v) => v > 0);

  Future<void> _submit() async {
    setState(() {
      _submitting = true;
      _error = null;
    });

    final result = await _service.submit(
      facultyInitials: _initialsCtrl.text,
      courseCode: _codeCtrl.text,
      ratings: Map<String, int>.from(_ratings),
      semester: _semesterCtrl.text,
      text: _textCtrl.text,
    );

    if (!mounted) return;

    if (result.isSuccess) {
      Navigator.pop(context, true);
      return;
    }

    setState(() {
      _submitting = false;
      _error = result.message;
    });
  }

  @override
  Widget build(BuildContext context) {
    final remaining = kMaxReviewTextChars - _textCtrl.text.trim().length;
    final overLimit = remaining < 0;

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Write a Review',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Posted anonymously. Your name is never attached.',
              style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 16),

            _field(_codeCtrl, 'Course code', hint: 'CSE110', caps: true),
            const SizedBox(height: 10),
            _field(
              _initialsCtrl,
              'Faculty initials',
              hint: 'MMR',
              caps: true,
              helper: 'As they appear on your class schedule',
            ),
            const SizedBox(height: 10),
            _field(_semesterCtrl, 'Semester (optional)', hint: 'Spring 2024'),

            const SizedBox(height: 18),
            for (final key in kRatingKeys) ...[
              _RatingRow(
                label: kRatingLabels[key]!,
                value: _ratings[key]!,
                onChanged: (v) => setState(() => _ratings[key] = v),
              ),
              const SizedBox(height: 6),
            ],

            const SizedBox(height: 10),
            TextField(
              controller: _textCtrl,
              maxLines: 4,
              style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
              decoration: InputDecoration(
                labelText: 'Your review (optional)',
                labelStyle: const TextStyle(color: AppTheme.textSecondary),
                helperText: '$remaining characters left',
                helperStyle: TextStyle(
                  color: overLimit ? Colors.redAccent : AppTheme.textMuted,
                  fontSize: 11,
                ),
                border: const OutlineInputBorder(),
              ),
            ),

            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: const TextStyle(color: Colors.redAccent, fontSize: 13),
              ),
            ],

            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: (_submitting || !_complete || overLimit) ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.green,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: _submitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.black,
                        ),
                      )
                    : Text(_complete ? 'Post review' : 'Rate all five to post'),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _field(
    TextEditingController ctrl,
    String label, {
    String? hint,
    String? helper,
    bool caps = false,
  }) {
    return TextField(
      controller: ctrl,
      textCapitalization:
          caps ? TextCapitalization.characters : TextCapitalization.sentences,
      style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        helperText: helper,
        helperStyle: const TextStyle(color: AppTheme.textMuted, fontSize: 11),
        labelStyle: const TextStyle(color: AppTheme.textSecondary),
        hintStyle: const TextStyle(color: AppTheme.textMuted),
        border: const OutlineInputBorder(),
      ),
    );
  }
}

class _RatingRow extends StatelessWidget {
  final String label;
  final int value;
  final ValueChanged<int> onChanged;

  const _RatingRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
          ),
        ),
        Row(
          children: List.generate(5, (i) {
            final score = i + 1;
            return Semantics(
              button: true,
              label: '$label $score of 5',
              child: IconButton(
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                padding: EdgeInsets.zero,
                onPressed: () => onChanged(score),
                icon: Icon(
                  score <= value ? Icons.star_rounded : Icons.star_outline_rounded,
                  size: 22,
                  color: score <= value ? AppTheme.gold : AppTheme.textMuted,
                ),
              ),
            );
          }),
        ),
      ],
    );
  }
}
