import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_provider.dart';
import '../../../core/supabase/tables.dart';
import '../../../core/utils/result.dart';
import '../../../core/utils/user_facing_error.dart';
import '../../practice/domain/practice_enums.dart';
import '../../tests/domain/attempt_status.dart';
import '../../tests/domain/player_question.dart';
import '../../tests/domain/question_option.dart';
import '../domain/attempt_results.dart';
import '../domain/attempt_review.dart';

part 'results_repository.g.dart';

/// Loads a submitted attempt's summary. Presentation never calls Supabase.
class ResultsRepository {
  ResultsRepository(this._client);

  final SupabaseClient _client;

  Future<Result<AttemptResults>> fetchAttemptResults(String attemptId) async {
    if (_client.auth.currentUser == null) {
      return const Failure('Not signed in.');
    }

    try {
      final raw = await _client.rpc(
        RpcFunctions.getAttemptResults,
        params: {GetAttemptResultsParams.attemptId: attemptId},
      );

      final map = _asJsonMap(raw);
      if (map == null) {
        return const Failure('Could not load results. Please try again.');
      }
      return Success(AttemptResults.fromJson(map));
    } on PostgrestException catch (e) {
      return Failure(UserFacingError.from(e, fallback: _mapError(e)));
    } catch (e) {
      return Failure(
        UserFacingError.from(
          e,
          fallback: 'Could not load results. Please try again.',
        ),
      );
    }
  }

  /// Per-question solutions. Reads `questions` through normal RLS — the same
  /// path as the test player. Do not use [RpcFunctions.getAttemptResults]
  /// here: that function is `security definer` and would leak explanation
  /// text the student's plan is not allowed to see.
  Future<Result<AttemptReview>> fetchAttemptReview(String attemptId) async {
    if (_client.auth.currentUser == null) {
      return const Failure('Not signed in.');
    }

    try {
      final attemptRows = await _client
          .from(Tables.attempts)
          .select(
            '${AttemptColumns.id},'
            '${AttemptColumns.testId},'
            '${AttemptColumns.status}',
          )
          .eq(AttemptColumns.id, attemptId)
          .limit(1);

      final attempts = (attemptRows as List<dynamic>)
          .cast<Map<String, dynamic>>();
      if (attempts.isEmpty) {
        return const Failure('Those results are not available.');
      }

      final attempt = attempts.first;
      final status = AttemptStatus.fromString(
        attempt[AttemptColumns.status] as String? ?? '',
      );
      if (status != AttemptStatus.submitted) {
        return const Failure('This attempt has not been submitted yet.');
      }

      final testId = attempt[AttemptColumns.testId] as String;

      final testRows = await _client
          .from(Tables.tests)
          .select(
            '${TestColumns.id},'
            '${TestColumns.title},'
            '${TestColumns.showExplanationLevel},'
            '${TestColumns.isEphemeralPractice}',
          )
          .eq(TestColumns.id, testId)
          .limit(1);

      final tests = (testRows as List<dynamic>).cast<Map<String, dynamic>>();
      final test = tests.isEmpty ? null : tests.first;
      // Catalog default is `full`. If the test row is hidden by RLS we still
      // proceed — missing question embeds become plan-locked placeholders.
      final explanationLevel = ExplanationLevel.fromString(
        test?[TestColumns.showExplanationLevel] as String? ?? 'full',
      );
      final title = test?[TestColumns.title] as String? ?? 'Review';
      final isPractice =
          test?[TestColumns.isEphemeralPractice] as bool? ?? false;

      final questionRows = await _client
          .from(Tables.testQuestions)
          .select(
            '${TestQuestionColumns.questionId},'
            '${TestQuestionColumns.orderIndex},'
            '${TestQuestionColumns.sectionNumber},'
            '${TestQuestionColumns.questionEmbed}:${Tables.questions}('
            '$_questionColumns'
            ')',
          )
          .eq(TestQuestionColumns.testId, testId)
          .order(TestQuestionColumns.orderIndex);

      var slots = (questionRows as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .map(reviewSlotFromJoinJson)
          // whereType drops nulls (malformed rows) without a crash.
          .whereType<ReviewSlot>()
          .toList();

      final answerRows = await _client
          .from(Tables.attemptAnswers)
          .select(
            '${AttemptAnswerColumns.questionId},'
            '${AttemptAnswerColumns.selectedOption}',
          )
          .eq(AttemptAnswerColumns.attemptId, attemptId);

      final answers = <String, QuestionOption?>{};
      for (final row
          in (answerRows as List<dynamic>).cast<Map<String, dynamic>>()) {
        final questionId = row[AttemptAnswerColumns.questionId] as String?;
        if (questionId == null) continue;
        answers[questionId] = parseSelectedOption(
          row[AttemptAnswerColumns.selectedOption],
        );
      }

      if (slots.isEmpty && answers.isNotEmpty) {
        slots = await _slotsFromAnswers(answers);
      }

      return Success(
        AttemptReview.merge(
          attemptId: attemptId,
          testId: testId,
          title: title,
          explanationLevel: explanationLevel,
          isEphemeralPractice: isPractice,
          slots: slots,
          answers: answers,
        ),
      );
    } catch (e) {
      return Failure(
        UserFacingError.from(
          e,
          fallback: 'Could not load solutions. Please try again.',
        ),
      );
    }
  }

  /// When `test_questions` is hidden (test plan-gated) we still have the
  /// student's own `attempt_answers`. Fetch those question ids through
  /// `questions` RLS so explanation text is never ungated.
  Future<List<ReviewSlot>> _slotsFromAnswers(
    Map<String, QuestionOption?> answers,
  ) async {
    final ids = answers.keys.toList();
    final questionById = <String, PlayerQuestion>{};
    if (ids.isNotEmpty) {
      final rows = await _client
          .from(Tables.questions)
          .select(_questionColumns)
          .inFilter(QuestionColumns.id, ids);

      var order = 0;
      for (final row in (rows as List<dynamic>).cast<Map<String, dynamic>>()) {
        final json = {
          ...row,
          TestQuestionColumns.orderIndex: order,
          TestQuestionColumns.sectionNumber: 1,
        };
        final question = PlayerQuestion.fromSnapshotJson(json);
        questionById[question.id] = question;
        order++;
      }
    }

    return [
      for (var i = 0; i < ids.length; i++)
        ReviewSlot(
          questionId: ids[i],
          orderIndex: i,
          question: questionById[ids[i]],
        ),
    ];
  }

  static const _questionColumns =
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
      '${QuestionColumns.imageUrl}';

  static Map<String, dynamic>? _asJsonMap(Object? raw) {
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return null;
  }

  static String _mapError(PostgrestException e) {
    final haystack = '${e.message} ${e.details} ${e.hint}';
    if (haystack.contains('NOT_AUTHENTICATED')) {
      return 'Not signed in.';
    }
    if (haystack.contains('ATTEMPT_NOT_FOUND') ||
        haystack.contains('ATTEMPT_NOT_OWNED')) {
      return 'Those results are not available.';
    }
    if (haystack.contains('ATTEMPT_NOT_SUBMITTED')) {
      return 'This attempt has not been submitted yet.';
    }
    return 'Could not load results. Please try again.';
  }
}

@Riverpod(keepAlive: true)
ResultsRepository resultsRepository(Ref ref) {
  return ResultsRepository(ref.watch(supabaseClientProvider));
}
