import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens [url] in the device browser and tells the student when it fails.
///
/// Only `https` (plus `mailto` for support links) is allowed so an imported
/// or markdown link cannot invoke `javascript:`, `file:`, `intent:`, or other
/// arbitrary OS URI schemes.
Future<void> openExternalLink(BuildContext context, String url) async {
  final uri = Uri.tryParse(url.trim());
  final scheme = uri?.scheme.toLowerCase();
  final safeScheme =
      uri != null &&
      ((scheme == 'https' && uri.host.isNotEmpty) ||
          (scheme == 'mailto' && uri.path.isNotEmpty));
  final opened = safeScheme
      ? await launchUrl(uri, mode: LaunchMode.externalApplication)
      : false;

  // `context.mounted` matters because we awaited: the screen may be gone.
  if (!opened && context.mounted) {
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text("Couldn't open that link")));
  }
}
