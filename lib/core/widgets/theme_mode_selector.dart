import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/spacing.dart';
import '../theme/theme_mode_provider.dart';

/// System / Light / Dark. Light is the stored default.
class ThemeModeSelector extends ConsumerWidget {
  const ThemeModeSelector({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Theme', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: Spacing.sm),
        SegmentedButton<ThemeMode>(
          segments: const [
            ButtonSegment(
              value: ThemeMode.system,
              icon: Icon(Icons.brightness_auto),
              label: Text('System'),
            ),
            ButtonSegment(
              value: ThemeMode.light,
              icon: Icon(Icons.light_mode),
              label: Text('Light'),
            ),
            ButtonSegment(
              value: ThemeMode.dark,
              icon: Icon(Icons.dark_mode),
              label: Text('Dark'),
            ),
          ],
          selected: {mode},
          showSelectedIcon: false,
          style: ButtonStyle(
            foregroundColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.selected)) {
                return scheme.onPrimary;
              }
              return scheme.onSurface;
            }),
            backgroundColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.selected)) {
                return scheme.primary;
              }
              return null;
            }),
          ),
          onSelectionChanged: (next) {
            if (next.isEmpty) return;
            ref.read(themeModeProvider.notifier).setMode(next.first);
          },
        ),
      ],
    );
  }
}
