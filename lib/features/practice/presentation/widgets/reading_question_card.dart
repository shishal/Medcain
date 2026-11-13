import 'package:material_ui/material_ui.dart';

import '../../../../core/theme/player_colors.dart';
import '../../../../core/theme/spacing.dart';
import '../../../../core/utils/open_external_link.dart';
import '../../../../core/widgets/comic_card.dart';
import '../../../../core/widgets/markdown_copy.dart';
import '../../../bookmarks/presentation/widgets/bookmark_icon_button.dart';
import '../../../tests/domain/player_question.dart';
import '../../../tests/domain/player_session_state.dart';
import '../../../tests/domain/question_option.dart';
import '../../../tests/presentation/widgets/option_list.dart';
import '../../domain/practice_enums.dart';

/// One MCQ in Reading Mode: stem, options, and the answer already marked.
class ReadingQuestionCard extends StatelessWidget {
  const ReadingQuestionCard({
    super.key,
    required this.number,
    required this.question,
    required this.explanationLevel,
  });

  final int number;
  final PlayerQuestion question;
  final ExplanationLevel explanationLevel;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    final imageUrl = question.imageUrl?.trim();
    final showExplanation = explanationLevel == ExplanationLevel.full;
    final explanation = showExplanation
        ? PlayerQuestion.joinedExplanation(
            question.explanationText,
            question.explanationDeep,
          )
        : null;
    final videoUrl = showExplanation
        ? question.explanationVideoUrl?.trim()
        : null;

    return ComicCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Question $number',
                style: textTheme.labelMedium?.copyWith(
                  color: colorScheme.primary,
                ),
              ),
              const Spacer(),
              BookmarkIconButton(questionId: question.id),
            ],
          ),
          Text(question.questionText, style: textTheme.titleMedium),
          if (imageUrl != null && imageUrl.isNotEmpty) ...[
            const SizedBox(height: Spacing.md),
            ClipRRect(
              borderRadius: BorderRadius.circular(Spacing.sm),
              child: Image.network(
                imageUrl,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) =>
                    const SizedBox.shrink(),
              ),
            ),
          ],
          const SizedBox(height: Spacing.md),
          for (final option in QuestionOption.values) ...[
            OptionTile(
              letter: option.label,
              text: question.textFor(option),
              visual: option == question.correctOption
                  ? OptionVisual.revealedCorrect
                  : OptionVisual.idle,
              locked: true,
              onTap: () {},
            ),
            const SizedBox(height: Spacing.sm),
          ],
          Text(
            'Answer ${question.correctOption.label}',
            style: textTheme.titleSmall?.copyWith(
              color: PlayerColors.correct,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (explanation != null) ...[
            const SizedBox(height: Spacing.md),
            Text('Explanation', style: textTheme.titleSmall),
            const SizedBox(height: Spacing.xs),
            MarkdownCopy(data: explanation),
          ],
          if (videoUrl != null && videoUrl.isNotEmpty)
            TextButton(
              onPressed: () => openExternalLink(context, videoUrl),
              child: const Text('Watch explanation'),
            ),
        ],
      ),
    );
  }
}
