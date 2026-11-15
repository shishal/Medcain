import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/comic_colors.dart';
import '../../../../core/theme/spacing.dart';
import '../../../../core/utils/user_facing_error.dart';
import '../../../../core/widgets/async_status_views.dart';
import '../../../../core/widgets/comic_card.dart';
import '../../../pyq/presentation/open_pyq_reader.dart';
import '../../domain/bookmarked_lesson.dart';
import '../../domain/bookmarked_question.dart';
import '../providers/bookmarks_provider.dart';
import '../widgets/bookmark_icon_button.dart';
import '../widgets/lesson_bookmark_icon_button.dart';

/// Saved questions and lessons. Data lives in Supabase `bookmarks`.
///
/// One scroll view for both sections: the lesson list used to be an unbounded
/// Column sitting below an Expanded question list, which overflows as soon as
/// a student saves a handful of lessons.
class BookmarksScreen extends ConsumerWidget {
  const BookmarksScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final listAsync = ref.watch(bookmarksListProvider);
    final lessonsAsync = ref.watch(lessonBookmarksListProvider);
    final ids = ref.watch(bookmarkedIdsProvider).value;

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Bookmarks'),
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
              return;
            }
            context.go(AppRoutes.home);
          },
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(bookmarksListProvider);
          ref.invalidate(lessonBookmarksListProvider);
          await ref.read(bookmarksListProvider.future);
        },
        child: listAsync.when(
          skipLoadingOnReload: true,
          loading: () => const AsyncLoadingView(),
          error: (error, _) => AsyncErrorView(
            message: UserFacingError.display(error),
            onAction: () => ref.invalidate(bookmarksListProvider),
          ),
          data: (items) {
            // Hide rows the ID set already dropped (optimistic unbookmark).
            final questions = ids == null
                ? items
                : items.where((item) => ids.contains(item.questionId)).toList();
            final lessonIds = ref.watch(bookmarkedLessonIdsProvider).value;
            final lessons = lessonIds == null
                ? (lessonsAsync.value ?? const <BookmarkedLesson>[])
                : (lessonsAsync.value ?? const <BookmarkedLesson>[])
                      .where((item) => lessonIds.contains(item.lessonId))
                      .toList();

            if (questions.isEmpty && lessons.isEmpty) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  SizedBox(
                    height: MediaQuery.sizeOf(context).height * 0.6,
                    child: const AsyncEmptyView(
                      icon: Icons.bookmark_border,
                      message:
                          'Nothing saved yet. Bookmark a PYQ, a lesson, or a '
                          'question from solution review.',
                    ),
                  ),
                ],
              );
            }

            // Allocate the reader sequence once instead of O(N^2) per row, and
            // build rows lazily via CustomScrollView + SliverList.builder.
            final questionIds = [
              for (final question in questions) question.questionId,
            ];

            return CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                if (questions.isNotEmpty) ...[
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(
                      Spacing.md,
                      Spacing.md,
                      Spacing.md,
                      0,
                    ),
                    sliver: SliverToBoxAdapter(
                      child: _SectionLabel(
                        'Questions'
                        '${questions.length > 1 ? ' · ${questions.length}' : ''}',
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
                    sliver: SliverList.builder(
                      itemCount: questions.length,
                      itemBuilder: (context, i) => Padding(
                        padding: const EdgeInsets.only(bottom: Spacing.sm),
                        child: _BookmarkTile(
                          item: questions[i],
                          index: i,
                          questionIds: questionIds,
                        ),
                      ),
                    ),
                  ),
                ],
                if (lessons.isNotEmpty) ...[
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(
                      Spacing.md,
                      questions.isEmpty ? Spacing.md : Spacing.lg,
                      Spacing.md,
                      0,
                    ),
                    sliver: SliverToBoxAdapter(
                      child: _SectionLabel(
                        'Lessons'
                        '${lessons.length > 1 ? ' · ${lessons.length}' : ''}',
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(
                      Spacing.md,
                      0,
                      Spacing.md,
                      Spacing.md,
                    ),
                    sliver: SliverList.builder(
                      itemCount: lessons.length,
                      itemBuilder: (context, i) => Padding(
                        padding: const EdgeInsets.only(bottom: Spacing.sm),
                        child: _LessonTile(item: lessons[i]),
                      ),
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.sm),
      child: Text(
        text,
        style: Theme.of(context).textTheme.titleSmall
            ?.copyWith(fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _BookmarkTile extends StatelessWidget {
  const _BookmarkTile({
    required this.item,
    required this.index,
    required this.questionIds,
  });

  final BookmarkedQuestion item;
  final int index;
  final List<String> questionIds;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final comic = ComicColors.of(context);
    final subtitle = item.subtitle;
    final tint = StickerFills.tintAt(index, Theme.of(context).brightness);

    return ComicCard(
      color: Color.alphaBlend(tint.withValues(alpha: 0.35), comic.sticker),
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.sm,
        vertical: Spacing.xs,
      ),
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(
          item.isPlanLocked ? Icons.lock_outline : Icons.quiz_outlined,
          color: item.isPlanLocked ? colorScheme.outline : colorScheme.primary,
        ),
        title: Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: subtitle == null
            ? (item.isPlanLocked
                  ? Text(
                      'Upgrade to see this question.',
                      style: TextStyle(color: colorScheme.onSurfaceVariant),
                    )
                  : null)
            : Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
        trailing: BookmarkIconButton(questionId: item.questionId),
        onTap: item.isPlanLocked
            ? () {
                final router = GoRouter.maybeOf(context);
                if (router == null) return;
                final matches = router.configuration.findMatch(
                  Uri.parse(AppRoutes.upgrade),
                );
                if (matches.isNotEmpty) {
                  router.push(AppRoutes.upgrade);
                }
              }
            : () => openPyqReader(
                context,
                questionId: item.questionId,
                questionIds: questionIds,
              ),
      ),
    );
  }
}

class _LessonTile extends StatelessWidget {
  const _LessonTile({required this.item});

  final BookmarkedLesson item;

  @override
  Widget build(BuildContext context) {
    return ComicCard(
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.sm,
        vertical: Spacing.xs,
      ),
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.article_outlined),
        title: Text(item.name, maxLines: 2, overflow: TextOverflow.ellipsis),
        trailing: LessonBookmarkIconButton(lessonId: item.lessonId),
        onTap: () =>
            context.push(AppRoutes.lessonPath(item.lessonId, item.name)),
      ),
    );
  }
}
