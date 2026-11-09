import 'package:flutter_test/flutter_test.dart';
import 'package:medico/features/practice/domain/practice_builder_draft.dart';
import 'package:medico/features/practice/domain/practice_enums.dart';

void main() {
  test('lessonIds stay on the draft used for lesson-scoped MCQ practice', () {
    const draft = PracticeBuilderDraft(
      sourceFilter: QuestionSourceFilter.all,
      lessonIds: {'lesson-1'},
    );
    expect(draft.lessonIds, {'lesson-1'});
    expect(draft.copyWith(questionCount: 5).lessonIds, {'lesson-1'});
  });

  test('lesson scope can be cleared without dropping other filters', () {
    const draft = PracticeBuilderDraft(
      lessonIds: {'lesson-1'},
      scopeLabel: 'Cell',
      sourceFilter: QuestionSourceFilter.all,
    );
    expect(draft.lessonScopeMessage, 'Only MCQs from Cell');

    final cleared = draft.withoutLessonScope();
    expect(cleared.lessonIds, isEmpty);
    expect(cleared.scopeLabel, isNull);
    expect(cleared.lessonScopeMessage, isNull);
    expect(cleared.sourceFilter, QuestionSourceFilter.all);
  });
}
