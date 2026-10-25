import '../../../core/supabase/tables.dart';
import '../../practice/domain/practice_enums.dart';
import '../../profile/domain/plan_tier.dart';
import 'question_format.dart';

/// What kind of sitting a paper was, from `exam_papers.exam_type`.
enum PaperExamType {
  prof,
  supply,
  preProf,
  internal;

  /// Unknown or missing values count as the university professional exam,
  /// the same default the database column uses.
  static PaperExamType fromDb(String? value) => switch (value) {
    'supply' => PaperExamType.supply,
    'pre_prof' => PaperExamType.preProf,
    'internal' => PaperExamType.internal,
    _ => PaperExamType.prof,
  };

  String get label => switch (this) {
    PaperExamType.prof => 'Prof',
    PaperExamType.supply => 'Supply',
    PaperExamType.preProf => 'Pre-prof',
    PaperExamType.internal => 'Internal',
  };

  /// Pre-prof and internal papers are set by a campus, not the university.
  bool get isCampusLevel =>
      this == PaperExamType.preProf || this == PaperExamType.internal;
}

/// One exam sitting a question appeared in (an `exam_papers` row).
class PaperSitting {
  const PaperSitting({
    required this.universityId,
    this.collegeId,
    this.examType = PaperExamType.prof,
    required this.year,
    this.month,
    this.paperName,
  });

  final String universityId;
  final String? collegeId;
  final PaperExamType examType;
  final int year;
  final int? month;

  /// Printed paper label such as `Paper I`. Null when the sheet left it blank.
  final String? paperName;

  /// Same text the paper chips show, e.g. `October · Paper I`.
  String get label => paperSittingLabel(month: month, paperName: paperName);
}

class PyqTeaser {
  const PyqTeaser({
    required this.id,
    this.lessonId,
    this.topicId,
    required this.questionText,
    this.marks,
    required this.requiredPlan,
    required this.appearanceCount,
    this.kind = 'pyq_theory',
    this.priority = QuestionPriority.should,
    this.textbookLine,
    this.appearanceYears = const [],
    this.paperNames = const [],
    this.topicName,
    this.lessonName,
    this.sittings = const [],
  });

  final String id;
  final String? lessonId;
  final String? topicId;
  final String questionText;
  final num? marks;
  final PlanTier requiredPlan;
  final int appearanceCount;
  final String kind;
  final QuestionPriority priority;
  final String? textbookLine;
  final List<int> appearanceYears;

  /// Paper labels from the selected university (e.g. Paper I).
  final List<String> paperNames;
  final String? topicName;
  final String? lessonName;

  /// Every sitting this question appeared in, across all universities.
  /// Only the subject feed fills this; [appearanceYears] and [paperNames]
  /// stay scoped to the student's own university.
  final List<PaperSitting> sittings;

  QuestionFormat get format =>
      QuestionFormat.fromKindAndMarks(kind: kind, marks: marks);

  bool get isHighYield => appearanceCount >= 2;

  factory PyqTeaser.fromJson(Map<String, dynamic> json) {
    return PyqTeaser(
      id: json[PyqTeaserColumns.id] as String,
      lessonId: json[PyqTeaserColumns.lessonId] as String?,
      topicId: json[PyqTeaserColumns.topicId] as String?,
      questionText: json[PyqTeaserColumns.questionText] as String,
      marks: json[PyqTeaserColumns.marks] as num?,
      requiredPlan: PlanTier.fromString(
        json[PyqTeaserColumns.requiredPlan] as String? ?? 'free',
      ),
      appearanceCount: _asInt(json[PyqTeaserColumns.appearanceCount]),
      kind: json[PyqTeaserColumns.kind] as String? ?? 'pyq_theory',
      priority: QuestionPriority.fromString(
        json[PyqTeaserColumns.difficulty] as String? ??
            json[QuestionColumns.difficulty] as String? ??
            QuestionPriority.should.dbValue,
      ),
    );
  }

  PyqTeaser copyWith({
    String? textbookLine,
    List<int>? appearanceYears,
    int? appearanceCount,
    List<String>? paperNames,
    String? topicName,
    String? lessonName,
    String? topicId,
    QuestionPriority? priority,
    List<PaperSitting>? sittings,
  }) {
    return PyqTeaser(
      id: id,
      lessonId: lessonId,
      topicId: topicId ?? this.topicId,
      questionText: questionText,
      marks: marks,
      requiredPlan: requiredPlan,
      appearanceCount: appearanceCount ?? this.appearanceCount,
      kind: kind,
      priority: priority ?? this.priority,
      textbookLine: textbookLine ?? this.textbookLine,
      appearanceYears: appearanceYears ?? this.appearanceYears,
      paperNames: paperNames ?? this.paperNames,
      topicName: topicName ?? this.topicName,
      lessonName: lessonName ?? this.lessonName,
      sittings: sittings ?? this.sittings,
    );
  }
}

class PyqLessonFeed {
  const PyqLessonFeed({required this.teasers});

  final List<PyqTeaser> teasers;
}

class PyqChapter {
  const PyqChapter({required this.id, required this.name});

  final String id;
  final String name;
}

/// Subject PYQ list: mixed-topic papers, with chapter tags for filters.
class PyqSubjectFeed {
  const PyqSubjectFeed({
    required this.teasers,
    this.paperNames = const [],
    this.years = const [],
    this.chapters = const [],
  });

  final List<PyqTeaser> teasers;
  final List<String> paperNames;
  final List<int> years;
  final List<PyqChapter> chapters;
}

class ResourceLink {
  const ResourceLink({
    required this.id,
    required this.title,
    required this.url,
    this.sourceLabel,
    required this.isFree,
  });

  final String id;
  final String title;
  final String url;
  final String? sourceLabel;
  final bool isFree;

  factory ResourceLink.fromJson(Map<String, dynamic> json) {
    return ResourceLink(
      id: json[ResourceColumns.id] as String,
      title: json[ResourceColumns.title] as String,
      url: json[ResourceColumns.url] as String,
      sourceLabel: json[ResourceColumns.sourceLabel] as String?,
      isFree: json[ResourceColumns.isFree] as bool? ?? false,
    );
  }
}

class TextbookCitation {
  const TextbookCitation({
    required this.title,
    this.authors,
    this.edition,
    required this.page,
    this.sectionHeading,
    this.sheetKey,
  });

  final String title;
  final String? authors;
  final String? edition;
  final int page;
  final String? sectionHeading;
  final String? sheetKey;

  String get label {
    final ed = edition == null ? '' : ' ($edition)';
    final sec = sectionHeading == null ? '' : ' · $sectionHeading';
    return '$title$ed p. $page$sec';
  }

  factory TextbookCitation.fromJson(Map<String, dynamic> json) {
    final book = json[TextbookRefColumns.textbookEmbed];
    final map = book is Map<String, dynamic> ? book : <String, dynamic>{};
    return TextbookCitation(
      title: map[TextbookColumns.title] as String? ?? 'Textbook',
      authors: map[TextbookColumns.authors] as String?,
      edition: map[TextbookColumns.edition] as String?,
      page: _asInt(json[TextbookRefColumns.page]),
      sectionHeading: json[TextbookRefColumns.sectionHeading] as String?,
      sheetKey: map[TextbookColumns.sheetKey] as String?,
    );
  }
}

const examMonthNames = <String>[
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

/// Sheet months are stored as 1–12. Null when the paper has no month yet.
String? examMonthName(Object? value) {
  final month = _asIntOrNull(value);
  if (month == null || month < 1 || month > 12) return null;
  return examMonthNames[month - 1];
}

/// "October · Paper I", or just the paper label when the month is unknown.
String paperSittingLabel({Object? month, String? paperName}) {
  final name = (paperName == null || paperName.trim().isEmpty)
      ? 'Paper'
      : paperName.trim();
  final monthName = examMonthName(month);
  if (monthName == null) return name;
  return '$monthName · $name';
}

class ExamAppearance {
  const ExamAppearance({required this.year, required this.paperName});

  final int year;
  final String paperName;

  factory ExamAppearance.fromJson(Map<String, dynamic> json) {
    final paper = json[AppearanceColumns.examPaperEmbed];
    final map = paper is Map<String, dynamic> ? paper : <String, dynamic>{};
    return ExamAppearance(
      year: _asInt(map[ExamPaperColumns.examYear]),
      paperName: paperSittingLabel(
        month: map[ExamPaperColumns.examMonth],
        paperName: map[ExamPaperColumns.paperName] as String?,
      ),
    );
  }
}

int _asInt(Object? value) {
  return _asIntOrNull(value) ?? 0;
}

int? _asIntOrNull(Object? value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString());
}
