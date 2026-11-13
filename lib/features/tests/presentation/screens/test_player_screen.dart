import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/spacing.dart';
import '../../../../core/utils/user_facing_error.dart';
import '../../../../core/widgets/async_status_views.dart';
import '../../../profile/domain/plan_tier.dart';
import '../../../security/domain/capture_event.dart';
import '../../../security/presentation/widgets/content_capture_guard.dart';
import '../../domain/player_session_state.dart';
import '../../domain/reading_mode_redirect.dart';
import '../providers/player_session_provider.dart';
import '../widgets/test_player_view.dart';

/// Question player for catalog tests and practice sessions.
///
/// Behavior branches on `tests.feedback_timing` inside [PlayerSessionState]:
/// Tutor Mode reveals + locks; Exam Mode does not. Same widget either way.
class TestPlayerScreen extends ConsumerStatefulWidget {
  const TestPlayerScreen({super.key, required this.testId});

  final String testId;

  static const _planLockedMessage =
      'This test is not available on your current plan.';

  @override
  ConsumerState<TestPlayerScreen> createState() => _TestPlayerScreenState();
}

class _TestPlayerScreenState extends ConsumerState<TestPlayerScreen>
    with WidgetsBindingObserver {
  bool _didNavigateToResults = false;
  bool _didRedirectToReading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void deactivate() {
    _flush();
    super.deactivate();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(playerSessionProvider(widget.testId).notifier).onAppResumed();
      return;
    }
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _flush();
    }
  }

  void _flush() {
    ref.read(playerSessionProvider(widget.testId).notifier).flushSave();
  }

  bool _isReadingRedirect(Object error) {
    if (error is ReadingModeRedirect) return true;
    return error.toString().contains('ReadingModeRedirect');
  }

  void _openReading(BuildContext context) {
    if (_didRedirectToReading || !context.mounted) return;
    _didRedirectToReading = true;
    context.go(AppRoutes.practiceReadingPath(widget.testId));
  }

  void _goToResults(PlayerSessionState session) {
    if (_didNavigateToResults || !mounted) return;
    _didNavigateToResults = true;
    ref.invalidate(playerSessionProvider(widget.testId));
    context.go(
      AppRoutes.resultsPath(
        session.attemptId,
        testId: widget.testId,
        isPractice: session.isEphemeralPractice,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final testId = widget.testId;
    final sessionAsync = ref.watch(playerSessionProvider(testId));

    ref.listen(playerSessionProvider(testId), (previous, next) {
      final session = next.asData?.value;
      if (session == null) return;
      if (session.isSubmitComplete) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _goToResults(session);
        });
        return;
      }
      if (session.isPendingSubmit) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          ref.read(playerSessionProvider(testId).notifier).ensureSubmitting();
        });
      }
    });

    return ContentCaptureGuard(
      screen: ContentScreens.testPlayer,
      child: sessionAsync.when(
        loading: () => Scaffold(
          appBar: AppBar(title: const Text('Test')),
          body: const AsyncLoadingView(),
        ),
        error: (error, _) {
          if (_isReadingRedirect(error)) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _openReading(context);
            });
            return Scaffold(
              appBar: AppBar(title: const Text('Reading')),
              body: const AsyncLoadingView(),
            );
          }
          final message = UserFacingError.display(error);
          final planLocked = message == TestPlayerScreen._planLockedMessage;
          return Scaffold(
            appBar: AppBar(title: const Text('Test')),
            body: AsyncErrorView(
              message: message,
              icon: planLocked ? Icons.lock_outline : null,
              actionLabel: planLocked ? 'View upgrade options' : 'Retry',
              onAction: planLocked
                  ? () => context.go(AppRoutes.upgradePath(PlanTier.pro))
                  : () => ref.invalidate(playerSessionProvider(testId)),
              secondaryLabel: 'Back',
              onSecondary: () => _exit(context),
            ),
          );
        },
        data: (session) {
          if (session.isSubmitComplete) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _goToResults(session);
            });
            return const _SubmittingBody();
          }

          if (session.isPendingSubmit) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              ref
                  .read(playerSessionProvider(testId).notifier)
                  .ensureSubmitting();
            });
            return _SubmittingBody(errorMessage: session.submitError);
          }

          return TestPlayerView(
            session: session,
            now: () => ref.read(playerSessionProvider(testId).notifier).now(),
            onSelectOption: (option) => ref
                .read(playerSessionProvider(testId).notifier)
                .selectOption(option),
            onGoTo: (index) =>
                ref.read(playerSessionProvider(testId).notifier).goTo(index),
            onClear: () => ref
                .read(playerSessionProvider(testId).notifier)
                .clearResponse(),
            onToggleMark: () =>
                ref.read(playerSessionProvider(testId).notifier).toggleMark(),
            onMarkAndNext: () => ref
                .read(playerSessionProvider(testId).notifier)
                .markForReviewAndNext(),
            onPrevious: () =>
                ref.read(playerSessionProvider(testId).notifier).previous(),
            onSaveAndNext: () =>
                ref.read(playerSessionProvider(testId).notifier).saveAndNext(),
            onSubmitSection: () => ref
                .read(playerSessionProvider(testId).notifier)
                .submitSection(),
            onFinish: () => ref
                .read(playerSessionProvider(testId).notifier)
                .finishAndSubmit(),
            onExit: () => _exit(context),
          );
        },
      ),
    );
  }

  void _exit(BuildContext context) {
    _flush();
    final practice =
        ref
            .read(playerSessionProvider(widget.testId))
            .asData
            ?.value
            .isEphemeralPractice ??
        false;
    if (practice) {
      context.go(AppRoutes.practice);
      return;
    }
    if (context.canPop()) {
      context.pop();
      return;
    }
    context.go(AppRoutes.home);
  }
}

class _SubmittingBody extends StatelessWidget {
  const _SubmittingBody({this.errorMessage});

  final String? errorMessage;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(Spacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: Spacing.md),
              const Text('Submitting…'),
              if (errorMessage != null) ...[
                const SizedBox(height: Spacing.sm),
                Text(
                  errorMessage!,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
