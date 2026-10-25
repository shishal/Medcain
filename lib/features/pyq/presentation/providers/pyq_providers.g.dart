// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'pyq_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(lessonPyqs)
final lessonPyqsProvider = LessonPyqsFamily._();

final class LessonPyqsProvider
    extends
        $FunctionalProvider<
          AsyncValue<PyqLessonFeed>,
          PyqLessonFeed,
          FutureOr<PyqLessonFeed>
        >
    with $FutureModifier<PyqLessonFeed>, $FutureProvider<PyqLessonFeed> {
  LessonPyqsProvider._({
    required LessonPyqsFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'lessonPyqsProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$lessonPyqsHash();

  @override
  String toString() {
    return r'lessonPyqsProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<PyqLessonFeed> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<PyqLessonFeed> create(Ref ref) {
    final argument = this.argument as String;
    return lessonPyqs(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is LessonPyqsProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$lessonPyqsHash() => r'ac051abcc090571a9a0fc6b05b77c3ef4d30ca33';

final class LessonPyqsFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<PyqLessonFeed>, String> {
  LessonPyqsFamily._()
    : super(
        retry: null,
        name: r'lessonPyqsProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  LessonPyqsProvider call(String lessonId) =>
      LessonPyqsProvider._(argument: lessonId, from: this);

  @override
  String toString() => r'lessonPyqsProvider';
}

/// "More on this topic" links for one lesson. This used to be an initState
/// fetch into local widget state, so it never refreshed and a failure showed
/// as an empty section.

@ProviderFor(lessonResources)
final lessonResourcesProvider = LessonResourcesFamily._();

/// "More on this topic" links for one lesson. This used to be an initState
/// fetch into local widget state, so it never refreshed and a failure showed
/// as an empty section.

final class LessonResourcesProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<ResourceLink>>,
          List<ResourceLink>,
          FutureOr<List<ResourceLink>>
        >
    with
        $FutureModifier<List<ResourceLink>>,
        $FutureProvider<List<ResourceLink>> {
  /// "More on this topic" links for one lesson. This used to be an initState
  /// fetch into local widget state, so it never refreshed and a failure showed
  /// as an empty section.
  LessonResourcesProvider._({
    required LessonResourcesFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'lessonResourcesProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$lessonResourcesHash();

  @override
  String toString() {
    return r'lessonResourcesProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<List<ResourceLink>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<ResourceLink>> create(Ref ref) {
    final argument = this.argument as String;
    return lessonResources(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is LessonResourcesProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$lessonResourcesHash() => r'91ffb3352836ab3f770e78c37f01745689e746ae';

/// "More on this topic" links for one lesson. This used to be an initState
/// fetch into local widget state, so it never refreshed and a failure showed
/// as an empty section.

final class LessonResourcesFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<List<ResourceLink>>, String> {
  LessonResourcesFamily._()
    : super(
        retry: null,
        name: r'lessonResourcesProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// "More on this topic" links for one lesson. This used to be an initState
  /// fetch into local widget state, so it never refreshed and a failure showed
  /// as an empty section.

  LessonResourcesProvider call(String lessonId) =>
      LessonResourcesProvider._(argument: lessonId, from: this);

  @override
  String toString() => r'lessonResourcesProvider';
}

/// Kept alive so leaving the subject and coming back does not re-show
/// the loading spinner while the feed is fetched again.

@ProviderFor(subjectPyqs)
final subjectPyqsProvider = SubjectPyqsFamily._();

/// Kept alive so leaving the subject and coming back does not re-show
/// the loading spinner while the feed is fetched again.

final class SubjectPyqsProvider
    extends
        $FunctionalProvider<
          AsyncValue<PyqSubjectFeed>,
          PyqSubjectFeed,
          FutureOr<PyqSubjectFeed>
        >
    with $FutureModifier<PyqSubjectFeed>, $FutureProvider<PyqSubjectFeed> {
  /// Kept alive so leaving the subject and coming back does not re-show
  /// the loading spinner while the feed is fetched again.
  SubjectPyqsProvider._({
    required SubjectPyqsFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'subjectPyqsProvider',
         isAutoDispose: false,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$subjectPyqsHash();

  @override
  String toString() {
    return r'subjectPyqsProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<PyqSubjectFeed> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<PyqSubjectFeed> create(Ref ref) {
    final argument = this.argument as String;
    return subjectPyqs(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is SubjectPyqsProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$subjectPyqsHash() => r'51191e4a7c9e0ead37e6bd15fdc795a7a01fbb8a';

/// Kept alive so leaving the subject and coming back does not re-show
/// the loading spinner while the feed is fetched again.

final class SubjectPyqsFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<PyqSubjectFeed>, String> {
  SubjectPyqsFamily._()
    : super(
        retry: null,
        name: r'subjectPyqsProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: false,
      );

  /// Kept alive so leaving the subject and coming back does not re-show
  /// the loading spinner while the feed is fetched again.

  SubjectPyqsProvider call(String subjectId) =>
      SubjectPyqsProvider._(argument: subjectId, from: this);

  @override
  String toString() => r'subjectPyqsProvider';
}

/// University / year / exam type / paper / MCQ-or-theory / chapter picks for
/// one subject's PYQ screen and its paper outlines.

@ProviderFor(SubjectPyqFilters)
final subjectPyqFiltersProvider = SubjectPyqFiltersFamily._();

/// University / year / exam type / paper / MCQ-or-theory / chapter picks for
/// one subject's PYQ screen and its paper outlines.
final class SubjectPyqFiltersProvider
    extends $NotifierProvider<SubjectPyqFilters, SubjectPyqFilter> {
  /// University / year / exam type / paper / MCQ-or-theory / chapter picks for
  /// one subject's PYQ screen and its paper outlines.
  SubjectPyqFiltersProvider._({
    required SubjectPyqFiltersFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'subjectPyqFiltersProvider',
         isAutoDispose: false,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$subjectPyqFiltersHash();

  @override
  String toString() {
    return r'subjectPyqFiltersProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  SubjectPyqFilters create() => SubjectPyqFilters();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(SubjectPyqFilter value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<SubjectPyqFilter>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is SubjectPyqFiltersProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$subjectPyqFiltersHash() => r'c4ea3e743e87ae8a22ca7709499161a5b576ca33';

/// University / year / exam type / paper / MCQ-or-theory / chapter picks for
/// one subject's PYQ screen and its paper outlines.

final class SubjectPyqFiltersFamily extends $Family
    with
        $ClassFamilyOverride<
          SubjectPyqFilters,
          SubjectPyqFilter,
          SubjectPyqFilter,
          SubjectPyqFilter,
          String
        > {
  SubjectPyqFiltersFamily._()
    : super(
        retry: null,
        name: r'subjectPyqFiltersProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: false,
      );

  /// University / year / exam type / paper / MCQ-or-theory / chapter picks for
  /// one subject's PYQ screen and its paper outlines.

  SubjectPyqFiltersProvider call(String subjectId) =>
      SubjectPyqFiltersProvider._(argument: subjectId, from: this);

  @override
  String toString() => r'subjectPyqFiltersProvider';
}

/// University / year / exam type / paper / MCQ-or-theory / chapter picks for
/// one subject's PYQ screen and its paper outlines.

abstract class _$SubjectPyqFilters extends $Notifier<SubjectPyqFilter> {
  late final _$args = ref.$arg as String;
  String get subjectId => _$args;

  SubjectPyqFilter build(String subjectId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<SubjectPyqFilter, SubjectPyqFilter>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<SubjectPyqFilter, SubjectPyqFilter>,
              SubjectPyqFilter,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}

@ProviderFor(pyqDetail)
final pyqDetailProvider = PyqDetailFamily._();

final class PyqDetailProvider
    extends
        $FunctionalProvider<
          AsyncValue<PyqDetail>,
          PyqDetail,
          FutureOr<PyqDetail>
        >
    with $FutureModifier<PyqDetail>, $FutureProvider<PyqDetail> {
  PyqDetailProvider._({
    required PyqDetailFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'pyqDetailProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$pyqDetailHash();

  @override
  String toString() {
    return r'pyqDetailProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<PyqDetail> $createElement($ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<PyqDetail> create(Ref ref) {
    final argument = this.argument as String;
    return pyqDetail(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is PyqDetailProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$pyqDetailHash() => r'8745bc3a0effe519046e16754fab8098ba9b116f';

final class PyqDetailFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<PyqDetail>, String> {
  PyqDetailFamily._()
    : super(
        retry: null,
        name: r'pyqDetailProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  PyqDetailProvider call(String questionId) =>
      PyqDetailProvider._(argument: questionId, from: this);

  @override
  String toString() => r'pyqDetailProvider';
}
