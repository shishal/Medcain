import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/spacing.dart';
import '../../../../core/utils/result.dart';
import '../../../../core/utils/user_facing_error.dart';
import '../../../../core/widgets/async_status_views.dart';
import '../../../practice/presentation/providers/practice_plan_context_provider.dart';
import '../../data/checkout_env.dart';
import '../../data/checkout_launcher.dart';
import '../../domain/plan_offer.dart';
import '../../domain/plan_tier.dart';
import '../providers/current_plan_provider.dart';
import '../providers/public_plans_provider.dart';
import '../providers/user_profile_provider.dart';
import '../widgets/plan_comparison_card.dart';
import '../widgets/plan_purchase_sheet.dart';

/// Plan comparison + a link out to web checkout.
///
/// Payment never happens in this app — the CTA opens the device browser.
class UpgradePromptScreen extends ConsumerStatefulWidget {
  const UpgradePromptScreen({super.key, this.requiredPlan = PlanTier.pro});

  /// Kept so older lock routes still open this screen. The list itself comes
  /// from the plans table, not from this tier.
  final PlanTier requiredPlan;

  @override
  ConsumerState<UpgradePromptScreen> createState() =>
      _UpgradePromptScreenState();
}

class _UpgradePromptScreenState extends ConsumerState<UpgradePromptScreen>
    with WidgetsBindingObserver {
  String? _openingPlanId;
  bool _awaitingPaymentReturn = false;
  Timer? _settleTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _settleTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _awaitingPaymentReturn) {
      _awaitingPaymentReturn = false;
      unawaited(_refreshAfterCheckout());
      // Follow up once 3s later in case the Razorpay webhook was still settling
      // when the student switched back from the browser.
      _settleTimer?.cancel();
      _settleTimer = Timer(const Duration(seconds: 3), () {
        if (mounted) unawaited(_refreshAfterCheckout());
      });
    }
  }

  Future<void> _refreshAfterCheckout() async {
    await ref.read(userProfileProvider.notifier).refresh();
    if (!mounted) return;
    ref.invalidate(effectivePlanProvider);
    ref.invalidate(currentPlanProvider);
    ref.invalidate(practicePlanContextProvider);
    ref.invalidate(publicPlansProvider);
  }

  Future<void> _openPurchase(PlanOffer plan) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        return PlanPurchaseSheet(
          plan: plan,
          onPay: (coupon) => _openCheckout(plan: plan, coupon: coupon),
        );
      },
    );
  }

  Future<bool> _openCheckout({
    required PlanOffer plan,
    required String coupon,
  }) async {
    setState(() => _openingPlanId = plan.id);

    final result = await ref.read(checkoutLauncherProvider).openCheckout(
      planId: plan.id,
      coupon: coupon,
    );

    if (!mounted) return false;
    setState(() => _openingPlanId = null);

    switch (result) {
      case Success():
        _awaitingPaymentReturn = true;
        return true;
      case Failure(:final message):
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
        return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final plansAsync = ref.watch(publicPlansProvider);
    final currentAsync = ref.watch(effectivePlanProvider);
    final currentId = currentAsync.asData?.value.id;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Plans'),
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go(AppRoutes.home);
            }
          },
        ),
      ),
      body: plansAsync.when(
        loading: () => const AsyncLoadingView(),
        error: (error, _) => AsyncErrorView(
          message: UserFacingError.display(error),
          onAction: () => ref.invalidate(publicPlansProvider),
        ),
        data: (plans) {
          return RefreshIndicator(
            onRefresh: _refreshAfterCheckout,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(Spacing.lg),
              children: [
                Text('Compare plans', style: textTheme.headlineSmall),
                const SizedBox(height: Spacing.sm),
                Text(
                  CheckoutEnv.webCheckoutEnabled
                      ? 'You will finish payment on our website in your browser. '
                            'This app never takes a card.'
                      : 'Paid checkout is paused during this beta. '
                            'You can keep using the Free plan.',
                  style: textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: Spacing.lg),
                for (final offer in plans) ...[
                  PlanComparisonCard(
                    offer: offer,
                    isCurrent: currentId == offer.id,
                    isOpening: _openingPlanId == offer.id,
                    onContinueInBrowser:
                        !CheckoutEnv.webCheckoutEnabled ||
                            !offer.isPurchasable ||
                            currentId == offer.id
                        ? null
                        : () => _openPurchase(offer),
                  ),
                  const SizedBox(height: Spacing.md),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}
