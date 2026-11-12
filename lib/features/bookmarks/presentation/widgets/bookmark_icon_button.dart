import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/result.dart';
import '../providers/bookmarks_provider.dart';

/// Filled vs outline bookmark icon. Writes through to Supabase on tap.
class BookmarkIconButton extends ConsumerWidget {
  const BookmarkIconButton({super.key, required this.questionId});

  final String questionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final idsAsync = ref.watch(bookmarkedIdsProvider);
    final isBookmarked = idsAsync.value?.contains(questionId) ?? false;
    final tooltip = isBookmarked ? 'Remove bookmark' : 'Bookmark';

    return IconButton(
      tooltip: tooltip,
      onPressed: idsAsync.isLoading
          ? null
          : () async {
              final result = await ref
                  .read(bookmarkedIdsProvider.notifier)
                  .toggle(questionId);
              if (!context.mounted) return;
              switch (result) {
                case Success():
                  break;
                case Failure(:final message):
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text(message)));
              }
            },
      icon: Icon(
        isBookmarked ? Icons.bookmark : Icons.bookmark_border,
        color: isBookmarked ? Theme.of(context).colorScheme.primary : null,
      ),
    );
  }
}
