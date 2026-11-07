/// Matches the Postgres `plan_tier` enum (free / pro / elite).
enum PlanTier {
  free,
  pro,
  elite;

  static PlanTier fromString(String value) {
    return switch (value.toLowerCase()) {
      'pro' => PlanTier.pro,
      'elite' => PlanTier.elite,
      _ => PlanTier.free,
    };
  }

  /// Same as Postgres `plan_rank()`. Pro and Elite unlock the same bank,
  /// so they share a rank. Device slots are separate from this number.
  int get rank => switch (this) {
        PlanTier.free => 0,
        PlanTier.pro => 1,
        PlanTier.elite => 1,
      };

  /// Whether this plan can open content that requires [required].
  bool covers(PlanTier required) => rank >= required.rank;

  /// Short label for UI (lock badges, profile header, etc.).
  String get label => switch (this) {
        PlanTier.free => 'Free',
        PlanTier.pro => 'Pro',
        PlanTier.elite => 'Elite',
      };
}
