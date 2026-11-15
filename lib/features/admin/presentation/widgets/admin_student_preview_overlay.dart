import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/spacing.dart';
import '../../../profile/presentation/providers/user_profile_provider.dart';
import '../providers/admin_student_preview_provider.dart';

/// Floating "back to Admin" chip. Drawn only while an admin is previewing
/// the student app, so other accounts never see it.
class AdminStudentPreviewOverlay extends ConsumerWidget {
  const AdminStudentPreviewOverlay({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final previewing = ref.watch(adminStudentPreviewProvider);
    final isAdmin = ref.watch(userProfileProvider).value?.isAdmin ?? false;
    if (!previewing || !isAdmin) return child;

    final scheme = Theme.of(context).colorScheme;
    final top = MediaQuery.paddingOf(context).top;

    // The chip sits above every student route, including ones outside the
    // bottom nav, without shifting their layout.
    return Stack(
      fit: StackFit.expand,
      children: [
        child,
        Positioned(
          top: top + Spacing.sm,
          left: 0,
          right: 0,
          child: Center(
            child: Material(
              elevation: 6,
              color: scheme.inverseSurface,
              borderRadius: BorderRadius.circular(999),
              child: Padding(
                padding: const EdgeInsets.only(left: Spacing.md),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Student view',
                      style: Theme.of(context).textTheme.labelLarge
                          ?.copyWith(color: scheme.onInverseSurface),
                    ),
                    TextButton(
                      style: TextButton.styleFrom(
                        foregroundColor: scheme.onInverseSurface,
                        visualDensity: VisualDensity.compact,
                      ),
                      onPressed: () {
                        ref.read(adminStudentPreviewProvider.notifier).close();
                      },
                      child: const Text('Admin'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
