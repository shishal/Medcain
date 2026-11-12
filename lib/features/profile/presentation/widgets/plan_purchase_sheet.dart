import 'package:material_ui/material_ui.dart';

import '../../../../core/theme/spacing.dart';
import '../../domain/plan_offer.dart';

/// Coupon, then a handoff to the website. No card form — Razorpay runs there.
class PlanPurchaseSheet extends StatefulWidget {
  const PlanPurchaseSheet({
    super.key,
    required this.plan,
    required this.onPay,
  });

  final PlanOffer plan;

  /// Returns true when the browser opened. The sheet closes itself then.
  final Future<bool> Function(String coupon) onPay;

  @override
  State<PlanPurchaseSheet> createState() => _PlanPurchaseSheetState();
}

class _PlanPurchaseSheetState extends State<PlanPurchaseSheet> {
  late final TextEditingController _coupon;
  var _opening = false;

  @override
  void initState() {
    super.initState();
    _coupon = TextEditingController(
      text: widget.plan.featuredDiscountCode ?? '',
    );
  }

  @override
  void dispose() {
    _coupon.dispose();
    super.dispose();
  }

  Future<void> _pay() async {
    setState(() => _opening = true);
    final opened = await widget.onPay(_coupon.text);
    if (!mounted) return;
    setState(() => _opening = false);
    if (opened) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    final promo = widget.plan.promoLine;

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
          Text('Purchase ${widget.plan.name}', style: textTheme.titleLarge),
          const SizedBox(height: Spacing.xs),
          Text(
            '${widget.plan.priceLabel} · ${widget.plan.durationText}. '
            'You pay on the website. A coupon takes a percent off that price.',
            style: textTheme.bodyMedium,
          ),
          if (promo != null) ...[
            const SizedBox(height: Spacing.sm),
            Text(promo, style: textTheme.titleSmall),
          ],
          const SizedBox(height: Spacing.md),
          TextField(
            controller: _coupon,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(
              labelText: 'Discount coupon',
              hintText: 'Optional',
            ),
          ),
          const SizedBox(height: Spacing.lg),
          FilledButton(
            onPressed: _opening ? null : _pay,
            child: Text(_opening ? 'Opening…' : 'Continue in browser'),
          ),
        ],
      ),
    );
  }
}
