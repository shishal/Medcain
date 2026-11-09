import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/spacing.dart';
import '../../../../core/utils/result.dart';
import '../../../../core/utils/user_facing_error.dart';
import '../../../../core/widgets/async_status_views.dart';
import '../../../profile/domain/plan_tier.dart';
import '../../data/practice_repository.dart';
import '../../domain/plan_limits.dart';
import '../../domain/practice_builder_draft.dart';
import '../../domain/practice_catalog.dart';
import '../../domain/practice_clamp_copy.dart';
import '../providers/practice_catalog_provider.dart';
import '../providers/practice_plan_context_provider.dart';
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
  }) async {
    setState(() {
      _errorMessage = null;
      _isSubmitting = true;
    });

    final result = await ref
        .read(practiceRepositoryProvider)
        .createSession(draft: draft, catalog: catalog);

    if (!mounted) return;

    setState(() => _isSubmitting = false);

    switch (result) {
      case Success(:final value):
        ref.invalidate(practicePlanContextProvider);
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
        context.go(AppRoutes.testPlayerPath(value.testId));
      case Failure(:final message):
        setState(() => _errorMessage = message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final catalogAsync = ref.watch(practiceCatalogProvider);
    final planAsync = ref.watch(practicePlanContextProvider);

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
              // Align stale IDs, then re-clamp to *this* plan — stored JSON
              // is a hint, not a grant (plan may have changed since last time).
              final draft = _draft
                  .alignedWithCatalog(catalog)
                  .clampedTo(planContext);
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
                    quotaExhausted: planContext.dailyQuotaExhausted,
                    onStart: _isSubmitting || planContext.dailyQuotaExhausted
                        ? null
                        : () => _submit(
                            draft: draft,
                            catalog: catalog,
                            planContext: planContext,
                          ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _StartBar extends StatelessWidget {
  const _StartBar({
    required this.errorMessage,
    required this.isSubmitting,
    required this.quotaExhausted,
    required this.onStart,
  });

  final String? errorMessage;
  final bool isSubmitting;
  final bool quotaExhausted;
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
                : const Text('Start practice'),
          ),
        ],
      ),
    );
  }
}
