import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:medico/features/profile/domain/billing_period.dart';
import 'package:medico/features/profile/domain/plan_tier.dart';
import 'package:medico/features/profile/presentation/widgets/plan_purchase_sheet.dart';

void main() {
  testWidgets('purchase sheet asks for a period and coupon, then hands off', (
    tester,
  ) async {
    BillingPeriod? chosen;
    String? coupon;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PlanPurchaseSheet(
            plan: PlanTier.elite,
            onPay: (period, code) async {
              chosen = period;
              coupon = code;
              return true;
            },
          ),
        ),
      ),
    );

    expect(find.text('1 year'), findsOneWidget);
    expect(find.text('2 years + 1 month extra'), findsOneWidget);
    expect(find.text('3 years + 2 months extra'), findsOneWidget);
    expect(find.text('4 years + 3 months extra'), findsOneWidget);
    expect(find.textContaining('₹'), findsNothing);

    await tester.tap(find.text('3 years + 2 months extra'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'campus20');
    await tester.tap(find.text('Pay on website'));
    await tester.pump();

    expect(chosen, BillingPeriod.y3);
    expect(coupon, 'campus20');
  });
}
