import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../core/utils/result.dart';
import '../../../../core/utils/wall_clock.dart';
import '../../../auth/presentation/providers/auth_session_provider.dart';
import '../../../practice/domain/practice_enums.dart';
import '../../data/local_attempt_store.dart';
import '../../data/tests_repository.dart';
import '../../domain/attempt_status.dart';
import '../../domain/attempt_submit_request.dart';
import '../../domain/player_session_state.dart';
import '../../domain/question_option.dart';
import '../../domain/reading_mode_redirect.dart';
import '../../domain/submit_backoff.dart';
import 'in_progress_attempts_provider.dart';

part 'player_session_provider.g.dart';

/// Player for one [testId]. Creates or resumes an `attempts` row, downloads
/// questions, and autosaves answers to a local JSON file (spec §4).
///
/// The countdown is derived from wall-clock elapsed time (spec §3). A 1s tick
/// only checks for expiry — remaining seconds are never written to disk.
@Riverpod(keepAlive: true)
class PlayerSession extends _$PlayerSession {
  static const _saveDebounce = Duration(milliseconds: 500);

  Timer? _saveTimer;
  Timer? _tickTimer;
  DateTime? _questionVisibleSince;
  String? _userId;
  LocalAttemptStore? _store;
  WallClock _clock = WallClock();
  var _alive = true;
  var _submitLoopStarted = false;

  /// Clock used by the countdown UI — includes server skew correction.
  DateTime now() => _clock.now();

  @override
  Future<PlayerSessionState> build(String testId) async {
    _alive = true;
    _submitLoopStarted = false;
    ref.onDispose(() {
      _alive = false;
      _tearDown();
    });

    final signedIn = ref.watch(authSessionProvider);
    final repo = ref.read(testsRepositoryProvider);
    final store = ref.read(localAttemptStoreProvider);
    _store = store;
    final userId = repo.currentUserId;
    if (!signedIn || userId == null) {
      throw Exception('Not signed in.');
    }
    _userId = userId;

    await _reconcileClock(repo);

    final local = await store.readOpenForTest(testId: testId, userId: userId);

    if (local != null && local.questions.isNotEmpty) {
      if (local.feedbackTiming == FeedbackTiming.reading) {
        throw const ReadingModeRedirect();
      }
      final remote = await repo.fetchAttempt(local.attemptId);
      final stillOpen = switch (remote) {
        Failure() => true, // Offline: trust the local file.
        Success(:final value) when value == null => false,
        Success(:final value) => value!.status == AttemptStatus.inProgress,
      };
      final submittedOnServer = switch (remote) {
        Success(:final value) => value?.status == AttemptStatus.submitted,
        _ => false,
      };

      if (!stillOpen) {
        // Idempotent RPC returns stored scores — don't start a retake.
        if (submittedOnServer &&
            local.localStatus == LocalAttemptStatus.pendingSubmit) {
          return PlayerSessionState.fromSnapshot(local);
        }
        await store.delete(local.attemptId);
      } else {
        var session = PlayerSessionState.fromSnapshot(local);
        session = switch (remote) {
          Success(:final value) when value != null => session.copyWith(
            startedAt: value.startedAt,
            sectionStartedAt: mergeSectionStartedAt(
              session.sectionStartedAt,
              value.sectionStartedAt,
            ),
          ),
          _ => session,
        };
        session = session.applyTimerExpiry(_clock.now());
        await store.write(session.toSnapshot(userId: userId));
        unawaited(_syncSectionStarts(session));
        _questionVisibleSince = DateTime.now();
        if (!session.isPendingSubmit) _startTicker();
        return session;
      }
    }

    final bundleResult = await repo.fetchPlayerBundle(testId);
    final bundle = switch (bundleResult) {
      Success(:final value) => value,
      Failure(:final message) => throw Exception(message),
    };

    if (bundle.feedbackTiming == FeedbackTiming.reading) {
      throw const ReadingModeRedirect();
    }

    final attemptResult = await repo.startOrResumeAttempt(testId);
    final attempt = switch (attemptResult) {
      Success(:final value) => value,
      Failure(:final message) => throw Exception(message),
    };

    var session = PlayerSessionState.fromBundle(
      bundle,
      attemptId: attempt.id,
      startedAt: attempt.startedAt,
    );
    if (local != null && local.attemptId == attempt.id) {
      session = session.restoreProgress(
        savedAnswers: local.answers,
        savedIndex: local.currentIndex,
        savedSectionStartedAt: mergeSectionStartedAt(
          local.sectionStartedAt,
          attempt.sectionStartedAt,
        ),
      );
    } else if (attempt.sectionStartedAt.isNotEmpty) {
      session = session.copyWith(
        sectionStartedAt: mergeSectionStartedAt(
          session.sectionStartedAt,
          attempt.sectionStartedAt,
        ),
      );
    }

    session = session.applyTimerExpiry(_clock.now());
    await store.write(session.toSnapshot(userId: userId));
    unawaited(_syncSectionStarts(session));
    _questionVisibleSince = DateTime.now();
    if (!session.isPendingSubmit) _startTicker();
    return session;
  }

  void selectOption(QuestionOption option) =>
      _update((session) => session.selectOption(option));

  void clearResponse() => _update((session) => session.clearResponse());

  void toggleMark() => _update((session) => session.toggleMark());

  void markForReviewAndNext() =>
      _update((session) => session.markForReviewAndNext());

  void saveAndNext() => _update((session) => session.saveAndNext());

  void previous() => _update((session) => session.previous());

  void goTo(int index) => _update((session) => session.goTo(index));

  void submitSection() {
    _update(
      (session) => session.submitSection(_clock.now()),
      persistImmediately: true,
    );
    final session = state.value;
    if (session != null) unawaited(_syncSectionStarts(session));
  }

  /// Manual "Submit test" / "Finish session". Timer expiry uses the same loop.
  void finishAndSubmit() {
    final current = state.value;
    if (current == null || current.isSubmitComplete) return;
    if (!current.isPendingSubmit) {
      _update(
        (session) =>
            session.copyWith(localStatus: LocalAttemptStatus.pendingSubmit),
        persistImmediately: true,
      );
    }
    unawaited(ensureSubmitting());
  }

  /// Starts the RPC + backoff loop once. Safe to call from the UI repeatedly.
  Future<void> ensureSubmitting() async {
    if (_submitLoopStarted) return;
    final session = state.value;
    if (session == null || session.isSubmitComplete) return;
    if (!session.isPendingSubmit) return;
    _submitLoopStarted = true;
    _tickTimer?.cancel();
    _tickTimer = null;
    await _submitLoop();
  }

  /// Re-check Postgres time and expiry after the app returns to the foreground.
  Future<void> onAppResumed() async {
    final repo = ref.read(testsRepositoryProvider);
    await _reconcileClock(repo);
    _applyExpiry(persist: true);
  }

  /// Write immediately (leaving the player, app backgrounded, force-quit window).
  Future<void> flushSave() async {
    _saveTimer?.cancel();
    _saveTimer = null;
    await _persist();
  }

  void _update(
    PlayerSessionState Function(PlayerSessionState) fn, {
    bool persistImmediately = false,
  }) {
    final current = state.value;
    if (current == null || current.isPendingSubmit) return;
    final timed = _applyElapsed(current);
    var next = fn(timed);
    next = next.applyTimerExpiry(_clock.now());
    state = AsyncData(next);
    _questionVisibleSince = DateTime.now();
    if (next.isPendingSubmit) {
      _tickTimer?.cancel();
      _tickTimer = null;
      unawaited(_persist());
      unawaited(ensureSubmitting());
      return;
    }
    if (persistImmediately) {
      unawaited(_persist());
    } else {
      _scheduleSave();
    }
  }

  PlayerSessionState _applyElapsed(PlayerSessionState session) {
    final since = _questionVisibleSince;
    if (since == null) return session;
    final extra = DateTime.now().difference(since).inSeconds;
    return session.addTimeToCurrent(extra);
  }

  void _startTicker() {
    _tickTimer?.cancel();
    _tickTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _applyExpiry(persist: true);
    });
  }

  void _applyExpiry({required bool persist}) {
    final current = state.value;
    if (current == null || current.isPendingSubmit) return;
    final next = current.applyTimerExpiry(_clock.now());
    if (identical(next, current)) return;
    final sectionChanged =
        next.currentIndex != current.currentIndex ||
        next.localStatus != current.localStatus ||
        next.sectionStartedAt != current.sectionStartedAt;
    if (!sectionChanged) return;
    state = AsyncData(next);
    if (next.isPendingSubmit) {
      _tickTimer?.cancel();
      _tickTimer = null;
      unawaited(ensureSubmitting());
    }
    if (persist) unawaited(_persist());
    if (next.sectionStartedAt != current.sectionStartedAt) {
      unawaited(_syncSectionStarts(next));
    }
  }

  Future<void> _submitLoop() async {
    var failures = 0;
    while (_alive) {
      final session = state.value;
      final store = _store;
      final userId = _userId;
      if (session == null || store == null || userId == null) return;
      if (session.isSubmitComplete) return;

      await _persist();
      final toSend = state.value ?? session;
      final result = await ref
          .read(testsRepositoryProvider)
          .submitAttempt(AttemptSubmitRequest.fromSession(toSend));

      if (!_alive) return;

      switch (result) {
        case Success(:final value):
          await store.delete(session.attemptId);
          if (!_alive) return;
          state = AsyncData(
            session.copyWith(submittedScore: value, clearSubmitError: true),
          );
          ref.invalidate(inProgressAttemptsProvider);
          return;
        case Failure(:final message) when isTerminalSubmitFailure(message):
          if (message != 'Not signed in.') {
            await store.delete(session.attemptId);
          }
          if (!_alive) return;
          state = AsyncData(session.copyWith(submitError: message));
          return;
        case Failure(:final message):
          failures++;
          state = AsyncData(session.copyWith(submitError: message));
          await Future<void>.delayed(SubmitBackoff.delayFor(failures));
      }
    }
  }

  Future<void> _reconcileClock(TestsRepository repo) async {
    final result = await repo.fetchServerNow();
    if (result is Success<DateTime>) {
      _clock = _clock.reconcile(
        serverNow: result.value,
        localNow: DateTime.now(),
      );
    }
  }

  Future<void> _syncSectionStarts(PlayerSessionState session) async {
    final repo = ref.read(testsRepositoryProvider);
    await repo.saveSectionStartedAt(
      attemptId: session.attemptId,
      sectionStartedAt: session.sectionStartedAt,
    );
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(_saveDebounce, () {
      unawaited(_persist());
    });
  }

  Future<void> _persist() async {
    final userId = _userId;
    final current = state.value;
    final store = _store;
    if (userId == null || current == null || store == null) return;
    if (current.isSubmitComplete) return;
    final timed = _applyElapsed(current);
    if (!identical(timed, current)) {
      state = AsyncData(timed);
      _questionVisibleSince = DateTime.now();
    }
    await store.write(timed.toSnapshot(userId: userId));
  }

  void _tearDown() {
    _saveTimer?.cancel();
    _saveTimer = null;
    _tickTimer?.cancel();
    _tickTimer = null;
    final userId = _userId;
    final current = state.value;
    final store = _store;
    if (userId == null || current == null || store == null) return;
    if (current.isSubmitComplete) return;
    final timed = _applyElapsed(current);
    unawaited(store.write(timed.toSnapshot(userId: userId)));
  }
}
