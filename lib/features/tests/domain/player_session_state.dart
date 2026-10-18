import '../../practice/domain/practice_enums.dart';
import 'attempt_score.dart';
import 'attempt_status.dart';
import 'local_attempt_snapshot.dart';
import 'palette_cell.dart';
import 'player_question.dart';
import 'question_answer.dart';
import 'question_option.dart';
import 'test_player_bundle.dart';

/// What the Tutor Mode panel should show after an option is locked.
///
/// Null in Exam Mode — that is the "no reveal until submit" guarantee.
class FeedbackReveal {
  const FeedbackReveal({
    required this.isCorrect,
    required this.highlightCorrectOption,
    this.explanationText,
  });

  final bool isCorrect;
  final bool highlightCorrectOption;
  final String? explanationText;
}

/// How one option chip should look. Exam Mode only uses [idle] / [selected].
enum OptionVisual {
  idle,
  selected,
  chosenCorrect,
  chosenIncorrect,
  revealedCorrect,
}

/// In-memory player session. Mutations return a new instance (immutable).
///
/// Answers live here and in a local JSON snapshot. Remaining time is always
/// computed from wall-clock elapsed time (spec §3), never stored as a countdown.
class PlayerSessionState {
  const PlayerSessionState({
    required this.attemptId,
    required this.testId,
    required this.title,
    required this.feedbackTiming,
    required this.explanationLevel,
    required this.isEphemeralPractice,
    required this.questions,
    required this.answers,
    required this.currentIndex,
    required this.startedAt,
    required this.sectionStartedAt,
    this.localStatus = LocalAttemptStatus.inProgress,
    this.submitError,
    this.submittedScore,
    this.isSectional = false,
    this.sectionCount = 1,
    this.questionsPerSection,
    this.sectionDurationMinutes,
    this.totalDurationMinutes = 0,
    this.timerEnabled = true,
  });

  factory PlayerSessionState.fromBundle(
    TestPlayerBundle bundle, {
    String attemptId = 'local',
    DateTime? startedAt,
  }) {
    final firstId = bundle.questions.first.id;
    final start = startedAt ?? DateTime.now();
    final firstSection = bundle.questions.first.sectionNumber;
    return PlayerSessionState(
      attemptId: attemptId,
      testId: bundle.testId,
      title: bundle.title,
      feedbackTiming: bundle.feedbackTiming,
      explanationLevel: bundle.explanationLevel,
      isEphemeralPractice: bundle.isEphemeralPractice,
      questions: bundle.questions,
      answers: {firstId: const QuestionAnswer(visited: true)},
      currentIndex: 0,
      startedAt: start,
      sectionStartedAt: {firstSection: start},
      isSectional: bundle.isSectional,
      sectionCount: bundle.sectionCount,
      questionsPerSection: bundle.questionsPerSection,
      sectionDurationMinutes: bundle.sectionDurationMinutes,
      totalDurationMinutes: bundle.totalDurationMinutes,
      timerEnabled: bundle.timerEnabled,
    );
  }

  factory PlayerSessionState.fromSnapshot(LocalAttemptSnapshot snapshot) {
    final clamped = snapshot.questions.isEmpty
        ? 0
        : snapshot.currentIndex.clamp(0, snapshot.questions.length - 1);
    final answers = Map<String, QuestionAnswer>.from(snapshot.answers);
    if (snapshot.questions.isNotEmpty) {
      final current = snapshot.questions[clamped];
      answers[current.id] = (answers[current.id] ?? const QuestionAnswer())
          .copyWith(visited: true);
    }
    return PlayerSessionState(
      attemptId: snapshot.attemptId,
      testId: snapshot.testId,
      title: snapshot.title,
      feedbackTiming: snapshot.feedbackTiming,
      explanationLevel: snapshot.explanationLevel,
      isEphemeralPractice: snapshot.isEphemeralPractice,
      questions: snapshot.questions,
      answers: answers,
      currentIndex: clamped,
      startedAt: snapshot.startedAt,
      sectionStartedAt: snapshot.sectionStartedAt,
      localStatus: snapshot.localStatus,
      isSectional: snapshot.isSectional,
      sectionCount: snapshot.sectionCount,
      questionsPerSection: snapshot.questionsPerSection,
      sectionDurationMinutes: snapshot.sectionDurationMinutes,
      totalDurationMinutes: snapshot.totalDurationMinutes,
      timerEnabled: snapshot.timerEnabled,
    );
  }

  final String attemptId;
  final String testId;
  final String title;
  final FeedbackTiming feedbackTiming;
  final ExplanationLevel explanationLevel;
  final bool isEphemeralPractice;
  final List<PlayerQuestion> questions;
  final Map<String, QuestionAnswer> answers;
  final int currentIndex;
  final DateTime startedAt;
  final Map<int, DateTime> sectionStartedAt;
  final LocalAttemptStatus localStatus;

  /// Last RPC error while retrying. Null after a successful submit.
  final String? submitError;

  /// Set when `submit_attempt` returns. Not persisted locally.
  final AttemptScore? submittedScore;
  final bool isSectional;
  final int sectionCount;
  final int? questionsPerSection;
  final int? sectionDurationMinutes;
  final int totalDurationMinutes;
  final bool timerEnabled;

  bool get isTutorMode => feedbackTiming == FeedbackTiming.immediate;

  PlayerQuestion get currentQuestion => questions[currentIndex];

  QuestionAnswer get currentAnswer => answerFor(currentQuestion);

  bool get isFirstQuestion => currentIndex <= 0;

  bool get isLastQuestion => currentIndex >= questions.length - 1;

  int get currentSection => currentQuestion.sectionNumber;

  bool get isLastSection {
    if (questions.isEmpty) return true;
    return !questions.any((q) => q.sectionNumber > currentSection);
  }

  /// Countdown UI + auto-submit. Practice with the timer off is excluded;
  /// duration 0 is treated as untimed so old snapshots don't instantly expire.
  bool get showsTimer => timerEnabled && _activeDurationSeconds > 0;

  bool get isPendingSubmit => localStatus == LocalAttemptStatus.pendingSubmit;

  bool get isSubmitComplete => submittedScore != null;

  /// Previous is blocked at the start of a locked-behind section.
  bool get canGoPrevious =>
      currentIndex > 0 && isIndexReachable(currentIndex - 1);

  /// Save & Next does not cross a section boundary — that's [submitSection].
  bool get canGoNext =>
      currentIndex < questions.length - 1 && isIndexReachable(currentIndex + 1);

  bool get canSubmitSection =>
      isSectional && !isPendingSubmit && !isLastSection;

  PaletteTally get paletteTally => PaletteTally.fromCells([
    for (var i = 0; i < questions.length; i++) paletteAt(i),
  ]);

  /// Tutor Mode locks the option the moment it is chosen.
  bool get isCurrentAnswerLocked =>
      isTutorMode && currentAnswer.selectedOption != null;

  /// Exam Mode is always false. Tutor Mode is true only after a selection.
  /// Every reveal UI must go through this getter — do not check correctness
  /// any other way in widgets, or Exam Mode will leak.
  bool get revealsFeedback =>
      isTutorMode && currentAnswer.selectedOption != null;

  QuestionAnswer answerFor(PlayerQuestion question) =>
      answers[question.id] ?? const QuestionAnswer();

  PaletteCell paletteAt(int index) {
    final question = questions[index];
    return PaletteCell.fromAnswer(
      questionNumber: index + 1,
      answer: answerFor(question),
      correctOption: question.correctOption,
      feedbackTiming: feedbackTiming,
    );
  }

  FeedbackReveal? get feedbackReveal {
    if (!revealsFeedback) return null;
    final selected = currentAnswer.selectedOption!;
    final isCorrect = selected == currentQuestion.correctOption;
    final showAnswer = explanationLevel != ExplanationLevel.none;
    final showText = explanationLevel == ExplanationLevel.full;
    final raw = PlayerQuestion.joinedExplanation(
      currentQuestion.explanationText,
      currentQuestion.explanationDeep,
    );
    return FeedbackReveal(
      isCorrect: isCorrect,
      highlightCorrectOption: showAnswer,
      explanationText: showText ? raw : null,
    );
  }

  OptionVisual visualFor(QuestionOption option) {
    final reveal = feedbackReveal;
    if (reveal == null) {
      return currentAnswer.selectedOption == option
          ? OptionVisual.selected
          : OptionVisual.idle;
    }
    final selected = currentAnswer.selectedOption!;
    final correct = currentQuestion.correctOption;
    if (option == selected && option == correct) {
      return OptionVisual.chosenCorrect;
    }
    if (option == selected && option != correct) {
      return OptionVisual.chosenIncorrect;
    }
    if (reveal.highlightCorrectOption && option == correct) {
      return OptionVisual.revealedCorrect;
    }
    return OptionVisual.idle;
  }

  PlayerSessionState selectOption(QuestionOption option) {
    if (isCurrentAnswerLocked) return this;
    return _writeCurrent(
      currentAnswer.copyWith(visited: true, selectedOption: option),
    );
  }

  PlayerSessionState clearResponse() {
    if (isCurrentAnswerLocked) return this;
    return _writeCurrent(currentAnswer.withoutSelection());
  }

  PlayerSessionState toggleMark() {
    return _writeCurrent(
      currentAnswer.copyWith(
        visited: true,
        markedForReview: !currentAnswer.markedForReview,
      ),
    );
  }

  /// Spec action: set the marked flag (keeping the answer) and advance.
  PlayerSessionState markForReviewAndNext() {
    final marked = _writeCurrent(
      currentAnswer.copyWith(visited: true, markedForReview: true),
    );
    return marked.goTo(currentIndex + 1);
  }

  PlayerSessionState saveAndNext() => goTo(currentIndex + 1);

  PlayerSessionState previous() => goTo(currentIndex - 1);

  PlayerSessionState goTo(int index) {
    if (index < 0 || index >= questions.length) return this;
    if (!isIndexReachable(index)) return this;
    final target = questions[index];
    return copyWith(
      answers: {
        ...answers,
        target.id: answerFor(target).copyWith(visited: true),
      },
      currentIndex: index,
    );
  }

  /// Spec §3: only the current (unlocked) section is reachable. Exited
  /// sections stay locked; later sections are not open until this one is
  /// submitted or its timer hits zero.
  bool isIndexReachable(int index) {
    if (index < 0 || index >= questions.length) return false;
    if (isPendingSubmit) return false;
    if (!isSectional) return true;
    return questions[index].sectionNumber == currentSection;
  }

  int unansweredInCurrentSection() {
    var count = 0;
    for (final question in questions) {
      if (question.sectionNumber != currentSection) continue;
      if (answerFor(question).selectedOption == null) count++;
    }
    return count;
  }

  /// Remaining countdown at [now]. Null when this session has no timer.
  ///
  /// Never reads a stored "seconds left" — always `duration - (now - start)`.
  Duration? remainingAt(DateTime now) {
    if (!showsTimer || isPendingSubmit) return null;
    final start = _timerStart();
    final elapsed = now.difference(start);
    final left = Duration(seconds: _activeDurationSeconds) - elapsed;
    return left.isNegative ? Duration.zero : left;
  }

  bool isTimerUrgentAt(DateTime now) {
    final left = remainingAt(now);
    if (left == null) return false;
    return left <= const Duration(minutes: 5);
  }

  /// If the current test/section should already have ended at [now], lock
  /// and auto-advance (or auto-submit). Safe to call repeatedly — fires the
  /// terminal transition at most once.
  PlayerSessionState applyTimerExpiry(DateTime now) {
    if (!showsTimer || isPendingSubmit) return this;
    if (!isSectional) {
      return _isExpiredAt(now) ? _markPendingSubmit() : this;
    }

    var session = this;
    var hops = 0;
    // Only the *entered* section can expire. Advancing starts the next
    // section's clock at [now], so we do not skip ahead through unentered
    // sections while the app was closed (spec: countdown starts on enter).
    while (session.showsTimer &&
        !session.isPendingSubmit &&
        session._isExpiredAt(now)) {
      if (++hops > session.questions.length) break;
      session = session._advanceFromExpiredSection(now);
    }
    return session;
  }

  /// Explicit "Submit Section & Continue". Last section submits the test.
  PlayerSessionState submitSection(DateTime now) {
    if (isPendingSubmit) return this;
    if (!isSectional || isLastSection) return _markPendingSubmit();
    final next = _nextSectionAfter(currentSection);
    if (next == null) return _markPendingSubmit();
    return _enterSection(next, now);
  }

  PlayerSessionState _advanceFromExpiredSection(DateTime now) {
    if (isLastSection) return _markPendingSubmit();
    final next = _nextSectionAfter(currentSection);
    if (next == null) return _markPendingSubmit();
    return _enterSection(next, now);
  }

  PlayerSessionState _enterSection(int section, DateTime now) {
    final index = _firstIndexInSection(section);
    if (index == null) return _markPendingSubmit();
    final target = questions[index];
    final starts = Map<int, DateTime>.from(sectionStartedAt);
    starts.putIfAbsent(section, () => now);
    return copyWith(
      currentIndex: index,
      sectionStartedAt: starts,
      answers: {
        ...answers,
        target.id: answerFor(target).copyWith(visited: true),
      },
    );
  }

  PlayerSessionState _markPendingSubmit() =>
      copyWith(localStatus: LocalAttemptStatus.pendingSubmit);

  int? _firstIndexInSection(int section) {
    for (var i = 0; i < questions.length; i++) {
      if (questions[i].sectionNumber == section) return i;
    }
    return null;
  }

  int? _nextSectionAfter(int section) {
    var next = -1;
    for (final question in questions) {
      if (question.sectionNumber <= section) continue;
      if (next < 0 || question.sectionNumber < next) {
        next = question.sectionNumber;
      }
    }
    return next < 0 ? null : next;
  }

  DateTime _timerStart() {
    if (isSectional) {
      return sectionStartedAt[currentSection] ?? startedAt;
    }
    return startedAt;
  }

  bool _isExpiredAt(DateTime now) {
    final left = remainingAt(now);
    return left != null && left <= Duration.zero;
  }

  int get _activeDurationSeconds {
    if (!timerEnabled) return 0;
    if (isSectional) {
      final minutes =
          sectionDurationMinutes ??
          (sectionCount > 0
              ? totalDurationMinutes ~/ sectionCount
              : totalDurationMinutes);
      return minutes * 60;
    }
    return totalDurationMinutes * 60;
  }

  PlayerSessionState addTimeToCurrent(int seconds) {
    if (seconds <= 0) return this;
    return _writeCurrent(currentAnswer.addTime(seconds));
  }

  /// Re-apply saved answers onto a freshly downloaded question list.
  PlayerSessionState restoreProgress({
    required Map<String, QuestionAnswer> savedAnswers,
    required int savedIndex,
    Map<int, DateTime>? savedSectionStartedAt,
  }) {
    final clamped = savedIndex.clamp(0, questions.length - 1);
    final target = questions[clamped];
    return copyWith(
      answers: {
        ...savedAnswers,
        target.id: (savedAnswers[target.id] ?? const QuestionAnswer()).copyWith(
          visited: true,
        ),
      },
      currentIndex: clamped,
      sectionStartedAt: savedSectionStartedAt ?? sectionStartedAt,
    );
  }

  LocalAttemptSnapshot toSnapshot({required String userId}) {
    return LocalAttemptSnapshot(
      attemptId: attemptId,
      testId: testId,
      userId: userId,
      title: title,
      startedAt: startedAt,
      sectionStartedAt: sectionStartedAt,
      currentIndex: currentIndex,
      localStatus: localStatus,
      feedbackTiming: feedbackTiming,
      explanationLevel: explanationLevel,
      isEphemeralPractice: isEphemeralPractice,
      answers: answers,
      questions: questions,
      isSectional: isSectional,
      sectionCount: sectionCount,
      questionsPerSection: questionsPerSection,
      sectionDurationMinutes: sectionDurationMinutes,
      totalDurationMinutes: totalDurationMinutes,
      timerEnabled: timerEnabled,
    );
  }

  PlayerSessionState copyWith({
    String? attemptId,
    String? testId,
    String? title,
    FeedbackTiming? feedbackTiming,
    ExplanationLevel? explanationLevel,
    bool? isEphemeralPractice,
    List<PlayerQuestion>? questions,
    Map<String, QuestionAnswer>? answers,
    int? currentIndex,
    DateTime? startedAt,
    Map<int, DateTime>? sectionStartedAt,
    LocalAttemptStatus? localStatus,
    String? submitError,
    bool clearSubmitError = false,
    AttemptScore? submittedScore,
    bool? isSectional,
    int? sectionCount,
    int? questionsPerSection,
    int? sectionDurationMinutes,
    int? totalDurationMinutes,
    bool? timerEnabled,
  }) {
    return PlayerSessionState(
      attemptId: attemptId ?? this.attemptId,
      testId: testId ?? this.testId,
      title: title ?? this.title,
      feedbackTiming: feedbackTiming ?? this.feedbackTiming,
      explanationLevel: explanationLevel ?? this.explanationLevel,
      isEphemeralPractice: isEphemeralPractice ?? this.isEphemeralPractice,
      questions: questions ?? this.questions,
      answers: answers ?? this.answers,
      currentIndex: currentIndex ?? this.currentIndex,
      startedAt: startedAt ?? this.startedAt,
      sectionStartedAt: sectionStartedAt ?? this.sectionStartedAt,
      localStatus: localStatus ?? this.localStatus,
      submitError: clearSubmitError ? null : (submitError ?? this.submitError),
      submittedScore: submittedScore ?? this.submittedScore,
      isSectional: isSectional ?? this.isSectional,
      sectionCount: sectionCount ?? this.sectionCount,
      questionsPerSection: questionsPerSection ?? this.questionsPerSection,
      sectionDurationMinutes:
          sectionDurationMinutes ?? this.sectionDurationMinutes,
      totalDurationMinutes: totalDurationMinutes ?? this.totalDurationMinutes,
      timerEnabled: timerEnabled ?? this.timerEnabled,
    );
  }

  PlayerSessionState _writeCurrent(QuestionAnswer next) {
    return copyWith(answers: {...answers, currentQuestion.id: next});
  }
}
