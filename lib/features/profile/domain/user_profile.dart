import '../../../core/supabase/tables.dart';
import 'plan_tier.dart';

/// Row from the `profiles` table for the logged-in user.
class UserProfile {
  const UserProfile({
    required this.id,
    this.fullName,
    this.phone,
    required this.plan,
    this.planStartedAt,
    this.planExpiresAt,
    this.planSuspendedAt,
    this.planSuspendReason,
    required this.createdAt,
    this.universityId,
    this.collegeId,
    this.batchYear,
    this.mbbsPhaseId,
    this.onboardingCompletedAt,
    this.isAdmin = false,
    this.blockedAt,
    this.blockedReason,
  });

  final String id;
  final String? fullName;
  final String? phone;

  /// Plan stored on the row — may still say `pro`/`elite` after expiry.
  final PlanTier plan;
  final DateTime? planStartedAt;
  final DateTime? planExpiresAt;

  /// When set, [effectivePlan] is free until support clears suspension.
  final DateTime? planSuspendedAt;
  final String? planSuspendReason;
  final DateTime createdAt;
  final String? universityId;
  final String? collegeId;
  final int? batchYear;
  final String? mbbsPhaseId;
  final DateTime? onboardingCompletedAt;

  /// Operator flag. Only the SQL editor can set this; the app only reads it.
  final bool isAdmin;

  /// Set when an admin blocks the account. Distinct from a device suspension.
  final DateTime? blockedAt;
  final String? blockedReason;

  bool get needsOnboarding => onboardingCompletedAt == null;

  bool get isPlanSuspended => planSuspendedAt != null;

  /// Effective plan for UI (lock icons, upgrade prompts).
  ///
  /// Mirrors Postgres `current_plan()`: suspended or expired → free. RLS still
  /// enforces access server-side; this is only for display decisions.
  PlanTier get effectivePlan {
    if (isPlanSuspended) return PlanTier.free;
    final expiresAt = planExpiresAt;
    if (expiresAt != null && expiresAt.isBefore(DateTime.now())) {
      return PlanTier.free;
    }
    return plan;
  }

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: json[ProfileColumns.id] as String,
      fullName: json[ProfileColumns.fullName] as String?,
      phone: json[ProfileColumns.phone] as String?,
      plan: PlanTier.fromString(json[ProfileColumns.plan] as String),
      planStartedAt: _parseDate(json[ProfileColumns.planStartedAt]),
      planExpiresAt: _parseDate(json[ProfileColumns.planExpiresAt]),
      planSuspendedAt: _parseDate(json[ProfileColumns.planSuspendedAt]),
      planSuspendReason: json[ProfileColumns.planSuspendReason] as String?,
      createdAt: _parseDate(json[ProfileColumns.createdAt]) ?? DateTime.now(),
      universityId: json[ProfileColumns.universityId] as String?,
      collegeId: json[ProfileColumns.collegeId] as String?,
      batchYear: _asInt(json[ProfileColumns.batchYear]),
      mbbsPhaseId: json[ProfileColumns.mbbsPhaseId] as String?,
      onboardingCompletedAt: _parseDate(
        json[ProfileColumns.onboardingCompletedAt],
      ),
      isAdmin: json[ProfileColumns.isAdmin] == true,
      blockedAt: _parseDate(json[ProfileColumns.blockedAt]),
      blockedReason: json[ProfileColumns.blockedReason] as String?,
    );
  }

  static int? _asInt(Object? value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString());
  }

  static DateTime? _parseDate(Object? value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    return DateTime.tryParse(value as String);
  }
}
