import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:medico/core/utils/result.dart';
import 'package:medico/features/bookmarks/presentation/providers/bookmarks_provider.dart';
import 'package:medico/features/practice/domain/practice_enums.dart';
import 'package:medico/features/practice/presentation/widgets/reading_question_card.dart';
import 'package:medico/features/tests/domain/player_question.dart';
import 'package:medico/features/tests/domain/question_option.dart';

void main() {
  const question = PlayerQuestion(
    id: 'q1',
    orderIndex: 0,
    sectionNumber: 1,
    questionText: 'Which valve is most often affected in rheumatic fever?',
    optionA: 'Aortic',
    optionB: 'Mitral',
    optionC: 'Pulmonary',
    optionD: 'Tricuspid',
    correctOption: QuestionOption.b,
    explanationText: 'The mitral valve takes the damage.',
  );

  Future<void> pump(WidgetTester tester, ExplanationLevel level) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [bookmarkedIdsProvider.overrideWith(_StubBookmarkedIds.new)],
        child: MaterialApp(
          home: Scaffold(
            body: ReadingQuestionCard(
              number: 1,
              question: question,
              explanationLevel: level,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows the stem and marks the answer', (tester) async {
    await pump(tester, ExplanationLevel.answerOnly);

    expect(
      find.text('Which valve is most often affected in rheumatic fever?'),
      findsOneWidget,
    );
    expect(find.text('Mitral'), findsOneWidget);
    expect(find.text('Answer B'), findsOneWidget);
    expect(find.text('The mitral valve takes the damage.'), findsNothing);
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
  });

  testWidgets('shows the explanation when the session allows it', (
    tester,
  ) async {
    await pump(tester, ExplanationLevel.full);

    expect(find.text('The mitral valve takes the damage.'), findsOneWidget);
    expect(find.text('Explanation'), findsOneWidget);
  });
}

class _StubBookmarkedIds extends BookmarkedIds {
  @override
  Future<Set<String>> build() async => {};

  @override
  Future<Result<void>> toggle(String questionId) async => const Success(null);
}
