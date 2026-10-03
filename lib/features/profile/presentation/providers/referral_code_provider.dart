import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../core/utils/result.dart';
import '../../../auth/presentation/providers/auth_session_provider.dart';
import '../../data/profile_repository.dart';
import '../../domain/referral_code.dart';

part 'referral_code_provider.g.dart';

/// Shareable code for the signed-in student. Null when none has been issued.
///
/// `keepAlive` matches the profile provider so the code stays put while they
/// move between Profile and Plans. Call sites should invalidate this after
/// a refresh.
@Riverpod(keepAlive: true)
Future<ReferralCode?> ownReferralCode(Ref ref) async {
  final signedIn = ref.watch(authSessionProvider);
  if (!signedIn) return null;

  final result = await ref.watch(profileRepositoryProvider).fetchOwnReferralCode();
  return switch (result) {
    Success(:final value) => value,
    Failure(:final message) => throw Exception(message),
  };
}
