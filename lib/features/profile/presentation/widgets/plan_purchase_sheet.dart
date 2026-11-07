import 'package:flutter/material.dart';

import '../../../../core/theme/spacing.dart';
import '../../domain/billing_period.dart';
import '../../domain/plan_tier.dart';

/// Period and coupon, then a handoff to the website. No price and no card
/// form — Razorpay runs on the checkout page.
class PlanPurchaseSheet extends StatefulWidget {
  const PlanPurchaseSheet({
    super.key,
    required this.plan,
    required this.onPay,
  });

  final PlanTier plan;

  /// Returns true when the browser opened. The sheet closes itself then.
  final Future<bool> Function(BillingPeriod period, String coupon) onPay;

  @override
  State<PlanPurchaseSheet> createState() => _PlanPurchaseSheetState();
}

class _PlanPurchaseSheetState extends State<PlanPurchaseSheet> {
  BillingPeriod _period = BillingPeriod.y1;
  final _coupon = TextEditingController();
  var _opening = false;

  @override
  void dispose() {
    _coupon.dispose();
    super.dispose();
  }

  Future<void> _pay() async {
    setState(() => _opening = true);
    final opened = await widget.onPay(_period, _coupon.text);
    if (!mounted) return;
    setState(() => _opening = false);
    if (opened) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final bottom = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        Spacing.lg,
        Spacing.sm,
        Spacing.lg,
        Spacing.lg + bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Purchase ${widget.plan.label}', style: textTheme.titleLarge),
          const SizedBox(height: Spacing.xs),
          Text(
            'Choose how long, then pay on the website. A coupon takes a percent off that price.',
            style: textTheme.bodyMedium,
          ),
          const SizedBox(height: Spacing.md),
          RadioGroup<BillingPeriod>(
            groupValue: _period,
            onChanged: _opening
                ? (_) {}
                : (value) {
                    if (value == null) return;
                    setState(() => _period = value);
                  },
            child: Column(
              children: [
                for (final period in BillingPeriod.values)
                  RadioListTile<BillingPeriod>(
                    value: period,
                    title: Text(period.label),
                    contentPadding: EdgeInsets.zero,
                  ),
              ],
            ),
          ),
          const SizedBox(height: Spacing.sm),
          TextField(
            controller: _coupon,
            enabled: !_opening,
            textCapitalization: TextCapitalization.characters,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'Discount coupon',
              hintText: 'Optional',
            ),
          ),
          const SizedBox(height: Spacing.md),
          FilledButton(
            onPressed: _opening ? null : _pay,
            child: _opening
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Pay on website'),
          ),
        ],
      ),
    );
  }
}
