import 'package:flutter_test/flutter_test.dart';

import 'package:medico/core/utils/result.dart';
import 'package:medico/features/profile/data/checkout_launcher.dart';
import 'package:medico/features/profile/domain/billing_period.dart';
import 'package:medico/features/profile/domain/plan_tier.dart';

void main() {
  test('openCheckout appends the plan query param', () async {
    late Uri launched;
    final launcher = CheckoutLauncher(
      checkoutUri: Uri.parse('https://checkout.test/pay'),
      launch: (uri) async {
        launched = uri;
        return true;
      },
    );

    final result = await launcher.openCheckout(plan: PlanTier.elite);

    expect(result, isA<Success<void>>());
    expect(launched.scheme, 'https');
    expect(launched.host, 'checkout.test');
    expect(launched.queryParameters['plan'], 'elite');
    expect(launched.queryParameters['period'], 'y1');
  });

  test('openCheckout keeps existing query params', () async {
    late Uri launched;
    final launcher = CheckoutLauncher(
      checkoutUri: Uri.parse('https://checkout.test/pay?src=app'),
      launch: (uri) async {
        launched = uri;
        return true;
      },
    );

    await launcher.openCheckout(plan: PlanTier.pro);

    expect(launched.queryParameters['src'], 'app');
    expect(launched.queryParameters['plan'], 'pro');
    expect(launched.queryParameters.containsKey('phone'), isFalse);
  });

  test('openCheckout appends phone as a prefill query param', () async {
    late Uri launched;
    final launcher = CheckoutLauncher(
      checkoutUri: Uri.parse('https://checkout.test/pay'),
      resolvePhone: () => '  +919876543210  ',
      launch: (uri) async {
        launched = uri;
        return true;
      },
    );

    await launcher.openCheckout(plan: PlanTier.pro);

    expect(launched.queryParameters['plan'], 'pro');
    expect(launched.queryParameters['phone'], '+919876543210');
    expect(launched.queryParameters['period'], 'y1');
  });

  test('openCheckout passes the period and coupon', () async {
    late Uri launched;
    final launcher = CheckoutLauncher(
      checkoutUri: Uri.parse('https://checkout.test/pay'),
      launch: (uri) async {
        launched = uri;
        return true;
      },
    );

    await launcher.openCheckout(
      plan: PlanTier.pro,
      period: BillingPeriod.y3,
      coupon: '  campus20  ',
    );

    expect(launched.queryParameters['plan'], 'pro');
    expect(launched.queryParameters['period'], 'y3');
    expect(launched.queryParameters['code'], 'campus20');
  });

  test('openCheckout refuses the free plan', () async {
    var launched = false;
    final launcher = CheckoutLauncher(
      checkoutUri: Uri.parse('https://checkout.test/pay'),
      launch: (_) async {
        launched = true;
        return true;
      },
    );

    final result = await launcher.openCheckout(plan: PlanTier.free);

    expect(launched, isFalse);
    expect(result, isA<Failure<void>>());
  });

  test('openCheckout fails when the URL is not configured', () async {
    final launcher = CheckoutLauncher(
      checkoutUri: null,
      launch: (_) async => true,
    );

    final result = await launcher.openCheckout(plan: PlanTier.pro);

    expect(result, isA<Failure<void>>());
    expect((result as Failure).message, contains('not set up'));
  });

  test('openCheckout fails when the browser cannot be opened', () async {
    final launcher = CheckoutLauncher(
      checkoutUri: Uri.parse('https://checkout.test/pay'),
      launch: (_) async => false,
    );

    final result = await launcher.openCheckout(plan: PlanTier.pro);

    expect(result, isA<Failure<void>>());
  });
}
