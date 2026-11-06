import 'package:flutter_test/flutter_test.dart';

import 'package:medico/core/supabase/tables.dart';
import 'package:medico/features/profile/domain/plan_tier.dart';
import 'package:medico/features/profile/domain/user_profile.dart';

void main() {
  UserProfile profile({required PlanTier plan, DateTime? planExpiresAt}) {
    return UserProfile(
      id: 'user-1',
      plan: plan,
      planExpiresAt: planExpiresAt,
      createdAt: DateTime.utc(2026, 1, 1),
    );
  }

  test('effectivePlan stays paid when expiry is in the future', () {
    final p = profile(
      plan: PlanTier.pro,
      planExpiresAt: DateTime.now().add(const Duration(days: 1)),
    );
    expect(p.effectivePlan, PlanTier.pro);
  });

  test('effectivePlan falls back to free when expiry is in the past', () {
    final p = profile(
      plan: PlanTier.elite,
      planExpiresAt: DateTime.now().subtract(const Duration(days: 1)),
    );
    expect(p.effectivePlan, PlanTier.free);
  });

  test('effectivePlan uses stored plan when expiry is null', () {
    final p = profile(plan: PlanTier.pro);
    expect(p.effectivePlan, PlanTier.pro);
  });

  test('effectivePlan is free when plan is suspended', () {
    final p = UserProfile(
      id: 'user-1',
      plan: PlanTier.pro,
      planExpiresAt: DateTime.now().add(const Duration(days: 30)),
      planSuspendedAt: DateTime.now(),
      planSuspendReason: 'multi_device',
      createdAt: DateTime.utc(2026, 1, 1),
    );
    expect(p.isPlanSuspended, isTrue);
    expect(p.effectivePlan, PlanTier.free);
  });

  test('needsOnboarding is true until onboarding_completed_at is set', () {
    final incomplete = profile(plan: PlanTier.free);
    expect(incomplete.needsOnboarding, isTrue);

    final done = UserProfile(
      id: 'user-1',
      plan: PlanTier.pro,
      createdAt: DateTime.utc(2026, 1, 1),
      onboardingCompletedAt: DateTime.utc(2026, 8, 1),
    );
    expect(done.needsOnboarding, isFalse);
  });

  test('fromJson reads academic onboarding fields', () {
    final p = UserProfile.fromJson({
      ProfileColumns.id: 'user-1',
      ProfileColumns.plan: 'pro',
      ProfileColumns.createdAt: '2026-01-01T00:00:00Z',
      ProfileColumns.universityId: 'uni-1',
      ProfileColumns.collegeId: 'col-1',
      ProfileColumns.batchYear: 2024,
      ProfileColumns.mbbsPhaseId: 'phase-2',
      ProfileColumns.onboardingCompletedAt: '2026-08-01T00:00:00Z',
    });
    expect(p.needsOnboarding, isFalse);
    expect(p.batchYear, 2024);
    expect(p.universityId, 'uni-1');
    expect(p.isAdmin, isFalse);
  });

  test('fromJson reads the admin flag and a block', () {
    final p = UserProfile.fromJson({
      ProfileColumns.id: 'user-1',
      ProfileColumns.plan: 'pro',
      ProfileColumns.createdAt: '2026-01-01T00:00:00Z',
      ProfileColumns.isAdmin: true,
      ProfileColumns.blockedAt: '2026-11-01T00:00:00Z',
      ProfileColumns.blockedReason: 'spam',
    });
    expect(p.isAdmin, isTrue);
    expect(p.blockedAt, isNotNull);
    expect(p.blockedReason, 'spam');
  });
}
