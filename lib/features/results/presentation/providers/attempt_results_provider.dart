import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../core/utils/cache_for_extension.dart';
import '../../../../core/utils/result.dart';
import '../../data/results_repository.dart';
import '../../domain/attempt_results.dart';

part 'attempt_results_provider.g.dart';

/// Submitted-attempt summary for the results screen.
@riverpod
Future<AttemptResults> attemptResults(Ref ref, String attemptId) async {
  ref.cacheFor(const Duration(minutes: 5));
  final result = await ref
      .read(resultsRepositoryProvider)
      .fetchAttemptResults(attemptId);
  return switch (result) {
    Success(:final value) => value,
    Failure(:final message) => throw Exception(message),
  };
}
