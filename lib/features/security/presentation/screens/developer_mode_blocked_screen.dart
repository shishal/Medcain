import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/spacing.dart';
import '../../../../core/widgets/brand_wordmark.dart';
import '../../data/developer_mode_monitor.dart';

/// Full-screen lock shown instead of the app while Developer options are on.
class DeveloperModeBlockedScreen extends ConsumerWidget {
  const DeveloperModeBlockedScreen({super.key});

  static const title = 'Developer options are on';

  static const body =
      'MEDCAIN stays closed while Developer options or USB debugging '
      'is enabled. A computer can capture the screen that way, even '
      'when screenshots are blocked.\n\n'
      'Turn Developer options off, then come back. The app unlocks on its own.';

  static const openSettingsLabel = 'Open Developer options';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;

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
                Icons.developer_mode,
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
            const SizedBox(height: Spacing.xl),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () {
                  unawaited(
                    ref.read(developerModeMonitorProvider).openSettings(),
                  );
                },
                child: const Text(openSettingsLabel),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
