import 'dart:math' as math;

import '../../../core/supabase/tables.dart';
import 'plan_limits.dart';
import 'practice_catalog.dart';
import 'practice_enums.dart';

/// Form state for the Practice Builder.
///
/// Immutable so "Practice Similar Again" can pass a pre-filled copy via
/// the route. [clampedTo] re-applies the current plan's limits — never trust
/// stored filters blindly if the user's plan changed.
class PracticeBuilderDraft {
  const PracticeBuilderDraft({
    this.selectedSubjectIds = const {},
    this.selectedTopicIds = const {},
    this.selectedTagIds = const {},
    this.selectedDifficulties = const {},
    this.sourceFilter = QuestionSourceFilter.unattempted,
    this.questionCount = 10,
    this.feedbackTiming = FeedbackTiming.immediate,
    this.explanationLevel = ExplanationLevel.answerOnly,
    this.timerEnabled = true,
    this.timerMinutes = 10,
    this.negativeMarking = false,
    this.lessonIds = const {},
    this.scopeLabel,
  });

  /// Empty set = all subjects. [Set] so toggling a chip is O(1) contains-check.
  final Set<String> selectedSubjectIds;
  final Set<String> selectedTopicIds;
  final Set<String> selectedTagIds;
  final Set<QuestionPriority> selectedDifficulties;
  final QuestionSourceFilter sourceFilter;
  final int questionCount;
  final FeedbackTiming feedbackTiming;
  final ExplanationLevel explanationLevel;
  final bool timerEnabled;
  final int timerMinutes;
  final bool negativeMarking;

  /// When set, the generator only picks MCQs on these lessons.
  final Set<String> lessonIds;

  /// Lesson title shown on the builder. Not sent to Postgres.
  final String? scopeLabel;

  /// Banner copy when the session is limited to [lessonIds].
  String? get lessonScopeMessage {
    if (lessonIds.isEmpty) return null;
    final label = scopeLabel?.trim();
    if (label != null && label.isNotEmpty) {
      return 'Only MCQs from $label';
    }
    return 'Only MCQs from your last lesson';
  }

  /// True when any subject / topic / tag chip is on.
  bool get hasContentFilters =>
      selectedSubjectIds.isNotEmpty ||
      selectedTopicIds.isNotEmpty ||
      selectedTagIds.isNotEmpty;

  /// Rebuilds the form from a practice `tests` row.
  ///
  /// Prefers the student's *requested* count/explanation from the JSON so a
  /// later plan change can grant more — [clampedTo] still caps to the
  /// current plan before anything is sent.
  factory PracticeBuilderDraft.fromPracticeTestRow(Map<String, dynamic> row) {
    final criteria = _asMap(row[TestColumns.practiceFilterCriteria]);

    final questionCount =
        _asNullableInt(
          criteria[PracticeFilterCriteriaKeys.requestedQuestionCount],
        ) ??
        _asInt(row[TestColumns.totalQuestions], fallback: 10);

    final hasTimerKey = criteria.containsKey(
      PracticeFilterCriteriaKeys.timerMinutes,
    );
    final timerMinutesRaw = criteria[PracticeFilterCriteriaKeys.timerMinutes];
    final timerEnabled = hasTimerKey
        ? timerMinutesRaw != null
        : (row[TestColumns.timerEnabled] as bool? ?? true);
    final timerMinutes = timerMinutesRaw != null
        ? _asInt(timerMinutesRaw, fallback: questionCount)
        : questionCount;

    final requestedExplanation =
        criteria[PracticeFilterCriteriaKeys.requestedExplanationLevel]
            as String?;

    return PracticeBuilderDraft(
      selectedSubjectIds: _stringSet(
        criteria[PracticeFilterCriteriaKeys.subjectIds],
      ),
      selectedTopicIds: _stringSet(
        criteria[PracticeFilterCriteriaKeys.topicIds],
      ),
      selectedTagIds: _stringSet(criteria[PracticeFilterCriteriaKeys.tagIds]),
      sourceFilter: QuestionSourceFilter.fromString(
        criteria[PracticeFilterCriteriaKeys.sourceFilter] as String? ??
            QuestionSourceFilter.unattempted.dbValue,
      ),
      questionCount: questionCount < 1 ? 1 : questionCount,
      feedbackTiming: FeedbackTiming.fromString(
        row[TestColumns.feedbackTiming] as String? ??
            FeedbackTiming.immediate.dbValue,
      ),
      explanationLevel: ExplanationLevel.fromString(
        requestedExplanation ??
            row[TestColumns.showExplanationLevel] as String? ??
            ExplanationLevel.answerOnly.dbValue,
      ),
      timerEnabled: timerEnabled,
      timerMinutes: timerMinutes < 1 ? 1 : timerMinutes,
      negativeMarking:
          criteria[PracticeFilterCriteriaKeys.negativeMarking] as bool? ??
          false,
      lessonIds: _stringSet(criteria[PracticeFilterCriteriaKeys.lessonIds]),
    );
  }

  /// Drop IDs that no longer exist; infer subjects from remaining topics.
  PracticeBuilderDraft alignedWithCatalog(PracticeCatalog catalog) {
    final topicById = {for (final topic in catalog.topics) topic.id: topic};
    final knownTagIds = catalog.tags.map((t) => t.id).toSet();
    final knownSubjectIds = catalog.subjects.map((s) => s.id).toSet();

    final topics = selectedTopicIds.where(topicById.containsKey).toSet();
    final tags = selectedTagIds.where(knownTagIds.contains).toSet();
    final subjects = selectedSubjectIds.isEmpty
        ? topics.map((id) => topicById[id]!.subjectId).toSet()
        : selectedSubjectIds.where(knownSubjectIds.contains).toSet();

    return copyWith(
      selectedSubjectIds: subjects,
      selectedTopicIds: topics,
      selectedTagIds: tags,
    );
  }

  /// Topic IDs to send to the RPC. Null means "no topic filter".
  ///
  /// A subject-only selection is sent as [resolvedSubjectIds] instead, so
  /// paper-tagged MCQs with an empty topic still match that subject.
  List<String>? resolvedTopicIds(PracticeCatalog catalog) {
    if (selectedTopicIds.isEmpty) return null;
    final known = catalog.topics.map((topic) => topic.id).toSet();
    final ids = selectedTopicIds.where(known.contains).toList();
    return ids.isEmpty ? null : ids;
  }

  /// Subject IDs to send when no topic is chosen. Null means every subject.
  ///
  /// Ignored once topics are selected — a topic is already inside a subject.
  List<String>? resolvedSubjectIds(PracticeCatalog catalog) {
    if (selectedTopicIds.isNotEmpty || selectedSubjectIds.isEmpty) return null;
    final known = catalog.subjects.map((subject) => subject.id).toSet();
    final ids = selectedSubjectIds.where(known.contains).toList();
    return ids.isEmpty ? null : ids;
  }

  List<String>? get resolvedTagIds =>
      selectedTagIds.isEmpty ? null : selectedTagIds.toList();

  /// Always null — priority is not a practice-session filter in the app.
  List<QuestionPriority>? get resolvedDifficulties => null;

  /// Minutes to send: null turns the timer off on the server.
  int? get resolvedTimerMinutes =>
      timerEnabled ? math.max(timerMinutes, 1) : null;

  PracticeBuilderDraft toggleSubject(String id, PracticeCatalog catalog) {
    final next = {...selectedSubjectIds};
    if (next.contains(id)) {
      next.remove(id);
      final drop = catalog.topics
          .where((t) => t.subjectId == id)
          .map((t) => t.id)
          .toSet();
      return copyWith(
        selectedSubjectIds: next,
        selectedTopicIds: selectedTopicIds.difference(drop),
      );
    }
    next.add(id);
    return copyWith(selectedSubjectIds: next);
  }

  PracticeBuilderDraft toggleTopic(String id) =>
      copyWith(selectedTopicIds: _toggle(selectedTopicIds, id));

  PracticeBuilderDraft toggleTag(String id) =>
      copyWith(selectedTagIds: _toggle(selectedTagIds, id));

  PracticeBuilderDraft clearContentFilters() => copyWith(
    selectedSubjectIds: const {},
    selectedTopicIds: const {},
    selectedTagIds: const {},
    selectedDifficulties: const {},
  );

  PracticeBuilderDraft withQuestionCount(int count) {
    var minutes = timerMinutes;
    if (minutes == questionCount) minutes = count;
    return copyWith(questionCount: count, timerMinutes: minutes);
  }

  /// `{...set}` copies then add/remove so the draft stays immutable.
  static Set<T> _toggle<T>(Set<T> current, T value) {
    final next = {...current};
    if (!next.add(value)) next.remove(value);
    return next;
  }

  /// Drop illegal selections and cap the count to what this plan allows.
  PracticeBuilderDraft clampedTo(PracticePlanContext ctx) {
    final maxQ = ctx.maxSelectableQuestions;
    var count = questionCount;
    if (maxQ <= 0) {
      count = 1;
    } else {
      count = count.clamp(1, maxQ);
    }

    var minutes = timerMinutes < 1 ? 1 : timerMinutes;
    // Keep the 1-min-per-question default in sync until the student edits it.
    if (minutes == questionCount) minutes = count;

    final explanation = ctx.limits.allowFullExplanation
        ? explanationLevel
        : (explanationLevel == ExplanationLevel.full
              ? ExplanationLevel.answerOnly
              : explanationLevel);

    return copyWith(
      selectedTagIds: ctx.limits.allowTagFilter ? selectedTagIds : const {},
      selectedDifficulties: const {},
      questionCount: count,
      explanationLevel: explanation,
      timerEnabled: ctx.limits.allowTimerToggle ? timerEnabled : true,
      timerMinutes: minutes,
      negativeMarking: ctx.limits.allowNegativeMarkingToggle
          ? negativeMarking
          : false,
    );
  }

  PracticeBuilderDraft copyWith({
    Set<String>? selectedSubjectIds,
    Set<String>? selectedTopicIds,
    Set<String>? selectedTagIds,
    Set<QuestionPriority>? selectedDifficulties,
    QuestionSourceFilter? sourceFilter,
    int? questionCount,
    FeedbackTiming? feedbackTiming,
    ExplanationLevel? explanationLevel,
    bool? timerEnabled,
    int? timerMinutes,
    bool? negativeMarking,
    Set<String>? lessonIds,
    String? scopeLabel,
    bool clearScopeLabel = false,
  }) {
    return PracticeBuilderDraft(
      selectedSubjectIds: selectedSubjectIds ?? this.selectedSubjectIds,
      selectedTopicIds: selectedTopicIds ?? this.selectedTopicIds,
      selectedTagIds: selectedTagIds ?? this.selectedTagIds,
      selectedDifficulties: selectedDifficulties ?? this.selectedDifficulties,
      sourceFilter: sourceFilter ?? this.sourceFilter,
      questionCount: questionCount ?? this.questionCount,
      feedbackTiming: feedbackTiming ?? this.feedbackTiming,
      explanationLevel: explanationLevel ?? this.explanationLevel,
      timerEnabled: timerEnabled ?? this.timerEnabled,
      timerMinutes: timerMinutes ?? this.timerMinutes,
      negativeMarking: negativeMarking ?? this.negativeMarking,
      lessonIds: lessonIds ?? this.lessonIds,
      scopeLabel: clearScopeLabel ? null : (scopeLabel ?? this.scopeLabel),
    );
  }

  /// Drop the lesson limit and practice the whole bank again.
  PracticeBuilderDraft withoutLessonScope() =>
      copyWith(lessonIds: const {}, clearScopeLabel: true);

  static Map<String, dynamic> _asMap(Object? value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return const {};
  }

  static Set<String> _stringSet(Object? value) {
    if (value is! List) return const {};
    return {
      for (final item in value)
        if (item != null) item.toString(),
    };
  }

  static int _asInt(Object? value, {int fallback = 0}) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString()) ?? fallback;
  }

  static int? _asNullableInt(Object? value) {
    if (value == null) return null;
    return _asInt(value);
  }
}
