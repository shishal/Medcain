import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../core/utils/result.dart';
import '../../../auth/presentation/providers/auth_session_provider.dart';
import '../../data/practice_repository.dart';
import '../../domain/plan_limits.dart';

part 'practice_plan_context_provider.g.dart';

/// Current plan's practice caps plus today's practice usage.
///
/// Invalidate after a successful session create so the remaining quota updates.
@Riverpod(keepAlive: true)
class PracticePlanContextNotifier extends _$PracticePlanContextNotifier {
  @override
  Future<PracticePlanContext> build() async {
    final isSignedIn = ref.watch(authSessionProvider);
    if (!isSignedIn) {
      throw Exception('Not signed in.');
    }

    final result = await ref.read(practiceRepositoryProvider).fetchPlanContext();
    return switch (result) {
      Success(:final value) => value,
      Failure(:final message) => throw Exception(message),
    };
  }

  Future<void> refresh() async {
    ref.invalidateSelf();
    await future;
  }
}
