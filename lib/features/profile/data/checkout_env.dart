import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Where "Pay on website" opens the device browser.
///
/// Razorpay runs on this page. The app never shows a card form.
/// `CHECKOUT_URL` in `.env` can point at a local page (`checkout/serve.py`).
/// If that variable is missing, or it still points at the old Google Sites
/// placeholder, the live checkout is used instead.
abstract final class CheckoutEnv {
  /// Live page: WhatsApp sign-in, then Razorpay.
  static final Uri production = Uri.parse(
    'https://medcain.shishal.com/checkout',
  );

  /// When false, the Plans screen hides Purchase so a store binary has no
  /// payment path. True opens the website checkout. The app still does not
  /// charge a card.
  static const webCheckoutEnabled = true;

  static Uri get url {
    try {
      return resolve(dotenv.env['CHECKOUT_URL']);
    } catch (_) {
      // dotenv not loaded (tests, or app started without .env).
      return production;
    }
  }

  /// Picks the page the Pay button should open.
  ///
  /// [value] is the raw `CHECKOUT_URL` string. An empty or placeholder value
  /// means "use production". `sites.google.com` is the old stand-in site and
  /// is never a checkout.
  static Uri resolve(String? value) {
    if (value == null ||
        value.isEmpty ||
        value.contains('YOUR_CHECKOUT_HOST')) {
      return production;
    }
    final uri = Uri.tryParse(value);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      return production;
    }
    final host = uri.host.toLowerCase();
    if (host == 'sites.google.com' || host.endsWith('.sites.google.com')) {
      return production;
    }
    return uri;
  }
}
