import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../core/utils/result.dart';
import '../../../auth/presentation/providers/auth_session_provider.dart';
import '../../data/local_attempt_store.dart';
import '../../data/tests_repository.dart';
import '../../domain/attempt.dart';
import '../../domain/attempt_status.dart';
import '../../domain/local_attempt_snapshot.dart';
import '../../domain/resumable_attempt.dart';

part 'in_progress_attempts_provider.g.dart';

/// In-progress attempts for the signed-in user, reconciled against the server.
///
/// Local files win for answers (offline). If the server says the attempt was
/// already submitted, the local file is deleted so we don't offer a dead resume.
@riverpod
class InProgressAttempts extends _$InProgressAttempts {
  @override
  Future<List<ResumableAttempt>> build() async {
    final signedIn = ref.watch(authSessionProvider);
    if (!signedIn) return const [];

    final repo = ref.read(testsRepositoryProvider);
    final store = ref.read(localAttemptStoreProvider);
    final userId = repo.currentUserId;
    if (userId == null) return const [];

    late final List<LocalAttemptSnapshot> local;
    late final Result<List<Attempt>> remoteResult;
    await Future.wait([
      store.listForUser(userId).then((v) => local = v),
      repo.listInProgressAttempts().then((v) => remoteResult = v),
    ]);
    final remoteList = switch (remoteResult) {
      Success(:final value) => value,
      Failure() => const <Attempt>[],
    };
    final remoteReachable = remoteResult is Success;
    final remoteById = {for (final attempt in remoteList) attempt.id: attempt};

    final resumable = <ResumableAttempt>[];
    final seen = <String>{};

    for (final snapshot in local) {
      if (snapshot.localStatus != LocalAttemptStatus.inProgress) continue;

      final remote = remoteById[snapshot.attemptId];
      if (remoteReachable && remote == null) {
        // Server is up and this attempt is gone / submitted / abandoned.
        await store.delete(snapshot.attemptId);
        continue;
      }

      resumable.add(ResumableAttempt.fromSnapshot(snapshot));
      seen.add(snapshot.attemptId);
    }

    if (remoteReachable) {
      for (final attempt in remoteList) {
        if (seen.contains(attempt.id)) continue;
        resumable.add(ResumableAttempt.fromAttempt(attempt));
      }
    }

    resumable.sort((a, b) => b.startedAt.compareTo(a.startedAt));
    return resumable;
  }
}
