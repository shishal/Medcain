/// Revision priority (MoSCoW) — how hard a student should chase a question.
///
/// Matches the Postgres `question_difficulty` enum, whose values are now
/// `must` / `should` / `could`. The column kept its old name; there is no
/// easy/medium/hard scale anywhere. Optional on import: a blank cell in the
/// Questions CSV lands on [should], so treat that as "unremarkable", not as a
/// deliberate tag.
enum QuestionPriority {
  // Declared in the order students scan a paper, so `values` is the UI order.
  must,
  should,
  could;

  static QuestionPriority fromString(String value) {
    return switch (value.toLowerCase().trim()) {
      'could' => QuestionPriority.could,
      'must' => QuestionPriority.must,
      _ => QuestionPriority.should,
    };
  }

  String get dbValue => name;

  String get label => switch (this) {
    QuestionPriority.could => 'Could',
    QuestionPriority.should => 'Should',
    QuestionPriority.must => 'Must',
  };

  /// [should] is the import default, so it carries no signal worth a chip.
  /// Must and Could are deliberate tags and are worth showing.
  bool get isNoteworthy => this != QuestionPriority.should;
}

/// `create_practice_session` `p_source_filter` values.
enum QuestionSourceFilter {
  unattempted,
  incorrect,
  bookmarked,
  all;

  static QuestionSourceFilter fromString(String value) {
    return switch (value.toLowerCase()) {
      'incorrect' => QuestionSourceFilter.incorrect,
      'bookmarked' => QuestionSourceFilter.bookmarked,
      'all' => QuestionSourceFilter.all,
      _ => QuestionSourceFilter.unattempted,
    };
  }

  String get dbValue => name;

  String get label => switch (this) {
    QuestionSourceFilter.unattempted => 'Unattempted',
    QuestionSourceFilter.incorrect => 'Previously Incorrect',
    QuestionSourceFilter.bookmarked => 'Bookmarked',
    QuestionSourceFilter.all => 'All',
  };

  String get subtitle => switch (this) {
    QuestionSourceFilter.unattempted => 'Questions you have not answered yet',
    QuestionSourceFilter.incorrect => 'Ones you got wrong last time',
    QuestionSourceFilter.bookmarked => 'From your bookmarks',
    QuestionSourceFilter.all => 'Entire question bank you can access',
  };
}

/// `tests.feedback_timing`: Tutor, Exam, or Reading.
///
/// [reading] does not start an attempt. The student scrolls questions with
/// the answer already open.
enum FeedbackTiming {
  immediate,
  onSubmit,
  reading;

  static FeedbackTiming fromString(String value) {
    return switch (value.toLowerCase()) {
      'immediate' => FeedbackTiming.immediate,
      'reading' => FeedbackTiming.reading,
      _ => FeedbackTiming.onSubmit,
    };
  }

  String get dbValue => switch (this) {
    FeedbackTiming.immediate => 'immediate',
    FeedbackTiming.onSubmit => 'on_submit',
    FeedbackTiming.reading => 'reading',
  };

  /// Labels students already know from other QBanks.
  String get label => switch (this) {
    FeedbackTiming.immediate => 'Tutor Mode',
    FeedbackTiming.onSubmit => 'Exam Mode',
    FeedbackTiming.reading => 'Reading Mode',
  };

  String get subtitle => switch (this) {
    FeedbackTiming.immediate =>
      'See the answer and explanation after each question',
    FeedbackTiming.onSubmit => 'See everything at the end, like a real test',
    FeedbackTiming.reading =>
      'Scroll through each question with the answer already open',
  };
}

/// `tests.show_explanation_level`.
enum ExplanationLevel {
  none,
  answerOnly,
  full;

  static ExplanationLevel fromString(String value) {
    return switch (value.toLowerCase()) {
      'none' => ExplanationLevel.none,
      'full' => ExplanationLevel.full,
      _ => ExplanationLevel.answerOnly,
    };
  }

  String get dbValue => switch (this) {
    ExplanationLevel.none => 'none',
    ExplanationLevel.answerOnly => 'answer_only',
    ExplanationLevel.full => 'full',
  };

  String get label => switch (this) {
    ExplanationLevel.none => 'None',
    ExplanationLevel.answerOnly => 'Answer only',
    ExplanationLevel.full => 'Full explanation',
  };
}
