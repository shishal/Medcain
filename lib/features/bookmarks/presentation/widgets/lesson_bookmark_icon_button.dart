import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/result.dart';
import '../providers/bookmarks_provider.dart';

/// Filled vs outline bookmark for a lesson. Reads the shared
/// [bookmarkedLessonIdsProvider] set so lists never trigger N+1 fetches.
class LessonBookmarkIconButton extends ConsumerWidget {
  const LessonBookmarkIconButton({super.key, required this.lessonId});

  final String lessonId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final idsAsync = ref.watch(bookmarkedLessonIdsProvider);
    final on = idsAsync.value?.contains(lessonId) ?? false;

    return IconButton(
      tooltip: on ? 'Remove bookmark' : 'Bookmark lesson',
      onPressed: () async {
        final result = await ref
            .read(bookmarkedLessonIdsProvider.notifier)
            .toggle(lessonId);
        if (!context.mounted) return;
        if (result case Failure(:final message)) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(message)));
        }
      },
      icon: Icon(
        on ? Icons.bookmark : Icons.bookmark_border,
        color: on ? Theme.of(context).colorScheme.primary : null,
      ),
    );
  }
}
