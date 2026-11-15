import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_provider.dart';
import '../../../core/supabase/tables.dart';
import '../../../core/utils/result.dart';
import '../../../core/utils/user_facing_error.dart';
import '../../profile/domain/plan_tier.dart';
import '../domain/pyq_models.dart';

part 'pyq_repository.g.dart';

class PyqDetail {
  const PyqDetail({
    required this.teaser,
    required this.appearances,
    required this.textbookRefs,
    required this.lessonResources,
    required this.questionResources,
    this.sampleAnswer,
    required this.canReadSample,
    required this.questionLearnt,
    this.optionA,
    this.optionB,
    this.optionC,
    this.optionD,
    this.correctOption,
    this.explanationText,
    this.explanationDeep,
  });

  final PyqTeaser teaser;
  final List<ExamAppearance> appearances;
  final List<TextbookCitation> textbookRefs;
  final List<ResourceLink> lessonResources;
  final List<ResourceLink> questionResources;
  final String? sampleAnswer;
  final bool canReadSample;
  final bool questionLearnt;
  final String? optionA;
  final String? optionB;
  final String? optionC;
  final String? optionD;
  final String? correctOption;
  final String? explanationText;
  final String? explanationDeep;

  bool get isMcq => teaser.kind == 'mcq';
}

class PyqRepository {
  PyqRepository(this._client);

  final SupabaseClient _client;

  static const _teaserSelect =
      '${QuestionColumns.id},${QuestionColumns.lessonId},'
      '${QuestionColumns.topicId},${QuestionColumns.questionText},'
      '${QuestionColumns.marks},${QuestionColumns.requiredPlan},'
      '${QuestionColumns.kind},${QuestionColumns.difficulty},'
      '${QuestionColumns.hasDirectAnswer},${QuestionColumns.hasExplanation},'
      '${QuestionColumns.publicCode},${QuestionColumns.isLocked}';

  Future<Result<List<ResourceLink>>> fetchLessonResources(
    String lessonId,
  ) async {
    if (_client.auth.currentUser == null) {
      return const Failure('Not signed in.');
    }
    try {
      final rows = await _client
          .from(Tables.lessonResources)
          .select()
          .eq(ResourceColumns.lessonId, lessonId)
          .order(ResourceColumns.displayOrder);
      return Success(
        (rows as List<dynamic>)
            .cast<Map<String, dynamic>>()
            .map(ResourceLink.fromJson)
            .toList(),
      );
    } catch (e) {
      return Failure(
        UserFacingError.from(e, fallback: 'Could not load topic links.'),
      );
    }
  }

  Future<Result<PyqLessonFeed>> fetchTeasersForLesson({
    required String lessonId,
    String? universityId,
  }) async {
    if (_client.auth.currentUser == null) {
      return const Failure('Not signed in.');
    }
    try {
      // Select only teaser header columns — not full essay sample answers or
      // explanations — and fetch appearances + textbook refs in parallel.
      final rows = await _client
          .from(Tables.questionListings)
          .select(_teaserSelect)
          .eq(PyqTeaserColumns.lessonId, lessonId)
          .order(PyqTeaserColumns.id);
      final all = (rows as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .map(PyqTeaser.fromJson)
          .toList();
      if (all.isEmpty) {
        return const Success(PyqLessonFeed(teasers: []));
      }

      final ids = all.map((t) => t.id).toList();
      late final List<dynamic> appRows;
      late final List<dynamic> refRows;
      await Future.wait([
        _client
            .from(Tables.questionAppearances)
            .select(
              '${AppearanceColumns.questionId},'
              '${AppearanceColumns.examPaperEmbed}:${Tables.examPapers}('
              '${ExamPaperColumns.universityId},'
              '${ExamPaperColumns.examYear})',
            )
            .inFilter(AppearanceColumns.questionId, ids)
            .then((v) => appRows = v as List<dynamic>),
        _client
            .from(Tables.questionTextbookRefs)
            .select(
              '${TextbookRefColumns.questionId},${TextbookRefColumns.page},'
              '${TextbookRefColumns.sectionHeading},'
              '${TextbookRefColumns.textbookEmbed}:${Tables.textbooks}('
              '${TextbookColumns.title},${TextbookColumns.edition},'
              '${TextbookColumns.sheetKey})',
            )
            .inFilter(TextbookRefColumns.questionId, ids)
            .then((v) => refRows = v as List<dynamic>),
      ]);

      final contentUni = universityId;

      final yearsByQuestionUni = <String, Map<String, List<int>>>{};
      final unisByQuestion = <String, Set<String>>{};
      for (final raw in appRows.cast<Map<String, dynamic>>()) {
        final qid = raw[AppearanceColumns.questionId] as String;
        final paper = raw[AppearanceColumns.examPaperEmbed];
        final map = paper is Map<String, dynamic> ? paper : <String, dynamic>{};
        final uid = map[ExamPaperColumns.universityId] as String?;
        if (uid != null) {
          unisByQuestion.putIfAbsent(qid, () => {}).add(uid);
        }
        final year = map[ExamPaperColumns.examYear];
        if (uid != null && year is num) {
          yearsByQuestionUni
              .putIfAbsent(qid, () => {})
              .putIfAbsent(uid, () => [])
              .add(year.toInt());
        }
      }

      final firstRef = <String, String>{};
      for (final raw in refRows.cast<Map<String, dynamic>>()) {
        final qid = raw[TextbookRefColumns.questionId] as String;
        if (firstRef.containsKey(qid)) continue;
        firstRef[qid] = TextbookCitation.fromJson(raw).label;
      }

      final teasers = <PyqTeaser>[];
      for (final t in all) {
        final owned = unisByQuestion[t.id];
        final isMcqBank = t.kind == 'mcq' && (owned == null || owned.isEmpty);
        final matchesUni =
            contentUni == null ||
            isMcqBank ||
            (owned != null && owned.contains(contentUni));
        if (!matchesUni) continue;
        final years = {...?yearsByQuestionUni[t.id]?[contentUni]}.toList()
          ..sort();
        teasers.add(
          t.copyWith(
            textbookLine: firstRef[t.id],
            appearanceYears: years,
            appearanceCount: years.length,
          ),
        );
      }

      teasers.sort((a, b) => b.appearanceCount.compareTo(a.appearanceCount));
      return Success(PyqLessonFeed(teasers: teasers));
    } catch (e) {
      return Failure(UserFacingError.from(e, fallback: 'Could not load PYQs.'));
    }
  }

  /// PYQs for a subject (mixed-topic papers). Chapters are tags, not a funnel.
  Future<Result<PyqSubjectFeed>> fetchTeasersForSubject({
    required String subjectId,
    String? universityId,
  }) async {
    if (_client.auth.currentUser == null) {
      return const Failure('Not signed in.');
    }
    try {
      late final List<dynamic> topicRows;
      late final List<dynamic> paperRows;
      await Future.wait([
        _client
            .from(Tables.topics)
            .select('${TopicColumns.id},${TopicColumns.name}')
            .eq(TopicColumns.subjectId, subjectId)
            .order(TopicColumns.displayOrder)
            .then((v) => topicRows = v as List<dynamic>),
        _client
            .from(Tables.examPapers)
            .select(ExamPaperColumns.id)
            .eq(ExamPaperColumns.subjectId, subjectId)
            .then((v) => paperRows = v as List<dynamic>),
      ]);
      final topics = topicRows.cast<Map<String, dynamic>>();
      final chapters = [
        for (final t in topics)
          PyqChapter(
            id: t[TopicColumns.id] as String,
            name: t[TopicColumns.name] as String? ?? 'Chapter',
          ),
      ];
      final topicNameById = {for (final c in chapters) c.id: c.name};
      final topicIds = chapters.map((c) => c.id).toList();
      final paperIds = [
        for (final raw in paperRows.cast<Map<String, dynamic>>())
          if (raw[ExamPaperColumns.id] is String)
            raw[ExamPaperColumns.id] as String,
      ];

      late final List<Map<String, dynamic>> lessonRows;
      late final List<Map<String, dynamic>> topicQuestionRows;
      late final List<Map<String, dynamic>> appearanceRows;
      await Future.wait([
        _inFilterSelect(
          table: Tables.lessons,
          column: LessonColumns.topicId,
          ids: topicIds,
          select:
              '${LessonColumns.id},${LessonColumns.name},${LessonColumns.topicId}',
        ).then((v) => lessonRows = v),
        _inFilterSelect(
          table: Tables.questionListings,
          column: QuestionColumns.topicId,
          ids: topicIds,
          select: _teaserSelect,
          activeOnly: true,
        ).then((v) => topicQuestionRows = v),
        _inFilterSelect(
          table: Tables.questionAppearances,
          column: AppearanceColumns.examPaperId,
          ids: paperIds,
          select: AppearanceColumns.questionId,
          orderColumns: const [
            AppearanceColumns.questionId,
            AppearanceColumns.examPaperId,
          ],
        ).then((v) => appearanceRows = v),
      ]);

      final lessonNameById = <String, String>{};
      final lessonTopicById = <String, String>{};
      for (final raw in lessonRows) {
        final id = raw[LessonColumns.id] as String;
        lessonNameById[id] = raw[LessonColumns.name] as String? ?? '';
        final tid = raw[LessonColumns.topicId] as String?;
        if (tid != null) lessonTopicById[id] = tid;
      }

      final questionById = <String, Map<String, dynamic>>{};
      void addQuestions(List<Map<String, dynamic>> rows) {
        for (final row in rows) {
          final id = row[QuestionColumns.id] as String?;
          if (id != null) questionById[id] = row;
        }
      }

      addQuestions(topicQuestionRows);

      if (appearanceRows.isNotEmpty) {
        final missingIds = <String>{
          for (final raw in appearanceRows)
            if (raw[AppearanceColumns.questionId] is String)
              raw[AppearanceColumns.questionId] as String,
        }.difference(questionById.keys.toSet());
        if (missingIds.isNotEmpty) {
          addQuestions(
            await _inFilterSelect(
              table: Tables.questionListings,
              column: QuestionColumns.id,
              ids: missingIds.toList(),
              select: _teaserSelect,
              activeOnly: true,
            ),
          );
        }
      }

      final all = questionById.values.map(PyqTeaser.fromJson).toList();
      if (all.isEmpty) {
        return Success(PyqSubjectFeed(teasers: const [], chapters: chapters));
      }

      final ids = all.map((t) => t.id).toList();
      const appSelect =
          '${AppearanceColumns.questionId},'
          '${AppearanceColumns.examPaperEmbed}:${Tables.examPapers}('
          '${ExamPaperColumns.universityId},'
          '${ExamPaperColumns.collegeId},'
          '${ExamPaperColumns.examType},'
          '${ExamPaperColumns.examYear},'
          '${ExamPaperColumns.examMonth},'
          '${ExamPaperColumns.paperName})';
      const refSelect =
          '${TextbookRefColumns.questionId},${TextbookRefColumns.page},'
          '${TextbookRefColumns.sectionHeading},'
          '${TextbookRefColumns.textbookEmbed}:${Tables.textbooks}('
          '${TextbookColumns.title},${TextbookColumns.edition},'
          '${TextbookColumns.sheetKey})';
      // `.then` attaches a listener immediately. Starting the Futures and
      // awaiting later lets a 400 surface as an unhandled async error
      // before this try/catch runs.
      late final List<Map<String, dynamic>> appRows;
      late final List<Map<String, dynamic>> refRows;
      await Future.wait([
        _inFilterSelect(
          table: Tables.questionAppearances,
          column: AppearanceColumns.questionId,
          ids: ids,
          select: appSelect,
          orderColumns: const [
            AppearanceColumns.questionId,
            AppearanceColumns.examPaperId,
          ],
        ).then((v) => appRows = v),
        _inFilterSelect(
          table: Tables.questionTextbookRefs,
          column: TextbookRefColumns.questionId,
          ids: ids,
          select: refSelect,
          orderColumns: const [
            TextbookRefColumns.questionId,
            TextbookRefColumns.textbookId,
          ],
        ).then((v) => refRows = v),
      ]);
      final contentUni = universityId;

      final yearsByQuestionUni = <String, Map<String, List<int>>>{};
      final papersByQuestionUni = <String, Map<String, Set<String>>>{};
      final sittingsByQuestion = <String, List<PaperSitting>>{};
      final unisByQuestion = <String, Set<String>>{};
      for (final raw in appRows) {
        final qid = raw[AppearanceColumns.questionId] as String;
        final paper = raw[AppearanceColumns.examPaperEmbed];
        final map = paper is Map<String, dynamic> ? paper : <String, dynamic>{};
        final uid = map[ExamPaperColumns.universityId] as String?;
        if (uid != null) {
          unisByQuestion.putIfAbsent(qid, () => {}).add(uid);
        }
        final year = map[ExamPaperColumns.examYear];
        if (uid != null && year is num) {
          yearsByQuestionUni
              .putIfAbsent(qid, () => {})
              .putIfAbsent(uid, () => [])
              .add(year.toInt());
        }
        final rawPaper = map[ExamPaperColumns.paperName] as String?;
        if (uid != null && year is num) {
          final month = map[ExamPaperColumns.examMonth];
          sittingsByQuestion
              .putIfAbsent(qid, () => [])
              .add(
                PaperSitting(
                  universityId: uid,
                  collegeId: map[ExamPaperColumns.collegeId] as String?,
                  examType: PaperExamType.fromDb(
                    map[ExamPaperColumns.examType] as String?,
                  ),
                  year: year.toInt(),
                  month: month is num ? month.toInt() : null,
                  paperName: (rawPaper == null || rawPaper.trim().isEmpty)
                      ? null
                      : rawPaper.trim(),
                ),
              );
        }
        final hasPaper = rawPaper != null && rawPaper.isNotEmpty;
        final hasMonth = examMonthName(map[ExamPaperColumns.examMonth]) != null;
        if (uid != null && (hasPaper || hasMonth)) {
          papersByQuestionUni
              .putIfAbsent(qid, () => {})
              .putIfAbsent(uid, () => {})
              .add(
                paperSittingLabel(
                  month: map[ExamPaperColumns.examMonth],
                  paperName: rawPaper,
                ),
              );
        }
      }

      final firstRef = <String, String>{};
      for (final raw in refRows) {
        final qid = raw[TextbookRefColumns.questionId] as String;
        if (firstRef.containsKey(qid)) continue;
        firstRef[qid] = TextbookCitation.fromJson(raw).label;
      }

      final teasers = <PyqTeaser>[];
      final paperNames = <String>{};
      final years = <int>{};
      for (final t in all) {
        final owned = unisByQuestion[t.id];
        final isMcqBank = t.kind == 'mcq' && (owned == null || owned.isEmpty);
        final sittings = sittingsByQuestion[t.id] ?? const <PaperSitting>[];
        // Other universities' papers stay in the feed: the subject screen
        // shows them in their own section. Stems with no paper at all are
        // dropped, except the MCQ bank.
        if (sittings.isEmpty && !isMcqBank) continue;
        final qYears = {...?yearsByQuestionUni[t.id]?[contentUni]}.toList()
          ..sort();
        final qPapers = {...?papersByQuestionUni[t.id]?[contentUni]}.toList()
          ..sort();
        paperNames.addAll(qPapers);
        years.addAll(qYears);
        final topicId =
            t.topicId ??
            (t.lessonId == null ? null : lessonTopicById[t.lessonId]);
        teasers.add(
          t.copyWith(
            textbookLine: firstRef[t.id],
            appearanceYears: qYears,
            appearanceCount: qYears.length,
            paperNames: qPapers,
            topicId: topicId,
            topicName: topicId == null ? null : topicNameById[topicId],
            lessonName: t.lessonId == null ? null : lessonNameById[t.lessonId],
            sittings: sittings,
          ),
        );
      }

      final yearList = years.toList()..sort((a, b) => b.compareTo(a));
      final paperList = paperNames.toList()..sort();
      return Success(
        PyqSubjectFeed(
          teasers: teasers,
          paperNames: paperList,
          years: yearList,
          chapters: chapters,
        ),
      );
    } catch (e) {
      return Failure(UserFacingError.from(e, fallback: 'Could not load PYQs.'));
    }
  }

  Future<Result<PyqDetail>> fetchDetail({
    required String questionId,
    required PlanTier plan,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      return const Failure('Not signed in.');
    }
    try {
      // Fetch teaser + detail columns from `question_listings` alongside
      // appearances, textbook citations, question links, and progress in one
      // parallel batch (instead of 7 sequential round-trips).
      const detailSelect =
          '$_teaserSelect,'
          '${QuestionColumns.optionA},${QuestionColumns.optionB},'
          '${QuestionColumns.optionC},${QuestionColumns.optionD},'
          '${QuestionColumns.correctOption},${QuestionColumns.explanationText},'
          '${QuestionColumns.explanationDeep},${QuestionColumns.sampleAnswer},'
          '${QuestionColumns.answersVisible}';

      late final List<dynamic> qRows;
      late final List<dynamic> appearancesRows;
      late final List<dynamic> refRows;
      late final List<dynamic> qRes;
      late final List<dynamic> progressRows;

      await Future.wait([
        _client
            .from(Tables.questionListings)
            .select(detailSelect)
            .eq(QuestionColumns.id, questionId)
            .limit(1)
            .then((v) => qRows = v as List<dynamic>),
        _client
            .from(Tables.questionAppearances)
            .select(
              '${AppearanceColumns.examPaperEmbed}:${Tables.examPapers}('
              '${ExamPaperColumns.examYear},${ExamPaperColumns.examMonth},'
              '${ExamPaperColumns.paperName})',
            )
            .eq(AppearanceColumns.questionId, questionId)
            .then((v) => appearancesRows = v as List<dynamic>),
        _client
            .from(Tables.questionTextbookRefs)
            .select(
              '${TextbookRefColumns.page},${TextbookRefColumns.sectionHeading},'
              '${TextbookRefColumns.textbookEmbed}:${Tables.textbooks}('
              '${TextbookColumns.title},${TextbookColumns.authors},'
              '${TextbookColumns.edition},${TextbookColumns.sheetKey})',
            )
            .eq(TextbookRefColumns.questionId, questionId)
            .then((v) => refRows = v as List<dynamic>),
        _client
            .from(Tables.questionResources)
            .select()
            .eq(ResourceColumns.questionId, questionId)
            .order(ResourceColumns.displayOrder)
            .then((v) => qRes = v as List<dynamic>),
        _client
            .from(Tables.questionProgress)
            .select(QuestionProgressColumns.learntAt)
            .eq(QuestionProgressColumns.userId, userId)
            .eq(QuestionProgressColumns.questionId, questionId)
            .limit(1)
            .then((v) => progressRows = v as List<dynamic>),
      ]);

      final qList = qRows.cast<Map<String, dynamic>>();
      if (qList.isEmpty) {
        return const Failure('This question is not available.');
      }
      final q = qList.first;
      final appearances = appearancesRows
          .cast<Map<String, dynamic>>()
          .map(ExamAppearance.fromJson)
          .toList();
      final teaser = PyqTeaser.fromJson(q).copyWith(
        appearanceCount: appearances.length,
      );
      final lessonId = teaser.lessonId;

      var lessonRes = <dynamic>[];
      if (lessonId != null) {
        lessonRes =
            await _client
                    .from(Tables.lessonResources)
                    .select()
                    .eq(ResourceColumns.lessonId, lessonId)
                    .order(ResourceColumns.displayOrder)
                as List<dynamic>;
      }

      final progress = progressRows.cast<Map<String, dynamic>>();
      final learnt =
          progress.isNotEmpty &&
          progress.first[QuestionProgressColumns.learntAt] != null;

      // Fire-and-forget analytics event so the reader renders without waiting
      // on an extra RPC round-trip.
      unawaited(
        _client
            .rpc(
              RpcFunctions.recordStudyEvent,
              params: {
                StudyEventParams.kind: 'opened_pyq',
                StudyEventParams.questionId: questionId,
                StudyEventParams.lessonId: lessonId,
              },
            )
            .then((_) {}, onError: (_) {}),
      );

      return Success(
        PyqDetail(
          teaser: teaser,
          appearances: appearances,
          textbookRefs: refRows
              .cast<Map<String, dynamic>>()
              .map(TextbookCitation.fromJson)
              .toList(),
          lessonResources: lessonRes
              .cast<Map<String, dynamic>>()
              .map(ResourceLink.fromJson)
              .toList(),
          questionResources: qRes
              .cast<Map<String, dynamic>>()
              .map(ResourceLink.fromJson)
              .toList(),
          sampleAnswer: q[QuestionColumns.sampleAnswer] as String?,
          canReadSample: q[QuestionColumns.answersVisible] == true,
          questionLearnt: learnt,
          optionA: q[QuestionColumns.optionA] as String?,
          optionB: q[QuestionColumns.optionB] as String?,
          optionC: q[QuestionColumns.optionC] as String?,
          optionD: q[QuestionColumns.optionD] as String?,
          correctOption: q[QuestionColumns.correctOption] as String?,
          explanationText: q[QuestionColumns.explanationText] as String?,
          explanationDeep: q[QuestionColumns.explanationDeep] as String?,
        ),
      );
    } catch (e) {
      return Failure(
        UserFacingError.from(e, fallback: 'Could not load this question.'),
      );
    }
  }

  /// PostgREST puts `.inFilter` values on the GET URL, so a subject with
  /// 1k+ question ids would blow past typical 8KB limits and look hung.
  /// We also page with `.range` because the API `max_rows` cap is 1000.
  Future<List<Map<String, dynamic>>> _inFilterSelect({
    required String table,
    required String column,
    required List<String> ids,
    String select = '*',
    List<String> orderColumns = const ['id'],
    bool activeOnly = false,
  }) async {
    if (ids.isEmpty) return const [];
    const chunkSize = 80;
    const maxParallelChunks = 4;
    const pageSize = 1000;
    final orders = orderColumns.isEmpty ? const ['id'] : orderColumns;

    Future<List<Map<String, dynamic>>> fetchChunk(List<String> chunk) async {
      final chunkRows = <Map<String, dynamic>>[];
      var from = 0;
      while (true) {
        var query = _client.from(table).select(select).inFilter(column, chunk);
        if (activeOnly) {
          query = query.eq(QuestionColumns.isActive, true);
        }
        var ordered = query.order(orders.first);
        for (var o = 1; o < orders.length; o++) {
          ordered = ordered.order(orders[o]);
        }
        final page = await ordered.range(from, from + pageSize - 1);
        final list = List<Map<String, dynamic>>.from(page as List);
        chunkRows.addAll(list);
        if (list.length < pageSize) break;
        from += pageSize;
      }
      return chunkRows;
    }

    final chunks = <List<String>>[
      for (var i = 0; i < ids.length; i += chunkSize)
        ids.sublist(i, i + chunkSize > ids.length ? ids.length : i + chunkSize),
    ];
    final rows = <Map<String, dynamic>>[];
    for (var b = 0; b < chunks.length; b += maxParallelChunks) {
      final batchEnd = b + maxParallelChunks > chunks.length
          ? chunks.length
          : b + maxParallelChunks;
      final batchResults = await Future.wait([
        for (var c = b; c < batchEnd; c++) fetchChunk(chunks[c]),
      ]);
      for (final chunkRows in batchResults) {
        rows.addAll(chunkRows);
      }
    }
    return rows;
  }

  Future<Result<void>> markLearnt(String questionId) async {
    try {
      await _client.rpc(
        RpcFunctions.markQuestionLearnt,
        params: {MarkLearntParams.questionId: questionId},
      );
      return const Success(null);
    } catch (e) {
      return Failure(
        UserFacingError.from(e, fallback: 'Could not mark as learnt.'),
      );
    }
  }
}

@Riverpod(keepAlive: true)
PyqRepository pyqRepository(Ref ref) {
  return PyqRepository(ref.watch(supabaseClientProvider));
}
