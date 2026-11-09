import 'package:flutter_test/flutter_test.dart';

import 'package:medico/features/profile/data/checkout_env.dart';

void main() {
  test('missing checkout URL opens the live Razorpay page', () {
    expect(CheckoutEnv.resolve(null), CheckoutEnv.production);
    expect(CheckoutEnv.resolve(''), CheckoutEnv.production);
    expect(
      CheckoutEnv.resolve('https://YOUR_CHECKOUT_HOST/pay'),
      CheckoutEnv.production,
    );
  });

  test('a Google Sites URL is not used as checkout', () {
    final uri = CheckoutEnv.resolve(
      'https://sites.google.com/view/medcain/pay?plan=pro',
    );

    expect(uri, CheckoutEnv.production);
    expect(uri.host, 'medcain.shishal.com');
    expect(uri.path, '/checkout');
  });

  test('an explicit checkout URL is kept, including local dev', () {
    expect(
      CheckoutEnv.resolve('https://medcain.shishal.com/checkout'),
      CheckoutEnv.production,
    );
    expect(
      CheckoutEnv.resolve('http://127.0.0.1:4173').host,
      '127.0.0.1',
    );
  });
}
