import 'package:flutter/material.dart';

import '../../../../core/theme/spacing.dart';
import '../../../../core/widgets/comic_card.dart';
import '../../domain/plan_limits.dart';
import '../../domain/practice_builder_draft.dart';
import '../../domain/practice_catalog.dart';
import '../../domain/practice_enums.dart';
import 'practice_builder_filter_sheet.dart';

/// The Practice Builder fields from spec §1. Each locked control stays visible
/// with an upgrade hint — never silently greyed out or hidden.
class PracticeBuilderForm extends StatelessWidget {
  const PracticeBuilderForm({
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

  PlanLimits get _limits => planContext.limits;

  @override
  Widget build(BuildContext context) {
    final lessonMessage = draft.lessonScopeMessage;

    return ListView(
      padding: const EdgeInsets.all(Spacing.lg),
      children: [
        if (lessonMessage != null) ...[
          ComicCard(
            child: Row(
              children: [
                Expanded(child: Text(lessonMessage)),
                TextButton(
                  onPressed: () => onChanged(draft.withoutLessonScope()),
                  child: const Text('All lessons'),
                ),
              ],
            ),
          ),
          const SizedBox(height: Spacing.lg),
        ],
        _SourceFilterSection(
          selected: draft.sourceFilter,
          onSelected: (value) => onChanged(draft.copyWith(sourceFilter: value)),
        ),
        const SizedBox(height: Spacing.lg),
        _FiltersEntry(
          draft: draft,
          catalog: catalog,
          onOpen: () => showPracticeBuilderFilterSheet(
            context: context,
            draft: draft,
            catalog: catalog,
            planContext: planContext,
            onChanged: onChanged,
            onUpgrade: onUpgrade,
          ),
        ),
        const SizedBox(height: Spacing.lg),
        _QuestionCountSection(
          count: draft.questionCount,
          planContext: planContext,
          onChanged: (count) => onChanged(draft.withQuestionCount(count)),
        ),
        const SizedBox(height: Spacing.lg),
        _FeedbackTimingSection(
          selected: draft.feedbackTiming,
          onSelected: (value) =>
              onChanged(draft.copyWith(feedbackTiming: value)),
        ),
        const SizedBox(height: Spacing.lg),
        _ExplanationLevelSection(
          selected: draft.explanationLevel,
          allowFull: _limits.allowFullExplanation,
          onSelected: (value) =>
              onChanged(draft.copyWith(explanationLevel: value)),
          onUpgrade: onUpgrade,
        ),
        const SizedBox(height: Spacing.lg),
        _TimerSection(
          enabled: draft.timerEnabled,
          minutes: draft.timerMinutes,
          canToggle: _limits.allowTimerToggle,
          onEnabledChanged: (value) =>
              onChanged(draft.copyWith(timerEnabled: value)),
          onMinutesChanged: (value) =>
              onChanged(draft.copyWith(timerMinutes: value)),
          onUpgrade: onUpgrade,
        ),
        const SizedBox(height: Spacing.lg),
        _NegativeMarkingSection(
          enabled: draft.negativeMarking,
          canToggle: _limits.allowNegativeMarkingToggle,
          onChanged: (value) =>
              onChanged(draft.copyWith(negativeMarking: value)),
          onUpgrade: onUpgrade,
        ),
        const SizedBox(height: Spacing.xl),
      ],
    );
  }
}

class _FiltersEntry extends StatelessWidget {
  const _FiltersEntry({
    required this.draft,
    required this.catalog,
    required this.onOpen,
  });

  final PracticeBuilderDraft draft;
  final PracticeCatalog catalog;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return ComicCard(
      onTap: onOpen,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  draft.hasContentFilters ? 'Filters · on' : 'Filters',
                  style: textTheme.titleMedium,
                ),
                const SizedBox(height: Spacing.xs),
                Text(
                  _summary(draft, catalog),
                  style: textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.tune),
        ],
      ),
    );
  }
}

String _summary(PracticeBuilderDraft draft, PracticeCatalog catalog) {
  if (!draft.hasContentFilters) {
    return 'Subjects, topics, and tags';
  }
  final parts = <String>[];
  if (draft.selectedSubjectIds.isNotEmpty) {
    parts.add(
      catalog.subjects
          .where((s) => draft.selectedSubjectIds.contains(s.id))
          .map((s) => s.name)
          .join(', '),
    );
  }
  if (draft.selectedTopicIds.isNotEmpty) {
    parts.add(
      catalog.topics
          .where((t) => draft.selectedTopicIds.contains(t.id))
          .map((t) => t.name)
          .join(', '),
    );
  }
  if (draft.selectedTagIds.isNotEmpty) {
    parts.add(
      catalog.tags
          .where((t) => draft.selectedTagIds.contains(t.id))
          .map((t) => t.chipLabel)
          .join(', '),
    );
  }
  return parts.join(' · ');
}

class _SourceFilterSection extends StatelessWidget {
  const _SourceFilterSection({
    required this.selected,
    required this.onSelected,
  });

  final QuestionSourceFilter selected;
  final ValueChanged<QuestionSourceFilter> onSelected;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final filters = QuestionSourceFilter.values;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Question source', style: textTheme.titleMedium),
        const SizedBox(height: Spacing.sm),
        for (var i = 0; i < filters.length; i += 2) ...[
          if (i > 0) const SizedBox(height: Spacing.xs),
          Row(
            children: [
              Expanded(
                child: _SourceCard(
                  filter: filters[i],
                  selected: selected == filters[i],
                  onTap: () => onSelected(filters[i]),
                ),
              ),
              const SizedBox(width: Spacing.xs),
              Expanded(
                child: _SourceCard(
                  filter: filters[i + 1],
                  selected: selected == filters[i + 1],
                  onTap: () => onSelected(filters[i + 1]),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: Spacing.sm),
        Text(
          selected.subtitle,
          style: textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _SourceCard extends StatelessWidget {
  const _SourceCard({
    required this.filter,
    required this.selected,
    required this.onTap,
  });

  final QuestionSourceFilter filter;
  final bool selected;
  final VoidCallback onTap;

  IconData get _icon => switch (filter) {
    QuestionSourceFilter.unattempted => Icons.quiz_outlined,
    QuestionSourceFilter.incorrect => Icons.replay,
    QuestionSourceFilter.bookmarked => Icons.bookmark_outline,
    QuestionSourceFilter.all => Icons.library_books_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return ComicCard(
      highlighted: selected,
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.sm,
        vertical: Spacing.sm,
      ),
      onTap: onTap,
      child: Row(
        children: [
          Icon(
            _icon,
            size: 18,
            color: selected
                ? colorScheme.primary
                : colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: Spacing.xs),
          Expanded(
            child: Text(
              filter.label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: textTheme.labelLarge?.copyWith(
                fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                color: selected ? colorScheme.primary : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuestionCountSection extends StatelessWidget {
  const _QuestionCountSection({
    required this.count,
    required this.planContext,
    required this.onChanged,
  });

  final int count;
  final PracticePlanContext planContext;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    final maxQ = planContext.maxSelectableQuestions;
    final remaining = planContext.remainingToday;
    final quota = planContext.limits.dailyPracticeQuestionQuota;
    final sliderMax = maxQ < 1 ? 1 : maxQ;
    final value = count.clamp(1, sliderMax).toDouble();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Question count', style: textTheme.titleMedium),
        const SizedBox(height: Spacing.xs),
        Text(
          'Your ${planContext.limits.plan.label} plan allows up to '
          '${planContext.limits.maxPracticeSessionQuestions} per session.',
          style: textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        if (quota != null) ...[
          const SizedBox(height: Spacing.xs),
          Text(
            remaining == 0
                ? "You've used today's $quota practice questions."
                : '$quota per day · $remaining left today.',
            style: textTheme.bodySmall?.copyWith(
              color: remaining == 0 ? colorScheme.error : colorScheme.primary,
            ),
          ),
        ],
        const SizedBox(height: Spacing.sm),
        if (planContext.dailyQuotaExhausted)
          const SizedBox.shrink()
        else
          Slider(
            min: 1,
            max: sliderMax.toDouble(),
            divisions: sliderMax > 1 ? sliderMax - 1 : null,
            value: value,
            label: '${value.round()}',
            onChanged: (v) => onChanged(v.round()),
          ),
        Text(
          '$count ${count == 1 ? 'question' : 'questions'}',
          style: textTheme.titleSmall,
        ),
      ],
    );
  }
}

class _FeedbackTimingSection extends StatelessWidget {
  const _FeedbackTimingSection({
    required this.selected,
    required this.onSelected,
  });

  final FeedbackTiming selected;
  final ValueChanged<FeedbackTiming> onSelected;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Feedback timing', style: textTheme.titleMedium),
        const SizedBox(height: Spacing.sm),
        SegmentedButton<FeedbackTiming>(
          segments: [
            for (final timing in FeedbackTiming.values)
              ButtonSegment(value: timing, label: Text(timing.label)),
          ],
          selected: {selected},
          onSelectionChanged: (value) => onSelected(value.first),
        ),
        const SizedBox(height: Spacing.sm),
        Text(
          selected.subtitle,
          style: textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _ExplanationLevelSection extends StatelessWidget {
  const _ExplanationLevelSection({
    required this.selected,
    required this.allowFull,
    required this.onSelected,
    required this.onUpgrade,
  });

  final ExplanationLevel selected;
  final bool allowFull;
  final ValueChanged<ExplanationLevel> onSelected;
  final VoidCallback onUpgrade;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text('Explanation level', style: textTheme.titleMedium),
            ),
            if (!allowFull)
              Icon(
                Icons.lock_outline,
                size: 18,
                color: Theme.of(context).colorScheme.primary,
              ),
          ],
        ),
        const SizedBox(height: Spacing.sm),
        Wrap(
          spacing: Spacing.sm,
          runSpacing: Spacing.sm,
          children: [
            for (final level in ExplanationLevel.values)
              ChoiceChip(
                label: Text(
                  level == ExplanationLevel.full && !allowFull
                      ? '${level.label} 🔒'
                      : level.label,
                ),
                selected: selected == level,
                onSelected: (!allowFull && level == ExplanationLevel.full)
                    ? null
                    : (_) => onSelected(level),
              ),
          ],
        ),
        if (!allowFull)
          _UpgradeHint(
            message: 'Upgrade to Pro for full explanations',
            onUpgrade: onUpgrade,
          ),
      ],
    );
  }
}

class _TimerSection extends StatelessWidget {
  const _TimerSection({
    required this.enabled,
    required this.minutes,
    required this.canToggle,
    required this.onEnabledChanged,
    required this.onMinutesChanged,
    required this.onUpgrade,
  });

  final bool enabled;
  final int minutes;
  final bool canToggle;
  final ValueChanged<bool> onEnabledChanged;
  final ValueChanged<int> onMinutesChanged;
  final VoidCallback onUpgrade;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text('Timer', style: textTheme.titleMedium)),
            if (!canToggle)
              Icon(
                Icons.lock_outline,
                size: 18,
                color: Theme.of(context).colorScheme.primary,
              ),
          ],
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Timed session'),
          subtitle: Text(
            canToggle
                ? 'Turn off to practice without a countdown'
                : 'Timer stays on for your plan',
          ),
          value: enabled,
          onChanged: canToggle ? onEnabledChanged : null,
        ),
        if (!canToggle)
          _UpgradeHint(
            message: 'Upgrade to turn the timer off',
            onUpgrade: onUpgrade,
          ),
        if (enabled) ...[
          const SizedBox(height: Spacing.sm),
          Row(
            children: [
              Text('Duration', style: textTheme.bodyLarge),
              const Spacer(),
              IconButton(
                tooltip: 'Fewer minutes',
                onPressed: minutes > 1
                    ? () => onMinutesChanged(minutes - 1)
                    : null,
                icon: const Icon(Icons.remove_circle_outline),
              ),
              Text('$minutes min', style: textTheme.titleSmall),
              IconButton(
                tooltip: 'More minutes',
                onPressed: minutes < 180
                    ? () => onMinutesChanged(minutes + 1)
                    : null,
                icon: const Icon(Icons.add_circle_outline),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _NegativeMarkingSection extends StatelessWidget {
  const _NegativeMarkingSection({
    required this.enabled,
    required this.canToggle,
    required this.onChanged,
    required this.onUpgrade,
  });

  final bool enabled;
  final bool canToggle;
  final ValueChanged<bool> onChanged;
  final VoidCallback onUpgrade;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Negative marking',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            if (!canToggle)
              Icon(
                Icons.lock_outline,
                size: 18,
                color: Theme.of(context).colorScheme.primary,
              ),
          ],
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Use +4 / −1 marking'),
          subtitle: const Text('Off by default — practice is for learning'),
          value: enabled,
          onChanged: canToggle ? onChanged : null,
        ),
        if (!canToggle)
          _UpgradeHint(
            message: 'Upgrade to practice with exam-style negative marking',
            onUpgrade: onUpgrade,
          ),
      ],
    );
  }
}

class _UpgradeHint extends StatelessWidget {
  const _UpgradeHint({required this.message, this.onUpgrade});

  final String message;
  final VoidCallback? onUpgrade;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(top: Spacing.xs),
      child: TextButton.icon(
        onPressed: onUpgrade,
        icon: Icon(Icons.lock_outline, size: 16, color: colorScheme.primary),
        label: Text(message),
        style: TextButton.styleFrom(
          padding: EdgeInsets.zero,
          visualDensity: VisualDensity.compact,
          alignment: Alignment.centerLeft,
        ),
      ),
    );
  }
}
