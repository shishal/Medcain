import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../core/utils/cache_for_extension.dart';
import '../../../../core/utils/result.dart';
import '../../data/results_repository.dart';
import '../../domain/attempt_review.dart';

part 'attempt_review_provider.g.dart';

/// Per-question solutions for a submitted attempt.
@riverpod
Future<AttemptReview> attemptReview(Ref ref, String attemptId) async {
  ref.cacheFor(const Duration(minutes: 5));
  final result = await ref
      .read(resultsRepositoryProvider)
      .fetchAttemptReview(attemptId);
  return switch (result) {
    Success(:final value) => value,
    Failure(:final message) => throw Exception(message),
  };
}
