import 'dart:developer' as developer;

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_provider.dart';
import '../../../core/supabase/tables.dart';
import '../../../core/utils/result.dart';
import '../../../core/utils/user_facing_error.dart';
import '../domain/app_announcement.dart';

part 'notifications_repository.g.dart';

/// Active announcements + own read receipts. Presentation never calls Supabase.
class NotificationsRepository {
  NotificationsRepository(this._client);

  final SupabaseClient _client;

  Future<Result<List<AppAnnouncement>>> fetchActive() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      return const Failure('Not signed in.');
    }

    try {
      // RLS hides inactive / expired rows. Embed only returns this user's reads.
      final rows = await _client
          .from(Tables.announcements)
          .select(
            '${AnnouncementColumns.id},'
            '${AnnouncementColumns.title},'
            '${AnnouncementColumns.body},'
            '${AnnouncementColumns.category},'
            '${AnnouncementColumns.deepLink},'
            '${AnnouncementColumns.publishedAt},'
            '${AnnouncementColumns.expiresAt},'
            '${AnnouncementColumns.readsEmbed}:${Tables.announcementReads}('
            '${AnnouncementReadColumns.readAt}'
            ')',
          )
          .order(AnnouncementColumns.publishedAt, ascending: false);

      return Success([
        for (final row in (rows as List<dynamic>).cast<Map<String, dynamic>>())
          ?AppAnnouncement.fromJson(row),
      ]);
    } catch (e) {
      return Failure(
        UserFacingError.from(
          e,
          fallback: 'Could not load notifications. Please try again.',
        ),
      );
    }
  }

  Future<Result<void>> markRead(String announcementId) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      return const Failure('Not signed in.');
    }

    try {
      // Plain insert (not upsert): PostgREST upsert is ON CONFLICT DO UPDATE
      // and needs UPDATE grants/policies we intentionally do not give students.
      await _client.from(Tables.announcementReads).insert({
        AnnouncementReadColumns.userId: userId,
        AnnouncementReadColumns.announcementId: announcementId,
      });
      return const Success(null);
    } on PostgrestException catch (e) {
      // Unique violation — already marked read.
      if (e.code == '23505') return const Success(null);
      return Failure(
        UserFacingError.from(
          e,
          fallback: 'Could not update notification. Please try again.',
        ),
      );
    } catch (e) {
      return Failure(
        UserFacingError.from(
          e,
          fallback: 'Could not update notification. Please try again.',
        ),
      );
    }
  }

  /// Saves this phone's Firebase token for the signed-in account.
  ///
  /// The row is keyed by the token, so the next account on this phone
  /// replaces the previous one. Call [unregisterPushToken] before sign-out
  /// removes the session.
  Future<Result<void>> registerPushToken(String token) {
    return _writeToken(
      RpcFunctions.registerPushToken,
      token,
      'Could not register this phone for notifications.',
    );
  }

  /// Removes this phone's Firebase token while the account is still signed in.
  Future<Result<void>> unregisterPushToken(String token) {
    return _writeToken(
      RpcFunctions.unregisterPushToken,
      token,
      'Could not remove this phone from notifications.',
    );
  }

  Future<Result<void>> _writeToken(
    String function,
    String token,
    String fallback,
  ) async {
    final trimmed = token.trim();
    if (trimmed.isEmpty) return const Success(null);
    if (_client.auth.currentUser == null) {
      return const Failure('Not signed in.');
    }

    try {
      await _client.rpc(
        function,
        params: {PushTokenParams.token: trimmed},
      );
      return const Success(null);
    } catch (error) {
      developer.log(fallback, name: 'broadcast_push', error: error);
      return Failure(UserFacingError.from(error, fallback: fallback));
    }
  }
}

@Riverpod(keepAlive: true)
NotificationsRepository notificationsRepository(Ref ref) {
  return NotificationsRepository(ref.watch(supabaseClientProvider));
}
