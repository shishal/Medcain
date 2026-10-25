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
  static const results = '/results/:attemptId';
  static const solutionReview = '/results/:attemptId/review';
  static const bookmarks = '/bookmarks';
  static const notifications = '/notifications';
  static const profile = '/profile';
  static const upgrade = '/upgrade';

  /// Login with a one-shot reason banner (e.g. kicked by another device).
  static String loginWithReason(String reason) =>
      Uri(path: login, queryParameters: {'reason': reason}).toString();

  static const loginReasonOtherDevice = 'other_device';
  static const loginReasonPlanSuspended = 'plan_suspended';

  static String subjectPath(String id, String title) =>
      Uri(path: '/subjects/$id', queryParameters: {'title': title}).toString();

  static String subjectTopicsPath(String id, String title) =>
      Uri(
        path: '/subjects/$id/topics',
        queryParameters: {'title': title},
      ).toString();

  /// [universityId] and [section] (a `PyqSection` name) scope the outline to
  /// the row that was tapped. Without them the year shows every sitting.
  static String subjectYearPath(
    String id,
    int year,
    String title, {
    String? universityId,
    String? section,
  }) => Uri(
    path: '/subjects/$id/years/$year',
    queryParameters: {
      'title': title,
      'uni': ?universityId,
      'section': ?section,
    },
  ).toString();

  static String topicPath(String id, String title) =>
      Uri(path: '/topics/$id', queryParameters: {'title': title}).toString();

  static String lessonPath(String id, String title) =>
      Uri(path: '/lessons/$id', queryParameters: {'title': title}).toString();

  static String pyqPath(String id) => '/pyq/$id';

  static String testDetailPath(String testId) => '/tests/$testId';
  static String testPlayerPath(String testId) => '/tests/$testId/play';

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
