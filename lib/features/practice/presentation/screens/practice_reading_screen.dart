import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/spacing.dart';
import '../../../../core/utils/result.dart';
import '../../../../core/widgets/async_status_views.dart';
import '../../../security/domain/capture_event.dart';
import '../../../security/presentation/widgets/content_capture_guard.dart';
import '../../../tests/data/tests_repository.dart';
import '../../../tests/domain/test_player_bundle.dart';
import '../../domain/practice_enums.dart';
import '../widgets/reading_question_card.dart';

/// Scroll of a practice session's questions with answers already open.
///
/// Does not create an attempt, so there is nothing to score or resume.
class PracticeReadingScreen extends ConsumerStatefulWidget {
  const PracticeReadingScreen({super.key, required this.testId});

  final String testId;

  @override
  ConsumerState<PracticeReadingScreen> createState() =>
      _PracticeReadingScreenState();
}

class _PracticeReadingScreenState extends ConsumerState<PracticeReadingScreen> {
  TestPlayerBundle? _bundle;
  String? _errorMessage;
  var _loading = true;
  var _leftForPlayer = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    final result = await ref
        .read(testsRepositoryProvider)
        .fetchPlayerBundle(widget.testId);

    if (!mounted) return;

    switch (result) {
      case Success(:final value):
        if (value.feedbackTiming != FeedbackTiming.reading) {
          _openPlayer();
          return;
        }
        setState(() {
          _bundle = value;
          _loading = false;
        });
      case Failure(:final message):
        setState(() {
          _errorMessage = message;
          _loading = false;
        });
    }
  }

  void _openPlayer() {
    if (_leftForPlayer) return;
    _leftForPlayer = true;
    context.go(AppRoutes.testPlayerPath(widget.testId));
  }

  void _close() {
    if (context.canPop()) {
      context.pop();
      return;
    }
    context.go(AppRoutes.practice);
  }

  @override
  Widget build(BuildContext context) {
    final bundle = _bundle;

    return ContentCaptureGuard(
      screen: ContentScreens.practiceReading,
      watermark: false,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Reading'),
          leading: IconButton(icon: const Icon(Icons.close), onPressed: _close),
        ),
        body: _loading
            ? const AsyncLoadingView()
            : _errorMessage != null
            ? AsyncErrorView(
                message: _errorMessage!,
                onAction: _load,
                secondaryLabel: 'Back',
                onSecondary: _close,
              )
            : bundle == null || bundle.questions.isEmpty
            ? AsyncEmptyView(
                icon: Icons.menu_book_outlined,
                message: 'No questions to read.',
                actionLabel: 'Back',
                onAction: _close,
              )
            : ListView.separated(
                padding: const EdgeInsets.all(Spacing.lg),
                itemCount: bundle.questions.length,
                separatorBuilder: (context, index) =>
                    const SizedBox(height: Spacing.lg),
                itemBuilder: (context, index) {
                  return ReadingQuestionCard(
                    number: index + 1,
                    question: bundle.questions[index],
                    explanationLevel: bundle.explanationLevel,
                  );
                },
              ),
      ),
    );
  }
}
