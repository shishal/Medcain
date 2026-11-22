import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/router/app_routes.dart';
import '../../../auth/presentation/providers/auth_session_provider.dart';
import '../../domain/announcement_link.dart';
import '../providers/broadcast_push_provider.dart';

/// Follows a notification tap after sign-in, splash, and onboarding.
class PushOpenHost extends ConsumerStatefulWidget {
  const PushOpenHost({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<PushOpenHost> createState() => _PushOpenHostState();
}

class _PushOpenHostState extends ConsumerState<PushOpenHost> {
  @override
  Widget build(BuildContext context) {
    final pending = ref.watch(pendingAnnouncementPathProvider);
    if (pending != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _open(pending);
      });
    }
    return widget.child;
  }

  void _open(String pending) {
    if (ref.read(pendingAnnouncementPathProvider) != pending) return;
    if (!ref.read(authSessionProvider)) return;
    final path = GoRouterState.of(context).uri.path;
    if (path == AppRoutes.splash ||
        path == AppRoutes.login ||
        path == AppRoutes.signup ||
        path == AppRoutes.onboarding) {
      return;
    }
    ref.read(pendingAnnouncementPathProvider.notifier).clear();
    openAnnouncementPath(context, pending);
  }
}
