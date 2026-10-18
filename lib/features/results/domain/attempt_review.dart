import '../../../core/supabase/tables.dart';
import '../../practice/domain/practice_enums.dart';
import '../../tests/domain/palette_cell.dart';
import '../../tests/domain/player_question.dart';
import '../../tests/domain/player_session_state.dart';
import '../../tests/domain/question_answer.dart';
import '../../tests/domain/question_option.dart';

/// One row from `test_questions`, before answers are merged.
///
/// [question] is null when `questions` RLS hid the embed (plan too low).
class ReviewSlot {
  const ReviewSlot({
    required this.questionId,
    required this.orderIndex,
    this.question,
  });

  final String questionId;
  final int orderIndex;
  final PlayerQuestion? question;
}

/// Reads a `test_questions` join row. A null/empty `question` embed is a
/// plan-locked slot, not a parse error — the review screen must not crash.
ReviewSlot? reviewSlotFromJoinJson(Map<String, dynamic> json) {
  final embed = json[TestQuestionColumns.questionEmbed];
  final embedMap = _asJsonMap(embed);
  final hasQuestion =
      embedMap != null && embedMap[QuestionColumns.id] is String;

  final question = hasQuestion ? PlayerQuestion.fromJoinJson(json) : null;
  final id = json[TestQuestionColumns.questionId] as String? ?? question?.id;
  if (id == null || id.isEmpty) return null;

  return ReviewSlot(
    questionId: id,
    orderIndex: _asInt(json[TestQuestionColumns.orderIndex] ?? 0),
    question: question,
  );
}

QuestionOption? parseSelectedOption(Object? raw) {
  if (raw == null) return null;
  final value = raw.toString().trim();
  if (value.isEmpty) return null;
  return QuestionOption.fromString(value);
}

/// One question on the solution review screen.
class ReviewItem {
  const ReviewItem({
    required this.questionId,
    required this.questionNumber,
    required this.explanationLevel,
    this.selectedOption,
    this.question,
  });

  final String questionId;
  final int questionNumber;
  final ExplanationLevel explanationLevel;
  final QuestionOption? selectedOption;

  /// Null when the `questions` row was hidden by RLS.
  final PlayerQuestion? question;

  bool get isPlanLocked => question == null;

  bool get isUnattempted => selectedOption == null;

  bool get isCorrect =>
      question != null && selectedOption == question!.correctOption;

  /// Practice spec §3: `none` only marks right/wrong — do not reveal the key.
  bool get highlightCorrectOption =>
      !isPlanLocked && explanationLevel != ExplanationLevel.none;

  /// Practice spec §3: explanation text only at `full`. The row may still
  /// contain `explanation_text` at `answer_only` — the UI must not show it.
  String? get visibleExplanation {
    if (isPlanLocked || explanationLevel != ExplanationLevel.full) {
      return null;
    }
    return PlayerQuestion.joinedExplanation(
      question?.explanationText,
      question?.explanationDeep,
    );
  }

  String? get visibleVideoUrl {
    if (isPlanLocked || explanationLevel != ExplanationLevel.full) {
      return null;
    }
    final raw = question?.explanationVideoUrl?.trim();
    if (raw == null || raw.isEmpty) return null;
    return raw;
  }

  String get statusLabel {
    if (isPlanLocked) return 'Unavailable';
    if (isUnattempted) return 'Skipped';
    return isCorrect ? 'Correct' : 'Incorrect';
  }

  String get yourAnswerLabel {
    if (isUnattempted) return 'You skipped this question.';
    return 'Your answer: ${selectedOption!.label}';
  }

  String? get correctAnswerLabel {
    if (!highlightCorrectOption || question == null) return null;
    return 'Correct answer: ${question!.correctOption.label}';
  }

  OptionVisual visualFor(QuestionOption option) {
    if (isPlanLocked || question == null) return OptionVisual.idle;
    final correct = question!.correctOption;
    final selected = selectedOption;
    if (selected != null) {
      if (option == selected && option == correct) {
        return OptionVisual.chosenCorrect;
      }
      if (option == selected && option != correct) {
        return OptionVisual.chosenIncorrect;
      }
    }
    if (highlightCorrectOption && option == correct) {
      return OptionVisual.revealedCorrect;
    }
    return OptionVisual.idle;
  }

  PaletteCell get paletteCell {
    if (isPlanLocked) {
      return PaletteCell(
        questionNumber: questionNumber,
        kind: PaletteKind.notVisited,
        markedForReview: false,
        isTutorMode: true,
      );
    }
    return PaletteCell.fromAnswer(
      questionNumber: questionNumber,
      answer: QuestionAnswer(visited: true, selectedOption: selectedOption),
      correctOption: question!.correctOption,
      feedbackTiming: FeedbackTiming.immediate,
    );
  }
}

/// Submitted attempt's per-question review payload.
class AttemptReview {
  const AttemptReview({
    required this.attemptId,
    required this.testId,
    required this.testTitle,
    required this.explanationLevel,
    required this.items,
    this.isEphemeralPractice = false,
  });

  final String attemptId;
  final String testId;
  final String testTitle;
  final ExplanationLevel explanationLevel;
  final bool isEphemeralPractice;
  final List<ReviewItem> items;

  factory AttemptReview.merge({
    required String attemptId,
    required String testId,
    required String title,
    required ExplanationLevel explanationLevel,
    required List<ReviewSlot> slots,
    required Map<String, QuestionOption?> answers,
    bool isEphemeralPractice = false,
  }) {
    final ordered = [...slots]
      ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
    return AttemptReview(
      attemptId: attemptId,
      testId: testId,
      testTitle: title,
      explanationLevel: explanationLevel,
      isEphemeralPractice: isEphemeralPractice,
      items: [
        for (var i = 0; i < ordered.length; i++)
          ReviewItem(
            questionId: ordered[i].questionId,
            questionNumber: i + 1,
            explanationLevel: explanationLevel,
            selectedOption: answers[ordered[i].questionId],
            question: ordered[i].question,
          ),
      ],
    );
  }
}

Map<String, dynamic>? _asJsonMap(Object? raw) {
  if (raw is Map<String, dynamic>) return raw;
  if (raw is Map) return Map<String, dynamic>.from(raw);
  if (raw is List && raw.isNotEmpty) return _asJsonMap(raw.first);
  return null;
}

int _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString()) ?? 0;
}
