import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../features/auth/data/auth_repository.dart';
import '../../features/auth/presentation/providers/auth_session_provider.dart';
import '../../features/auth/presentation/screens/login_screen.dart';
import '../../features/auth/presentation/screens/signup_screen.dart';
import '../../features/auth/presentation/screens/splash_screen.dart';
import '../../features/catalog/presentation/screens/catalog_screens.dart';
import '../../features/onboarding/presentation/screens/onboarding_screen.dart';
import '../../features/profile/domain/plan_tier.dart';
import '../../features/profile/presentation/providers/user_profile_provider.dart';
import '../../features/profile/presentation/screens/profile_screen.dart';
import '../../features/profile/presentation/screens/upgrade_prompt_screen.dart';
import '../../features/practice/presentation/screens/practice_upcoming_screen.dart';
import '../../features/progress/presentation/screens/progress_screens.dart';
import '../../features/search/presentation/screens/search_screen.dart';
import '../../features/pyq/presentation/screens/pyq_reader_screen.dart';
import '../../features/pyq/presentation/screens/subject_pyq_screen.dart';
import '../../features/pyq/presentation/screens/year_paper_outline_screen.dart';
import '../../features/bookmarks/presentation/screens/bookmarks_screen.dart';
import '../../features/notifications/presentation/screens/notifications_inbox_screen.dart';
import '../../features/results/presentation/screens/results_screen.dart';
import '../../features/results/presentation/screens/solution_review_screen.dart';
import '../../features/tests/presentation/screens/home_screen.dart';
import '../../features/tests/presentation/screens/test_instructions_screen.dart';
import '../../features/tests/presentation/screens/test_player_screen.dart';
import '../widgets/app_shell.dart';
import 'app_routes.dart';
import 'comic_page.dart';
import 'go_router_refresh_stream.dart';

part 'app_router.g.dart';

@Riverpod(keepAlive: true)
GoRouter goRouter(Ref ref) {
  final isAuthenticated = ref.watch(authSessionProvider);
  final authRepository = ref.watch(authRepositoryProvider);
  final profileAsync = ref.watch(userProfileProvider);

  final refreshListenable = GoRouterRefreshStream(
    authRepository.authStateChanges,
  );
  ref.onDispose(refreshListenable.dispose);

  return GoRouter(
    initialLocation: AppRoutes.splash,
    refreshListenable: refreshListenable,
    redirect: (context, state) {
      final location = state.matchedLocation;
      final onSplash = location == AppRoutes.splash;
      final onAuth =
          location == AppRoutes.login || location == AppRoutes.signup;

      // Splash handles its own navigation after a brief display.
      if (onSplash) return null;

      if (!isAuthenticated && !onAuth) {
        return AppRoutes.login;
      }
      if (isAuthenticated && onAuth) {
        return AppRoutes.home;
      }
      if (isAuthenticated && !onAuth) {
        if (profileAsync.isLoading) return null;
        final needsOnboarding = profileAsync.value?.needsOnboarding ?? false;
        final onOnboarding = location == AppRoutes.onboarding;
        if (needsOnboarding && !onOnboarding) {
          return AppRoutes.onboarding;
        }
        if (!needsOnboarding && onOnboarding) {
          return AppRoutes.home;
        }
      }
      return null;
    },
    routes: [
      comicGoRoute(
        path: AppRoutes.splash,
        builder: (context, state) => const SplashScreen(),
      ),
      comicGoRoute(
        path: AppRoutes.login,
        builder: (context, state) => const LoginScreen(),
      ),
      comicGoRoute(
        path: AppRoutes.signup,
        builder: (context, state) => const SignupScreen(),
      ),
      comicGoRoute(
        path: AppRoutes.onboarding,
        builder: (context, state) => const OnboardingScreen(),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            AppShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            routes: [
              comicGoRoute(
                path: AppRoutes.home,
                builder: (context, state) => const HomeScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              comicGoRoute(
                path: AppRoutes.practice,
                builder: (context, state) => const PracticeUpcomingScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              comicGoRoute(
                path: AppRoutes.profile,
                builder: (context, state) => const ProfileScreen(),
              ),
            ],
          ),
        ],
      ),
      comicGoRoute(
        path: AppRoutes.search,
        builder: (context, state) => const SearchScreen(),
      ),
      comicGoRoute(
        path: AppRoutes.progress,
        builder: (context, state) => const ProgressScreen(),
      ),
      comicGoRoute(
        path: AppRoutes.subjectTopics,
        builder: (context, state) {
          final id = state.pathParameters['subjectId']!;
          final title = state.uri.queryParameters['title'] ?? 'Subject';
          return SubjectListScreen(subjectId: id, title: title);
        },
      ),
      comicGoRoute(
        path: AppRoutes.subjectYear,
        builder: (context, state) {
          final id = state.pathParameters['subjectId']!;
          final year = int.tryParse(state.pathParameters['year'] ?? '') ?? 0;
          final title = state.uri.queryParameters['title'] ?? 'Subject';
          return YearPaperOutlineScreen(
            subjectId: id,
            year: year,
            title: title,
            universityId: state.uri.queryParameters['uni'],
            section: state.uri.queryParameters['section'],
          );
        },
      ),
      comicGoRoute(
        path: AppRoutes.subject,
        builder: (context, state) {
          final id = state.pathParameters['subjectId']!;
          final title = state.uri.queryParameters['title'] ?? 'Subject';
          return SubjectPyqScreen(subjectId: id, title: title);
        },
      ),
      comicGoRoute(
        path: AppRoutes.topic,
        builder: (context, state) {
          final id = state.pathParameters['topicId']!;
          final title = state.uri.queryParameters['title'] ?? 'Topic';
          return TopicLessonsScreen(topicId: id, title: title);
        },
      ),
      comicGoRoute(
        path: AppRoutes.lesson,
        builder: (context, state) {
          final id = state.pathParameters['lessonId']!;
          final title = state.uri.queryParameters['title'] ?? 'Lesson';
          return LessonScreen(lessonId: id, title: title);
        },
      ),
      comicGoRoute(
        path: AppRoutes.pyq,
        builder: (context, state) {
          final id = state.pathParameters['questionId']!;
          return PyqReaderScreen(questionId: id);
        },
      ),
      // More specific `/play` route before bare `:testId` so paths match correctly.
      comicGoRoute(
        path: AppRoutes.testPlayer,
        builder: (context, state) {
          final testId = state.pathParameters['testId']!;
          return TestPlayerScreen(testId: testId);
        },
      ),
      comicGoRoute(
        path: AppRoutes.testDetail,
        builder: (context, state) {
          final testId = state.pathParameters['testId']!;
          return TestInstructionsScreen(testId: testId);
        },
      ),
      comicGoRoute(
        path: AppRoutes.solutionReview,
        builder: (context, state) {
          final attemptId = state.pathParameters['attemptId']!;
          return SolutionReviewScreen(attemptId: attemptId);
        },
      ),
      comicGoRoute(
        path: AppRoutes.results,
        builder: (context, state) {
          final attemptId = state.pathParameters['attemptId']!;
          final testId = state.uri.queryParameters['testId'];
          final isPractice = state.uri.queryParameters['practice'] == '1';
          return ResultsScreen(
            attemptId: attemptId,
            testId: testId,
            isPractice: isPractice,
          );
        },
      ),
      comicGoRoute(
        path: AppRoutes.bookmarks,
        builder: (context, state) => const BookmarksScreen(),
      ),
      comicGoRoute(
        path: AppRoutes.notifications,
        builder: (context, state) => const NotificationsInboxScreen(),
      ),
      comicGoRoute(
        path: AppRoutes.upgrade,
        builder: (context, state) {
          final planParam = state.uri.queryParameters['plan'];
          final requiredPlan = planParam != null
              ? PlanTier.fromString(planParam)
              : PlanTier.pro;
          return UpgradePromptScreen(requiredPlan: requiredPlan);
        },
      ),
    ],
  );
}
