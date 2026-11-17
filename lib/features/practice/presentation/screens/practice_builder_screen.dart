import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_routes.dart';
import '../../../../core/supabase/tables.dart';
import '../../../../core/theme/spacing.dart';
import '../../../../core/utils/result.dart';
import '../../../../core/utils/user_facing_error.dart';
import '../../../../core/widgets/async_status_views.dart';
import '../../../profile/domain/plan_tier.dart';
import '../../../tests/data/local_attempt_store.dart';
import '../../../tests/data/tests_repository.dart';
import '../../../tests/domain/attempt_submit_request.dart';
import '../../../tests/domain/attempt_status.dart';
import '../../../tests/presentation/providers/in_progress_attempts_provider.dart';
import '../../data/practice_repository.dart';
import '../../domain/plan_limits.dart';
import '../../domain/practice_builder_draft.dart';
import '../../domain/practice_catalog.dart';
import '../../domain/practice_clamp_copy.dart';
import '../../domain/practice_slot.dart';
import '../providers/practice_catalog_provider.dart';
import '../providers/practice_plan_context_provider.dart';
import '../providers/practice_slot_provider.dart';
import '../widgets/practice_builder_filter_sheet.dart';
import '../widgets/practice_builder_form.dart';

/// Form that calls `create_practice_session()` and opens the question player.
class PracticeBuilderScreen extends ConsumerStatefulWidget {
  const PracticeBuilderScreen({super.key, this.initialDraft});

  /// Pre-fill for "Practice Similar Again" (Phase 4B.4).
  final PracticeBuilderDraft? initialDraft;

  @override
  ConsumerState<PracticeBuilderScreen> createState() =>
      _PracticeBuilderScreenState();
}

class _PracticeBuilderScreenState extends ConsumerState<PracticeBuilderScreen> {
  late PracticeBuilderDraft _draft;
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _draft = widget.initialDraft ?? const PracticeBuilderDraft();
  }

  @override
  void didUpdateWidget(PracticeBuilderScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = widget.initialDraft;
    // A new extra from "Practice similar" or a lesson replaces the form.
    // A tab revisit passes null and must keep what the student already set.
    if (next != null && !identical(next, oldWidget.initialDraft)) {
      _draft = next;
    }
  }

  Future<void> _submit({
    required PracticeBuilderDraft draft,
    required PracticeCatalog catalog,
    required PracticePlanContext planContext,
    required PracticeSlot? slot,
  }) async {
    if (slot != null && slot.isOpen) {
      final replace = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Start a new practice?'),
          content: const Text(
            'This replaces your current practice. Questions you already answered stay marked as attempted.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Start new'),
            ),
          ],
        ),
      );
      if (replace != true || !mounted) return;
    }

    setState(() {
      _errorMessage = null;
      _isSubmitting = true;
    });

    // An open session's selections live in a local file until submit. Send
    // them with the replace call, or the next Unattempted filter would
    // offer those questions again.
    final handoff = await _priorAnswersForReplace(slot);
    if (!mounted || handoff == null) return;

    final result = await ref
        .read(practiceRepositoryProvider)
        .createSession(
          draft: draft,
          catalog: catalog,
          priorAnswers: handoff.priorAnswers,
        );

    if (!mounted) return;

    setState(() => _isSubmitting = false);

    switch (result) {
      case Success(:final value):
        final attemptId = handoff.attemptIdToDelete;
        if (attemptId != null) {
          await ref.read(localAttemptStoreProvider).delete(attemptId);
        }
        ref.invalidate(practicePlanContextProvider);
        ref.invalidate(practiceSlotProvider);
        ref.invalidate(inProgressAttemptsProvider);
        if (!mounted) return;
        final toast = PracticeClampCopy.toast(
          requested: draft,
          actual: value,
          maxSessionQuestions: planContext.limits.maxPracticeSessionQuestions,
        );
        if (toast != null) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(toast)));
        }
        final path = draft.isReading
            ? AppRoutes.practiceReadingPath(value.testId)
            : AppRoutes.testPlayerPath(value.testId);
        context.go(path);
      case Failure(:final message):
        setState(() => _errorMessage = message);
    }
  }

  /// Null means the replace stopped (submit of a finished session failed).
  Future<_ReplaceHandoff?> _priorAnswersForReplace(PracticeSlot? slot) async {
    if (slot == null || !slot.isOpen) {
      return const _ReplaceHandoff();
    }

    final userId = ref.read(testsRepositoryProvider).currentUserId;
    if (userId == null) return const _ReplaceHandoff();

    final store = ref.read(localAttemptStoreProvider);
    final snapshot = await store.readOpenForTest(
      testId: slot.testId,
      userId: userId,
    );
    if (snapshot == null) return const _ReplaceHandoff();

    if (snapshot.localStatus == LocalAttemptStatus.pendingSubmit) {
      final submitted = await ref
          .read(testsRepositoryProvider)
          .submitAttempt(AttemptSubmitRequest.fromSnapshot(snapshot));
      if (!mounted) return null;
      switch (submitted) {
        case Success():
          await store.delete(snapshot.attemptId);
          return const _ReplaceHandoff();
        case Failure(:final message) when isTerminalSubmitFailure(message):
          await store.delete(snapshot.attemptId);
          return const _ReplaceHandoff();
        case Failure(:final message):
          setState(() {
            _isSubmitting = false;
            _errorMessage = message;
          });
          return null;
      }
    }

    return _ReplaceHandoff(
      priorAnswers: [
        for (final entry in snapshot.answers.entries)
          if (entry.value.selectedOption != null)
            {
              AttemptAnswerColumns.questionId: entry.key,
              AttemptAnswerColumns.selectedOption:
                  entry.value.selectedOption!.dbValue,
            },
      ],
      attemptIdToDelete: snapshot.attemptId,
    );
  }

  void _resume(PracticeSlot slot) {
    final path = slot.opensReader
        ? AppRoutes.practiceReadingPath(slot.testId)
        : AppRoutes.testPlayerPath(slot.testId);
    context.go(path);
  }

  @override
  Widget build(BuildContext context) {
    final catalogAsync = ref.watch(practiceCatalogProvider);
    final planAsync = ref.watch(practicePlanContextProvider);
    final slotAsync = ref.watch(practiceSlotProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Practice'),
        automaticallyImplyLeading: false,
        actions: [
          if (catalogAsync.hasValue &&
              catalogAsync.requireValue.subjects.isNotEmpty &&
              planAsync.hasValue)
            TextButton(
              onPressed: () {
                final catalog = catalogAsync.requireValue;
                final planContext = planAsync.requireValue;
                final draft = _draft
                    .alignedWithCatalog(catalog)
                    .clampedTo(planContext);
                showPracticeBuilderFilterSheet(
                  context: context,
                  draft: draft,
                  catalog: catalog,
                  planContext: planContext,
                  onChanged: (next) => setState(() => _draft = next),
                  onUpgrade: () =>
                      context.go(AppRoutes.upgradePath(PlanTier.pro)),
                );
              },
              child: Text(
                _draft.hasContentFilters ? 'Filters · on' : 'Filters',
              ),
            ),
          IconButton(
            tooltip: 'Refresh',
            onPressed: () {
              ref.read(practiceCatalogProvider.notifier).refresh();
              ref.read(practicePlanContextProvider.notifier).refresh();
              ref.read(practiceSlotProvider.notifier).refresh();
            },
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: catalogAsync.when(
        loading: () => const AsyncLoadingView(),
        error: (error, _) => AsyncErrorView(
          message: UserFacingError.display(error),
          onAction: () => ref.read(practiceCatalogProvider.notifier).refresh(),
        ),
        data: (catalog) {
          if (catalog.subjects.isEmpty) {
            return AsyncEmptyView(
              icon: Icons.menu_book_outlined,
              message: 'No practice content is available yet.',
              actionLabel: 'Retry',
              onAction: () =>
                  ref.read(practiceCatalogProvider.notifier).refresh(),
            );
          }
          return planAsync.when(
            loading: () => const AsyncLoadingView(),
            error: (error, _) => AsyncErrorView(
              message: UserFacingError.display(error),
              onAction: () =>
                  ref.read(practicePlanContextProvider.notifier).refresh(),
            ),
            data: (planContext) {
              return slotAsync.when(
                loading: () => const AsyncLoadingView(),
                error: (error, _) => AsyncErrorView(
                  message: UserFacingError.display(error),
                  onAction: () =>
                      ref.read(practiceSlotProvider.notifier).refresh(),
                ),
                data: (slot) {
                  // Align stale IDs, then re-clamp to *this* plan — stored JSON
                  // is a hint, not a grant (plan may have changed since last time).
                  final draft = _draft
                      .alignedWithCatalog(catalog)
                      .clampedTo(planContext);
                  final open = slot != null && slot.isOpen;
                  final label = switch ((open, draft.isReading)) {
                    (true, _) => 'Start new',
                    (false, true) => 'Start reading',
                    (false, false) => 'Start practice',
                  };
                  return Column(
                    children: [
                      Expanded(
                        child: PracticeBuilderForm(
                          draft: draft,
                          catalog: catalog,
                          planContext: planContext,
                          onChanged: (next) => setState(() => _draft = next),
                          onUpgrade: () =>
                              context.go(AppRoutes.upgradePath(PlanTier.pro)),
                        ),
                      ),
                      _StartBar(
                        errorMessage: _errorMessage,
                        isSubmitting: _isSubmitting,
                        label: label,
                        quotaExhausted: planContext.dailyQuotaExhausted,
                        showUpgradeOnExhausted:
                            planContext.limits.plan == PlanTier.free,
                        onUpgrade: () =>
                            context.go(AppRoutes.upgradePath(PlanTier.pro)),
                        onResume: slot != null && slot.isOpen && !_isSubmitting
                            ? () => _resume(slot)
                            : null,
                        onStart:
                            _isSubmitting || planContext.dailyQuotaExhausted
                            ? null
                            : () => _submit(
                                draft: draft,
                                catalog: catalog,
                                planContext: planContext,
                                slot: slot,
                              ),
                      ),
                    ],
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}

/// Answers to send with the replace call, and the local file to drop after.
class _ReplaceHandoff {
  const _ReplaceHandoff({this.priorAnswers = const [], this.attemptIdToDelete});

  final List<Map<String, String>> priorAnswers;
  final String? attemptIdToDelete;
}

class _StartBar extends StatelessWidget {
  const _StartBar({
    required this.errorMessage,
    required this.isSubmitting,
    required this.label,
    required this.quotaExhausted,
    this.showUpgradeOnExhausted = false,
    this.onUpgrade,
    this.onResume,
    required this.onStart,
  });

  final String? errorMessage;
  final bool isSubmitting;
  final String label;
  final bool quotaExhausted;
  final bool showUpgradeOnExhausted;
  final VoidCallback? onUpgrade;
  final VoidCallback? onResume;
  final VoidCallback? onStart;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(
        Spacing.lg,
        Spacing.sm,
        Spacing.lg,
        Spacing.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (errorMessage != null) ...[
            Text(
              errorMessage!,
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: colorScheme.error),
            ),
            const SizedBox(height: Spacing.sm),
          ],
          if (quotaExhausted)
            Padding(
              padding: const EdgeInsets.only(bottom: Spacing.sm),
              child: Text(
                "You've used today's practice questions. Come back tomorrow.",
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: colorScheme.error),
              ),
            ),
          if (onResume != null) ...[
            OutlinedButton(onPressed: onResume, child: const Text('Resume')),
            const SizedBox(height: Spacing.sm),
          ],
          if (quotaExhausted && showUpgradeOnExhausted && onUpgrade != null)
            FilledButton.icon(
              onPressed: onUpgrade,
              icon: const Icon(Icons.lock_open_outlined, size: 18),
              label: const Text('Upgrade to Pro for unlimited practice'),
            )
          else
            FilledButton(
              onPressed: onStart,
              child: isSubmitting
                  ? SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Theme.of(context).colorScheme.onPrimary,
                      ),
                    )
                  : Text(label),
            ),
        ],
      ),
    );
  }
}
