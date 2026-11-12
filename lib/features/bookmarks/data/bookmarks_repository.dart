import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_provider.dart';
import '../../../core/supabase/tables.dart';
import '../../../core/utils/result.dart';
import '../../../core/utils/user_facing_error.dart';
import '../domain/bookmarked_lesson.dart';
import '../domain/bookmarked_question.dart';

part 'bookmarks_repository.g.dart';

/// Own-user bookmarks. Presentation never calls Supabase directly.
class BookmarksRepository {
  BookmarksRepository(this._client);

  final SupabaseClient _client;

  Future<Result<Set<String>>> fetchIds() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      return const Failure('Not signed in.');
    }

    try {
      final rows = await _client
          .from(Tables.bookmarks)
          .select(BookmarkColumns.questionId)
          .eq(BookmarkColumns.userId, userId);

      return Success({
        for (final row in (rows as List<dynamic>).cast<Map<String, dynamic>>())
          if (row[BookmarkColumns.questionId] is String)
            row[BookmarkColumns.questionId] as String,
      });
    } catch (e) {
      return Failure(
        UserFacingError.from(
          e,
          fallback: 'Could not load bookmarks. Please try again.',
        ),
      );
    }
  }

  Future<Result<List<BookmarkedQuestion>>> fetchAll() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      return const Failure('Not signed in.');
    }

    try {
      final rows = await _client
          .from(Tables.bookmarks)
          .select(
            '${BookmarkColumns.questionId},${BookmarkColumns.createdAt}',
          )
          .eq(BookmarkColumns.userId, userId)
          .order(BookmarkColumns.createdAt, ascending: false);

      final bookmarks = (rows as List<dynamic>).cast<Map<String, dynamic>>();
      final questionIds = [
        for (final row in bookmarks)
          if (row[BookmarkColumns.questionId] is String)
            row[BookmarkColumns.questionId] as String,
      ];
      final listingRows = questionIds.isEmpty
          ? const <Map<String, dynamic>>[]
          : (await _client
                    .from(Tables.questionListings)
                    .select(
                      '${QuestionColumns.id},${QuestionColumns.questionText},'
                      '${QuestionColumns.topicId}',
                    )
                    .inFilter(QuestionColumns.id, questionIds)
                as List<dynamic>)
              .cast<Map<String, dynamic>>();
      final listingById = {
        for (final row in listingRows)
          if (row[QuestionColumns.id] is String)
            row[QuestionColumns.id] as String: row,
      };
      final topicIds = {
        for (final row in listingRows)
          if (row[QuestionColumns.topicId] is String)
            row[QuestionColumns.topicId] as String,
      };
      final topicRows = topicIds.isEmpty
          ? const <Map<String, dynamic>>[]
          : (await _client
                    .from(Tables.topics)
                    .select(
                      '${TopicColumns.id},${TopicColumns.name},'
                      '${TopicColumns.subjectId}',
                    )
                    .inFilter(TopicColumns.id, topicIds.toList())
                as List<dynamic>)
              .cast<Map<String, dynamic>>();
      final subjectIds = {
        for (final row in topicRows)
          if (row[TopicColumns.subjectId] is String)
            row[TopicColumns.subjectId] as String,
      };
      final subjectRows = subjectIds.isEmpty
          ? const <Map<String, dynamic>>[]
          : (await _client
                    .from(Tables.subjects)
                    .select('${SubjectColumns.id},${SubjectColumns.name}')
                    .inFilter(SubjectColumns.id, subjectIds.toList())
                as List<dynamic>)
              .cast<Map<String, dynamic>>();
      final subjectName = {
        for (final row in subjectRows)
          if (row[SubjectColumns.id] is String)
            row[SubjectColumns.id] as String:
                row[SubjectColumns.name] as String? ?? '',
      };
      final topicById = {
        for (final row in topicRows)
          if (row[TopicColumns.id] is String)
            row[TopicColumns.id] as String: row,
      };

      return Success([
        for (final row in bookmarks)
          if (row[BookmarkColumns.questionId] is String)
            ?_bookmarked(row, listingById, topicById, subjectName),
      ]);
    } catch (e) {
      return Failure(
        UserFacingError.from(
          e,
          fallback: 'Could not load bookmarks. Please try again.',
        ),
      );
    }
  }

  Future<Result<void>> add(String questionId) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      return const Failure('Not signed in.');
    }

    try {
      await _client.from(Tables.bookmarks).insert({
        BookmarkColumns.userId: userId,
        BookmarkColumns.questionId: questionId,
      });
      return const Success(null);
    } on PostgrestException catch (e) {
      // Unique violation — already bookmarked. Treat as success.
      if (e.code == '23505') return const Success(null);
      return Failure(
        UserFacingError.from(
          e,
          fallback: 'Could not save bookmark. Please try again.',
        ),
      );
    } catch (e) {
      return Failure(
        UserFacingError.from(
          e,
          fallback: 'Could not save bookmark. Please try again.',
        ),
      );
    }
  }

  Future<Result<void>> remove(String questionId) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      return const Failure('Not signed in.');
    }

    try {
      await _client
          .from(Tables.bookmarks)
          .delete()
          .eq(BookmarkColumns.userId, userId)
          .eq(BookmarkColumns.questionId, questionId);
      return const Success(null);
    } catch (e) {
      return Failure(
        UserFacingError.from(
          e,
          fallback: 'Could not remove bookmark. Please try again.',
        ),
      );
    }
  }

  Future<Result<Set<String>>> fetchLessonIds() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      return const Failure('Not signed in.');
    }

    try {
      final rows = await _client
          .from(Tables.lessonBookmarks)
          .select(LessonBookmarkColumns.lessonId)
          .eq(LessonBookmarkColumns.userId, userId);

      return Success({
        for (final row in (rows as List<dynamic>).cast<Map<String, dynamic>>())
          if (row[LessonBookmarkColumns.lessonId] is String)
            row[LessonBookmarkColumns.lessonId] as String,
      });
    } catch (e) {
      return Failure(
        UserFacingError.from(
          e,
          fallback: 'Could not load lesson bookmarks. Please try again.',
        ),
      );
    }
  }

  Future<Result<List<BookmarkedLesson>>> fetchLessons() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      return const Failure('Not signed in.');
    }

    try {
      final rows = await _client
          .from(Tables.lessonBookmarks)
          .select(
            '${LessonBookmarkColumns.lessonId},'
            '${LessonBookmarkColumns.lessonEmbed}:${Tables.lessons}('
            '${LessonColumns.id},${LessonColumns.name})',
          )
          .eq(LessonBookmarkColumns.userId, userId)
          .order(LessonBookmarkColumns.createdAt, ascending: false);

      return Success([
        for (final row in (rows as List<dynamic>).cast<Map<String, dynamic>>())
          if (row[LessonBookmarkColumns.lessonId] is String)
            BookmarkedLesson(
              lessonId: row[LessonBookmarkColumns.lessonId] as String,
              name: _lessonName(row),
            ),
      ]);
    } catch (e) {
      return Failure(
        UserFacingError.from(
          e,
          fallback: 'Could not load lesson bookmarks. Please try again.',
        ),
      );
    }
  }

  Future<Result<void>> addLesson(String lessonId) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      return const Failure('Not signed in.');
    }

    try {
      await _client.from(Tables.lessonBookmarks).insert({
        LessonBookmarkColumns.userId: userId,
        LessonBookmarkColumns.lessonId: lessonId,
      });
      return const Success(null);
    } on PostgrestException catch (e) {
      if (e.code == '23505') return const Success(null);
      return Failure(
        UserFacingError.from(
          e,
          fallback: 'Could not save bookmark. Please try again.',
        ),
      );
    } catch (e) {
      return Failure(
        UserFacingError.from(
          e,
          fallback: 'Could not save bookmark. Please try again.',
        ),
      );
    }
  }

  Future<Result<void>> removeLesson(String lessonId) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      return const Failure('Not signed in.');
    }

    try {
      await _client
          .from(Tables.lessonBookmarks)
          .delete()
          .eq(LessonBookmarkColumns.userId, userId)
          .eq(LessonBookmarkColumns.lessonId, lessonId);
      return const Success(null);
    } catch (e) {
      return Failure(
        UserFacingError.from(
          e,
          fallback: 'Could not remove bookmark. Please try again.',
        ),
      );
    }
  }

  static String _lessonName(Map<String, dynamic> row) {
    final embed = row[LessonBookmarkColumns.lessonEmbed];
    if (embed is Map<String, dynamic>) {
      return embed[LessonColumns.name] as String? ?? 'Lesson';
    }
    if (embed is Map) {
      return embed[LessonColumns.name] as String? ?? 'Lesson';
    }
    return 'Lesson';
  }
}

BookmarkedQuestion? _bookmarked(
  Map<String, dynamic> row,
  Map<String, Map<String, dynamic>> listingById,
  Map<String, Map<String, dynamic>> topicById,
  Map<String, String> subjectName,
) {
  final id = row[BookmarkColumns.questionId] as String?;
  if (id == null) return null;
  final listing = listingById[id];
  final topicId = listing?[QuestionColumns.topicId] as String?;
  final topic = topicId == null ? null : topicById[topicId];
  final subjectId = topic?[TopicColumns.subjectId] as String?;
  return BookmarkedQuestion.fromJson({
    BookmarkColumns.questionId: id,
    BookmarkColumns.createdAt: row[BookmarkColumns.createdAt],
    BookmarkColumns.questionEmbed: listing == null
        ? null
        : {
            QuestionColumns.id: id,
            QuestionColumns.questionText: listing[QuestionColumns.questionText],
            QuestionColumns.topicEmbed: topic == null
                ? null
                : {
                    TopicColumns.name: topic[TopicColumns.name],
                    TopicColumns.subjectEmbed: {
                      SubjectColumns.name: subjectName[subjectId],
                    },
                  },
          },
  });
}

@Riverpod(keepAlive: true)
BookmarksRepository bookmarksRepository(Ref ref) {
  return BookmarksRepository(ref.watch(supabaseClientProvider));
}
