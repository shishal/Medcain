import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:medico/features/profile/domain/plan_offer.dart';
import 'package:medico/features/profile/presentation/widgets/plan_purchase_sheet.dart';

void main() {
  testWidgets('purchase sheet shows the plan price and hands off the coupon', (
    tester,
  ) async {
    String? coupon;
    const plan = PlanOffer(
      id: 'elite-id',
      code: 'elite',
      name: 'Elite',
      benefits: ['Two phones'],
      amountPaise: 299900,
      durationMonths: 12,
      durationLabel: '1 year',
      maxRegisteredDevices: 2,
      promoHeadline: 'Early bird',
      promoDetail: 'Use Early30',
      featuredDiscountCode: 'EARLY30',
      isPublic: true,
      isActive: true,
      sortOrder: 2,
      contentDepth: 'explanation',
      accessMode: 'filtered',
      allowPractice: true,
      allowTutorMode: true,
      allowExamMode: true,
      allowTimerToggle: true,
      allowTagFilter: true,
      allowDifficultyFilter: true,
      allowNegativeMarkingToggle: true,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PlanPurchaseSheet(
            plan: plan,
            onPay: (code) async {
              coupon = code;
              return true;
            },
          ),
        ),
      ),
    );

    expect(find.text('Purchase Elite'), findsOneWidget);
    expect(find.textContaining('₹2999'), findsOneWidget);
    expect(find.textContaining('1 year'), findsOneWidget);
    expect(find.textContaining('Early bird'), findsOneWidget);
    expect(find.text('1 year'), findsNothing);
    expect(find.text('3 years + 2 months extra'), findsNothing);

    await tester.enterText(find.byType(TextField), 'campus20');
    await tester.tap(find.text('Continue in browser'));
    await tester.pump();

    expect(coupon, 'campus20');
  });
}
