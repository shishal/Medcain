import 'plan_tier.dart';

/// One row in the upgrade-screen comparison (included or not on that plan).
class PlanFeatureLine {
  const PlanFeatureLine(this.label, {required this.included});

  final String label;
  final bool included;
}

/// Marketing copy for Free / Pro / Elite — display only.
///
/// Access is still enforced by RLS and `plan_limits`; this list is what we
/// show on the paywall so students can compare before leaving the app.
class PlanOffering {
  const PlanOffering({
    required this.tier,
    required this.tagline,
    required this.features,
  });

  final PlanTier tier;
  final String tagline;
  final List<PlanFeatureLine> features;

  static const List<PlanOffering> comparison = [free, pro, elite];

  static const free = PlanOffering(
    tier: PlanTier.free,
    tagline: 'A sample after the trial',
    features: [
      PlanFeatureLine('Sample questions', included: true),
      PlanFeatureLine('All years and subjects', included: false),
      PlanFeatureLine('Answers on every question', included: false),
    ],
  );

  static const pro = PlanOffering(
    tier: PlanTier.pro,
    tagline: 'The full bank on one phone',
    features: [
      PlanFeatureLine('All questions, all years, all subjects', included: true),
      PlanFeatureLine('Answers included', included: true),
      PlanFeatureLine('1 registered device', included: true),
    ],
  );

  static const elite = PlanOffering(
    tier: PlanTier.elite,
    tagline: 'The same bank on two phones',
    features: [
      PlanFeatureLine('All questions, all years, all subjects', included: true),
      PlanFeatureLine('Answers included', included: true),
      PlanFeatureLine('2 registered devices', included: true),
    ],
  );
}
