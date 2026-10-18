import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_provider.dart';
import '../../../core/supabase/tables.dart';
import '../../../core/utils/result.dart';
import '../../../core/utils/user_facing_error.dart';
import '../../../core/utils/wall_clock.dart';
import '../domain/attempt.dart';
import '../domain/attempt_score.dart';
import '../domain/attempt_status.dart';
import '../domain/attempt_submit_request.dart';
import '../domain/player_question.dart';
import '../domain/test_detail.dart';
import '../domain/test_player_bundle.dart';

part 'tests_repository.g.dart';

/// Fetches plan-gated test details for the Practice player.
/// Presentation never calls Supabase directly.
///
/// Full rows (marking, sections) come from [Tables.tests] and are RLS-gated —
/// empty result means upgrade required. Practice sessions create these rows.
class TestsRepository {
  TestsRepository(this._client);

  final SupabaseClient _client;

  static const _attemptColumns =
      '${AttemptColumns.id},'
      '${AttemptColumns.userId},'
      '${AttemptColumns.testId},'
      '${AttemptColumns.status},'
      '${AttemptColumns.startedAt},'
      '${AttemptColumns.sectionStartedAt}';

  static const _attemptListSelect =
      '$_attemptColumns,'
      '${AttemptColumns.testEmbed}:${Tables.tests}('
      '${TestColumns.title},'
      '${TestColumns.isEphemeralPractice}'
      ')';

  String? get currentUserId => _client.auth.currentUser?.id;

  /// Instructions payload for one test. RLS returns no row if plan is too low.
  Future<Result<TestDetail>> fetchTestDetail(String testId) async {
    if (_client.auth.currentUser == null) {
      return const Failure('Not signed in.');
    }

    try {
      final rows = await _client
          .from(Tables.tests)
          .select(
            '${TestColumns.id},'
            '${TestColumns.title},'
            '${TestColumns.description},'
            '${TestColumns.testType},'
            '${TestColumns.requiredPlan},'
            '${TestColumns.isSectional},'
            '${TestColumns.sectionCount},'
            '${TestColumns.questionsPerSection},'
            '${TestColumns.sectionDurationMinutes},'
            '${TestColumns.totalDurationMinutes},'
            '${TestColumns.totalQuestions},'
            '${TestColumns.correctMarks},'
            '${TestColumns.incorrectMarks},'
            '${TestColumns.unattemptedMarks}',
          )
          .eq(TestColumns.id, testId)
          .limit(1);

      final list = (rows as List<dynamic>).cast<Map<String, dynamic>>();
      if (list.isEmpty) {
        // Empty under RLS almost always means plan gate — not a network glitch.
        return const Failure(
          'This test is not available on your current plan.',
        );
      }

      return Success(TestDetail.fromJson(list.first));
    } catch (e) {
      return Failure(
        UserFacingError.from(
          e,
          fallback: 'Could not load test details. Please try again.',
        ),
      );
    }
  }

  /// Questions + session flags for the player. Same RLS path as catalog tests
  /// (`tests` / `test_questions` / `questions`) — no separate ungated fetch.
  Future<Result<TestPlayerBundle>> fetchPlayerBundle(String testId) async {
    if (_client.auth.currentUser == null) {
      return const Failure('Not signed in.');
    }

    try {
      final testRows = await _client
          .from(Tables.tests)
          .select(
            '${TestColumns.id},'
            '${TestColumns.title},'
            '${TestColumns.feedbackTiming},'
            '${TestColumns.showExplanationLevel},'
            '${TestColumns.isEphemeralPractice},'
            '${TestColumns.isSectional},'
            '${TestColumns.sectionCount},'
            '${TestColumns.questionsPerSection},'
            '${TestColumns.sectionDurationMinutes},'
            '${TestColumns.totalDurationMinutes},'
            '${TestColumns.timerEnabled}',
          )
          .eq(TestColumns.id, testId)
          .limit(1);

      final tests = (testRows as List<dynamic>).cast<Map<String, dynamic>>();
      if (tests.isEmpty) {
        return const Failure(
          'This test is not available on your current plan.',
        );
      }

      final questionRows = await _client
          .from(Tables.testQuestions)
          .select(
            '${TestQuestionColumns.orderIndex},'
            '${TestQuestionColumns.sectionNumber},'
            '${TestQuestionColumns.questionEmbed}:${Tables.questions}('
            '${QuestionColumns.id},'
            '${QuestionColumns.questionText},'
            '${QuestionColumns.optionA},'
            '${QuestionColumns.optionB},'
            '${QuestionColumns.optionC},'
            '${QuestionColumns.optionD},'
            '${QuestionColumns.correctOption},'
            '${QuestionColumns.explanationText},'
            '${QuestionColumns.explanationDeep},'
            '${QuestionColumns.explanationVideoUrl},'
            '${QuestionColumns.imageUrl}'
            ')',
          )
          .eq(TestQuestionColumns.testId, testId)
          .order(TestQuestionColumns.orderIndex);

      final questions = (questionRows as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .where((row) => row[TestQuestionColumns.questionEmbed] != null)
          .map(PlayerQuestion.fromJoinJson)
          .toList();

      if (questions.isEmpty) {
        return const Failure('Could not load questions for this test.');
      }

      return Success(
        TestPlayerBundle.fromParts(testRow: tests.first, questions: questions),
      );
    } catch (e) {
      return Failure(
        UserFacingError.from(
          e,
          fallback: 'Could not load this test. Please try again.',
        ),
      );
    }
  }

  /// Existing in-progress attempt for this test, or null if none.
  Future<Result<Attempt?>> findInProgressAttempt(String testId) async {
    final userId = currentUserId;
    if (userId == null) {
      return const Failure('Not signed in.');
    }

    try {
      final rows = await _client
          .from(Tables.attempts)
          .select(_attemptColumns)
          .eq(AttemptColumns.userId, userId)
          .eq(AttemptColumns.testId, testId)
          .eq(AttemptColumns.status, AttemptStatus.inProgress.dbValue)
          .limit(1);

      final list = (rows as List<dynamic>).cast<Map<String, dynamic>>();
      if (list.isEmpty) return const Success(null);
      return Success(Attempt.fromJson(list.first));
    } catch (e) {
      return Failure(
        UserFacingError.from(
          e,
          fallback: 'Could not check for an existing attempt.',
        ),
      );
    }
  }

  Future<Result<Attempt?>> fetchAttempt(String attemptId) async {
    if (currentUserId == null) {
      return const Failure('Not signed in.');
    }

    try {
      final rows = await _client
          .from(Tables.attempts)
          .select(_attemptColumns)
          .eq(AttemptColumns.id, attemptId)
          .limit(1);

      final list = (rows as List<dynamic>).cast<Map<String, dynamic>>();
      if (list.isEmpty) return const Success(null);
      return Success(Attempt.fromJson(list.first));
    } catch (e) {
      return Failure(
        UserFacingError.from(e, fallback: 'Could not load this attempt.'),
      );
    }
  }

  /// Open attempts for the resume banner. Title comes from an embedded test.
  Future<Result<List<Attempt>>> listInProgressAttempts() async {
    final userId = currentUserId;
    if (userId == null) {
      return const Failure('Not signed in.');
    }

    try {
      final rows = await _client
          .from(Tables.attempts)
          .select(_attemptListSelect)
          .eq(AttemptColumns.userId, userId)
          .eq(AttemptColumns.status, AttemptStatus.inProgress.dbValue)
          .order(AttemptColumns.startedAt, ascending: false);

      final attempts = (rows as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .map(Attempt.fromJson)
          .toList();
      return Success(attempts);
    } catch (e) {
      return Failure(
        UserFacingError.from(e, fallback: 'Could not load in-progress tests.'),
      );
    }
  }

  /// Resume the existing in-progress row, or insert a new one.
  ///
  /// Duplicate inserts hit `idx_attempts_one_in_progress` (23505) and fall
  /// back to a re-fetch so two taps cannot create two rows.
  Future<Result<Attempt>> startOrResumeAttempt(String testId) async {
    final existing = await findInProgressAttempt(testId);
    switch (existing) {
      case Failure(:final message):
        return Failure(message);
      case Success(:final value) when value != null:
        return Success(value);
      case Success():
        return _createAttempt(testId);
    }
  }

  Future<Result<Attempt>> _createAttempt(String testId) async {
    final userId = currentUserId;
    if (userId == null) {
      return const Failure('Not signed in.');
    }

    try {
      final row = await _client
          .from(Tables.attempts)
          .insert({
            AttemptColumns.userId: userId,
            AttemptColumns.testId: testId,
            AttemptColumns.status: AttemptStatus.inProgress.dbValue,
          })
          .select(_attemptColumns)
          .single();

      return Success(Attempt.fromJson(row));
    } on PostgrestException catch (e) {
      // Unique violation — another request created the row first.
      if (e.code == '23505') {
        final retry = await findInProgressAttempt(testId);
        if (retry is Success<Attempt?> && retry.value != null) {
          return Success(retry.value!);
        }
      }
      return Failure(
        UserFacingError.from(
          e,
          fallback: 'Could not start this test. Please try again.',
        ),
      );
    } catch (e) {
      return Failure(
        UserFacingError.from(
          e,
          fallback: 'Could not start this test. Please try again.',
        ),
      );
    }
  }

  /// Best-effort write of section enter timestamps. Failures are ignored by
  /// the caller — local JSON is the offline source of truth.
  Future<Result<bool>> saveSectionStartedAt({
    required String attemptId,
    required Map<int, DateTime> sectionStartedAt,
  }) async {
    if (currentUserId == null) {
      return const Failure('Not signed in.');
    }

    try {
      await _client
          .from(Tables.attempts)
          .update({
            AttemptColumns.sectionStartedAt: encodeSectionStartedAt(
              sectionStartedAt,
            ),
          })
          .eq(AttemptColumns.id, attemptId);
      return const Success(true);
    } catch (e) {
      return Failure(
        UserFacingError.from(e, fallback: 'Could not sync section timer.'),
      );
    }
  }

  /// Postgres `now()` — used to correct a skewed device clock (spec §3).
  Future<Result<DateTime>> fetchServerNow() async {
    try {
      final raw = await _client.rpc(RpcFunctions.serverNow);
      final parsed = DateTime.tryParse(raw.toString());
      if (parsed == null) {
        return const Failure('Could not read server time.');
      }
      return Success(parsed);
    } catch (e) {
      return Failure(
        UserFacingError.from(e, fallback: 'Could not read server time.'),
      );
    }
  }

  /// Syncs local answers and asks Postgres to score. Never sends a score.
  Future<Result<AttemptScore>> submitAttempt(
    AttemptSubmitRequest request,
  ) async {
    if (currentUserId == null) {
      return const Failure('Not signed in.');
    }

    try {
      final raw = await _client.rpc(
        RpcFunctions.submitAttempt,
        params: request.toRpcParams(),
      );

      final map = _asJsonMap(raw);
      if (map == null) {
        return const Failure(
          'Could not submit. Check your connection and try again.',
        );
      }
      return Success(AttemptScore.fromJson(map));
    } on PostgrestException catch (e) {
      return Failure(UserFacingError.from(e, fallback: _mapSubmitError(e)));
    } catch (e) {
      return Failure(
        UserFacingError.from(
          e,
          fallback: 'Could not submit. Check your connection and try again.',
        ),
      );
    }
  }

  static Map<String, dynamic>? _asJsonMap(Object? raw) {
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return null;
  }

  static String _mapSubmitError(PostgrestException e) {
    final haystack = '${e.message} ${e.details} ${e.hint}';
    if (haystack.contains('NOT_AUTHENTICATED')) {
      return 'Not signed in.';
    }
    if (haystack.contains('ATTEMPT_NOT_FOUND') ||
        haystack.contains('ATTEMPT_NOT_OWNED') ||
        haystack.contains('ATTEMPT_NOT_IN_PROGRESS')) {
      return 'This attempt can no longer be submitted.';
    }
    return 'Could not submit. Check your connection and try again.';
  }
}

@Riverpod(keepAlive: true)
TestsRepository testsRepository(Ref ref) {
  return TestsRepository(ref.watch(supabaseClientProvider));
}
