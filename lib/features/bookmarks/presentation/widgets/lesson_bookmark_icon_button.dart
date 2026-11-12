import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/result.dart';
import '../../data/bookmarks_repository.dart';

/// Filled vs outline bookmark for a lesson. Writes `lesson_bookmarks`.
class LessonBookmarkIconButton extends ConsumerStatefulWidget {
  const LessonBookmarkIconButton({super.key, required this.lessonId});

  final String lessonId;

  @override
  ConsumerState<LessonBookmarkIconButton> createState() =>
      _LessonBookmarkIconButtonState();
}

class _LessonBookmarkIconButtonState
    extends ConsumerState<LessonBookmarkIconButton> {
  bool _on = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(_load);
  }

  Future<void> _load() async {
    try {
      final result = await ref.read(bookmarksRepositoryProvider).fetchLessonIds();
      if (!mounted) return;
      if (result case Success(:final value)) {
        setState(() => _on = value.contains(widget.lessonId));
      }
    } catch (_) {
      // Tests (and missing Supabase) skip the icon state.
    }
  }

  Future<void> _toggle() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _on = !_on;
    });
    final repo = ref.read(bookmarksRepositoryProvider);
    final result = _on
        ? await repo.addLesson(widget.lessonId)
        : await repo.removeLesson(widget.lessonId);
    if (!mounted) return;
    setState(() => _busy = false);
    if (result case Failure(:final message)) {
      setState(() => _on = !_on);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: _on ? 'Remove bookmark' : 'Bookmark lesson',
      onPressed: _busy ? null : _toggle,
      icon: Icon(
        _on ? Icons.bookmark : Icons.bookmark_border,
        color: _on ? Theme.of(context).colorScheme.primary : null,
      ),
    );
  }
}
