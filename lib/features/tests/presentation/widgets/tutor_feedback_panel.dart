import 'package:material_ui/material_ui.dart';

import '../../../../core/theme/spacing.dart';
import '../../../../core/widgets/markdown_copy.dart';
import '../../domain/player_session_state.dart';
import '../../../../core/theme/player_colors.dart';

/// Shown only when [PlayerSessionState.revealsFeedback] is true (Tutor Mode).
class TutorFeedbackPanel extends StatelessWidget {
  const TutorFeedbackPanel({super.key, required this.reveal});

  final FeedbackReveal reveal;

  @override
  Widget build(BuildContext context) {
    final color = reveal.isCorrect
        ? PlayerColors.correct
        : PlayerColors.incorrect;
    final label = reveal.isCorrect ? 'Correct' : 'Incorrect';

    return Semantics(
      label: label,
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
                  Icon(
                    reveal.isCorrect ? Icons.check_circle : Icons.cancel,
                    color: color,
                  ),
                  const SizedBox(width: Spacing.sm),
                  Text(
                    label,
                    style: Theme.of(context).textTheme.titleSmall
                        ?.copyWith(color: color, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
              if (reveal.explanationText != null) ...[
                const SizedBox(height: Spacing.sm),
                MarkdownCopy(data: reveal.explanationText!),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
