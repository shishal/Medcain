import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Reads the external checkout URL from `.env` (see `.env.example`).
///
/// Missing or placeholder values return null so the upgrade screen can explain
/// instead of crashing. The page itself lives in `checkout/` (Phase 7.2).
abstract final class CheckoutEnv {
  /// When false, the Plans screen hides Purchase so a store binary has no
  /// payment path. True opens the website checkout. The app still does not
  /// charge a card.
  static const webCheckoutEnabled = true;

  static Uri? get urlOrNull {
    try {
      final value = dotenv.env['CHECKOUT_URL'];
      if (value == null ||
          value.isEmpty ||
          value.contains('YOUR_CHECKOUT_HOST')) {
        return null;
      }
      final uri = Uri.tryParse(value);
      if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
        return null;
      }
      return uri;
    } catch (_) {
      // dotenv not loaded (tests, or app started without .env).
      return null;
    }
  }
}
