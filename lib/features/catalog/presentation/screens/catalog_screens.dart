import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/spacing.dart';
import '../../../../core/utils/open_external_link.dart';
import '../../../../core/utils/result.dart';
import '../../../../core/utils/user_facing_error.dart';
import '../../../../core/widgets/async_status_views.dart';
import '../../../../core/widgets/comic_card.dart';
import '../../../bookmarks/presentation/widgets/lesson_bookmark_icon_button.dart';
import '../../../profile/domain/plan_tier.dart';
import '../../../profile/presentation/providers/current_plan_provider.dart';
import '../../../pyq/domain/pyq_models.dart';
import '../../../pyq/domain/question_format.dart';
import '../../../pyq/presentation/open_pyq_reader.dart';
import '../../../pyq/presentation/providers/pyq_providers.dart';
import '../../../pyq/presentation/widgets/pyq_teaser_card.dart';
import '../../data/catalog_repository.dart';
import '../../domain/catalog_models.dart';
import '../providers/catalog_providers.dart';
import '../widgets/catalog_row_card.dart';

class SubjectListScreen extends ConsumerWidget {
  const SubjectListScreen({
    super.key,
    required this.subjectId,
    required this.title,
  });

  final String subjectId;
  final String title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final topics = ref.watch(subjectTopicsProvider(subjectId));
    return Scaffold(
      appBar: AppBar(title: Text('$title chapters')),
      body: topics.when(
        loading: () => const AsyncLoadingView(),
        error: (e, _) => AsyncErrorView(
          message: UserFacingError.display(e),
          onAction: () => ref.invalidate(subjectTopicsProvider(subjectId)),
        ),
        data: (items) {
          if (items.isEmpty) {
            return const AsyncEmptyView(
              message: 'No chapters in this subject yet.',
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(Spacing.md),
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(height: Spacing.sm),
            itemBuilder: (context, i) {
              final topic = items[i];
              return CatalogRowCard(
                title: topic.name,
                index: i,
                onTap: () =>
                    context.push(AppRoutes.topicPath(topic.id, topic.name)),
              );
            },
          );
        },
      ),
    );
  }
}

class TopicLessonsScreen extends ConsumerWidget {
  const TopicLessonsScreen({
    super.key,
    required this.topicId,
    required this.title,
  });

  final String topicId;
  final String title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lessons = ref.watch(topicLessonsProvider(topicId));
    final plan = ref.watch(currentPlanProvider).value ?? PlanTier.free;
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: lessons.when(
        loading: () => const AsyncLoadingView(),
        error: (e, _) => AsyncErrorView(
          message: UserFacingError.display(e),
          onAction: () => ref.invalidate(topicLessonsProvider(topicId)),
        ),
        data: (items) {
          if (items.isEmpty) {
            return const AsyncEmptyView(
              message: 'No lessons in this topic yet.',
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(Spacing.md),
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(height: Spacing.sm),
            itemBuilder: (context, i) {
              final lesson = items[i];
              final locked = !plan.covers(lesson.requiredPlan);
              return CatalogRowCard(
                title: lesson.name,
                index: i,
                trailing: Icon(
                  locked ? Icons.lock_outline : Icons.chevron_right_rounded,
                ),
                onTap: () {
                  if (locked) {
                    context.push(AppRoutes.upgradePath(lesson.requiredPlan));
                    return;
                  }
                  context.push(AppRoutes.lessonPath(lesson.id, lesson.name));
                },
              );
            },
          );
        },
      ),
    );
  }
}

class LessonScreen extends ConsumerStatefulWidget {
  const LessonScreen({super.key, required this.lessonId, required this.title});

  final String lessonId;
  final String title;

  @override
  ConsumerState<LessonScreen> createState() => _LessonScreenState();
}

class _LessonScreenState extends ConsumerState<LessonScreen> {
  bool _recordedOpen = false;
  bool _redirectedToUpgrade = false;
  QuestionFormat? _formatFilter;

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(_recordOpen);
  }

  Future<void> _recordOpen() async {
    if (_recordedOpen) return;
    _recordedOpen = true;
    await ref
        .read(catalogRepositoryProvider)
        .recordOpenedLesson(widget.lessonId);
  }

  /// Sends a student to the upgrade screen if this lesson is above their plan.
  ///
  /// Two things this has to get right. It must fire at most once — the old
  /// version ran on every rebuild and queued a fresh redirect each time. And
  /// it must wait for a *known* plan: treating "still loading" as Free would
  /// eject a paying student from a lesson they own.
  void _gateOnPlan(CatalogLesson? lesson, PlanTier? plan) {
    if (_redirectedToUpgrade || lesson == null || plan == null) return;
    if (plan.covers(lesson.requiredPlan)) return;

    _redirectedToUpgrade = true;
    // Navigation cannot run while this widget is still building.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.pushReplacement(AppRoutes.upgradePath(lesson.requiredPlan));
    });
  }

  Future<void> _openLink(ResourceLink link, PlanTier plan) async {
    if (!link.isFree && plan.rank < PlanTier.pro.rank) {
      if (!mounted) return;
      context.push(AppRoutes.upgradePath(PlanTier.pro));
      return;
    }
    await openExternalLink(context, link.url);
  }

  @override
  Widget build(BuildContext context) {
    final pyqs = ref.watch(lessonPyqsProvider(widget.lessonId));
    final resources =
        ref.watch(lessonResourcesProvider(widget.lessonId)).value ??
        const <ResourceLink>[];
    final knownPlan = ref.watch(currentPlanProvider).value;
    final plan = knownPlan ?? PlanTier.free;
    _gateOnPlan(
      ref.watch(lessonDetailProvider(widget.lessonId)).value,
      knownPlan,
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [LessonBookmarkIconButton(lessonId: widget.lessonId)],
      ),
      body: pyqs.when(
        loading: () => const AsyncLoadingView(),
        error: (e, _) => AsyncErrorView(
          message: UserFacingError.display(e),
          onAction: () => ref.invalidate(lessonPyqsProvider(widget.lessonId)),
        ),
        data: (feed) {
          final items = [
            for (final t in feed.teasers)
              if (_formatFilter == null || t.format == _formatFilter) t,
          ];
          return ListView(
            padding: const EdgeInsets.all(Spacing.md),
            children: [
              // A permanently disabled "Practice · upcoming" button used to
              // sit here, above the real actions. Practice mode gets its own
              // tab when it ships; a dead control in the best spot on the
              // screen is worse than no control.
              FilledButton.tonal(
                onPressed: () async {
                  final result = await ref
                      .read(catalogRepositoryProvider)
                      .markLessonLearnt(widget.lessonId);
                  if (!context.mounted) return;
                  final message = switch (result) {
                    Success() => 'Marked as learnt',
                    Failure(:final message) => message,
                  };
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text(message)));
                },
                child: const Text('Mark lesson learnt'),
              ),
              if (resources.isNotEmpty) ...[
                const SizedBox(height: Spacing.lg),
                Text(
                  'More on this topic',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                for (final link in resources)
                  Padding(
                    padding: const EdgeInsets.only(top: Spacing.sm),
                    child: ComicCard(
                      padding: const EdgeInsets.symmetric(
                        horizontal: Spacing.sm,
                        vertical: Spacing.xs,
                      ),
                      onTap: () => _openLink(link, plan),
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          link.isFree ? Icons.open_in_new : Icons.lock_outline,
                        ),
                        title: Text(link.title),
                        subtitle: link.sourceLabel == null
                            ? null
                            : Text(link.sourceLabel!),
                      ),
                    ),
                  ),
              ],
              const SizedBox(height: Spacing.lg),
              Text(
                'Previous year questions',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: Spacing.sm),
              PyqFormatChips(
                selected: _formatFilter,
                onSelected: (value) => setState(() => _formatFilter = value),
              ),
              const SizedBox(height: Spacing.sm),
              if (items.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: Spacing.xl),
                  child: AsyncEmptyView(
                    icon: Icons.description_outlined,
                    message: _formatFilter == null
                        ? 'No PYQs tagged to this lesson yet.'
                        : 'No ${_formatFilter!.label} questions in this lesson.',
                    actionLabel: _formatFilter == null ? null : 'Show all',
                    onAction: _formatFilter == null
                        ? null
                        : () => setState(() => _formatFilter = null),
                  ),
                )
              else
                for (var i = 0; i < items.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: Spacing.sm),
                    child: PyqTeaserCard(
                      teaser: items[i],
                      index: i,
                      onTap: () => openPyqReader(
                        context,
                        questionId: items[i].id,
                        questionIds: [for (final item in items) item.id],
                      ),
                    ),
                  ),
            ],
          );
        },
      ),
    );
  }
}
