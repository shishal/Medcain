import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/comic_colors.dart';
import '../../../../core/theme/spacing.dart';
import '../../../../core/utils/date_format.dart';
import '../../../../core/utils/user_facing_error.dart';
import '../../../../core/widgets/async_status_views.dart';
import '../../../../core/widgets/comic_card.dart';
import '../../../../core/widgets/coverage_ring.dart';
import '../../../catalog/presentation/widgets/subject_tile.dart';
import '../providers/ug_home_providers.dart';

class ProgressScreen extends ConsumerWidget {
  const ProgressScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = ref.watch(studyProgressProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Progress')),
      body: progress.when(
        loading: () => const AsyncLoadingView(),
        error: (e, _) => AsyncErrorView(
          message: UserFacingError.display(e),
          onAction: () => ref.invalidate(studyProgressProvider),
        ),
        data: (p) {
          final comic = ComicColors.of(context);
          final dark = Theme.of(context).brightness == Brightness.dark;
          final scheme = Theme.of(context).colorScheme;
          final streakTint = dark
              ? Color.alphaBlend(
                  scheme.primary.withValues(alpha: 0.16),
                  comic.stickerLift,
                )
              : Color.alphaBlend(
                  StickerFills.peach.withValues(alpha: 0.45),
                  comic.sticker,
                );
          final events30 = p.days30.fold<int>(0, (sum, d) => sum + d.count);
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(studyProgressProvider);
              await ref.read(studyProgressProvider.future);
            },
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(Spacing.lg),
              children: [
                ComicCard(
                  color: streakTint,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${p.streak}-day streak',
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: Spacing.xs),
                      Text(
                        // "events" is our analytics word, not a student's.
                        events30 == 1
                            ? '1 study session in the last 30 days'
                            : '$events30 study sessions in the last 30 days',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: Spacing.lg),
                Text(
                  'Last 7 days',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: Spacing.sm),
                Wrap(
                  spacing: Spacing.sm,
                  runSpacing: Spacing.sm,
                  children: [
                    // Was `substring(5)`, i.e. a bare "08-29".
                    for (final d in p.days7)
                      Chip(
                        label: Text(
                          '${DateFormats.weekdayAndDay(d.date)} · ${d.count}',
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: Spacing.lg),
                Text('Subjects', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: Spacing.sm),
                for (var i = 0; i < p.subjects.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: Spacing.sm),
                    child: ComicCard(
                      onTap: () => GoRouter.maybeOf(context)?.push(
                        AppRoutes.subjectPath(
                          p.subjects[i].id,
                          p.subjects[i].name,
                        ),
                      ),
                      color: Color.alphaBlend(
                        StickerFills.tintAt(
                          i,
                          Theme.of(context).brightness,
                        ).withValues(alpha: dark ? 0.25 : 0.4),
                        comic.sticker,
                      ),
                      child: Row(
                        children: [
                          CoverageRing(
                            progress: p.subjects[i].totalLessons == 0
                                ? 0
                                : p.subjects[i].learntLessons /
                                      p.subjects[i].totalLessons,
                            size: 48,
                            child: Text(
                              '${p.subjects[i].learntLessons}',
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                          ),
                          const SizedBox(width: Spacing.md),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  p.subjects[i].name,
                                  style: Theme.of(context).textTheme.titleMedium
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                                Text(
                                  p.subjects[i].totalLessons > 0
                                      ? '${p.subjects[i].learntLessons} of ${p.subjects[i].totalLessons} lessons learnt'
                                      : subjectTileCaption(
                                          showLessonProgress: true,
                                          totalPyqs: p.subjects[i].totalPyqs,
                                        ),
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            Icons.chevron_right_rounded,
                            color: scheme.onSurfaceVariant,
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
