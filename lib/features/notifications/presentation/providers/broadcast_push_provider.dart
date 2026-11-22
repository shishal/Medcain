import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../auth/data/auth_repository.dart';
import '../../../auth/presentation/providers/auth_session_provider.dart';
import '../../data/broadcast_push.dart';
import '../../data/notifications_repository.dart';
import 'notifications_provider.dart';

part 'broadcast_push_provider.g.dart';

@Riverpod(keepAlive: true)
BroadcastPushController broadcastPushController(Ref ref) {
  final controller = BroadcastPushController();
  ref.onDispose(controller.dispose);
  return controller;
}

/// Path from a notification tap, opened once the student is past splash.
@Riverpod(keepAlive: true)
class PendingAnnouncementPath extends _$PendingAnnouncementPath {
  @override
  String? build() => null;

  void setPath(String path) => state = path;

  void clear() => state = null;
}

/// Keeps this install on the broadcast topic while a session exists.
@Riverpod(keepAlive: true)
void broadcastPush(Ref ref) {
  final signedIn = ref.watch(authSessionProvider);
  final controller = ref.watch(broadcastPushControllerProvider);
  final auth = ref.watch(authRepositoryProvider);

  controller.onOpen = (path) {
    ref.read(pendingAnnouncementPathProvider.notifier).setPath(path);
  };
  controller.onForeground = () {
    ref.invalidate(announcementsProvider);
  };
  controller.onToken = (token) async {
    await ref.read(notificationsRepositoryProvider).registerPushToken(token);
  };
  // The hook runs before AuthRepository drops the JWT, so the delete
  // still belongs to this account. Topic unsubscribe follows in sync.
  auth.setBeforeSignOut(() async {
    final token = await controller.takeTokenForSignOut();
    if (token == null) return;
    await ref.read(notificationsRepositoryProvider).unregisterPushToken(token);
  });
  // A tap can arrive while this provider is between builds. Deliver it
  // after build so we don't write another provider mid-build.
  final pending = controller.takePendingPath();
  final refreshInbox = controller.takeForeground();
  if (pending != null || refreshInbox) {
    unawaited(
      Future.microtask(() {
        if (pending != null) {
          ref.read(pendingAnnouncementPathProvider.notifier).setPath(pending);
        }
        if (refreshInbox) ref.invalidate(announcementsProvider);
      }),
    );
  }
  ref.onDispose(() {
    controller.onOpen = null;
    controller.onForeground = null;
    controller.onToken = null;
    auth.setBeforeSignOut(null);
  });

  unawaited(controller.sync(signedIn: signedIn));
}
