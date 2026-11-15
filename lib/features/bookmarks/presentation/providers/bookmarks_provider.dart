import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../core/utils/result.dart';
import '../../../auth/presentation/providers/auth_session_provider.dart';
import '../../data/bookmarks_repository.dart';
import '../../domain/bookmarked_lesson.dart';
import '../../domain/bookmarked_question.dart';

part 'bookmarks_provider.g.dart';

/// Question IDs the signed-in user has bookmarked. Persists in Supabase;
/// this set is only a cache so the review-screen icon can toggle instantly.
@Riverpod(keepAlive: true)
class BookmarkedIds extends _$BookmarkedIds {
  final _inFlight = <String>{};

  @override
  Future<Set<String>> build() async {
    _inFlight.clear();
    final isSignedIn = ref.watch(authSessionProvider);
    if (!isSignedIn) return {};

    final result = await ref.read(bookmarksRepositoryProvider).fetchIds();
    return switch (result) {
      Success(:final value) => value,
      Failure(:final message) => throw Exception(message),
    };
  }

  /// Optimistic add/remove, then write through to Supabase. Reverts the
  /// icon if the write fails so the UI never claims a row that isn't stored.
  Future<Result<void>> toggle(String questionId) async {
    if (_inFlight.contains(questionId)) {
      return const Success(null);
    }

    final current = Set<String>.from(state.value ?? const <String>{});
    final adding = !current.contains(questionId);
    final next = Set<String>.from(current);
    if (adding) {
      next.add(questionId);
    } else {
      next.remove(questionId);
    }
    state = AsyncData(next);
    _inFlight.add(questionId);

    try {
      final repo = ref.read(bookmarksRepositoryProvider);
      final result = adding
          ? await repo.add(questionId)
          : await repo.remove(questionId);

      switch (result) {
        case Success():
          ref.invalidate(bookmarksListProvider);
          return result;
        case Failure():
          state = AsyncData(current);
          return result;
      }
    } finally {
      _inFlight.remove(questionId);
    }
  }
}

/// Full bookmark rows for "My Bookmarks". Plan-locked questions stay in the
/// list as placeholders — we still have the id, just not the stem.
@riverpod
Future<List<BookmarkedQuestion>> bookmarksList(Ref ref) async {
  final isSignedIn = ref.watch(authSessionProvider);
  if (!isSignedIn) return const [];

  final result = await ref.read(bookmarksRepositoryProvider).fetchAll();
  return switch (result) {
    Success(:final value) => value,
    Failure(:final message) => throw Exception(message),
  };
}

/// Lesson IDs the signed-in user has bookmarked. Shared across all
/// `LessonBookmarkIconButton`s so rendering N lesson rows fires 1 query,
/// not N parallel queries, and toggling updates `BookmarksScreen` immediately.
@Riverpod(keepAlive: true)
class BookmarkedLessonIds extends _$BookmarkedLessonIds {
  final _inFlight = <String>{};

  @override
  Future<Set<String>> build() async {
    _inFlight.clear();
    final isSignedIn = ref.watch(authSessionProvider);
    if (!isSignedIn) return {};

    final result = await ref.read(bookmarksRepositoryProvider).fetchLessonIds();
    return switch (result) {
      Success(:final value) => value,
      Failure(:final message) => throw Exception(message),
    };
  }

  Future<Result<void>> toggle(String lessonId) async {
    if (_inFlight.contains(lessonId)) {
      return const Success(null);
    }

    final current = Set<String>.from(state.value ?? const <String>{});
    final adding = !current.contains(lessonId);
    final next = Set<String>.from(current);
    if (adding) {
      next.add(lessonId);
    } else {
      next.remove(lessonId);
    }
    state = AsyncData(next);
    _inFlight.add(lessonId);

    try {
      final repo = ref.read(bookmarksRepositoryProvider);
      final result = adding
          ? await repo.addLesson(lessonId)
          : await repo.removeLesson(lessonId);

      switch (result) {
        case Success():
          ref.invalidate(lessonBookmarksListProvider);
          return result;
        case Failure():
          state = AsyncData(current);
          return result;
      }
    } finally {
      _inFlight.remove(lessonId);
    }
  }
}

/// Bookmarked lessons, shown as a second section under the questions.
@riverpod
Future<List<BookmarkedLesson>> lessonBookmarksList(Ref ref) async {
  final isSignedIn = ref.watch(authSessionProvider);
  if (!isSignedIn) return const [];

  final result = await ref.read(bookmarksRepositoryProvider).fetchLessons();
  return switch (result) {
    Success(:final value) => value,
    Failure(:final message) => throw Exception(message),
  };
}
