import '../../../core/supabase/tables.dart';
import 'question_option.dart';

/// One question in a player session, already joined from `test_questions`.
class PlayerQuestion {
  const PlayerQuestion({
    required this.id,
    required this.orderIndex,
    required this.sectionNumber,
    required this.questionText,
    required this.optionA,
    required this.optionB,
    required this.optionC,
    required this.optionD,
    required this.correctOption,
    this.explanationText,
    this.explanationDeep,
    this.explanationVideoUrl,
    this.imageUrl,
  });

  final String id;
  final int orderIndex;
  final int sectionNumber;
  final String questionText;
  final String optionA;
  final String optionB;
  final String optionC;
  final String optionD;
  final QuestionOption correctOption;
  final String? explanationText;
  final String? explanationDeep;
  final String? explanationVideoUrl;
  final String? imageUrl;

  String textFor(QuestionOption option) => switch (option) {
    QuestionOption.a => optionA,
    QuestionOption.b => optionB,
    QuestionOption.c => optionC,
    QuestionOption.d => optionD,
  };

  factory PlayerQuestion.fromJoinJson(Map<String, dynamic> json) {
    final nested = json[TestQuestionColumns.questionEmbed];
    final question = nested is Map<String, dynamic>
        ? nested
        : (nested is List && nested.isNotEmpty
              ? nested.first as Map<String, dynamic>
              : <String, dynamic>{});

    return PlayerQuestion(
      id: question[QuestionColumns.id] as String,
      orderIndex: _asInt(json[TestQuestionColumns.orderIndex] ?? 0),
      sectionNumber: _asInt(json[TestQuestionColumns.sectionNumber] ?? 1),
      questionText: question[QuestionColumns.questionText] as String? ?? '',
      optionA: question[QuestionColumns.optionA] as String? ?? '',
      optionB: question[QuestionColumns.optionB] as String? ?? '',
      optionC: question[QuestionColumns.optionC] as String? ?? '',
      optionD: question[QuestionColumns.optionD] as String? ?? '',
      correctOption: QuestionOption.fromString(
        question[QuestionColumns.correctOption] as String? ?? 'A',
      ),
      explanationText: question[QuestionColumns.explanationText] as String?,
      explanationDeep: question[QuestionColumns.explanationDeep] as String?,
      explanationVideoUrl:
          question[QuestionColumns.explanationVideoUrl] as String?,
      imageUrl: question[QuestionColumns.imageUrl] as String?,
    );
  }

  /// Flat JSON for the local attempt snapshot (not the nested PostgREST join).
  factory PlayerQuestion.fromSnapshotJson(Map<String, dynamic> json) {
    return PlayerQuestion(
      id: json[QuestionColumns.id] as String,
      orderIndex: _asInt(json[TestQuestionColumns.orderIndex] ?? 0),
      sectionNumber: _asInt(json[TestQuestionColumns.sectionNumber] ?? 1),
      questionText: json[QuestionColumns.questionText] as String? ?? '',
      optionA: json[QuestionColumns.optionA] as String? ?? '',
      optionB: json[QuestionColumns.optionB] as String? ?? '',
      optionC: json[QuestionColumns.optionC] as String? ?? '',
      optionD: json[QuestionColumns.optionD] as String? ?? '',
      correctOption: QuestionOption.fromString(
        json[QuestionColumns.correctOption] as String? ?? 'A',
      ),
      explanationText: json[QuestionColumns.explanationText] as String?,
      explanationDeep: json[QuestionColumns.explanationDeep] as String?,
      explanationVideoUrl: json[QuestionColumns.explanationVideoUrl] as String?,
      imageUrl: json[QuestionColumns.imageUrl] as String?,
    );
  }

  Map<String, dynamic> toSnapshotJson() {
    return {
      QuestionColumns.id: id,
      TestQuestionColumns.orderIndex: orderIndex,
      TestQuestionColumns.sectionNumber: sectionNumber,
      QuestionColumns.questionText: questionText,
      QuestionColumns.optionA: optionA,
      QuestionColumns.optionB: optionB,
      QuestionColumns.optionC: optionC,
      QuestionColumns.optionD: optionD,
      QuestionColumns.correctOption: correctOption.dbValue,
      QuestionColumns.explanationText: explanationText,
      QuestionColumns.explanationDeep: explanationDeep,
      QuestionColumns.explanationVideoUrl: explanationVideoUrl,
      QuestionColumns.imageUrl: imageUrl,
    };
  }

  /// Sheet `exp_1` then `exp_2`, both markdown.
  static String? joinedExplanation(String? shortText, String? deepText) {
    final parts = <String>[
      if (shortText != null && shortText.trim().isNotEmpty) shortText.trim(),
      if (deepText != null && deepText.trim().isNotEmpty) deepText.trim(),
    ];
    if (parts.isEmpty) return null;
    return parts.join('\n\n');
  }

  static int _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.parse(value.toString());
  }
}
