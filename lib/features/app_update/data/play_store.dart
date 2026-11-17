import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

/// This app's Play listing. Hard-coded so an admin setting cannot swap the
/// link for a different store page.
abstract final class PlayStore {
  static const applicationId = 'com.shishal.medico';

  /// Opens the Play Store app on the listing, where Update is shown when a
  /// newer build is published.
  static final Uri marketUri = Uri.parse('market://details?id=$applicationId');

  /// Same listing in the browser when the Play Store app is missing.
  static final Uri httpsUri = Uri.parse(
    'https://play.google.com/store/apps/details?id=$applicationId',
  );
}

/// Opens the Play Store listing. Tries the Play app first, then the browser.
Future<void> openPlayStoreUpdate(BuildContext context) async {
  final opened =
      await _tryLaunch(PlayStore.marketUri) ||
      await _tryLaunch(PlayStore.httpsUri);
  if (!opened && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Couldn't open the Play Store")),
    );
  }
}

Future<bool> _tryLaunch(Uri uri) async {
  try {
    return await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    return false;
  }
}
