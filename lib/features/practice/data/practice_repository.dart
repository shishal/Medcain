import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_provider.dart';
import '../../../core/supabase/tables.dart';
import '../../../core/utils/result.dart';
import '../../../core/utils/user_facing_error.dart';
import '../domain/created_practice_session.dart';
import '../domain/plan_limits.dart';
import '../domain/practice_builder_draft.dart';
import '../domain/practice_catalog.dart';

part 'practice_repository.g.dart';

/// Practice Builder data + `create_practice_session` RPC.
/// Presentation never calls Supabase directly.
class PracticeRepository {
  PracticeRepository(this._client);

  final SupabaseClient _client;

  Future<Result<PracticeCatalog>> fetchCatalog() async {
    if (_client.auth.currentUser == null) {
      return const Failure('Not signed in.');
    }

    try {
      final results = await Future.wait([
        _client
            .from(Tables.subjects)
            .select(
              '${SubjectColumns.id},'
              '${SubjectColumns.name},'
              '${SubjectColumns.displayOrder},'
              '${SubjectColumns.mbbsPhaseId}',
            )
            .order(SubjectColumns.displayOrder),
        _client
            .from(Tables.topics)
            .select(
              '${TopicColumns.id},'
              '${TopicColumns.subjectId},'
              '${TopicColumns.name},'
              '${TopicColumns.displayOrder}',
            )
            .order(TopicColumns.displayOrder),
        _client
            .from(Tables.tags)
            .select('${TagColumns.id},${TagColumns.name}')
            .order(TagColumns.name),
        _client
            .from(Tables.mbbsPhases)
            .select(
              '${MbbsPhaseColumns.id},'
              '${MbbsPhaseColumns.name},'
              '${MbbsPhaseColumns.displayOrder}',
            ),
      ]);

      final phases = <String, Map<String, dynamic>>{
        for (final row
            in (results[3] as List<dynamic>).cast<Map<String, dynamic>>())
          row[MbbsPhaseColumns.id] as String: row,
      };
      final subjects =
          [
            for (final row
                in (results[0] as List<dynamic>).cast<Map<String, dynamic>>())
              _subjectFromRow(row, phases),
          ]..sort((a, b) {
            final byPhase = a.phaseOrder.compareTo(b.phaseOrder);
            if (byPhase != 0) return byPhase;
            return a.displayOrder.compareTo(b.displayOrder);
          });

      return Success(
        PracticeCatalog(
          subjects: subjects,
          topics: _mapRows(results[1], Topic.fromJson),
          tags: _mapRows(results[2], PracticeTag.fromJson),
        ),
      );
    } catch (e) {
      return Failure(
        UserFacingError.from(
          e,
          fallback: 'Could not load practice options. Please try again.',
        ),
      );
    }
  }

  Future<Result<PracticePlanContext>> fetchPlanContext() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      return const Failure('Not signed in.');
    }

    try {
      final limitsRaw = await _client.rpc(RpcFunctions.currentPlanDetail);
      if (limitsRaw is! Map) {
        return const Failure('Could not load your plan limits. Please try again.');
      }
      final limitsRow = Map<String, dynamic>.from(limitsRaw);

      final usageRows = await _client
          .from(Tables.dailyPracticeUsage)
          .select(DailyPracticeUsageColumns.questionsUsed)
          .eq(DailyPracticeUsageColumns.userId, userId)
          .eq(DailyPracticeUsageColumns.usageDate, _todayIsoDate())
          .limit(1);

      final usageList = (usageRows as List<dynamic>)
          .cast<Map<String, dynamic>>();
      final used = usageList.isEmpty
          ? 0
          : _asInt(usageList.first[DailyPracticeUsageColumns.questionsUsed]);

      return Success(
        PracticePlanContext(
          limits: PlanLimits.fromPlan(limitsRow),
          questionsUsedToday: used,
        ),
      );
    } catch (e) {
      return Failure(
        UserFacingError.from(
          e,
          fallback: 'Could not load your plan limits. Please try again.',
        ),
      );
    }
  }

  /// Creates an ephemeral practice test. Limits are enforced in Postgres —
  /// this method must not compute or send a "trusted" score or cap.
  Future<Result<CreatedPracticeSession>> createSession({
    required PracticeBuilderDraft draft,
    required PracticeCatalog catalog,
  }) async {
    if (_client.auth.currentUser == null) {
      return const Failure('Not signed in.');
    }

    try {
      final raw = await _client.rpc(
        RpcFunctions.createPracticeSession,
        params: {
          CreatePracticeSessionParams.topicIds: draft.resolvedTopicIds(catalog),
          CreatePracticeSessionParams.subjectIds: draft.resolvedSubjectIds(
            catalog,
          ),
          CreatePracticeSessionParams.tagIds: draft.resolvedTagIds,
          CreatePracticeSessionParams.difficulties: draft.resolvedDifficulties
              ?.map((d) => d.dbValue)
              .toList(),
          CreatePracticeSessionParams.sourceFilter: draft.sourceFilter.dbValue,
          CreatePracticeSessionParams.questionCount: draft.questionCount,
          CreatePracticeSessionParams.feedbackTiming:
              draft.feedbackTiming.dbValue,
          CreatePracticeSessionParams.explanationLevel:
              draft.explanationLevel.dbValue,
          CreatePracticeSessionParams.timerMinutes: draft.resolvedTimerMinutes,
          CreatePracticeSessionParams.negativeMarking: draft.negativeMarking,
          CreatePracticeSessionParams.lessonIds: draft.lessonIds.isEmpty
              ? null
              : draft.lessonIds.toList(),
        },
      );

      final testId = raw as String;

      final rows = await _client
          .from(Tables.tests)
          .select(
            '${TestColumns.id},'
            '${TestColumns.totalQuestions},'
            '${TestColumns.showExplanationLevel},'
            '${TestColumns.timerEnabled},'
            '${TestColumns.totalDurationMinutes}',
          )
          .eq(TestColumns.id, testId)
          .limit(1);

      final list = (rows as List<dynamic>).cast<Map<String, dynamic>>();
      if (list.isEmpty) {
        // Session exists; we just couldn't re-read it — still let them play.
        return Success(
          CreatedPracticeSession(
            testId: testId,
            totalQuestions: draft.questionCount,
            explanationLevel: draft.explanationLevel,
            timerEnabled: draft.timerEnabled,
            totalDurationMinutes: draft.resolvedTimerMinutes ?? 0,
          ),
        );
      }

      return Success(CreatedPracticeSession.fromJson(list.first));
    } on PostgrestException catch (e) {
      return Failure(UserFacingError.from(e, fallback: _mapRpcError(e)));
    } catch (e) {
      return Failure(
        UserFacingError.from(
          e,
          fallback: 'Could not start practice. Please try again.',
        ),
      );
    }
  }

  /// Filters stored on a practice session, for "Practice Similar Again".
  ///
  /// Returns [Success] with `null` for catalog tests (no button to show).
  /// Does not clamp here — the builder and `create_practice_session` both
  /// re-apply the *current* plan, in case it changed since this session.
  Future<Result<PracticeBuilderDraft?>> fetchSimilarDraft(String testId) async {
    if (_client.auth.currentUser == null) {
      return const Failure('Not signed in.');
    }

    try {
      final rows = await _client
          .from(Tables.tests)
          .select(
            '${TestColumns.id},'
            '${TestColumns.isEphemeralPractice},'
            '${TestColumns.feedbackTiming},'
            '${TestColumns.showExplanationLevel},'
            '${TestColumns.timerEnabled},'
            '${TestColumns.totalQuestions},'
            '${TestColumns.practiceFilterCriteria}',
          )
          .eq(TestColumns.id, testId)
          .limit(1);

      final list = (rows as List<dynamic>).cast<Map<String, dynamic>>();
      if (list.isEmpty) {
        return const Failure('Could not load that practice session.');
      }

      final row = list.first;
      final isPractice = row[TestColumns.isEphemeralPractice] as bool? ?? false;
      if (!isPractice) return const Success(null);

      return Success(PracticeBuilderDraft.fromPracticeTestRow(row));
    } catch (e) {
      return Failure(
        UserFacingError.from(
          e,
          fallback: 'Could not restore those filters. Please try again.',
        ),
      );
    }
  }

  static Subject _subjectFromRow(
    Map<String, dynamic> row,
    Map<String, Map<String, dynamic>> phases,
  ) {
    final phaseId = row[SubjectColumns.mbbsPhaseId] as String?;
    final phase = phaseId == null ? null : phases[phaseId];
    return Subject.fromJson(
      row,
      phaseName: phase?[MbbsPhaseColumns.name] as String?,
      phaseOrder: phase == null
          ? 0
          : _asInt(phase[MbbsPhaseColumns.displayOrder]),
    );
  }

  static List<T> _mapRows<T>(
    dynamic rows,
    T Function(Map<String, dynamic>) fromJson,
  ) {
    return (rows as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .map(fromJson)
        .toList();
  }

  static int _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.parse(value.toString());
  }

  /// Local calendar date as `yyyy-MM-dd` — matches Postgres `date` literals.
  static String _todayIsoDate() {
    final now = DateTime.now();
    final month = now.month.toString().padLeft(2, '0');
    final day = now.day.toString().padLeft(2, '0');
    return '${now.year}-$month-$day';
  }

  static String _mapRpcError(PostgrestException e) {
    final haystack = '${e.message} ${e.details} ${e.hint}';
    if (haystack.contains('DAILY_PRACTICE_QUOTA_EXCEEDED')) {
      return "You've used today's practice questions. Come back tomorrow.";
    }
    if (haystack.contains('NO_QUESTIONS_MATCH_FILTERS')) {
      return 'No questions match these filters. Try widening your selection.';
    }
    if (haystack.contains('NOT_AUTHENTICATED')) {
      return 'Not signed in.';
    }
    return 'Could not start practice. Please try again.';
  }
}

@Riverpod(keepAlive: true)
PracticeRepository practiceRepository(Ref ref) {
  return PracticeRepository(ref.watch(supabaseClientProvider));
}
