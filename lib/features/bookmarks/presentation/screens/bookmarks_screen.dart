import 'package:flutter/material.dart';
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
            final lessons = lessonsAsync.value ?? const <BookmarkedLesson>[];

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

            return ListView(
              padding: const EdgeInsets.all(Spacing.md),
              children: [
                if (questions.isNotEmpty) ...[
                  _SectionLabel(
                    'Questions'
                    '${questions.length > 1 ? ' · ${questions.length}' : ''}',
                  ),
                  for (var i = 0; i < questions.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: Spacing.sm),
                      child: _BookmarkTile(
                        item: questions[i],
                        index: i,
                        questionIds: [
                          for (final question in questions) question.questionId,
                        ],
                      ),
                    ),
                ],
                if (lessons.isNotEmpty) ...[
                  const SizedBox(height: Spacing.md),
                  _SectionLabel(
                    'Lessons'
                    '${lessons.length > 1 ? ' · ${lessons.length}' : ''}',
                  ),
                  for (final item in lessons)
                    Padding(
                      padding: const EdgeInsets.only(bottom: Spacing.sm),
                      child: _LessonTile(item: item),
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
            ? null
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
