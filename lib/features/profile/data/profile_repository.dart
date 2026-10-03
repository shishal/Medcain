import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_provider.dart';
import '../../../core/supabase/tables.dart';
import '../../../core/utils/result.dart';
import '../../../core/utils/user_facing_error.dart';
import '../domain/plan_tier.dart';
import '../domain/referral_code.dart';
import '../domain/user_profile.dart';

part 'profile_repository.g.dart';

/// Loads the signed-in user's profile. Presentation never calls Supabase
/// directly — screens go through this repository (and the plan providers).
class ProfileRepository {
  ProfileRepository(this._client);

  final SupabaseClient _client;

  /// Own `profiles` row (RLS: `auth.uid() = id`).
  Future<Result<UserProfile>> fetchOwnProfile() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      return const Failure('Not signed in.');
    }

    try {
      final row = await _client
          .from(Tables.profiles)
          .select()
          .eq(ProfileColumns.id, userId)
          .single();

      return Success(UserProfile.fromJson(row));
    } catch (e) {
      return Failure(
        UserFacingError.from(
          e,
          fallback: 'Could not load your profile. Please try again.',
        ),
      );
    }
  }

  /// Server-side effective plan via `current_plan()` — same function RLS uses.
  ///
  /// Prefer [UserProfile.effectivePlan] for routine UI reads after a profile
  /// fetch; use this when you want to re-check against Postgres `now()`.
  Future<Result<PlanTier>> fetchCurrentPlanRpc() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      return const Failure('Not signed in.');
    }

    try {
      final raw = await _client.rpc(
        RpcFunctions.currentPlan,
        params: {CurrentPlanParams.userId: userId},
      );

      if (raw is! String) {
        return const Failure('Could not load your plan. Please try again.');
      }

      return Success(PlanTier.fromString(raw));
    } catch (e) {
      return Failure(
        UserFacingError.from(
          e,
          fallback: 'Could not load your plan. Please try again.',
        ),
      );
    }
  }

  Future<Result<UserProfile>> saveOnboarding({
    required String fullName,
    required String universityId,
    required String collegeId,
    required int batchYear,
    required String mbbsPhaseId,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      return const Failure('Not signed in.');
    }

    try {
      final row = await _client
          .from(Tables.profiles)
          .update({
            ProfileColumns.fullName: fullName,
            ProfileColumns.universityId: universityId,
            ProfileColumns.collegeId: collegeId,
            ProfileColumns.batchYear: batchYear,
            ProfileColumns.mbbsPhaseId: mbbsPhaseId,
            ProfileColumns.onboardingCompletedAt: DateTime.now()
                .toUtc()
                .toIso8601String(),
          })
          .eq(ProfileColumns.id, userId)
          .select()
          .single();
      return Success(UserProfile.fromJson(row));
    } catch (e) {
      return Failure(
        UserFacingError.from(
          e,
          fallback: 'Could not save your profile. Please try again.',
        ),
      );
    }
  }

  /// The signed-in student's own shareable code, if one has been issued.
  ///
  /// RLS only returns rows whose `owner_user_id` is this user. A missing row
  /// means they have nothing to share yet — that is not an error.
  Future<Result<ReferralCode?>> fetchOwnReferralCode() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      return const Failure('Not signed in.');
    }

    try {
      final row = await _client
          .from(Tables.discountCodes)
          .select(
            '${DiscountCodeColumns.code}, ${DiscountCodeColumns.percentOff}',
          )
          .eq(DiscountCodeColumns.ownerUserId, userId)
          .eq(DiscountCodeColumns.active, true)
          .maybeSingle();

      if (row == null) return const Success(null);

      final code = row[DiscountCodeColumns.code];
      final percent = row[DiscountCodeColumns.percentOff];
      if (code is! String || percent is! num) {
        return const Failure('Could not load your referral code.');
      }

      return Success(
        ReferralCode(code: code, percentOff: percent.toInt()),
      );
    } catch (e) {
      return Failure(
        UserFacingError.from(
          e,
          fallback: 'Could not load your referral code. Please try again.',
        ),
      );
    }
  }

  /// Change name / university / year / college / batch after onboarding.
  Future<Result<UserProfile>> updateAcademic({
    String? fullName,
    required String universityId,
    String? collegeId,
    required int batchYear,
    required String mbbsPhaseId,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      return const Failure('Not signed in.');
    }

    try {
      final row = await _client
          .from(Tables.profiles)
          .update({
            ProfileColumns.fullName: ?fullName,
            ProfileColumns.universityId: universityId,
            ProfileColumns.collegeId: collegeId,
            ProfileColumns.batchYear: batchYear,
            ProfileColumns.mbbsPhaseId: mbbsPhaseId,
          })
          .eq(ProfileColumns.id, userId)
          .select()
          .single();
      return Success(UserProfile.fromJson(row));
    } catch (e) {
      return Failure(
        UserFacingError.from(
          e,
          fallback: 'Could not update your course. Please try again.',
        ),
      );
    }
  }
}

@Riverpod(keepAlive: true)
ProfileRepository profileRepository(Ref ref) {
  return ProfileRepository(ref.watch(supabaseClientProvider));
}
