import 'package:material_ui/material_ui.dart';

import '../../../../core/theme/spacing.dart';
import '../../../../core/widgets/markdown_copy.dart';
import '../../../tests/domain/question_option.dart';
import '../../../tests/presentation/widgets/option_list.dart';
import '../../../../core/theme/player_colors.dart';
import '../../domain/attempt_review.dart';

/// Options in review: tap does nothing; colors come from [ReviewItem.visualFor].
class ReviewOptionList extends StatelessWidget {
  const ReviewOptionList({super.key, required this.item});

  final ReviewItem item;

  @override
  Widget build(BuildContext context) {
    final question = item.question;
    if (question == null) return const SizedBox.shrink();

    return Column(
      children: [
        for (final option in QuestionOption.values) ...[
          OptionTile(
            letter: option.label,
            text: question.textFor(option),
            visual: item.visualFor(option),
            locked: true,
            onTap: () {},
          ),
          const SizedBox(height: Spacing.sm),
        ],
      ],
    );
  }
}

/// Correct / incorrect / skipped banner, plus explanation when allowed.
class ReviewStatusBanner extends StatelessWidget {
  const ReviewStatusBanner({super.key, required this.item});

  final ReviewItem item;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final (color, icon) = _style(colorScheme);
    final explanation = item.visibleExplanation;
    final videoUrl = item.visibleVideoUrl;

    return Semantics(
      label: item.statusLabel,
      container: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(Spacing.sm),
          border: Border.all(color: color),
        ),
        child: Padding(
          padding: const EdgeInsets.all(Spacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, color: color),
                  const SizedBox(width: Spacing.sm),
                  Text(
                    item.statusLabel,
                    style: Theme.of(context).textTheme.titleSmall
                        ?.copyWith(color: color, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
              const SizedBox(height: Spacing.sm),
              Text(
                item.yourAnswerLabel,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              if (item.correctAnswerLabel != null) ...[
                const SizedBox(height: Spacing.xs),
                Text(
                  item.correctAnswerLabel!,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
              if (explanation != null) ...[
                const SizedBox(height: Spacing.sm),
                MarkdownCopy(data: explanation),
              ],
              if (videoUrl != null) ...[
                const SizedBox(height: Spacing.sm),
                Text(
                  'Video: $videoUrl',
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: colorScheme.onSurfaceVariant),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  (Color, IconData) _style(ColorScheme scheme) {
    if (item.isPlanLocked) {
      return (scheme.onSurfaceVariant, Icons.lock_outline);
    }
    if (item.isUnattempted) {
      return (scheme.onSurfaceVariant, Icons.remove_circle_outline);
    }
    if (item.isCorrect) {
      return (PlayerColors.correct, Icons.check_circle);
    }
    return (scheme.error, Icons.cancel);
  }
}
