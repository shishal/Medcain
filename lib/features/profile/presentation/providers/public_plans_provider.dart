import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/result.dart';
import '../../data/profile_repository.dart';
import '../../domain/plan_offer.dart';

/// Plans the paywall may show. Hidden and archived rows are not included.
final publicPlansProvider = FutureProvider<List<PlanOffer>>((ref) async {
  final result = await ref.watch(profileRepositoryProvider).fetchPublicPlans();
  return switch (result) {
    Success(:final value) => value,
    Failure(:final message) => throw Exception(message),
  };
});

/// The signed-in student's effective plan, after expiry and suspension.
final effectivePlanProvider = FutureProvider<PlanOffer>((ref) async {
  final result = await ref.watch(profileRepositoryProvider).fetchEffectivePlan();
  return switch (result) {
    Success(:final value) => value,
    Failure(:final message) => throw Exception(message),
  };
});
