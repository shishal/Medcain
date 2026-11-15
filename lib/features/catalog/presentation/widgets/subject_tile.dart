import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/comic_colors.dart';
import '../../../../core/theme/spacing.dart';
import '../../../../core/widgets/comic_card.dart';
import '../../../../core/widgets/async_status_views.dart';
import '../../../../core/widgets/comic_med_glyph.dart';
import '../../../../core/widgets/staggered_fade.dart';
import '../../domain/catalog_models.dart';
import '../../domain/subject_visual.dart';
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

    final coverageById = {for (final row in coverage) row.id: row};
    final textScale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.35);

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
      itemCount: subjects.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: Spacing.md,
        crossAxisSpacing: Spacing.md,
        // Scale card height with accessibility font size so `Spacer()` never
        // collapses and overflows on compact 360dp screens at 1.3x+ text scale.
        mainAxisExtent: 152 * textScale,
      ),
      itemBuilder: (context, i) {
        final subject = subjects[i];
        return StaggeredFade(
          index: i,
          child: SubjectSticker(
            subject: subject,
            coverage: showLessonProgress ? coverageById[subject.id] : null,
            showLessonProgress: showLessonProgress,
          ),
        );
      },
    );
  }
}

class SubjectSticker extends StatelessWidget {
  const SubjectSticker({
    super.key,
    required this.subject,
    this.coverage,
    this.showLessonProgress = true,
  });

  final CatalogSubject subject;
  final SubjectCoverage? coverage;
  final bool showLessonProgress;

  @override
  Widget build(BuildContext context) {
    final comic = ComicColors.of(context);
    final accent = StickerFills.subjectAccent(subject.name);
    // PYQ count comes from get_study_progress — not a client-computed score.
    // It is every university for the subject (same stems the subject list shows).
    // Hide the badge when Home has no papers for the selected university yet.
    final pyqs = showLessonProgress ? (coverage?.totalPyqs ?? 0) : 0;

    return ComicCard(
      key: ValueKey('subject-tile-${subject.id}'),
      color: comic.sticker,
      semanticLabel: subject.name,
      onTap: () =>
          context.push(AppRoutes.subjectPath(subject.id, subject.name)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(14),
                ),
                alignment: Alignment.center,
                child: ComicMedGlyph(
                  glyph: glyphForSubject(subject.name),
                  size: 28,
                  color: accent,
                ),
              ),
              const Spacer(),
              // A CoverageRing at progress: 0 drew an empty track that read as
              // "0% done", and the number was then repeated in the caption
              // below. One pill, stated once.
              if (showLessonProgress && pyqs > 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: Spacing.sm,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '$pyqs',
                    style: Theme.of(context).textTheme.labelMedium
                        ?.copyWith(color: accent, fontWeight: FontWeight.w800),
                  ),
                ),
            ],
          ),
          const Spacer(),
          Text(
            subject.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          Text(
            subjectTileCaption(
              showLessonProgress: showLessonProgress,
              totalPyqs: pyqs,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
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
