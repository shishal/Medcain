import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../../core/theme/spacing.dart';
import '../../../core/widgets/brand_wordmark.dart';
import '../data/play_store.dart';

/// Full-screen lock shown instead of the app when this build is too old.
class ForceUpdateScreen extends StatelessWidget {
  const ForceUpdateScreen({
    this.requiredVersionName = '',
    this.onUpdate,
    super.key,
  });

  /// Label the admin saved, such as `1.1.26`. Empty hides that sentence.
  final String requiredVersionName;

  /// Null opens the Play Store listing. Tests pass a callback.
  final Future<void> Function(BuildContext context)? onUpdate;

  static const title = 'Update required';

  static const body =
      'MEDCAIN needs an update before you can continue.\n\n'
      'Install the latest version from the Play Store, then open the app again.';

  static const buttonLabel = 'Update on Play Store';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final version = requiredVersionName.trim();

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(Spacing.lg),
          children: [
            const SizedBox(height: Spacing.xl),
            const BrandWordmark(
              alignment: MainAxisAlignment.center,
              markSize: 40,
            ),
            const SizedBox(height: Spacing.xl),
            Center(
              child: Icon(
                Icons.system_update,
                size: 48,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: Spacing.md),
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: Spacing.md),
            Text(
              body,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge?.copyWith(color: muted),
            ),
            if (version.isNotEmpty) ...[
              const SizedBox(height: Spacing.md),
              Text(
                'Version $version or newer.',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium,
              ),
            ],
            const SizedBox(height: Spacing.xl),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () {
                  final action = onUpdate ?? openPlayStoreUpdate;
                  unawaited(action(context));
                },
                child: const Text(buttonLabel),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
