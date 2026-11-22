import 'package:material_ui/material_ui.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/spacing.dart';
import '../../../../core/widgets/question_stem_image.dart';
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
    final finishLabel = session.isTutorMode ? 'Finish session' : 'Submit test';

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmExit(context);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(session.title),
          leading: IconButton(
            tooltip: 'Save and exit',
            icon: const Icon(Icons.close),
            onPressed: () => _confirmExit(context),
          ),
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
              onPressed: () => _confirmFinish(context),
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
              child: session.isEphemeralPractice
                  ? _PracticeQuestionPager(
                      session: session,
                      onGoTo: onGoTo,
                      onSelectOption: onSelectOption,
                    )
                  : _QuestionBody(
                      session: session,
                      onSelectOption: onSelectOption,
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

  Future<void> _confirmFinish(BuildContext context) async {
    final tally = session.paletteTally;
    final unanswered = tally.notAnswered + tally.notVisited;
    final title = session.isTutorMode ? 'Finish session?' : 'Submit test?';
    final actionLabel = session.isTutorMode ? 'Finish session' : 'Submit test';
    final summary = <String>[
      if (unanswered > 0)
        '$unanswered ${unanswered == 1 ? 'question is' : 'questions are'} still unanswered.',
      if (tally.marked > 0)
        '${tally.marked} ${tally.marked == 1 ? 'question is' : 'questions are'} marked for review.',
      if (unanswered == 0 && tally.marked == 0)
        'All ${session.questions.length} questions have been answered.',
      'Your answers will be scored and locked.',
    ].join(' ');

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(title),
          content: Text(summary),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Keep going'),
            ),
            FilledButton(
              key: const Key('confirm-finish-test'),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(actionLabel),
            ),
          ],
        );
      },
    );
    if (confirmed == true) onFinish();
  }

  Future<void> _confirmExit(BuildContext context) async {
    final timerWarning = session.showsTimer
        ? ' The countdown keeps running while you are away.'
        : '';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Save and leave?'),
          content: Text(
            'Your progress is saved on this phone and you can resume from Home.$timerWarning',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Stay'),
            ),
            FilledButton(
              key: const Key('confirm-exit-test'),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Save & leave'),
            ),
          ],
        );
      },
    );
    if (confirmed == true) onExit();
  }
}

/// One question: stem, options, and tutor feedback when this question is revealed.
class _QuestionBody extends StatelessWidget {
  const _QuestionBody({required this.session, required this.onSelectOption});

  final PlayerSessionState session;
  final ValueChanged<QuestionOption> onSelectOption;

  @override
  Widget build(BuildContext context) {
    final question = session.currentQuestion;
    final reveal = session.feedbackReveal;

    return ListView(
      // Keying by question ID resets scroll offset to the top when this
      // question is built again after leaving it.
      key: ValueKey(question.id),
      padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
      children: [
        Text(
          question.questionText,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        QuestionStemImage(imageUrl: question.imageUrl),
        const SizedBox(height: Spacing.md),
        OptionList(session: session, onSelect: onSelectOption),
        if (reveal != null) ...[
          const SizedBox(height: Spacing.md),
          TutorFeedbackPanel(reveal: reveal),
        ],
      ],
    );
  }
}

/// Practice questions sit in a horizontal [PageView].
///
/// A finger moving left brings in the next question; a finger moving right
/// brings back the previous one. Each page has its own vertical list, so
/// scrolling up and down still reads a long stem. Catalog tests stay on the
/// action-bar buttons — a stray swipe there would skip a scored question.
class _PracticeQuestionPager extends StatefulWidget {
  const _PracticeQuestionPager({
    required this.session,
    required this.onGoTo,
    required this.onSelectOption,
  });

  final PlayerSessionState session;
  final ValueChanged<int> onGoTo;
  final ValueChanged<QuestionOption> onSelectOption;

  @override
  State<_PracticeQuestionPager> createState() => _PracticeQuestionPagerState();
}

class _PracticeQuestionPagerState extends State<_PracticeQuestionPager> {
  late final PageController _pages;
  late int _page;

  /// True while the buttons or the palette move the page. [PageView] reports
  /// every page it passes, and we ignore those so a jump from question 1 to
  /// question 5 does not stop on question 2.
  var _syncing = false;
  var _syncToken = 0;

  @override
  void initState() {
    super.initState();
    _page = widget.session.currentIndex;
    _pages = PageController(initialPage: _page);
  }

  @override
  void didUpdateWidget(covariant _PracticeQuestionPager oldWidget) {
    super.didUpdateWidget(oldWidget);
    final target = widget.session.currentIndex;
    if (target == _page) return;
    _page = target;
    _animateTo(target);
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _animateTo(int target) {
    if (!_pages.hasClients) return;
    final current = _pages.page;
    if (current != null && (current - target).abs() < 0.01) return;
    final token = ++_syncToken;
    _syncing = true;
    _pages
        .animateToPage(
          target,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
        )
        .whenComplete(() {
          if (!mounted || token != _syncToken) return;
          _syncing = false;
        });
  }

  void _onPageChanged(int index) {
    if (_syncing) return;
    if (!widget.session.isIndexReachable(index)) {
      _page = widget.session.currentIndex;
      _animateTo(_page);
      return;
    }
    _page = index;
    if (index != widget.session.currentIndex) widget.onGoTo(index);
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    return PageView.builder(
      controller: _pages,
      itemCount: session.questions.length,
      onPageChanged: _onPageChanged,
      itemBuilder: (context, index) {
        // copyWith only changes which question this page *displays*. The
        // session's real index still updates through [onGoTo].
        final page = session.copyWith(currentIndex: index);
        return IgnorePointer(
          ignoring: index != session.currentIndex,
          child: _QuestionBody(
            session: page,
            onSelectOption: widget.onSelectOption,
          ),
        );
      },
    );
  }
}
