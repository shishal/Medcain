// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'catalog_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(universities)
final universitiesProvider = UniversitiesProvider._();

final class UniversitiesProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<University>>,
          List<University>,
          FutureOr<List<University>>
        >
    with $FutureModifier<List<University>>, $FutureProvider<List<University>> {
  UniversitiesProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'universitiesProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$universitiesHash();

  @$internal
  @override
  $FutureProviderElement<List<University>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<University>> create(Ref ref) {
    return universities(ref);
  }
}

String _$universitiesHash() => r'e026971e4e8f1a8895988bd41192f91d3643e496';

@ProviderFor(mbbsPhases)
final mbbsPhasesProvider = MbbsPhasesProvider._();

final class MbbsPhasesProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<MbbsPhase>>,
          List<MbbsPhase>,
          FutureOr<List<MbbsPhase>>
        >
    with $FutureModifier<List<MbbsPhase>>, $FutureProvider<List<MbbsPhase>> {
  MbbsPhasesProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'mbbsPhasesProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$mbbsPhasesHash();

  @$internal
  @override
  $FutureProviderElement<List<MbbsPhase>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<MbbsPhase>> create(Ref ref) {
    return mbbsPhases(ref);
  }
}

String _$mbbsPhasesHash() => r'42d89ec7b6d301af8a9d02782c71081a1c9d338f';

@ProviderFor(colleges)
final collegesProvider = CollegesFamily._();

final class CollegesProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<College>>,
          List<College>,
          FutureOr<List<College>>
        >
    with $FutureModifier<List<College>>, $FutureProvider<List<College>> {
  CollegesProvider._({
    required CollegesFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'collegesProvider',
         isAutoDispose: false,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$collegesHash();

  @override
  String toString() {
    return r'collegesProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<List<College>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<College>> create(Ref ref) {
    final argument = this.argument as String;
    return colleges(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is CollegesProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$collegesHash() => r'37536d66dd638670b2397508c5598aa151fb1b10';

final class CollegesFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<List<College>>, String> {
  CollegesFamily._()
    : super(
        retry: null,
        name: r'collegesProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: false,
      );

  CollegesProvider call(String universityId) =>
      CollegesProvider._(argument: universityId, from: this);

  @override
  String toString() => r'collegesProvider';
}

@ProviderFor(phaseSubjects)
final phaseSubjectsProvider = PhaseSubjectsProvider._();

final class PhaseSubjectsProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<CatalogSubject>>,
          List<CatalogSubject>,
          FutureOr<List<CatalogSubject>>
        >
    with
        $FutureModifier<List<CatalogSubject>>,
        $FutureProvider<List<CatalogSubject>> {
  PhaseSubjectsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'phaseSubjectsProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$phaseSubjectsHash();

  @$internal
  @override
  $FutureProviderElement<List<CatalogSubject>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<CatalogSubject>> create(Ref ref) {
    return phaseSubjects(ref);
  }
}

String _$phaseSubjectsHash() => r'fdc2c48cd90eeca9e64b42aedcc4265813c15dc6';

@ProviderFor(subjectTopics)
final subjectTopicsProvider = SubjectTopicsFamily._();

final class SubjectTopicsProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<CatalogTopic>>,
          List<CatalogTopic>,
          FutureOr<List<CatalogTopic>>
        >
    with
        $FutureModifier<List<CatalogTopic>>,
        $FutureProvider<List<CatalogTopic>> {
  SubjectTopicsProvider._({
    required SubjectTopicsFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'subjectTopicsProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$subjectTopicsHash();

  @override
  String toString() {
    return r'subjectTopicsProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<List<CatalogTopic>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<CatalogTopic>> create(Ref ref) {
    final argument = this.argument as String;
    return subjectTopics(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is SubjectTopicsProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$subjectTopicsHash() => r'aa42872344a128276291d592b79df033d9287fdb';

final class SubjectTopicsFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<List<CatalogTopic>>, String> {
  SubjectTopicsFamily._()
    : super(
        retry: null,
        name: r'subjectTopicsProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  SubjectTopicsProvider call(String subjectId) =>
      SubjectTopicsProvider._(argument: subjectId, from: this);

  @override
  String toString() => r'subjectTopicsProvider';
}

@ProviderFor(topicLessons)
final topicLessonsProvider = TopicLessonsFamily._();

final class TopicLessonsProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<CatalogLesson>>,
          List<CatalogLesson>,
          FutureOr<List<CatalogLesson>>
        >
    with
        $FutureModifier<List<CatalogLesson>>,
        $FutureProvider<List<CatalogLesson>> {
  TopicLessonsProvider._({
    required TopicLessonsFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'topicLessonsProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$topicLessonsHash();

  @override
  String toString() {
    return r'topicLessonsProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<List<CatalogLesson>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<CatalogLesson>> create(Ref ref) {
    final argument = this.argument as String;
    return topicLessons(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is TopicLessonsProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$topicLessonsHash() => r'0cef956706d3acedcba45c033465e9a85a4c87a2';

final class TopicLessonsFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<List<CatalogLesson>>, String> {
  TopicLessonsFamily._()
    : super(
        retry: null,
        name: r'topicLessonsProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  TopicLessonsProvider call(String topicId) =>
      TopicLessonsProvider._(argument: topicId, from: this);

  @override
  String toString() => r'topicLessonsProvider';
}

@ProviderFor(universityCoverage)
final universityCoverageProvider = UniversityCoverageProvider._();

final class UniversityCoverageProvider
    extends
        $FunctionalProvider<
          AsyncValue<UniversityCoverage>,
          UniversityCoverage,
          FutureOr<UniversityCoverage>
        >
    with
        $FutureModifier<UniversityCoverage>,
        $FutureProvider<UniversityCoverage> {
  UniversityCoverageProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'universityCoverageProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$universityCoverageHash();

  @$internal
  @override
  $FutureProviderElement<UniversityCoverage> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<UniversityCoverage> create(Ref ref) {
    return universityCoverage(ref);
  }
}

String _$universityCoverageHash() =>
    r'6d93cc60edbfd04432f7ea563ae562b2c5403c90';

@ProviderFor(lessonDetail)
final lessonDetailProvider = LessonDetailFamily._();

final class LessonDetailProvider
    extends
        $FunctionalProvider<
          AsyncValue<CatalogLesson?>,
          CatalogLesson?,
          FutureOr<CatalogLesson?>
        >
    with $FutureModifier<CatalogLesson?>, $FutureProvider<CatalogLesson?> {
  LessonDetailProvider._({
    required LessonDetailFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'lessonDetailProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$lessonDetailHash();

  @override
  String toString() {
    return r'lessonDetailProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<CatalogLesson?> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<CatalogLesson?> create(Ref ref) {
    final argument = this.argument as String;
    return lessonDetail(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is LessonDetailProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$lessonDetailHash() => r'a0f411cf1dc0c27e3aefac249cee84f09c980289';

final class LessonDetailFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<CatalogLesson?>, String> {
  LessonDetailFamily._()
    : super(
        retry: null,
        name: r'lessonDetailProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  LessonDetailProvider call(String lessonId) =>
      LessonDetailProvider._(argument: lessonId, from: this);

  @override
  String toString() => r'lessonDetailProvider';
}
