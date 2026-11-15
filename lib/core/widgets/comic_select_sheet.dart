import 'package:material_ui/material_ui.dart';

import '../theme/spacing.dart';
import '../utils/soft_keyboard.dart';
import 'comic_card.dart';

/// Bottom sheet of tappable sticker rows — more reliable than dropdowns,
/// and it actually lets the student change year / college / batch.
Future<T?> showComicSelectSheet<T>({
  required BuildContext context,
  required String title,
  required List<T> items,
  required String Function(T item) labelOf,
  T? selected,
  String emptyMessage = 'Nothing to pick yet.',
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) {
      return _ComicSelectSheet<T>(
        title: title,
        items: items,
        labelOf: labelOf,
        selected: selected,
        emptyMessage: emptyMessage,
      );
    },
  );
}

class _ComicSelectSheet<T> extends StatefulWidget {
  const _ComicSelectSheet({
    required this.title,
    required this.items,
    required this.labelOf,
    required this.selected,
    required this.emptyMessage,
  });

  final String title;
  final List<T> items;
  final String Function(T item) labelOf;
  final T? selected;
  final String emptyMessage;

  /// Long lists (colleges) get a search box so tapping the field can type.
  static const searchAfterCount = 8;

  @override
  State<_ComicSelectSheet<T>> createState() => _ComicSelectSheetState<T>();
}

class _ComicSelectSheetState<T> extends State<_ComicSelectSheet<T>> {
  final _query = TextEditingController();
  late List<({T item, String label, String lower})> _indexed;

  bool get _showSearch =>
      widget.items.length >= _ComicSelectSheet.searchAfterCount;

  @override
  void initState() {
    super.initState();
    _rebuildIndex();
  }

  @override
  void didUpdateWidget(covariant _ComicSelectSheet<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.items, widget.items) ||
        oldWidget.labelOf != widget.labelOf) {
      _rebuildIndex();
    }
  }

  void _rebuildIndex() {
    _indexed = [
      for (final item in widget.items)
        (
          item: item,
          label: widget.labelOf(item),
          lower: widget.labelOf(item).toLowerCase(),
        ),
    ];
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final q = _query.text.trim().toLowerCase();
    final visible = q.isEmpty
        ? _indexed
        : _indexed.where((entry) => entry.lower.contains(q)).toList();
    final media = MediaQuery.of(context);
    // Give the list a real height. A min-size Column + maxHeight ConstrainedBox
    // was collapsing to ~one row once the keyboard opened.
    final listHeight = (visible.length * 76.0).clamp(
      0.0,
      media.size.height * 0.55,
    );

    return Padding(
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            Spacing.lg,
            Spacing.sm,
            Spacing.lg,
            Spacing.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(widget.title, style: Theme.of(context).textTheme.titleLarge),
              if (_showSearch) ...[
                const SizedBox(height: Spacing.md),
                TextField(
                  controller: _query,
                  keyboardType: TextInputType.text,
                  textInputAction: TextInputAction.search,
                  // Flutter enables stylus handwriting by default; on API 34+
                  // emulators that can swallow the tap instead of opening IME.
                  stylusHandwritingEnabled: false,
                  onTap: requestSoftKeyboard,
                  onTapOutside: dismissSoftKeyboard,
                  decoration: const InputDecoration(
                    hintText: 'Search',
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ],
              const SizedBox(height: Spacing.md),
              if (widget.items.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: Spacing.lg),
                  child: Text(widget.emptyMessage),
                )
              else if (visible.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(bottom: Spacing.lg),
                  child: Text('No matches.'),
                )
              else
                SizedBox(
                  height: listHeight,
                  child: ListView.separated(
                    itemCount: visible.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(height: Spacing.sm),
                    itemBuilder: (context, i) {
                      final entry = visible[i];
                      final selectedNow = widget.selected == entry.item;
                      return ComicCard(
                        padding: const EdgeInsets.symmetric(
                          horizontal: Spacing.md,
                          vertical: Spacing.sm,
                        ),
                        onTap: () => Navigator.pop(context, entry.item),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                entry.label,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ),
                            if (selectedNow)
                              const Icon(Icons.check_circle_rounded),
                          ],
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Field that opens [showComicSelectSheet] — used on onboarding and profile.
class ComicSelectField<T> extends StatelessWidget {
  const ComicSelectField({
    super.key,
    required this.label,
    required this.items,
    required this.labelOf,
    required this.onSelected,
    this.value,
    this.placeholder = 'Tap to choose',
    this.enabled = true,
  });

  final String label;
  final List<T> items;
  final String Function(T item) labelOf;
  final ValueChanged<T> onSelected;
  final T? value;
  final String placeholder;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final String text;
    if (value != null) {
      text = labelOf(value as T);
    } else if (items.isEmpty) {
      // Enabled + empty usually means the list is still loading. Disabled +
      // empty is "pick the previous field first" (state before university).
      text = enabled ? 'Loading…' : placeholder;
    } else {
      text = placeholder;
    }
    return ComicCard(
      semanticLabel: label,
      onTap: !enabled || items.isEmpty
          ? null
          : () async {
              final picked = await showComicSelectSheet<T>(
                context: context,
                title: label,
                items: items,
                labelOf: labelOf,
                selected: value,
              );
              if (picked != null) onSelected(picked);
            },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: Spacing.xs),
          Row(
            children: [
              Expanded(
                child: Text(
                  text,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              const Icon(Icons.expand_more_rounded),
            ],
          ),
        ],
      ),
    );
  }
}
