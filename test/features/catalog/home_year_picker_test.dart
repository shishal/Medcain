import 'dart:io';
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:medico/core/router/app_routes.dart';
import 'package:medico/core/theme/app_theme.dart';
import 'package:medico/features/catalog/domain/catalog_models.dart';
import 'package:medico/features/catalog/domain/university_coverage.dart';
import 'package:medico/features/catalog/presentation/providers/catalog_providers.dart';
import 'package:medico/features/profile/domain/plan_tier.dart';
import 'package:medico/features/profile/domain/user_profile.dart';
import 'package:medico/features/profile/presentation/providers/user_profile_provider.dart';
import 'package:medico/features/progress/domain/progress_models.dart';
import 'package:medico/features/progress/presentation/providers/ug_home_providers.dart';
import 'package:medico/features/tests/domain/resumable_attempt.dart';
import 'package:medico/features/tests/presentation/providers/in_progress_attempts_provider.dart';
import 'package:medico/features/tests/presentation/providers/pending_submit_sync_provider.dart';
import 'package:medico/features/tests/presentation/screens/home_screen.dart';

class _StubProfile extends UserProfileNotifier {
  @override
  Future<UserProfile?> build() async {
    return UserProfile(
      id: 'user-1',
      fullName: 'Asha',
      plan: PlanTier.pro,
      createdAt: DateTime.utc(2026, 1, 1),
      mbbsPhaseId: 'p1',
      onboardingCompletedAt: DateTime.utc(2026, 8, 1),
    );
  }
}

class _NoAttempts extends InProgressAttempts {
  @override
  Future<List<ResumableAttempt>> build() async => const [];
}

class _NoopSync extends PendingSubmitSync {
  @override
  Future<void> build() async {}
}

void main() {
  testWidgets(
    'Home follows the profile year without a week strip or year switcher',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(400, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final router = GoRouter(
        initialLocation: AppRoutes.home,
        routes: [
          GoRoute(path: AppRoutes.home, builder: (_, _) => const HomeScreen()),
          GoRoute(
            path: AppRoutes.search,
            builder: (_, _) => const SizedBox.shrink(),
          ),
          GoRoute(
            path: AppRoutes.profile,
            builder: (_, _) => const SizedBox.shrink(),
          ),
          GoRoute(
            path: '/subjects/:subjectId',
            builder: (_, _) => const SizedBox.shrink(),
          ),
          GoRoute(
            path: AppRoutes.practice,
            builder: (_, _) => const SizedBox.shrink(),
          ),
          GoRoute(
            path: AppRoutes.progress,
            builder: (_, _) => const SizedBox.shrink(),
          ),
          GoRoute(
            path: AppRoutes.bookmarks,
            builder: (_, _) => const SizedBox.shrink(),
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            userProfileProvider.overrideWith(_StubProfile.new),
            mbbsPhasesProvider.overrideWith(
              (ref) async => const [
                MbbsPhase(
                  id: 'p1',
                  code: 'Y1',
                  name: '1st year',
                  displayOrder: 1,
                ),
                MbbsPhase(
                  id: 'p2',
                  code: 'Y2',
                  name: '2nd year',
                  displayOrder: 2,
                ),
              ],
            ),
            phaseSubjectsProvider.overrideWith((ref) async {
              final phaseId = ref.watch(userProfileProvider).value?.mbbsPhaseId;
              if (phaseId == 'p2') {
                return const [
                  CatalogSubject(
                    id: 'path',
                    name: 'Pathology',
                    displayOrder: 1,
                  ),
                ];
              }
              return const [
                CatalogSubject(id: 'anat', name: 'Anatomy', displayOrder: 1),
              ];
            }),
            studyProgressProvider.overrideWith(
              (ref) async => const StudyProgress(
                streak: 2,
                days7: [],
                days30: [],
                subjects: [
                  SubjectCoverage(
                    id: 'anat',
                    name: 'Anatomy',
                    learntLessons: 0,
                    totalLessons: 1,
                    totalPyqs: 12,
                  ),
                ],
              ),
            ),
            inProgressAttemptsProvider.overrideWith(_NoAttempts.new),
            pendingSubmitSyncProvider.overrideWith(_NoopSync.new),
            universitiesProvider.overrideWith((ref) async => const []),
            universityCoverageProvider.overrideWith(
              (ref) async => const UniversityCoverage(
                paperCount: 12,
                pyqCount: 40,
                contentUniversityId: 'kuhs',
              ),
            ),
          ],
          child: RepaintBoundary(
            child: MaterialApp.router(
              theme: AppTheme.light,
              routerConfig: router,
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 80));
      });
      await tester.pump(const Duration(milliseconds: 800));

      expect(find.text('Anatomy'), findsOneWidget);
      expect(find.text('12 PYQs'), findsOneWidget);
      expect(find.textContaining('lessons learnt'), findsNothing);
      expect(find.text('Pathology'), findsNothing);
      expect(find.text('Your year'), findsNothing);
      expect(find.text('Practice'), findsOneWidget);
      expect(find.text('Tutor or exam mode'), findsOneWidget);
      expect(find.byKey(const ValueKey('year-chip-p2')), findsNothing);
      expect(
        find.textContaining('Tap a subject for previous-year papers'),
        findsOneWidget,
      );
      expect(
        tester.getTopLeft(find.text('Subjects')).dy,
        lessThan(tester.getTopLeft(find.text('Practice')).dy),
      );
      await _savePng(tester, 'home_profile_year_subjects.png');
    },
  );

  testWidgets(
    'Home still shows year subjects when the university has no papers',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(400, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final router = GoRouter(
        initialLocation: AppRoutes.home,
        routes: [
          GoRoute(path: AppRoutes.home, builder: (_, _) => const HomeScreen()),
          GoRoute(
            path: AppRoutes.search,
            builder: (_, _) => const SizedBox.shrink(),
          ),
          GoRoute(
            path: AppRoutes.profile,
            builder: (_, _) => const SizedBox.shrink(),
          ),
          GoRoute(
            path: '/subjects/:subjectId',
            builder: (_, _) => const SizedBox.shrink(),
          ),
          GoRoute(
            path: AppRoutes.practice,
            builder: (_, _) => const SizedBox.shrink(),
          ),
          GoRoute(
            path: AppRoutes.progress,
            builder: (_, _) => const SizedBox.shrink(),
          ),
          GoRoute(
            path: AppRoutes.bookmarks,
            builder: (_, _) => const SizedBox.shrink(),
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            userProfileProvider.overrideWith(_StubProfile.new),
            phaseSubjectsProvider.overrideWith(
              (ref) async => const [
                CatalogSubject(id: 'anat', name: 'Anatomy', displayOrder: 1),
              ],
            ),
            studyProgressProvider.overrideWith(
              (ref) async => const StudyProgress(
                streak: 0,
                days7: [],
                days30: [],
                subjects: [
                  SubjectCoverage(
                    id: 'anat',
                    name: 'Anatomy',
                    learntLessons: 0,
                    totalLessons: 14,
                  ),
                ],
              ),
            ),
            inProgressAttemptsProvider.overrideWith(_NoAttempts.new),
            pendingSubmitSyncProvider.overrideWith(_NoopSync.new),
            universitiesProvider.overrideWith((ref) async => const []),
            universityCoverageProvider.overrideWith(
              (ref) async => const UniversityCoverage(
                paperCount: 0,
                pyqCount: 0,
                contentUniversityId: 'rguhs',
              ),
            ),
          ],
          child: MaterialApp.router(
            theme: AppTheme.light,
            routerConfig: router,
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Anatomy'), findsOneWidget);
      expect(find.text('No PYQs yet'), findsOneWidget);
      expect(find.textContaining('lessons learnt'), findsNothing);
    },
  );
}

Future<void> _savePng(WidgetTester tester, String filename) async {
  final dir = Directory('/opt/cursor/artifacts');
  if (!dir.existsSync()) return;
  await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byType(RepaintBoundary).first,
    );
    final image = await boundary.toImage(pixelRatio: 1.5);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    if (bytes == null) return;
    await File('${dir.path}/$filename')
        .writeAsBytes(bytes.buffer.asUint8List());
  });
}
