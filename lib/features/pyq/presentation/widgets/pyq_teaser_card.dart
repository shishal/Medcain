import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/comic_colors.dart';
import '../../../../core/theme/player_colors.dart';
import '../../../../core/theme/spacing.dart';
import '../../../../core/widgets/comic_card.dart';
import '../../../bookmarks/presentation/widgets/bookmark_icon_button.dart';
import '../../../profile/domain/plan_tier.dart';
import '../../../profile/presentation/providers/current_plan_provider.dart';
import '../../domain/pyq_models.dart';
import '../../domain/question_format.dart';

class PyqFormatChips extends StatelessWidget {
  const PyqFormatChips({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  final QuestionFormat? selected;
  final ValueChanged<QuestionFormat?> onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: Spacing.sm,
      runSpacing: Spacing.sm,
      children: [
        _chip(context, null, 'All'),
        for (final format in QuestionFormat.values)
          _chip(context, format, format.label),
      ],
    );
  }

  Widget _chip(BuildContext context, QuestionFormat? value, String label) {
    final on = selected == value;
    return FilterChip(
      label: Text(label),
      selected: on,
      onSelected: (_) => onSelected(value),
    );
  }
}

class PyqTeaserCard extends ConsumerWidget {
  const PyqTeaserCard({
    super.key,
    required this.teaser,
    required this.index,
    this.onTap,
  });

  final PyqTeaser teaser;
  final int index;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final comic = ComicColors.of(context);
    final scheme = Theme.of(context).colorScheme;
    final years = teaser.appearanceYears.map((y) => '$y').join(', ');
    // ref.watch rebuilds this card when the profile plan arrives. A locked
    // card drops [onTap] so it cannot open the answer screen.
    final locked = teaser.isLockedFor(ref.watch(currentPlanProvider).value);
    final planTint = teaser.requiredPlan == PlanTier.free
        ? null
        : comic.proGold;

    return ComicCard(
      onTap: locked ? null : onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: Spacing.sm,
                  runSpacing: Spacing.xs,
                  children: [
                    if (teaser.publicCode.isNotEmpty)
                      _MetaChip(label: teaser.publicCode),
                    _MetaChip(
                      label: teaser.requiredPlan.label,
                      color: planTint,
                    ),
                    if (teaser.format != QuestionFormat.unclassified)
                      _MetaChip(label: teaser.format.label),
                    if (teaser.marks != null)
                      _MetaChip(label: '${teaser.marks} marks'),
                    if (teaser.hasDirectAnswer)
                      const _MetaChip(
                        label: 'Answer available',
                        color: PlayerColors.correct,
                      ),
                    if (teaser.hasExplanation)
                      const _MetaChip(
                        label: 'Solution available',
                        color: PlayerColors.correct,
                      ),
                    // `should` is what a blank CSV cell imports as, so a chip
                    // there would sit on every card and mean nothing.
                    if (teaser.priority.isNoteworthy)
                      _MetaChip(label: teaser.priority.label),
                    if (teaser.isHighYield)
                      _MetaChip(label: 'High yield', color: scheme.primary),
                  ],
                ),
              ),
              BookmarkIconButton(questionId: teaser.id),
            ],
          ),
          const SizedBox(height: Spacing.sm),
          if (locked)
            const _MaskedStem()
          else
            Text(
              teaser.questionText,
              // The reader shows the full stem; a 10-mark essay would otherwise
              // fill the screen and make the paper outline unscannable.
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          if (years.isNotEmpty || teaser.paperNames.isNotEmpty) ...[
            const SizedBox(height: Spacing.sm),
            Text(
              [
                if (teaser.paperNames.isNotEmpty) teaser.paperNames.join(' · '),
                if (years.isNotEmpty) years,
                if (teaser.appearanceCount > 1)
                  'asked ${teaser.appearanceCount}×',
              ].join(' · '),
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: comic.ink.withValues(alpha: 0.7)),
            ),
          ],
          if (teaser.topicName != null) ...[
            const SizedBox(height: Spacing.xs),
            Text(
              [
                teaser.topicName,
                if (teaser.lessonName != null &&
                    teaser.lessonName != teaser.topicName)
                  teaser.lessonName,
              ].join(' · '),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          if (!locked && teaser.textbookLine != null) ...[
            const SizedBox(height: Spacing.sm),
            Text(
              teaser.textbookLine!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }
}

/// Grey bars in place of a stem the student's plan cannot read.
/// The real text is not in the tree, so a mask cannot be copied out.
class _MaskedStem extends StatelessWidget {
  const _MaskedStem();

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurface
        .withValues(alpha: 0.18);
    return Semantics(
      label: 'Question text hidden',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _bar(color, 1),
          const SizedBox(height: Spacing.sm),
          _bar(color, 0.92),
          const SizedBox(height: Spacing.sm),
          _bar(color, 0.55),
        ],
      ),
    );
  }

  Widget _bar(Color color, double widthFactor) {
    return Align(
      alignment: Alignment.centerLeft,
      child: FractionallySizedBox(
        widthFactor: widthFactor,
        child: Container(
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(6),
          ),
        ),
      ),
    );
  }
}

/// Compact metadata pill. Lighter than a stock [Chip] so three of them on one
/// card stay readable; [color] tints it for the one fact worth emphasising.
class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.label, this.color});

  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tint = color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Spacing.sm, vertical: 3),
      decoration: BoxDecoration(
        color: tint == null
            ? scheme.surfaceContainerHighest
            : tint.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: tint ?? scheme.onSurfaceVariant,
          fontWeight: tint == null ? FontWeight.w600 : FontWeight.w700,
        ),
      ),
    );
  }
}
