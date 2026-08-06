import 'package:flutter/material.dart';

import '../core/transcript.dart';
import '../models/course.dart';
import '../models/semester.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_card.dart';

/// Shows what was parsed before any of it is applied.
///
/// Import replaces the whole transcript, and the parser cannot be fully
/// validated against every BRACU layout — so the student confirms what was
/// read rather than discovering afterwards that it was wrong.
class TranscriptImportSheet extends StatelessWidget {
  final TranscriptParseResult result;
  final String fileName;

  /// True when there is existing data that import would replace.
  final bool willReplaceExisting;

  const TranscriptImportSheet({
    super.key,
    required this.result,
    required this.fileName,
    required this.willReplaceExisting,
  });

  int get _courseCount =>
      result.semesters.fold(0, (sum, s) => sum + s.courses.length);

  double get _creditCount => result.semesters
      .expand((s) => s.courses)
      .fold(0.0, (sum, c) => sum + c.credits);

  @override
  Widget build(BuildContext context) {
    final credits = _creditCount;
    final creditLabel = credits == credits.roundToDouble()
        ? credits.toInt().toString()
        : credits.toStringAsFixed(1);

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, controller) => Column(
        children: [
          Expanded(
            child: ListView(
              controller: controller,
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
              children: [
                const Text(
                  'Check before importing',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  fileName,
                  style: const TextStyle(color: AppTheme.textMuted, fontSize: 12),
                ),
                const SizedBox(height: 14),

                GlassCard(
                  child: Row(
                    children: [
                      _Stat(label: 'Semesters', value: '${result.semesters.length}'),
                      _Stat(label: 'Courses', value: '$_courseCount'),
                      _Stat(label: 'Credits', value: creditLabel),
                    ],
                  ),
                ),

                if (result.detectedDept != null) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      const Icon(Icons.school_outlined,
                          size: 15, color: AppTheme.textMuted),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          result.detectedDept!,
                          style: const TextStyle(
                              color: AppTheme.textSecondary, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ],

                if (willReplaceExisting) ...[
                  const SizedBox(height: 12),
                  const GlassCard(
                    borderColor: AppTheme.gold,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.warning_amber_rounded,
                            size: 16, color: AppTheme.gold),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'This replaces the semesters you already have, '
                            'here and on the website.',
                            style: TextStyle(color: AppTheme.gold, fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 16),
                for (final semester in result.semesters)
                  _SemesterPreview(semester: semester),
              ],
            ),
          ),
          _Actions(
            onCancel: () => Navigator.pop(context, false),
            onConfirm: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  const _Stat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(
          children: [
            Text(value,
                style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textPrimary)),
            Text(label,
                style: const TextStyle(
                    color: AppTheme.textSecondary, fontSize: 11)),
          ],
        ),
      );
}

class _SemesterPreview extends StatelessWidget {
  final ParsedSemester semester;
  const _SemesterPreview({required this.semester});

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      margin: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(semester.name,
              style: const TextStyle(
                  color: AppTheme.green,
                  fontWeight: FontWeight.w700,
                  fontSize: 13)),
          const SizedBox(height: 6),
          for (final course in semester.courses)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      course.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: AppTheme.textPrimary, fontSize: 12),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text('${course.credits.toStringAsFixed(0)} cr',
                      style: const TextStyle(
                          color: AppTheme.textMuted, fontSize: 11)),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 44,
                    child: Text(
                      course.grade.isEmpty ? '—' : course.grade,
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        color: course.grade.startsWith('F')
                            ? Colors.redAccent
                            : AppTheme.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Actions extends StatelessWidget {
  final VoidCallback onCancel;
  final VoidCallback onConfirm;
  const _Actions({required this.onCancel, required this.onConfirm});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
        child: Row(
          children: [
            Expanded(
              child: TextButton(
                onPressed: onCancel,
                child: const Text('Cancel',
                    style: TextStyle(color: AppTheme.textSecondary)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: ElevatedButton(
                onPressed: onConfirm,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.green,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: const Text('Import',
                    style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Converts a parsed transcript into semesters for the shared state document.
///
/// Ids are allocated from [startingId] so they are ints and unique — the web
/// discards any semester whose id is not a number.
List<Semester> semestersFromParsed(
  List<ParsedSemester> parsed, {
  int startingId = 0,
}) {
  final out = <Semester>[];
  for (var i = 0; i < parsed.length; i++) {
    out.add(Semester(
      id: startingId + i,
      name: parsed[i].name,
      courses: [
        for (final c in parsed[i].courses)
          Course(
            name: c.name,
            credits: c.credits,
            grade: c.grade,
            storedGradePoint: c.gradePoint,
          ),
      ],
    ));
  }
  return out;
}
