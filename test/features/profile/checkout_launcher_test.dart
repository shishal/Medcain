import 'package:flutter_test/flutter_test.dart';

import 'package:medico/core/utils/result.dart';
import 'package:medico/features/profile/data/checkout_launcher.dart';

void main() {
  const planId = '11111111-1111-1111-1111-111111111111';

  test('openCheckout appends the plan id', () async {
    late Uri launched;
    final launcher = CheckoutLauncher(
      checkoutUri: Uri.parse('https://checkout.test/pay'),
      launch: (uri) async {
        launched = uri;
        return true;
      },
    );

    final result = await launcher.openCheckout(planId: planId);

    expect(result, isA<Success<void>>());
    expect(launched.scheme, 'https');
    expect(launched.host, 'checkout.test');
    expect(launched.queryParameters['plan'], planId);
    expect(launched.queryParameters.containsKey('period'), isFalse);
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

    await launcher.openCheckout(planId: planId);

    expect(launched.queryParameters['src'], 'app');
    expect(launched.queryParameters['plan'], planId);
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

    await launcher.openCheckout(planId: planId);

    expect(launched.queryParameters['plan'], planId);
    expect(launched.queryParameters['phone'], '+919876543210');
  });

  test('openCheckout passes the coupon', () async {
    late Uri launched;
    final launcher = CheckoutLauncher(
      checkoutUri: Uri.parse('https://checkout.test/pay'),
      launch: (uri) async {
        launched = uri;
        return true;
      },
    );

    await launcher.openCheckout(planId: planId, coupon: '  campus20  ');

    expect(launched.queryParameters['plan'], planId);
    expect(launched.queryParameters['code'], 'campus20');
    expect(launched.queryParameters.containsKey('period'), isFalse);
  });

  test('openCheckout refuses a blank plan id', () async {
    var launched = false;
    final launcher = CheckoutLauncher(
      checkoutUri: Uri.parse('https://checkout.test/pay'),
      launch: (_) async {
        launched = true;
        return true;
      },
    );

    final result = await launcher.openCheckout(planId: '  ');

    expect(launched, isFalse);
    expect(result, isA<Failure<void>>());
  });

  test('openCheckout fails when the URL is not configured', () async {
    final launcher = CheckoutLauncher(
      checkoutUri: null,
      launch: (_) async => true,
    );

    final result = await launcher.openCheckout(planId: planId);

    expect(result, isA<Failure<void>>());
    expect((result as Failure).message, contains('not set up'));
  });

  test('openCheckout fails when the browser cannot be opened', () async {
    final launcher = CheckoutLauncher(
      checkoutUri: Uri.parse('https://checkout.test/pay'),
      launch: (_) async => false,
    );

    final result = await launcher.openCheckout(planId: planId);

    expect(result, isA<Failure<void>>());
  });
}
