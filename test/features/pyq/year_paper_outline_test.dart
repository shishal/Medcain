import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:medico/core/router/app_routes.dart';
import 'package:medico/core/utils/result.dart';
import 'package:medico/features/bookmarks/presentation/providers/bookmarks_provider.dart';
import 'package:medico/features/profile/domain/plan_tier.dart';
import 'package:medico/features/profile/domain/user_profile.dart';
import 'package:medico/features/profile/presentation/providers/user_profile_provider.dart';
import 'package:medico/features/pyq/domain/paper_outline.dart';
import 'package:medico/features/pyq/domain/pyq_models.dart';
import 'package:medico/features/pyq/presentation/providers/pyq_providers.dart';
import 'package:medico/features/pyq/presentation/screens/year_paper_outline_screen.dart';

PyqTeaser _teaser({
  required String id,
  required String text,
  String kind = 'pyq_theory',
  num? marks = 10,
  List<String> papers = const ['Paper I'],
  List<int> years = const [2024],
  PlanTier requiredPlan = PlanTier.free,
}) {
  return PyqTeaser(
    id: id,
    topicId: 't',
    questionText: text,
    marks: marks,
    requiredPlan: requiredPlan,
    appearanceCount: 1,
    kind: kind,
    appearanceYears: years,
    paperNames: papers,
    topicName: 'Thorax',
    sittings: [
      for (final year in years)
        for (final paper in papers)
          PaperSitting(universityId: 'u1', year: year, paperName: paper),
    ],
  );
}

void main() {
  test('teasersForOutlineTab merges papers and folds VSA into short notes', () {
    final teasers = [
      _teaser(
        id: 'essay-ii',
        text: 'Long essay Paper II',
        papers: const ['Paper II'],
        marks: 10,
      ),
      _teaser(
        id: 'essay-i',
        text: 'Long essay Paper I',
        papers: const ['Paper I'],
        marks: 15,
      ),
      _teaser(id: 'short', text: 'Short note', marks: 5),
      _teaser(id: 'vsa', text: 'Very short', marks: 2),
      _teaser(id: 'mcq', text: 'MCQ stem', kind: 'mcq', marks: 1),
      _teaser(id: 'other', text: 'Marks not entered', marks: null),
      _teaser(id: 'other-year', text: '2023 essay', years: const [2023]),
    ];

    final laq = teasersForOutlineTab(
      teasers: teasers,
      year: 2024,
      tab: PaperOutlineTab.longAnswer,
    );
    expect(laq.map((t) => t.id), ['essay-i', 'essay-ii']);

    final notes = teasersForOutlineTab(
      teasers: teasers,
      year: 2024,
      tab: PaperOutlineTab.shortNotes,
    );
    expect(notes.map((t) => t.id), ['short', 'vsa']);

    final mcq = teasersForOutlineTab(
      teasers: teasers,
      year: 2024,
      tab: PaperOutlineTab.mcq,
    );
    expect(mcq.single.id, 'mcq');

    final other = teasersForOutlineTab(
      teasers: teasers,
      year: 2024,
      tab: PaperOutlineTab.other,
    );
    expect(other.single.id, 'other');
  });

  test('defaultPaperOutlineTabIndex skips empty long-answer tab', () {
    expect(
      defaultPaperOutlineTabIndex(
        longAnswer: const [],
        shortNotes: [_teaser(id: 's', text: 'note', marks: 5)],
        mcq: const [],
        other: const [],
      ),
      1,
    );
    expect(
      defaultPaperOutlineTabIndex(
        longAnswer: [_teaser(id: 'e', text: 'essay')],
        shortNotes: const [],
        mcq: const [],
        other: const [],
      ),
      0,
    );
  });

  testWidgets('year outline pins tabs and swaps the list without stems mixed', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final router = GoRouter(
      initialLocation: AppRoutes.subjectYearPath('anat', 2024, 'Anatomy'),
      routes: [
        GoRoute(
          path: AppRoutes.subjectYear,
          builder: (_, state) => YearPaperOutlineScreen(
            subjectId: state.pathParameters['subjectId']!,
            year: int.parse(state.pathParameters['year']!),
            title: state.uri.queryParameters['title'] ?? 'Subject',
          ),
        ),
        GoRoute(
          path: AppRoutes.pyq,
          builder: (_, state) =>
              Text('Reader ${state.pathParameters['questionId']}'),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          subjectPyqsProvider.overrideWith(
            (ref, id) async => PyqSubjectFeed(
              teasers: [
                _teaser(id: 'essay', text: 'Describe the femoral triangle.'),
                _teaser(
                  id: 'mcq',
                  text: 'Which artery?',
                  kind: 'mcq',
                  marks: 1,
                  papers: const ['Paper II'],
                ),
              ],
              paperNames: const ['Paper I', 'Paper II'],
              years: const [2024],
            ),
          ),
          bookmarkedIdsProvider.overrideWith(_StubBookmarkedIds.new),
          userProfileProvider.overrideWith(_StubProfile.new),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('LAQ'), findsOneWidget);
    expect(find.textContaining('Short notes'), findsOneWidget);
    expect(find.textContaining('MCQ'), findsWidgets);
    expect(find.text('Describe the femoral triangle.'), findsOneWidget);
    expect(find.text('Which artery?'), findsNothing);

    await tester.tap(find.textContaining('MCQ').first);
    await tester.pumpAndSettle();
    expect(find.text('Which artery?'), findsOneWidget);
    expect(find.text('Describe the femoral triangle.'), findsNothing);

    await tester.tap(find.text('Which artery?'));
    await tester.pumpAndSettle();
    expect(find.text('Reader mcq'), findsOneWidget);
  });

  testWidgets('a free plan does not open a Pro question from the outline', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final router = GoRouter(
      initialLocation: AppRoutes.subjectYearPath('anat', 2024, 'Anatomy'),
      routes: [
        GoRoute(
          path: AppRoutes.subjectYear,
          builder: (_, state) => YearPaperOutlineScreen(
            subjectId: state.pathParameters['subjectId']!,
            year: int.parse(state.pathParameters['year']!),
            title: state.uri.queryParameters['title'] ?? 'Subject',
          ),
        ),
        GoRoute(
          path: AppRoutes.pyq,
          builder: (_, state) =>
              Text('Reader ${state.pathParameters['questionId']}'),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          subjectPyqsProvider.overrideWith(
            (ref, id) async => PyqSubjectFeed(
              teasers: [
                _teaser(id: 'free', text: 'Describe the femoral triangle.'),
                _teaser(
                  id: 'pro',
                  text: 'Write an essay on myocardial infarction.',
                  requiredPlan: PlanTier.pro,
                ),
              ],
            ),
          ),
          bookmarkedIdsProvider.overrideWith(_StubBookmarkedIds.new),
          userProfileProvider.overrideWith(_StubProfile.new),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Free'), findsOneWidget);
    expect(find.text('Pro'), findsOneWidget);
    expect(find.text('Describe the femoral triangle.'), findsOneWidget);
    expect(find.text('Write an essay on myocardial infarction.'), findsNothing);

    await tester.tap(find.text('Pro'));
    await tester.pumpAndSettle();
    expect(find.text('Reader pro'), findsNothing);

    await tester.tap(find.text('Describe the femoral triangle.'));
    await tester.pumpAndSettle();
    expect(find.text('Reader free'), findsOneWidget);
  });

  testWidgets('a paper route shows only that paper', (tester) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final router = GoRouter(
      initialLocation: AppRoutes.subjectYearPath(
        'anat',
        2024,
        'Anatomy',
        universityId: 'u1',
        section: 'ownUniversity',
        paperName: 'Paper I',
      ),
      routes: [
        GoRoute(
          path: AppRoutes.subjectYear,
          builder: (_, state) => YearPaperOutlineScreen(
            subjectId: state.pathParameters['subjectId']!,
            year: int.parse(state.pathParameters['year']!),
            title: state.uri.queryParameters['title'] ?? 'Subject',
            universityId: state.uri.queryParameters['uni'],
            section: state.uri.queryParameters['section'],
            paperName: state.uri.queryParameters['paper'],
          ),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          subjectPyqsProvider.overrideWith(
            (ref, id) async => PyqSubjectFeed(
              teasers: [
                _teaser(id: 'essay-i', text: 'Long essay Paper I'),
                _teaser(
                  id: 'essay-ii',
                  text: 'Long essay Paper II',
                  papers: const ['Paper II'],
                ),
                _teaser(
                  id: 'other-year',
                  text: '2023 Paper I',
                  years: const [2023],
                ),
              ],
            ),
          ),
          bookmarkedIdsProvider.overrideWith(_StubBookmarkedIds.new),
          userProfileProvider.overrideWith(_StubProfile.new),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Anatomy · 2024 · Paper I'), findsOneWidget);
    expect(find.text('Long essay Paper I'), findsOneWidget);
    expect(find.text('Long essay Paper II'), findsNothing);
    expect(find.text('2023 Paper I'), findsNothing);
  });

  testWidgets('a month route hides the other month of the same paper', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          subjectPyqsProvider.overrideWith(
            (ref, id) async => PyqSubjectFeed(
              teasers: [
                PyqTeaser(
                  id: 'aug',
                  questionText: 'August femoral triangle',
                  marks: 10,
                  requiredPlan: PlanTier.free,
                  appearanceCount: 1,
                  kind: 'pyq_theory',
                  sittings: const [
                    PaperSitting(
                      universityId: 'u1',
                      year: 2024,
                      month: 8,
                      paperName: 'Paper I',
                    ),
                  ],
                ),
                PyqTeaser(
                  id: 'oct',
                  questionText: 'October femoral triangle',
                  marks: 10,
                  requiredPlan: PlanTier.free,
                  appearanceCount: 1,
                  kind: 'pyq_theory',
                  sittings: const [
                    PaperSitting(
                      universityId: 'u1',
                      year: 2024,
                      month: 10,
                      paperName: 'Paper I',
                    ),
                  ],
                ),
              ],
            ),
          ),
          bookmarkedIdsProvider.overrideWith(_StubBookmarkedIds.new),
          userProfileProvider.overrideWith(_StubProfile.new),
        ],
        child: const MaterialApp(
          home: YearPaperOutlineScreen(
            subjectId: 'anat',
            year: 2024,
            title: 'Anatomy',
            universityId: 'u1',
            section: 'ownUniversity',
            paperName: 'Paper I',
            monthQuery: '8',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Anatomy · 2024 · August · Paper I'), findsOneWidget);
    expect(find.text('August femoral triangle'), findsOneWidget);
    expect(find.text('October femoral triangle'), findsNothing);
  });
}

class _StubBookmarkedIds extends BookmarkedIds {
  @override
  Future<Set<String>> build() async => {};

  @override
  Future<Result<void>> toggle(String questionId) async {
    return const Success(null);
  }
}

class _StubProfile extends UserProfileNotifier {
  @override
  Future<UserProfile?> build() async => UserProfile(
    id: 'me',
    plan: PlanTier.free,
    createdAt: DateTime(2026),
    universityId: 'u1',
  );
}
