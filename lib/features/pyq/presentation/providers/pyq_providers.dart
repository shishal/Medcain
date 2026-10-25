import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../core/utils/result.dart';
import '../../../profile/domain/plan_tier.dart';
import '../../../profile/presentation/providers/current_plan_provider.dart';
import '../../../profile/presentation/providers/user_profile_provider.dart';
import '../../data/pyq_repository.dart';
import '../../domain/pyq_models.dart';
import '../../domain/subject_pyq_filters.dart';
import '../../../practice/domain/practice_enums.dart';

part 'pyq_providers.g.dart';

@riverpod
Future<PyqLessonFeed> lessonPyqs(Ref ref, String lessonId) async {
  final profile = await ref.watch(userProfileProvider.future);
  final result = await ref
      .watch(pyqRepositoryProvider)
      .fetchTeasersForLesson(
        lessonId: lessonId,
        universityId: profile?.universityId,
      );
  return switch (result) {
    Success(:final value) => value,
    Failure(:final message) => throw Exception(message),
  };
}

/// "More on this topic" links for one lesson. This used to be an initState
/// fetch into local widget state, so it never refreshed and a failure showed
/// as an empty section.
@riverpod
Future<List<ResourceLink>> lessonResources(Ref ref, String lessonId) async {
  final result = await ref
      .watch(pyqRepositoryProvider)
      .fetchLessonResources(lessonId);
  return switch (result) {
    Success(:final value) => value,
    Failure(:final message) => throw Exception(message),
  };
}

/// Kept alive so leaving the subject and coming back does not re-show
/// the loading spinner while the feed is fetched again.
@Riverpod(keepAlive: true)
Future<PyqSubjectFeed> subjectPyqs(Ref ref, String subjectId) async {
  final profile = await ref.watch(userProfileProvider.future);
  final result = await ref
      .watch(pyqRepositoryProvider)
      .fetchTeasersForSubject(
        subjectId: subjectId,
        universityId: profile?.universityId,
      );
  return switch (result) {
    Success(:final value) => value,
    Failure(:final message) => throw Exception(message),
  };
}

/// University / year / exam type / paper / MCQ-or-theory / chapter picks for
/// one subject's PYQ screen and its paper outlines.
@Riverpod(keepAlive: true)
class SubjectPyqFilters extends _$SubjectPyqFilters {
  @override
  SubjectPyqFilter build(String subjectId) => const SubjectPyqFilter();

  // Sitting-level picks are checked against the loaded feed so that changing
  // a parent (say University) clears a child (say Year) that no longer exists.
  void _set(SubjectPyqFilter next) {
    final teasers =
        ref.read(subjectPyqsProvider(subjectId)).value?.teasers ?? const [];
    state = reconcileFilter(next, teasers);
  }

  void setUniversity(String? universityId) =>
      _set(state.copyWith(universityId: universityId));

  void setYear(int? year) => _set(state.copyWith(year: year));

  void setExamType(PaperExamType? examType) =>
      _set(state.copyWith(examType: examType));

  void setPaperName(String? paperName) =>
      _set(state.copyWith(paperName: paperName));

  void setFormat({bool? isMcq}) => _set(state.copyWith(isMcq: isMcq));

  void setTopicId(String? topicId) => _set(state.copyWith(topicId: topicId));

  void togglePriority(QuestionPriority value) {
    final next = {...state.priorities};
    if (!next.add(value)) next.remove(value);
    _set(state.copyWith(priorities: next));
  }

  void clear() {
    state = const SubjectPyqFilter();
  }
}

@riverpod
Future<PyqDetail> pyqDetail(Ref ref, String questionId) async {
  final plan = ref.watch(currentPlanProvider).value ?? PlanTier.free;
  final result = await ref
      .watch(pyqRepositoryProvider)
      .fetchDetail(questionId: questionId, plan: plan);
  return switch (result) {
    Success(:final value) => value,
    Failure(:final message) => throw Exception(message),
  };
}
