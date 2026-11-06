import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/result.dart';
import '../../../profile/presentation/providers/user_profile_provider.dart';
import '../../data/auth_repository.dart';
import '../providers/auth_session_provider.dart';

/// On app resume, confirms this install is still the active device.
///
/// If another phone claimed the account, forces a local sign-out.
class DeviceSessionGuard extends ConsumerStatefulWidget {
  const DeviceSessionGuard({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<DeviceSessionGuard> createState() => _DeviceSessionGuardState();
}

class _DeviceSessionGuardState extends ConsumerState<DeviceSessionGuard>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // ignore: discarded_futures
      _assertOnResume();
    }
  }

  Future<void> _assertOnResume() async {
    if (!ref.read(authSessionProvider)) return;

    final result = await ref.read(authRepositoryProvider).assertActiveDevice();
    if (!mounted) return;

    switch (result) {
      case Success(:final value):
        if (!value) {
          await ref
              .read(authSessionProvider.notifier)
              .signOutBecauseOtherDevice();
        }
      case Failure():
        // Network blip — don't kick; next resume / splash will retry.
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    // A banned session can outlive the GoTrue ban by one access token.
    // blocked_at on the profile row signs that session out locally.
    ref.listen(userProfileProvider, (previous, next) {
      if (next.asData?.value?.blockedAt == null) return;
      ref.read(authRepositoryProvider).signOut();
    });
    return widget.child;
  }
}
