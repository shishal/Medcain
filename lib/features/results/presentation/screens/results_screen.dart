import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/spacing.dart';
import '../../../../core/utils/result.dart';
import '../../../../core/utils/user_facing_error.dart';
import '../../../../core/widgets/async_status_views.dart';
import '../../../practice/data/practice_repository.dart';
import '../providers/attempt_results_provider.dart';
import '../widgets/results_summary.dart';

/// Score / accuracy / percentile / subject breakdown after submit.
class ResultsScreen extends ConsumerStatefulWidget {
  const ResultsScreen({
    super.key,
    required this.attemptId,
    this.testId,
    this.isPractice = false,
  });

  final String attemptId;
  final String? testId;
  final bool isPractice;

  @override
  ConsumerState<ResultsScreen> createState() => _ResultsScreenState();
}

class _ResultsScreenState extends ConsumerState<ResultsScreen> {
  bool _similarBusy = false;

  Future<void> _practiceSimilarAgain(String testId) async {
    setState(() => _similarBusy = true);

    final result = await ref
        .read(practiceRepositoryProvider)
        .fetchSimilarDraft(testId);

    if (!mounted) return;
    setState(() => _similarBusy = false);

    switch (result) {
      case Success(:final value):
        if (value == null) {
          _showMessage('Could not restore those filters.');
          return;
        }
        context.go(AppRoutes.practice, extra: value);
      case Failure(:final message):
        _showMessage(message);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  void _goHome() => context.go(AppRoutes.home);

  @override
  Widget build(BuildContext context) {
    final resultsAsync = ref.watch(attemptResultsProvider(widget.attemptId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Results'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _goHome,
        ),
      ),
      body: resultsAsync.when(
        loading: () => const AsyncLoadingView(),
        error: (error, _) => AsyncErrorView(
          message: UserFacingError.display(error),
          onAction: () =>
              ref.invalidate(attemptResultsProvider(widget.attemptId)),
          secondaryLabel: 'Back to home',
          onSecondary: _goHome,
        ),
        data: (results) => Column(
          children: [
            Expanded(child: ResultsSummary(results: results)),
            _ResultsActions(
              showPracticeSimilar:
                  results.isEphemeralPractice || widget.isPractice,
              similarBusy: _similarBusy,
              onReview: () =>
                  context.push(AppRoutes.solutionReviewPath(widget.attemptId)),
              onPracticeSimilar: () =>
                  _practiceSimilarAgain(widget.testId ?? results.testId),
              onHome: _goHome,
            ),
          ],
        ),
      ),
    );
  }
}

class _ResultsActions extends StatelessWidget {
  const _ResultsActions({
    required this.showPracticeSimilar,
    required this.similarBusy,
    required this.onReview,
    required this.onPracticeSimilar,
    required this.onHome,
  });

  final bool showPracticeSimilar;
  final bool similarBusy;
  final VoidCallback onReview;
  final VoidCallback onPracticeSimilar;
  final VoidCallback onHome;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
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
            FilledButton.tonal(
              onPressed: onReview,
              child: const Text('Review solutions'),
            ),
            const SizedBox(height: Spacing.md),
            if (showPracticeSimilar) ...[
              FilledButton.tonal(
                onPressed: similarBusy ? null : onPracticeSimilar,
                child: similarBusy
                    ? SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Theme.of(context)
                              .colorScheme
                              .onSecondaryContainer,
                        ),
                      )
                    : const Text('Practice Similar Again'),
              ),
              const SizedBox(height: Spacing.md),
            ],
            FilledButton(onPressed: onHome, child: const Text('Back to home')),
          ],
        ),
      ),
    );
  }
}
