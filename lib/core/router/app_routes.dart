import '../../features/profile/domain/plan_tier.dart';

/// Central route path constants — use these instead of string literals.
abstract final class AppRoutes {
  static const splash = '/splash';
  static const login = '/login';
  static const signup = '/signup';
  static const onboarding = '/onboarding';
  static const home = '/home';
  static const practice = '/practice';
  static const search = '/search';
  static const progress = '/progress';
  static const subject = '/subjects/:subjectId';
  static const subjectTopics = '/subjects/:subjectId/topics';
  static const subjectYear = '/subjects/:subjectId/years/:year';
  static const topic = '/topics/:topicId';
  static const lesson = '/lessons/:lessonId';
  static const pyq = '/pyq/:questionId';
  static const testDetail = '/tests/:testId';
  static const testPlayer = '/tests/:testId/play';
  static const practiceReading = '/tests/:testId/read';
  static const results = '/results/:attemptId';
  static const solutionReview = '/results/:attemptId/review';
  static const bookmarks = '/bookmarks';
  static const notifications = '/notifications';
  static const profile = '/profile';
  static const upgrade = '/upgrade';
  static const admin = '/admin';
  static const adminUsers = '/admin/users';
  static const adminUser = '/admin/users/:userId';
  static const adminQuestions = '/admin/questions';
  static const adminQuestionNew = '/admin/question/new';
  static const adminQuestion = '/admin/questions/:questionId';
  static const adminAnnouncements = '/admin/announcements';
  static const adminAnnouncementNew = '/admin/announcement/new';
  static const adminAnnouncement = '/admin/announcements/:announcementId';

  static String adminUserPath(String userId) => '/admin/users/$userId';

  static String adminQuestionPath(String questionId) =>
      '/admin/questions/$questionId';

  static String adminAnnouncementPath(String announcementId) =>
      '/admin/announcements/$announcementId';

  /// Login with a one-shot reason banner (e.g. kicked by another device).
  static String loginWithReason(String reason) =>
      Uri(path: login, queryParameters: {'reason': reason}).toString();

  static const loginReasonOtherDevice = 'other_device';
  static const loginReasonPlanSuspended = 'plan_suspended';
  static const loginReasonDeviceLimit = 'device_limit';

  static String subjectPath(String id, String title) =>
      Uri(path: '/subjects/$id', queryParameters: {'title': title}).toString();

  static String subjectTopicsPath(String id, String title) => Uri(
    path: '/subjects/$id/topics',
    queryParameters: {'title': title},
  ).toString();

  /// [universityId], [section] (a `PyqSection` name), optional [collegeId], and
  /// [paperName] scope the outline to the row that was tapped. Without the
  /// university and section the year shows every sitting. A null [paperName]
  /// keeps every paper in that year; an empty string means the sheet left
  /// the paper label blank.
  ///
  /// [scopeMonth] keeps one month of that paper. [month] is 1–12; null means
  /// the sheet had no month. Omit [scopeMonth] to keep every month.
  static String subjectYearPath(
    String id,
    int year,
    String title, {
    String? universityId,
    String? section,
    String? collegeId,
    String? paperName,
    int? month,
    bool scopeMonth = false,
  }) => Uri(
    path: '/subjects/$id/years/$year',
    queryParameters: {
      'title': title,
      'uni': ?universityId,
      'section': ?section,
      'college': ?collegeId,
      'paper': ?paperName,
      if (scopeMonth) 'month': month == null ? '' : '$month',
    },
  ).toString();

  static String topicPath(String id, String title) =>
      Uri(path: '/topics/$id', queryParameters: {'title': title}).toString();

  static String lessonPath(String id, String title) =>
      Uri(path: '/lessons/$id', queryParameters: {'title': title}).toString();

  static String pyqPath(String id) => '/pyq/$id';

  static String testDetailPath(String testId) => '/tests/$testId';
  static String testPlayerPath(String testId) => '/tests/$testId/play';
  static String practiceReadingPath(String testId) => '/tests/$testId/read';

  static String resultsPath(
    String attemptId, {
    String? testId,
    bool isPractice = false,
  }) {
    final params = <String, String>{
      'testId': ?testId,
      if (isPractice) 'practice': '1',
    };
    if (params.isEmpty) return '/results/$attemptId';
    return Uri(path: '/results/$attemptId', queryParameters: params).toString();
  }

  static String solutionReviewPath(String attemptId) =>
      '/results/$attemptId/review';

  /// Opens the upgrade prompt for the plan needed to unlock tapped content.
  static String upgradePath(PlanTier requiredPlan) =>
      '$upgrade?plan=${requiredPlan.name}';
}
