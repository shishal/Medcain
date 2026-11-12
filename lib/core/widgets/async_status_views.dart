import 'package:material_ui/material_ui.dart';

import '../theme/spacing.dart';
import '../utils/user_facing_error.dart';
import 'brand_pulse_loader.dart';

/// Full-screen spinner for [AsyncValue.loading].
class AsyncLoadingView extends StatelessWidget {
  const AsyncLoadingView({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: BrandPulseLoader(color: Theme.of(context).colorScheme.primary),
    );
  }
}

/// Full-screen (or compact) failure with an optional primary + secondary action.
class AsyncErrorView extends StatelessWidget {
  const AsyncErrorView({
    super.key,
    required this.message,
    this.icon,
    this.actionLabel = 'Retry',
    this.onAction,
    this.secondaryLabel,
    this.onSecondary,
    this.compact = false,
  });

  final String message;
  final IconData? icon;
  final String actionLabel;
  final VoidCallback? onAction;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  /// Drop the large icon — for a banner inside an otherwise-usable screen.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final resolvedIcon =
        icon ??
        (UserFacingError.looksOffline(message)
            ? Icons.cloud_off_outlined
            : Icons.error_outline);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Spacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!compact) ...[
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: colorScheme.primary.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(resolvedIcon, size: 34, color: colorScheme.primary),
              ),
              const SizedBox(height: Spacing.md),
            ],
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            if (onAction != null) ...[
              const SizedBox(height: Spacing.md),
              FilledButton(onPressed: onAction, child: Text(actionLabel)),
            ],
            if (onSecondary != null && secondaryLabel != null)
              TextButton(onPressed: onSecondary, child: Text(secondaryLabel!)),
          ],
        ),
      ),
    );
  }
}

/// Successful fetch that has nothing to show (empty catalog, no bookmarks).
class AsyncEmptyView extends StatelessWidget {
  const AsyncEmptyView({
    super.key,
    required this.message,
    this.icon = Icons.inbox_outlined,
    this.actionLabel,
    this.onAction,
  });

  final String message;
  final IconData icon;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Spacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: colorScheme.primary.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 34, color: colorScheme.primary),
            ),
            const SizedBox(height: Spacing.md),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge
                  ?.copyWith(color: colorScheme.onSurfaceVariant),
            ),
            if (onAction != null && actionLabel != null) ...[
              const SizedBox(height: Spacing.md),
              FilledButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}

/// Error line inside a screen that should stay navigable while offline.
class InlineErrorMessage extends StatelessWidget {
  const InlineErrorMessage({super.key, required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          message,
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(color: Theme.of(context).colorScheme.error),
        ),
        if (onRetry != null)
          TextButton(onPressed: onRetry, child: const Text('Retry')),
      ],
    );
  }
}
