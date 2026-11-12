import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/spacing.dart';
import '../../../../core/utils/user_facing_error.dart';
import '../../../../core/widgets/async_status_views.dart';
import '../../../../core/widgets/comic_section_title.dart';
import '../../../catalog/presentation/providers/catalog_providers.dart';
import '../../../catalog/presentation/widgets/subject_tile.dart';
import '../../../notifications/presentation/providers/notifications_provider.dart';
import '../../../notifications/presentation/widgets/home_unread_announcement_banner.dart';
import '../../../progress/presentation/providers/ug_home_providers.dart';
import '../providers/pending_submit_sync_provider.dart';
import '../widgets/home_hero_banner.dart';
import '../widgets/home_quick_actions.dart';
import '../widgets/home_resume_banner.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subjects = ref.watch(phaseSubjectsProvider);
    final coverage =
        ref.watch(studyProgressProvider).value?.subjects ?? const [];
    final hasUniversityPapers =
        (ref.watch(universityCoverageProvider).value?.paperCount ?? 0) > 0;
    ref.watch(pendingSubmitSyncProvider);

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(phaseSubjectsProvider);
            ref.invalidate(studyProgressProvider);
            ref.invalidate(universityCoverageProvider);
            ref.invalidate(announcementsProvider);
          },
          child: ListView(
            padding: const EdgeInsets.only(bottom: Spacing.xl),
            children: [
              const HomeHeroBanner(),
              const HomeUnreadAnnouncementBanner(),
              const HomeCoverageBanner(),
              const ComicSectionTitle(
                title: 'Subjects',
                subtitle: 'Tap a subject for previous-year papers.',
              ),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 280),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                child: subjects.when(
                  data: (items) => SubjectStickerGrid(
                    // The switcher keeps the first grid when this key stays
                    // the same. Subjects often paint before progress, which
                    // left every card on "No PYQs yet" after the counts arrived.
                    key: ValueKey(
                      '${items.map((s) => s.id).join(',')}|'
                      '$hasUniversityPapers|'
                      '${coverage.map((c) => '${c.id}:${c.totalPyqs}').join(',')}',
                    ),
                    subjects: items,
                    coverage: coverage,
                    showLessonProgress: hasUniversityPapers,
                  ),
                  loading: () => const Padding(
                    key: ValueKey('subjects-loading'),
                    padding: EdgeInsets.all(Spacing.lg),
                    child: LinearProgressIndicator(),
                  ),
                  error: (e, _) => Padding(
                    key: const ValueKey('subjects-error'),
                    padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
                    child: InlineErrorMessage(
                      message: UserFacingError.display(e),
                      onRetry: () => ref.invalidate(phaseSubjectsProvider),
                    ),
                  ),
                ),
              ),
              const HomeResumeBanner(),
              const ComicSectionTitle(title: 'More'),
              const HomeQuickActions(),
            ],
          ),
        ),
      ),
    );
  }
}
