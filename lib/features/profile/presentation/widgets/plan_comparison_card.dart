import 'package:flutter/material.dart';

import '../../../../core/theme/spacing.dart';
import '../../domain/plan_offer.dart';

/// One plan on the upgrade screen. Checkout CTAs live here as
/// "Purchase …" — the charge happens in the browser, not in the app.
class PlanComparisonCard extends StatelessWidget {
  const PlanComparisonCard({
    super.key,
    required this.offer,
    required this.isCurrent,
    this.onContinueInBrowser,
    this.isOpening = false,
  });

  final PlanOffer offer;
  final bool isCurrent;

  /// Null when this plan is not for sale, or it is already current.
  final VoidCallback? onContinueInBrowser;
  final bool isOpening;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final promo = offer.promoLine;

    return Card(
      color: isCurrent
          ? colorScheme.primaryContainer.withValues(alpha: 0.35)
          : null,
      child: Padding(
        padding: const EdgeInsets.all(Spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: Text(offer.name, style: textTheme.titleLarge)),
                if (offer.amountPaise > 0)
                  Text(offer.priceLabel, style: textTheme.titleMedium),
                if (isCurrent) ...[
                  const SizedBox(width: Spacing.sm),
                  const Chip(
                    label: Text('Current'),
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                  ),
                ],
              ],
            ),
            const SizedBox(height: Spacing.xs),
            Text(
              [
                if ((offer.tagline ?? '').trim().isNotEmpty) offer.tagline!.trim(),
                if (offer.isPurchasable) offer.durationText,
              ].join(' · '),
              style: textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            if (promo != null) ...[
              const SizedBox(height: Spacing.sm),
              Text(promo, style: textTheme.titleSmall),
            ],
            const SizedBox(height: Spacing.md),
            for (final feature in offer.benefits)
              Padding(
                padding: const EdgeInsets.only(bottom: Spacing.sm),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.check, size: 20, color: colorScheme.primary),
                    const SizedBox(width: Spacing.sm),
                    Expanded(child: Text(feature, style: textTheme.bodyMedium)),
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
                    : Text('Purchase ${offer.name}'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
