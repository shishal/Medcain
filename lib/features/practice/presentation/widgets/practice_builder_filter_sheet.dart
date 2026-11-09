import 'package:flutter/material.dart';

import '../../../../core/theme/spacing.dart';
import '../../domain/plan_limits.dart';
import '../../domain/practice_builder_draft.dart';
import '../../domain/practice_catalog.dart';

Future<void> showPracticeBuilderFilterSheet({
  required BuildContext context,
  required PracticeBuilderDraft draft,
  required PracticeCatalog catalog,
  required PracticePlanContext planContext,
  required ValueChanged<PracticeBuilderDraft> onChanged,
  required VoidCallback onUpgrade,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) {
      return PracticeBuilderFilterSheet(
        draft: draft,
        catalog: catalog,
        planContext: planContext,
        onChanged: onChanged,
        onUpgrade: onUpgrade,
      );
    },
  );
}

class PracticeBuilderFilterSheet extends StatefulWidget {
  const PracticeBuilderFilterSheet({
    super.key,
    required this.draft,
    required this.catalog,
    required this.planContext,
    required this.onChanged,
    required this.onUpgrade,
  });

  final PracticeBuilderDraft draft;
  final PracticeCatalog catalog;
  final PracticePlanContext planContext;
  final ValueChanged<PracticeBuilderDraft> onChanged;
  final VoidCallback onUpgrade;

  @override
  State<PracticeBuilderFilterSheet> createState() =>
      _PracticeBuilderFilterSheetState();
}

class _PracticeBuilderFilterSheetState
    extends State<PracticeBuilderFilterSheet> {
  late PracticeBuilderDraft _draft;

  @override
  void initState() {
    super.initState();
    _draft = widget.draft;
  }

  PlanLimits get _limits => widget.planContext.limits;

  void _set(PracticeBuilderDraft next) {
    setState(() => _draft = next);
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final topics = widget.catalog.topicsForSubjects(_draft.selectedSubjectIds);
    final media = MediaQuery.of(context);
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: media.size.height * 0.85),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              Spacing.lg,
              Spacing.sm,
              Spacing.lg,
              Spacing.lg,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Filters', style: textTheme.titleLarge),
                const SizedBox(height: Spacing.md),
                Expanded(
                  child: ListView(
                    children: [
                      for (
                        var i = 0;
                        i < widget.catalog.subjectsByPhase.length;
                        i++
                      ) ...[
                        if (i > 0) const SizedBox(height: Spacing.md),
                        _ChipBlock(
                          title:
                              widget.catalog.subjectsByPhase[i].phaseName ??
                              'Subjects',
                          helper: i == 0 && _draft.selectedSubjectIds.isEmpty
                              ? 'None chosen — all subjects'
                              : null,
                          children: [
                            for (final subject
                                in widget.catalog.subjectsByPhase[i].subjects)
                              FilterChip(
                                label: Text(subject.name),
                                selected: _draft.selectedSubjectIds.contains(
                                  subject.id,
                                ),
                                onSelected: (_) => _set(
                                  _draft.toggleSubject(
                                    subject.id,
                                    widget.catalog,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                      const SizedBox(height: Spacing.md),
                      _ChipBlock(
                        title: 'Topics',
                        helper: _draft.selectedTopicIds.isEmpty
                            ? 'None chosen — all topics in the selected subjects'
                            : null,
                        children: [
                          if (topics.isEmpty)
                            Text(
                              'No topics for the selected subjects yet.',
                              style: textTheme.bodyMedium?.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                            )
                          else
                            for (final topic in topics)
                              FilterChip(
                                label: Text(topic.name),
                                selected: _draft.selectedTopicIds.contains(
                                  topic.id,
                                ),
                                onSelected: (_) =>
                                    _set(_draft.toggleTopic(topic.id)),
                              ),
                        ],
                      ),
                      const SizedBox(height: Spacing.md),
                      _ChipBlock(
                        title: 'Tags',
                        locked: !_limits.allowTagFilter,
                        upgradeHint: 'Upgrade to filter by tags',
                        onUpgrade: widget.onUpgrade,
                        children: [
                          for (final tag in widget.catalog.tags)
                            FilterChip(
                              label: Text(tag.chipLabel),
                              selected: _draft.selectedTagIds.contains(tag.id),
                              onSelected: _limits.allowTagFilter
                                  ? (_) => _set(_draft.toggleTag(tag.id))
                                  : null,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: Spacing.md),
                Row(
                  children: [
                    TextButton(
                      onPressed: _draft.hasContentFilters
                          ? () => _set(_draft.clearContentFilters())
                          : null,
                      child: const Text('Clear all'),
                    ),
                    const Spacer(),
                    FilledButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Done'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ChipBlock extends StatelessWidget {
  const _ChipBlock({
    required this.title,
    required this.children,
    this.helper,
    this.locked = false,
    this.upgradeHint,
    this.onUpgrade,
  });

  final String title;
  final List<Widget> children;
  final String? helper;
  final bool locked;
  final String? upgradeHint;
  final VoidCallback? onUpgrade;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(title, style: textTheme.titleSmall)),
            if (locked)
              Icon(
                Icons.lock_outline,
                size: 18,
                color: Theme.of(context).colorScheme.primary,
              ),
          ],
        ),
        if (helper != null && !locked) ...[
          const SizedBox(height: Spacing.xs),
          Text(
            helper!,
            style: textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        const SizedBox(height: Spacing.sm),
        Opacity(
          opacity: locked ? 0.55 : 1,
          child: Wrap(
            spacing: Spacing.sm,
            runSpacing: Spacing.sm,
            children: children,
          ),
        ),
        if (locked && upgradeHint != null)
          TextButton.icon(
            onPressed: onUpgrade,
            icon: Icon(
              Icons.lock_outline,
              size: 16,
              color: Theme.of(context).colorScheme.primary,
            ),
            label: Text(upgradeHint!),
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
              alignment: Alignment.centerLeft,
            ),
          ),
      ],
    );
  }
}
