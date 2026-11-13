/// Native capture activity while a content screen is mounted.
enum CaptureEvent { screenshot, recordingStarted, recordingStopped }

/// `screenshot_events.screen` values — only screens that show question text.
abstract final class ContentScreens {
  static const testPlayer = 'test_player';
  static const solutionReview = 'solution_review';
  static const pyqReader = 'pyq_reader';
  static const practiceReading = 'practice_reading';
}
