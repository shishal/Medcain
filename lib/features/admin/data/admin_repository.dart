import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_provider.dart';
import '../../../core/supabase/tables.dart';
import '../../../core/utils/result.dart';
import '../../../core/utils/user_facing_error.dart';
import '../domain/admin_models.dart';

part 'admin_repository.g.dart';

/// Admin reads and writes. Screens call this; it calls RPCs or the
/// admin-user-auth Edge Function. It never uses the service-role key.
class AdminRepository {
  AdminRepository(this._client);

  final SupabaseClient _client;

  Future<Result<List<AdminUser>>> searchUsers(String query) {
    return _list(
      RpcFunctions.adminSearchUsers,
      {AdminRpcParams.query: query.trim()},
      AdminUser.fromJson,
      'Could not search users.',
    );
  }

  Future<Result<AdminUser>> getUser(String userId) {
    return _one(
      RpcFunctions.adminGetUser,
      {AdminRpcParams.userId: userId},
      AdminUser.fromJson,
      'Could not load that user.',
    );
  }

  Future<Result<AdminUser>> updateProfile(AdminProfileInput input) {
    return _one(
      RpcFunctions.adminUpdateProfile,
      {
        AdminRpcParams.userId: input.userId,
        AdminRpcParams.fullName: input.fullName,
        AdminRpcParams.phone: input.phone,
        AdminRpcParams.universityId: input.universityId,
        AdminRpcParams.collegeId: input.collegeId,
        AdminRpcParams.batchYear: input.batchYear,
        AdminRpcParams.mbbsPhaseId: input.mbbsPhaseId,
      },
      AdminUser.fromJson,
      'Could not update that profile.',
    );
  }

  /// Each row is id, label, and whether the plan can be newly assigned.
  Future<Result<List<(String, String, bool)>>> listAssignablePlans() async {
    try {
      final raw = await _client.rpc(RpcFunctions.adminListPlans);
      if (raw is! List) return const Success([]);
      return Success([
        for (final item in raw)
          if (item is Map && item['id'] is String)
            (
              item['id'] as String,
              item['is_active'] == true
                  ? (item['name'] as String? ?? 'Plan')
                  : '${item['name'] ?? 'Plan'} (archived)',
              item['is_active'] == true,
            ),
      ]);
    } catch (e) {
      return Failure(
        UserFacingError.from(e, fallback: 'Could not load plans.'),
      );
    }
  }

  Future<Result<AdminUser>> setPlan({
    required String userId,
    required String plan,
    required DateTime? expiresAt,
  }) {
    return _one(
      RpcFunctions.adminSetPlan,
      {
        AdminRpcParams.userId: userId,
        AdminRpcParams.planId: plan,
        AdminRpcParams.expiresAt: expiresAt?.toUtc().toIso8601String(),
      },
      AdminUser.fromJson,
      'Could not update that plan.',
    );
  }

  Future<Result<AdminUser>> clearDeviceSuspension(String userId) {
    return _one(
      RpcFunctions.adminClearDeviceSuspension,
      {AdminRpcParams.userId: userId},
      AdminUser.fromJson,
      'Could not clear the device suspension.',
    );
  }

  Future<Result<void>> setPassword({
    required String userId,
    required String password,
  }) {
    return _authAction({
      'action': 'set_password',
      'user_id': userId,
      'password': password,
    });
  }

  Future<Result<void>> setEmail({
    required String userId,
    required String email,
  }) {
    return _authAction({
      'action': 'set_email',
      'user_id': userId,
      'email': email.trim(),
    });
  }

  Future<Result<void>> setBlocked({
    required String userId,
    required bool blocked,
    String? reason,
  }) {
    return _authAction({
      'action': blocked ? 'block' : 'unblock',
      'user_id': userId,
      'reason': reason ?? '',
    });
  }

  Future<Result<List<AdminQuestionSummary>>> searchQuestions(String query) {
    return _list(
      RpcFunctions.adminSearchQuestions,
      {AdminRpcParams.query: query.trim()},
      AdminQuestionSummary.fromJson,
      'Could not search questions.',
    );
  }

  Future<Result<AdminQuestionDetail>> getQuestion(String questionId) {
    return _one(
      RpcFunctions.adminGetQuestion,
      {AdminRpcParams.questionId: questionId},
      AdminQuestionDetail.fromJson,
      'Could not load that question.',
    );
  }

  Future<Result<String>> saveQuestion(AdminQuestionInput input) async {
    final saved = await _map(RpcFunctions.adminSaveQuestion, {
      AdminRpcParams.body: input.toJson(),
    }, 'Could not save that question.');
    return switch (saved) {
      Success(:final value) => Success(value['id'] as String),
      Failure(:final message) => Failure(message),
    };
  }

  Future<Result<void>> saveAppearance(AdminSittingInput input) async {
    final saved = await _map(RpcFunctions.adminSaveAppearance, {
      AdminRpcParams.body: input.toJson(),
    }, 'Could not save that paper.');
    return switch (saved) {
      Success() => const Success(null),
      Failure(:final message) => Failure(message),
    };
  }

  Future<Result<void>> deleteAppearance({
    required String questionId,
    required String examPaperId,
  }) async {
    try {
      await _client.rpc(
        RpcFunctions.adminDeleteAppearance,
        params: {
          AdminRpcParams.questionId: questionId,
          AdminRpcParams.examPaperId: examPaperId,
        },
      );
      return const Success(null);
    } catch (error) {
      return Failure(_message(error, 'Could not remove that paper.'));
    }
  }

  Future<Result<List<AdminAnnouncement>>> listAnnouncements() {
    return _list(
      RpcFunctions.adminListAnnouncements,
      const {},
      AdminAnnouncement.fromJson,
      'Could not load notifications.',
    );
  }

  Future<Result<AdminAnnouncement>> upsertAnnouncement(
    AdminAnnouncementInput input,
  ) {
    return _one(
      RpcFunctions.adminUpsertAnnouncement,
      {AdminRpcParams.body: input.toJson()},
      AdminAnnouncement.fromJson,
      'Could not save that notification.',
    );
  }

  Future<Result<List<T>>> _list<T>(
    String fn,
    Map<String, dynamic> params,
    T Function(Map<String, dynamic> json) parse,
    String fallback,
  ) async {
    try {
      final raw = await _client.rpc(fn, params: params);
      final rows = raw is List ? raw : const [];
      return Success([
        for (final row in rows)
          if (row is Map) parse(Map<String, dynamic>.from(row)),
      ]);
    } catch (error) {
      return Failure(_message(error, fallback));
    }
  }

  Future<Result<T>> _one<T>(
    String fn,
    Map<String, dynamic> params,
    T Function(Map<String, dynamic> json) parse,
    String fallback,
  ) async {
    final row = await _map(fn, params, fallback);
    return switch (row) {
      Success(:final value) => Success(parse(value)),
      Failure(:final message) => Failure(message),
    };
  }

  Future<Result<Map<String, dynamic>>> _map(
    String fn,
    Map<String, dynamic> params,
    String fallback,
  ) async {
    try {
      final raw = await _client.rpc(fn, params: params);
      if (raw is! Map) {
        return Failure(fallback);
      }
      return Success(Map<String, dynamic>.from(raw));
    } catch (error) {
      return Failure(_message(error, fallback));
    }
  }

  Future<Result<void>> _authAction(Map<String, dynamic> body) async {
    try {
      final response = await _client.functions.invoke(
        RpcFunctions.adminUserAuth,
        body: body,
      );
      final data = response.data;
      if (data is Map && data['ok'] == true) {
        return const Success(null);
      }
      return Failure(_payloadMessage(data, 'Could not update that account.'));
    } on FunctionException catch (error) {
      return Failure(
        _payloadMessage(error.details, 'Could not update that account.'),
      );
    } catch (error) {
      return Failure(_message(error, 'Could not update that account.'));
    }
  }

  String _message(Object error, String fallback) {
    if (UserFacingError.looksOffline(error)) {
      return UserFacingError.offlineMessage;
    }
    if (error is PostgrestException) {
      return _payloadMessage(error.message, fallback);
    }
    return fallback;
  }

  /// Postgres `raise exception` text and Edge Function `{error}` bodies.
  String _payloadMessage(Object? payload, String fallback) {
    if (payload is String) {
      final message = payload.trim();
      if (message.isNotEmpty && message.length < 300) return message;
    }
    if (payload is Map && payload['error'] is String) {
      final message = (payload['error'] as String).trim();
      if (message.isNotEmpty) return message;
    }
    return fallback;
  }
}

@Riverpod(keepAlive: true)
AdminRepository adminRepository(Ref ref) {
  return AdminRepository(ref.watch(supabaseClientProvider));
}
