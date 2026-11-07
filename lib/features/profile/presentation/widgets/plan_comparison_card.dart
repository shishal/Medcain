import 'package:flutter/material.dart';

import '../../../../core/theme/spacing.dart';
import '../../domain/plan_offering.dart';

/// One plan column on the upgrade screen. Checkout CTAs live here as
/// "Continue in browser" — never a Buy/price action inside the app.
class PlanComparisonCard extends StatelessWidget {
  const PlanComparisonCard({
    super.key,
    required this.offering,
    required this.isCurrent,
    required this.isRequired,
    this.onContinueInBrowser,
    this.isOpening = false,
  });

  final PlanOffering offering;
  final bool isCurrent;
  final bool isRequired;

  /// Null on Free, or when this card is already the user's current plan.
  final VoidCallback? onContinueInBrowser;
  final bool isOpening;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final highlighted = isRequired || isCurrent;

    return Card(
      color: highlighted
          ? colorScheme.primaryContainer.withValues(alpha: 0.35)
          : null,
      child: Padding(
        padding: const EdgeInsets.all(Spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(offering.tier.label, style: textTheme.titleLarge),
                ),
                if (isCurrent)
                  Chip(
                    label: const Text('Current'),
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                  ),
                if (isRequired && !isCurrent)
                  Chip(
                    label: const Text('Needed'),
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    backgroundColor: colorScheme.primaryContainer,
                  ),
              ],
            ),
            const SizedBox(height: Spacing.xs),
            Text(
              offering.tagline,
              style: textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: Spacing.md),
            for (final feature in offering.features)
              Padding(
                padding: const EdgeInsets.only(bottom: Spacing.sm),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      feature.included ? Icons.check : Icons.close,
                      size: 20,
                      color: feature.included
                          ? colorScheme.primary
                          : colorScheme.outline,
                    ),
                    const SizedBox(width: Spacing.sm),
                    Expanded(
                      child: Text(
                        feature.label,
                        style: textTheme.bodyMedium?.copyWith(
                          color: feature.included
                              ? null
                              : colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            if (onContinueInBrowser != null) ...[
              const SizedBox(height: Spacing.sm),
              FilledButton(
                onPressed: isOpening ? null : onContinueInBrowser,
                child: isOpening
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text('Purchase ${offering.tier.label}'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
