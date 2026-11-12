import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/spacing.dart';
import '../../../../core/utils/result.dart';
import '../../../../core/utils/soft_keyboard.dart';
import '../../../../core/widgets/async_status_views.dart';
import '../../../../core/widgets/comic_card.dart';
import '../../../progress/data/progress_repository.dart';
import '../../../progress/domain/progress_models.dart';
import '../../../pyq/presentation/open_pyq_reader.dart';

/// Search is server-side (`search_catalog` RPC) and needs at least 2
/// characters, so the screen has to say so rather than ignoring Enter.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  static const _minQueryLength = 2;

  final _controller = TextEditingController();
  bool _loading = false;
  String? _error;
  SearchHits? _hits;
  bool _searched = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _run(String raw) async {
    final query = raw.trim();
    if (query.length < _minQueryLength) {
      setState(() => _error = 'Type at least $_minQueryLength letters.');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
      _searched = true;
    });
    final result = await ref.read(progressRepositoryProvider).search(query);
    if (!mounted) return;
    switch (result) {
      case Success(:final value):
        setState(() {
          _hits = value;
          _loading = false;
        });
      case Failure(:final message):
        setState(() {
          _error = message;
          _loading = false;
        });
    }
  }

  void _clear() {
    _controller.clear();
    setState(() {
      _hits = null;
      _error = null;
      _searched = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final hits = _hits;
    final empty =
        hits != null &&
        hits.subjects.isEmpty &&
        hits.lessons.isEmpty &&
        hits.questions.isEmpty;

    return Scaffold(
      appBar: AppBar(title: const Text('Search')),
      body: Padding(
        padding: const EdgeInsets.all(Spacing.lg),
        child: Column(
          children: [
            TextField(
              controller: _controller,
              autofocus: true,
              keyboardType: TextInputType.text,
              textInputAction: TextInputAction.search,
              stylusHandwritingEnabled: false,
              onTap: requestSoftKeyboard,
              // Rebuild on every keystroke so the clear button appears and
              // the "at least 2 letters" hint can disappear as you type.
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Subjects, lessons, PYQs',
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _controller.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear',
                        icon: const Icon(Icons.close_rounded),
                        onPressed: _clear,
                      ),
              ),
              onSubmitted: _run,
            ),
            const SizedBox(height: Spacing.md),
            if (_loading) const LinearProgressIndicator(),
            if (_error != null)
              InlineErrorMessage(
                message: _error!,
                onRetry: _controller.text.trim().length >= _minQueryLength
                    ? () => _run(_controller.text)
                    : null,
              ),
            if (_searched && empty && !_loading)
              const Expanded(
                child: AsyncEmptyView(
                  icon: Icons.search_off_rounded,
                  message: 'No matches. Try another word.',
                ),
              ),
            if (hits != null && !empty)
              Expanded(
                child: ListView(
                  children: [
                    if (hits.subjects.isNotEmpty)
                      _ResultGroup(
                        label: 'Subjects',
                        children: [
                          for (final s in hits.subjects)
                            _ResultTile(
                              icon: Icons.book_outlined,
                              title: s.title,
                              onTap: () => context.push(
                                AppRoutes.subjectPath(s.id, s.title),
                              ),
                            ),
                        ],
                      ),
                    if (hits.lessons.isNotEmpty)
                      _ResultGroup(
                        label: 'Lessons',
                        children: [
                          for (final l in hits.lessons)
                            _ResultTile(
                              icon: Icons.article_outlined,
                              title: l.title,
                              onTap: () => context.push(
                                AppRoutes.lessonPath(l.id, l.title),
                              ),
                            ),
                        ],
                      ),
                    if (hits.questions.isNotEmpty)
                      _ResultGroup(
                        label: 'Previous year questions',
                        children: [
                          for (final q in hits.questions)
                            _ResultTile(
                              icon: Icons.quiz_outlined,
                              title: q.title,
                              onTap: () => openPyqReader(
                                context,
                                questionId: q.id,
                                questionIds: [
                                  for (final hit in hits.questions) hit.id,
                                ],
                              ),
                            ),
                        ],
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Subjects, lessons and PYQs used to run together in one undifferentiated
/// list, so a lesson and a question stem looked like the same kind of result.
class _ResultGroup extends StatelessWidget {
  const _ResultGroup({required this.label, required this.children});

  final String label;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: Spacing.sm),
          child: Text(
            '$label · ${children.length}',
            style: Theme.of(context).textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
        ),
        ...children,
        const SizedBox(height: Spacing.md),
      ],
    );
  }
}

class _ResultTile extends StatelessWidget {
  const _ResultTile({
    required this.icon,
    required this.title,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.sm),
      child: ComicCard(
        padding: const EdgeInsets.symmetric(
          horizontal: Spacing.sm,
          vertical: Spacing.xs,
        ),
        onTap: onTap,
        child: ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(icon),
          title: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis),
        ),
      ),
    );
  }
}
