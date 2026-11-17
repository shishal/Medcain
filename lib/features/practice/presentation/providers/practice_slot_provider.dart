import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../core/utils/result.dart';
import '../../../auth/presentation/providers/auth_session_provider.dart';
import '../../data/practice_repository.dart';
import '../../domain/practice_slot.dart';

part 'practice_slot_provider.g.dart';

/// The signed-in student's one practice row, or null.
///
/// Invalidate after a session is created so Resume disappears once the
/// previous row has been replaced.
@Riverpod(keepAlive: true)
class PracticeSlotNotifier extends _$PracticeSlotNotifier {
  @override
  Future<PracticeSlot?> build() async {
    final isSignedIn = ref.watch(authSessionProvider);
    if (!isSignedIn) {
      throw Exception('Not signed in.');
    }

    final result = await ref
        .read(practiceRepositoryProvider)
        .fetchCurrentSlot();
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
