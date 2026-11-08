import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/comic_colors.dart';
import '../../../../core/theme/spacing.dart';
import '../../../../core/widgets/async_status_views.dart';
import '../../../../core/widgets/navy_story_widgets.dart';
import '../../../../core/widgets/staggered_fade.dart';
import '../../domain/catalog_models.dart';
import '../../../progress/domain/progress_models.dart';

class SubjectStickerGrid extends StatelessWidget {
  const SubjectStickerGrid({
    super.key,
    required this.subjects,
    this.coverage = const [],
    this.showLessonProgress = true,
  });

  final List<CatalogSubject> subjects;
  final List<SubjectCoverage> coverage;
  final bool showLessonProgress;

  @override
  Widget build(BuildContext context) {
    if (subjects.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: Spacing.xl),
        child: AsyncEmptyView(
          icon: Icons.school_outlined,
          message: 'No subjects for this MBBS year yet.',
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
      child: Column(
        children: [
          for (var i = 0; i < subjects.length; i++)
            StaggeredFade(
              index: i,
              child: SubjectSticker(
                subject: subjects[i],
                coverage: showLessonProgress ? _match(subjects[i]) : null,
                showLessonProgress: showLessonProgress,
                last: i == subjects.length - 1,
              ),
            ),
        ],
      ),
    );
  }

  SubjectCoverage? _match(CatalogSubject subject) {
    for (final row in coverage) {
      if (row.id == subject.id) return row;
    }
    return null;
  }
}

class SubjectSticker extends StatelessWidget {
  const SubjectSticker({
    super.key,
    required this.subject,
    this.coverage,
    this.showLessonProgress = true,
    this.last = false,
  });

  final CatalogSubject subject;
  final SubjectCoverage? coverage;
  final bool showLessonProgress;
  final bool last;

  @override
  Widget build(BuildContext context) {
    // PYQ count comes from get_study_progress — not a client-computed score.
    // It is every university for the subject (same stems the subject list shows).
    // Hide the count when Home has no papers for the selected university yet.
    final pyqs = showLessonProgress ? (coverage?.totalPyqs ?? 0) : 0;
    final caption = subjectTileCaption(
      showLessonProgress: showLessonProgress,
      totalPyqs: pyqs,
    );
    final textTheme = Theme.of(context).textTheme;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;

    return TimelineTile(
      key: ValueKey('subject-tile-${subject.id}'),
      tone: StickerFills.subjectAccent(subject.name),
      last: last,
      semanticLabel: '${subject.name}, $caption',
      onTap: () =>
          context.push(AppRoutes.subjectPath(subject.id, subject.name)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            subject.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          Text(
            caption,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textTheme.bodySmall?.copyWith(color: muted),
          ),
        ],
      ),
    );
  }
}

/// Home sticker subtitle: PYQ count for the subject (all universities).
String subjectTileCaption({
  required bool showLessonProgress,
  int totalPyqs = 0,
}) {
  if (!showLessonProgress) return 'No PYQs yet';
  if (totalPyqs == 1) return '1 PYQ';
  if (totalPyqs > 1) return '$totalPyqs PYQs';
  return 'No PYQs yet';
}
