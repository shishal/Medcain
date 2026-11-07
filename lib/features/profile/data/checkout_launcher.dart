import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/utils/result.dart';
import '../../../core/utils/user_facing_error.dart';
import '../../auth/data/auth_repository.dart';
import '../domain/billing_period.dart';
import '../domain/plan_tier.dart';
import 'checkout_env.dart';

part 'checkout_launcher.g.dart';

/// Opens the web checkout in the **device browser** — never an in-app
/// purchase, WebView, or payment form.
class CheckoutLauncher {
  CheckoutLauncher({
    required this.checkoutUri,
    required this.launch,
    this.resolveEmail,
  });

  final Uri? checkoutUri;
  final Future<bool> Function(Uri uri) launch;

  /// Prefill for the web login field — not a session or login token.
  ///
  /// `String? Function()?` is an optional callback: if provided, we call it
  /// and, when it returns a non-empty string, append `?email=`.
  final String? Function()? resolveEmail;

  /// Opens the website with the plan, period, and optional coupon prefilled.
  ///
  /// The page prices the order. This method does not send an amount.
  Future<Result<void>> openCheckout({
    required PlanTier plan,
    BillingPeriod period = BillingPeriod.y1,
    String? coupon,
  }) async {
    if (plan == PlanTier.free) {
      return const Failure('The Free plan does not need checkout.');
    }

    final base = checkoutUri;
    if (base == null) {
      return const Failure(
        'Checkout is not set up yet. Please try again later.',
      );
    }

    final query = {
      ...base.queryParameters,
      'plan': plan.name,
      'period': period.code,
    };
    final code = coupon?.trim();
    if (code != null && code.isNotEmpty) {
      query['code'] = code;
    }
    final email = resolveEmail?.call()?.trim();
    if (email != null && email.isNotEmpty) {
      query['email'] = email;
    }

    final uri = base.replace(queryParameters: query);

    try {
      final opened = await launch(uri);
      if (!opened) {
        return const Failure(
          'Could not open the checkout page in your browser.',
        );
      }
      return const Success(null);
    } catch (e) {
      return Failure(
        UserFacingError.from(
          e,
          fallback: 'Could not open the checkout page in your browser.',
        ),
      );
    }
  }
}

@Riverpod(keepAlive: true)
CheckoutLauncher checkoutLauncher(Ref ref) {
  return CheckoutLauncher(
    checkoutUri: CheckoutEnv.urlOrNull,
    // externalApplication = the system browser, not an in-app WebView.
    launch: (uri) => launchUrl(uri, mode: LaunchMode.externalApplication),
    resolveEmail: () => ref.read(authRepositoryProvider).currentEmail,
  );
}
