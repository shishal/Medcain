/// Prepaid window chosen before the app opens the website checkout.
///
/// Codes match `paid_plan_catalog.period`. The extra months on the longer
/// options are free time on top of the years paid for. The rupee amount is
/// not stored here — Postgres prices the order.
enum BillingPeriod {
  y1(code: 'y1', label: '1 year'),
  y2(code: 'y2', label: '2 years + 1 month extra'),
  y3(code: 'y3', label: '3 years + 2 months extra'),
  y4(code: 'y4', label: '4 years + 3 months extra');

  const BillingPeriod({required this.code, required this.label});

  final String code;
  final String label;

  static BillingPeriod fromCode(String? value) {
    return switch (value) {
      'y2' => BillingPeriod.y2,
      'y3' => BillingPeriod.y3,
      'y4' => BillingPeriod.y4,
      _ => BillingPeriod.y1,
    };
  }
}
