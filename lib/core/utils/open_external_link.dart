import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens [url] in the device browser and tells the student when it fails.
///
/// Resource URLs come from the content sheet, so a typo is a realistic input.
/// The call sites used to `return` on an unparseable URL and ignore whatever
/// [launchUrl] reported, which made the tap look like a dead button.
Future<void> openExternalLink(BuildContext context, String url) async {
  final uri = Uri.tryParse(url);
  final opened = uri == null
      ? false
      : await launchUrl(uri, mode: LaunchMode.externalApplication);

  // `context.mounted` matters because we awaited: the screen may be gone.
  if (!opened && context.mounted) {
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text("Couldn't open that link")));
  }
}
