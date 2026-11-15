// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'bookmarks_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Question IDs the signed-in user has bookmarked. Persists in Supabase;
/// this set is only a cache so the review-screen icon can toggle instantly.

@ProviderFor(BookmarkedIds)
final bookmarkedIdsProvider = BookmarkedIdsProvider._();

/// Question IDs the signed-in user has bookmarked. Persists in Supabase;
/// this set is only a cache so the review-screen icon can toggle instantly.
final class BookmarkedIdsProvider
    extends $AsyncNotifierProvider<BookmarkedIds, Set<String>> {
  /// Question IDs the signed-in user has bookmarked. Persists in Supabase;
  /// this set is only a cache so the review-screen icon can toggle instantly.
  BookmarkedIdsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'bookmarkedIdsProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$bookmarkedIdsHash();

  @$internal
  @override
  BookmarkedIds create() => BookmarkedIds();
}

String _$bookmarkedIdsHash() => r'2a4b0de05ebbd868d50c17f4e8f92ce117afdea7';

/// Question IDs the signed-in user has bookmarked. Persists in Supabase;
/// this set is only a cache so the review-screen icon can toggle instantly.

abstract class _$BookmarkedIds extends $AsyncNotifier<Set<String>> {
  FutureOr<Set<String>> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<AsyncValue<Set<String>>, Set<String>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<Set<String>>, Set<String>>,
              AsyncValue<Set<String>>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

/// Full bookmark rows for "My Bookmarks". Plan-locked questions stay in the
/// list as placeholders — we still have the id, just not the stem.

@ProviderFor(bookmarksList)
final bookmarksListProvider = BookmarksListProvider._();

/// Full bookmark rows for "My Bookmarks". Plan-locked questions stay in the
/// list as placeholders — we still have the id, just not the stem.

final class BookmarksListProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<BookmarkedQuestion>>,
          List<BookmarkedQuestion>,
          FutureOr<List<BookmarkedQuestion>>
        >
    with
        $FutureModifier<List<BookmarkedQuestion>>,
        $FutureProvider<List<BookmarkedQuestion>> {
  /// Full bookmark rows for "My Bookmarks". Plan-locked questions stay in the
  /// list as placeholders — we still have the id, just not the stem.
  BookmarksListProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'bookmarksListProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$bookmarksListHash();

  @$internal
  @override
  $FutureProviderElement<List<BookmarkedQuestion>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<BookmarkedQuestion>> create(Ref ref) {
    return bookmarksList(ref);
  }
}

String _$bookmarksListHash() => r'40311f49469854dd8d175f3974d9d17238c10956';

/// Lesson IDs the signed-in user has bookmarked. Shared across all
/// `LessonBookmarkIconButton`s so rendering N lesson rows fires 1 query,
/// not N parallel queries, and toggling updates `BookmarksScreen` immediately.

@ProviderFor(BookmarkedLessonIds)
final bookmarkedLessonIdsProvider = BookmarkedLessonIdsProvider._();

/// Lesson IDs the signed-in user has bookmarked. Shared across all
/// `LessonBookmarkIconButton`s so rendering N lesson rows fires 1 query,
/// not N parallel queries, and toggling updates `BookmarksScreen` immediately.
final class BookmarkedLessonIdsProvider
    extends $AsyncNotifierProvider<BookmarkedLessonIds, Set<String>> {
  /// Lesson IDs the signed-in user has bookmarked. Shared across all
  /// `LessonBookmarkIconButton`s so rendering N lesson rows fires 1 query,
  /// not N parallel queries, and toggling updates `BookmarksScreen` immediately.
  BookmarkedLessonIdsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'bookmarkedLessonIdsProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$bookmarkedLessonIdsHash();

  @$internal
  @override
  BookmarkedLessonIds create() => BookmarkedLessonIds();
}

String _$bookmarkedLessonIdsHash() =>
    r'a443857e7151e7079040ca349c53a4afd8336a79';

/// Lesson IDs the signed-in user has bookmarked. Shared across all
/// `LessonBookmarkIconButton`s so rendering N lesson rows fires 1 query,
/// not N parallel queries, and toggling updates `BookmarksScreen` immediately.

abstract class _$BookmarkedLessonIds extends $AsyncNotifier<Set<String>> {
  FutureOr<Set<String>> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<AsyncValue<Set<String>>, Set<String>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<Set<String>>, Set<String>>,
              AsyncValue<Set<String>>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

/// Bookmarked lessons, shown as a second section under the questions.

@ProviderFor(lessonBookmarksList)
final lessonBookmarksListProvider = LessonBookmarksListProvider._();

/// Bookmarked lessons, shown as a second section under the questions.

final class LessonBookmarksListProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<BookmarkedLesson>>,
          List<BookmarkedLesson>,
          FutureOr<List<BookmarkedLesson>>
        >
    with
        $FutureModifier<List<BookmarkedLesson>>,
        $FutureProvider<List<BookmarkedLesson>> {
  /// Bookmarked lessons, shown as a second section under the questions.
  LessonBookmarksListProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'lessonBookmarksListProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$lessonBookmarksListHash();

  @$internal
  @override
  $FutureProviderElement<List<BookmarkedLesson>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<BookmarkedLesson>> create(Ref ref) {
    return lessonBookmarksList(ref);
  }
}

String _$lessonBookmarksListHash() =>
    r'0a8b7ac3478963d09dd9d8e78dc31fc55a8f1305';
