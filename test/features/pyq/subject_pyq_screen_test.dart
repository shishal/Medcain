import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:medico/core/router/app_routes.dart';
import 'package:medico/core/utils/result.dart';
import 'package:medico/features/bookmarks/presentation/providers/bookmarks_provider.dart';
import 'package:medico/features/catalog/domain/catalog_models.dart';
import 'package:medico/features/catalog/presentation/providers/catalog_providers.dart';
import 'package:medico/features/practice/domain/practice_enums.dart';
import 'package:medico/features/profile/domain/plan_tier.dart';
import 'package:medico/features/profile/domain/user_profile.dart';
import 'package:medico/features/profile/presentation/providers/user_profile_provider.dart';
import 'package:medico/features/pyq/domain/pyq_models.dart';
import 'package:medico/features/pyq/domain/subject_pyq_filters.dart';
import 'package:medico/features/pyq/presentation/providers/pyq_providers.dart';
import 'package:medico/features/pyq/presentation/screens/subject_pyq_screen.dart';

PyqTeaser _teaser({
  required String id,
  required String text,
  String? topicId,
  String? topicName,
  List<String> papers = const ['Paper I'],
  List<int> years = const [2024],
  String kind = 'pyq_theory',
  num marks = 10,
  QuestionPriority priority = QuestionPriority.should,
  List<PaperSitting>? sittings,
}) {
  return PyqTeaser(
    id: id,
    topicId: topicId,
    questionText: text,
    marks: marks,
    requiredPlan: PlanTier.free,
    appearanceCount: years.length,
    kind: kind,
    priority: priority,
    appearanceYears: years,
    paperNames: papers,
    topicName: topicName,
    sittings:
        sittings ??
        [
          for (final year in years)
            for (final paper in papers)
              PaperSitting(universityId: 'u1', year: year, paperName: paper),
        ],
  );
}

/// u1 is the student's university and c1 their college. q4 is another
/// campus of u1; q5 belongs to u2.
PyqSubjectFeed _feed() {
  return PyqSubjectFeed(
    teasers: [
      _teaser(
        id: 'q1',
        text: 'Describe the femoral triangle.',
        topicId: 'll',
        topicName: 'Lower limb',
        papers: const ['Paper II'],
      ),
      _teaser(id: 'q1b', text: 'Scalp layers', papers: const ['Paper I']),
      _teaser(
        id: 'q2',
        text: 'Brachial plexus',
        topicId: 'ul',
        topicName: 'Upper limb',
        papers: const ['Paper I'],
        years: const [2023],
      ),
      _teaser(
        id: 'q3',
        text: 'Peptic ulcer',
        sittings: const [
          PaperSitting(
            universityId: 'u1',
            collegeId: 'c1',
            examType: PaperExamType.preProf,
            year: 2025,
            paperName: 'Paper I',
          ),
        ],
      ),
      _teaser(
        id: 'q4',
        text: 'Other campus stem',
        sittings: const [
          PaperSitting(
            universityId: 'u1',
            collegeId: 'c2',
            examType: PaperExamType.internal,
            year: 2022,
            paperName: 'Paper I',
          ),
        ],
      ),
      _teaser(
        id: 'q5',
        text: 'Other university stem',
        sittings: const [
          PaperSitting(universityId: 'u2', year: 2024, paperName: 'Paper I'),
        ],
      ),
    ],
    paperNames: const ['Paper I', 'Paper II'],
    years: const [2024, 2023],
    chapters: const [
      PyqChapter(id: 'ul', name: 'Upper limb'),
      PyqChapter(id: 'll', name: 'Lower limb'),
    ],
  );
}

void main() {
  test(
    'filterSubjectPyqs keeps mixed-paper stems until a chapter is picked',
    () {
      final mixed = [
        _teaser(
          id: 'q1',
          text: 'Coronary arteries',
          topicId: 'thorax',
          topicName: 'Thorax',
          papers: const ['Paper II'],
        ),
        _teaser(
          id: 'q2',
          text: 'Femoral triangle',
          topicId: 'll',
          topicName: 'Lower limb',
          papers: const ['Paper II'],
        ),
      ];
      expect(filterSubjectPyqs(teasers: mixed).map((t) => t.id), ['q1', 'q2']);
      expect(
        filterSubjectPyqs(teasers: mixed, topicIds: {'ll'}).single.id,
        'q2',
      );
      expect(
        filterSubjectPyqs(teasers: mixed, paperNames: {'Paper I'}),
        isEmpty,
      );
      expect(
        filterSubjectPyqs(
          teasers: mixed,
          paperNames: {'Paper II'},
          years: {2024},
        ).map((t) => t.id),
        ['q1', 'q2'],
      );
    },
  );

  test('filterSubjectPyqs keeps only Must when that priority is chosen', () {
    final teasers = [
      _teaser(id: 'must', text: 'Must', priority: QuestionPriority.must),
      _teaser(id: 'could', text: 'Could', priority: QuestionPriority.could),
    ];
    expect(
      filterSubjectPyqs(
        teasers: teasers,
        priorities: {QuestionPriority.must},
      ).single.id,
      'must',
    );
  });

  test('filterSubjectPyqs puts essays first when a full paper is selected', () {
    final teasers = [
      _teaser(
        id: 'mcq',
        text: 'MCQ',
        topicId: 't',
        topicName: 'Thorax',
        kind: 'mcq',
        marks: 1,
      ),
      _teaser(
        id: 'essay',
        text: 'Essay',
        topicId: 't',
        topicName: 'Thorax',
        marks: 10,
      ),
    ];
    final ordered = filterSubjectPyqs(
      teasers: teasers,
      paperNames: {'Paper I'},
      years: {2024},
    );
    expect(ordered.first.id, 'essay');
    expect(ordered.last.id, 'mcq');
  });

  test('filterSubjectPyqs keeps untagged stems until a chapter is picked', () {
    final teasers = [
      _teaser(
        id: 'tagged',
        text: 'Femoral triangle',
        topicId: 'll',
        topicName: 'Lower limb',
      ),
      _teaser(id: 'untagged', text: 'Write short notes on shock.'),
    ];
    expect(filterSubjectPyqs(teasers: teasers).map((t) => t.id), [
      'tagged',
      'untagged',
    ]);
    expect(
      filterSubjectPyqs(teasers: teasers, topicIds: {'ll'}).single.id,
      'tagged',
    );
  });

  test('filterSubjectPyqs separates MCQ from theory', () {
    final teasers = [
      _teaser(id: 'mcq', text: 'MCQ', kind: 'mcq', marks: 1),
      _teaser(id: 'essay', text: 'Essay'),
    ];
    expect(
      filterSubjectPyqs(
        teasers: teasers,
        questionKinds: {PyqQuestionKind.mcq},
      ).single.id,
      'mcq',
    );
    expect(
      filterSubjectPyqs(
        teasers: teasers,
        questionKinds: {PyqQuestionKind.theory},
      ).single.id,
      'essay',
    );
    expect(
      filterSubjectPyqs(
        teasers: teasers,
        questionKinds: {PyqQuestionKind.mcq, PyqQuestionKind.theory},
      ).map((t) => t.id),
      ['mcq', 'essay'],
    );
  });

  Future<GoRouter> pumpScreen(
    WidgetTester tester, {
    PyqSubjectFeed? feed,
  }) async {
    // Tall enough that expanded sections still lay out every year heading.
    tester.view.physicalSize = const Size(400, 3200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final router = GoRouter(
      initialLocation: AppRoutes.subjectPath('anat', 'Anatomy'),
      routes: [
        GoRoute(
          path: AppRoutes.subject,
          builder: (_, state) => SubjectPyqScreen(
            subjectId: state.pathParameters['subjectId']!,
            title: state.uri.queryParameters['title'] ?? 'Subject',
          ),
        ),
        GoRoute(
          path: AppRoutes.subjectYear,
          builder: (_, state) => Text(
            'Outline ${state.pathParameters['year']} '
            '${state.uri.queryParameters['uni']} '
            '${state.uri.queryParameters['section']} '
            '${state.uri.queryParameters['paper']}',
          ),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          subjectPyqsProvider.overrideWith((ref, id) async {
            expect(id, 'anat');
            return feed ?? _feed();
          }),
          bookmarkedIdsProvider.overrideWith(_StubBookmarkedIds.new),
          userProfileProvider.overrideWith(_StubProfile.new),
          universitiesProvider.overrideWith(
            (ref) async => const [
              University(
                id: 'u1',
                code: 'GGSIPU',
                name: 'Guru Gobind Singh Indraprastha University',
                state: 'Delhi',
                slug: 'ggsipu',
              ),
              University(
                id: 'u2',
                code: 'KUHS',
                name: 'Kerala University of Health Sciences',
                state: 'Kerala',
                slug: 'kuhs',
              ),
              University(
                id: 'u3',
                code: 'RGUHS',
                name: 'Rajiv Gandhi University of Health Sciences',
                state: 'Karnataka',
                slug: 'rguhs',
              ),
            ],
          ),
          collegesProvider.overrideWith(
            (ref, universityId) async => const [
              College(
                id: 'c1',
                universityId: 'u1',
                name: 'Maulana Azad Medical College',
                shortForm: 'MAMC',
              ),
              College(
                id: 'c2',
                universityId: 'u1',
                name: 'Dr Baba Saheb Ambedkar Medical College',
                shortForm: 'BSAMC',
              ),
            ],
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    return router;
  }

  Future<void> expandSection(WidgetTester tester, String title) async {
    final header = find.text(title);
    await tester.ensureVisible(header);
    await tester.pumpAndSettle();
    await tester.tap(header);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'subject screen shows own university, campus papers, then others',
    (tester) async {
      await pumpScreen(tester);

      final own = find.text('GGSIPU previous year questions');
      final college = find.text('GGSIPU internal / pre-prof');
      final other = find.text('Other universities');
      expect(own, findsOneWidget);
      expect(college, findsOneWidget);
      expect(other, findsOneWidget);

      final ownY = tester.getTopLeft(own).dy;
      final collegeY = tester.getTopLeft(college).dy;
      final otherY = tester.getTopLeft(other).dy;
      expect(ownY, lessThan(collegeY));
      expect(collegeY, lessThan(otherY));

      // Closed until opened, so the long paper list is not on screen yet.
      expect(find.text('Paper I'), findsNothing);
      expect(find.text('MAMC'), findsNothing);

      await expandSection(tester, 'GGSIPU previous year questions');
      await expandSection(tester, 'GGSIPU internal / pre-prof');
      await expandSection(tester, 'Other universities');

      // Newest year first, Paper I above Paper II, and no stems in the list.
      expect(
        tester.getTopLeft(find.text('2024').first).dy,
        lessThan(tester.getTopLeft(find.text('Paper I').first).dy),
      );
      expect(
        tester.getTopLeft(find.text('Paper I').first).dy,
        lessThan(tester.getTopLeft(find.text('Paper II')).dy),
      );
      expect(
        tester.getTopLeft(find.text('Paper II')).dy,
        lessThan(tester.getTopLeft(find.text('2023')).dy),
      );
      expect(find.text('Chapters'), findsNothing);
      expect(find.text('Brachial plexus'), findsNothing);

      // Own college (MAMC) before the other campus (BSAMC); other university
      // alone in section three, so 2024 appears once there plus once under
      // GGSIPU prof.
      expect(find.text('MAMC'), findsOneWidget);
      expect(find.text('BSAMC'), findsOneWidget);
      expect(find.text('2022'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('MAMC')).dy,
        lessThan(tester.getTopLeft(find.text('BSAMC')).dy),
      );
      expect(
        tester.getTopLeft(find.text('2025')).dy,
        lessThan(tester.getTopLeft(find.text('2022')).dy),
      );
      expect(find.text('2024'), findsNWidgets(2));
    },
  );

  testWidgets('tapping a row opens the outline scoped to that row', (
    tester,
  ) async {
    await pumpScreen(tester);
    await expandSection(tester, 'GGSIPU internal / pre-prof');

    final paper = find.byKey(const ValueKey('ownCollege-2025-Paper I-c1'));
    await tester.ensureVisible(paper);
    await tester.pumpAndSettle();
    await tester.tap(paper);
    await tester.pumpAndSettle();
    expect(find.text('Outline 2025 u1 ownCollege Paper I'), findsOneWidget);
  });

  /// Chips live in a scrollable sheet; scroll into view before tapping so a
  /// short phone viewport (as in CI) does not miss lower rows like Chapters.
  Future<void> tapFilterChip(WidgetTester tester, String label) async {
    final chip = find.widgetWithText(FilterChip, label);
    await tester.ensureVisible(chip);
    await tester.pumpAndSettle();
    await tester.tap(chip);
    await tester.pumpAndSettle();
  }

  testWidgets('Filters sheet narrows the sections and can be cleared', (
    tester,
  ) async {
    await pumpScreen(tester);

    await tester.tap(find.text('Filters'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(FilterChip, 'Pre-prof'), findsOneWidget);
    await tapFilterChip(tester, 'KUHS');
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    // Empty sections stay visible so the three-block layout never collapses.
    expect(find.text('GGSIPU previous year questions'), findsOneWidget);
    expect(find.text('GGSIPU internal / pre-prof'), findsOneWidget);
    expect(find.text('Other universities'), findsOneWidget);
    expect(find.text('No papers match these filters.'), findsNWidgets(2));
    expect(find.byIcon(Icons.filter_alt_rounded), findsOneWidget);

    await tester.tap(find.text('Filters'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clear all'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.text('GGSIPU previous year questions'), findsOneWidget);
  });

  testWidgets('Filters sheet hides years that do not match the paper', (
    tester,
  ) async {
    await pumpScreen(tester);

    await tester.tap(find.text('Filters'));
    await tester.pumpAndSettle();
    await tapFilterChip(tester, 'Paper II');
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    expect(find.text('2024'), findsOneWidget);
    expect(find.text('2023'), findsNothing);
    // Active filters are named above the list, and the matching paper row
    // repeats the same label. The icon fills in.
    expect(find.text('Paper II'), findsNWidgets(2));
    expect(find.byIcon(Icons.filter_alt_rounded), findsOneWidget);

    await tester.tap(find.text('Filters'));
    await tester.pumpAndSettle();
    expect(find.text('Chapters'), findsOneWidget);
    await tester.tap(find.text('Clear all'));
    await tester.pumpAndSettle();
    await tapFilterChip(tester, 'Upper limb');
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.text('2023'), findsOneWidget);
    expect(find.text('2024'), findsNothing);
  });

  testWidgets('Filters sheet keeps every selected year', (tester) async {
    await pumpScreen(tester);

    await tester.tap(find.text('Filters'));
    await tester.pumpAndSettle();
    await tapFilterChip(tester, '2024');
    await tapFilterChip(tester, '2023');
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    expect(find.text('2024, 2023'), findsOneWidget);
    expect(find.text('2024'), findsWidgets);
    expect(find.text('2023'), findsWidgets);
    expect(find.text('2025'), findsNothing);
    expect(find.text('2022'), findsNothing);

    await tester.tap(find.text('Filters'));
    await tester.pumpAndSettle();
    await tapFilterChip(tester, '2024');
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    expect(find.text('2023'), findsWidgets);
    expect(find.text('2024'), findsNothing);
  });

  testWidgets('other universities are ordered by newest paper', (tester) async {
    await pumpScreen(
      tester,
      feed: PyqSubjectFeed(
        teasers: [
          _teaser(
            id: 'old-uni',
            text: 'Older paper',
            sittings: const [
              PaperSitting(
                universityId: 'u2',
                year: 2018,
                paperName: 'Paper I',
              ),
            ],
          ),
          _teaser(
            id: 'new-uni',
            text: 'Newer paper',
            sittings: const [
              PaperSitting(
                universityId: 'u3',
                year: 2024,
                paperName: 'Paper I',
              ),
            ],
          ),
        ],
      ),
    );

    await expandSection(tester, 'Other universities');
    // RGUHS's newest paper is 2024; KUHS only has 2018, so RGUHS is first
    // even though KUHS comes first in the alphabet.
    expect(
      tester.getTopLeft(find.text('RGUHS')).dy,
      lessThan(tester.getTopLeft(find.text('KUHS')).dy),
    );
  });

  testWidgets('more than three years hides the rest behind show more', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      feed: PyqSubjectFeed(
        teasers: [
          for (final year in [2024, 2023, 2022, 2021, 2020])
            _teaser(id: 'y$year', text: 'Stem $year', years: [year]),
        ],
      ),
    );

    await expandSection(tester, 'GGSIPU previous year questions');
    expect(find.text('2024'), findsOneWidget);
    expect(find.text('2022'), findsOneWidget);
    expect(find.text('2021'), findsNothing);
    expect(find.text('2020'), findsNothing);

    await tester.tap(find.text('Show 2 earlier years'));
    await tester.pumpAndSettle();
    expect(find.text('2021'), findsOneWidget);
    expect(find.text('2020'), findsOneWidget);
    expect(find.text('Show less'), findsOneWidget);

    await tester.tap(find.text('Show less'));
    await tester.pumpAndSettle();
    expect(find.text('2020'), findsNothing);
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
    collegeId: 'c1',
  );
}
