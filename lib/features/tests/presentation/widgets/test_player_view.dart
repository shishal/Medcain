import 'package:material_ui/material_ui.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/spacing.dart';
import '../../domain/player_session_state.dart';
import '../../domain/question_option.dart';
import 'option_list.dart';
import 'palette_summary_bar.dart';
import 'player_action_bar.dart';
import 'question_palette_sheet.dart';
import 'session_timer_banner.dart';
import 'tutor_feedback_panel.dart';

/// Shared question player. Tutor vs Exam is a state branch, not a second screen.
class TestPlayerView extends StatelessWidget {
  const TestPlayerView({
    super.key,
    required this.session,
    required this.onSelectOption,
    required this.onGoTo,
    required this.onClear,
    required this.onToggleMark,
    required this.onMarkAndNext,
    required this.onPrevious,
    required this.onSaveAndNext,
    required this.onFinish,
    required this.onExit,
    this.onSubmitSection,
    this.now,
  });

  final PlayerSessionState session;
  final ValueChanged<QuestionOption> onSelectOption;
  final ValueChanged<int> onGoTo;
  final VoidCallback onClear;
  final VoidCallback onToggleMark;
  final VoidCallback onMarkAndNext;
  final VoidCallback onPrevious;
  final VoidCallback onSaveAndNext;
  final VoidCallback onFinish;
  final VoidCallback onExit;
  final VoidCallback? onSubmitSection;
  final DateTime Function()? now;

  @override
  Widget build(BuildContext context) {
    final question = session.currentQuestion;
    final reveal = session.feedbackReveal;
    final finishLabel = session.isTutorMode ? 'Finish session' : 'Submit test';

    return Scaffold(
      appBar: AppBar(
        title: Text(session.title),
        leading: IconButton(icon: const Icon(Icons.close), onPressed: onExit),
        actions: [
          IconButton(
            tooltip: session.currentAnswer.markedForReview
                ? 'Unmark for review'
                : 'Mark for review',
            onPressed: onToggleMark,
            icon: Icon(
              session.currentAnswer.markedForReview
                  ? Icons.flag
                  : Icons.flag_outlined,
            ),
          ),
          TextButton(
            style: session.isTutorMode
                ? null
                : TextButton.styleFrom(
                    foregroundColor: Theme.of(context).urgentAccent,
                  ),
            onPressed: onFinish,
            child: Text(finishLabel),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (session.showsTimer)
            Align(
              alignment: Alignment.centerRight,
              child: SessionTimerBanner(session: session, now: now),
            ),
          PaletteSummaryBar(
            tally: session.paletteTally,
            isTutorMode: session.isTutorMode,
            currentIndex: session.currentIndex,
            total: session.questions.length,
            onOpenPalette: () => _openPalette(context),
          ),
          if (session.isTutorMode)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Spacing.md,
                Spacing.xs,
                Spacing.md,
                0,
              ),
              child: Text(
                'Tutor Mode',
                style: Theme.of(context).textTheme.labelMedium
                    ?.copyWith(color: Theme.of(context).colorScheme.primary),
              ),
            ),
          const SizedBox(height: Spacing.sm),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
              children: [
                Text(
                  question.questionText,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: Spacing.md),
                OptionList(session: session, onSelect: onSelectOption),
                if (reveal != null) ...[
                  const SizedBox(height: Spacing.md),
                  TutorFeedbackPanel(reveal: reveal),
                ],
              ],
            ),
          ),
          PlayerActionBar(
            session: session,
            onClear: onClear,
            onMarkAndNext: onMarkAndNext,
            onPrevious: onPrevious,
            onSaveAndNext: onSaveAndNext,
            onSubmitSection: onSubmitSection == null
                ? null
                : () => _confirmSubmitSection(context),
          ),
        ],
      ),
    );
  }

  void _openPalette(BuildContext context) {
    QuestionPaletteSheet.show(
      context: context,
      cells: [
        for (var i = 0; i < session.questions.length; i++) session.paletteAt(i),
      ],
      currentIndex: session.currentIndex,
      isTutorMode: session.isTutorMode,
      sectionNumbers: [
        for (final question in session.questions) question.sectionNumber,
      ],
      isReachable: session.isIndexReachable,
      onSelect: onGoTo,
    );
  }

  Future<void> _confirmSubmitSection(BuildContext context) async {
    final unanswered = session.unansweredInCurrentSection();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Submit this section?'),
          content: Text(
            unanswered == 0
                ? 'You cannot return to this section once you continue.'
                : '$unanswered ${unanswered == 1 ? 'question is' : 'questions are'} '
                      'still unanswered in this section. You cannot return once you continue.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: const Key('confirm-submit-section'),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Submit section'),
            ),
          ],
        );
      },
    );
    if (confirmed == true) onSubmitSection?.call();
  }
}
