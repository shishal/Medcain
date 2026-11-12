import 'package:material_ui/material_ui.dart';

import '../../../../core/theme/comic_colors.dart';
import '../../../../core/theme/spacing.dart';
import '../../domain/player_session_state.dart';

class PlayerActionBar extends StatelessWidget {
  const PlayerActionBar({
    super.key,
    required this.session,
    required this.onClear,
    required this.onMarkAndNext,
    required this.onPrevious,
    required this.onSaveAndNext,
    this.onSubmitSection,
  });

  final PlayerSessionState session;
  final VoidCallback onClear;
  final VoidCallback onMarkAndNext;
  final VoidCallback onPrevious;
  final VoidCallback onSaveAndNext;
  final VoidCallback? onSubmitSection;

  @override
  Widget build(BuildContext context) {
    final comic = ComicColors.of(context);

    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(
        Spacing.md,
        Spacing.sm,
        Spacing.md,
        Spacing.md,
      ),
      child: Material(
        color: comic.sticker,
        elevation: 3,
        shadowColor: comic.shadow,
        borderRadius: BorderRadius.circular(22),
        child: Padding(
          padding: const EdgeInsets.all(Spacing.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      key: const Key('player-clear'),
                      onPressed: session.isCurrentAnswerLocked ? null : onClear,
                      child: const Text('Clear Response'),
                    ),
                  ),
                  const SizedBox(width: Spacing.sm),
                  Expanded(
                    child: OutlinedButton(
                      key: const Key('player-mark-next'),
                      onPressed: onMarkAndNext,
                      child: const Text(
                        'Mark for Review & Next',
                        textAlign: TextAlign.center,
                        maxLines: 2,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Spacing.sm),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      key: const Key('player-previous'),
                      onPressed: session.canGoPrevious ? onPrevious : null,
                      child: const Text('Previous'),
                    ),
                  ),
                  const SizedBox(width: Spacing.sm),
                  Expanded(
                    child: FilledButton(
                      key: const Key('player-save-next'),
                      onPressed: session.canGoNext ? onSaveAndNext : null,
                      child: const Text('Save & Next'),
                    ),
                  ),
                ],
              ),
              if (session.canSubmitSection && onSubmitSection != null) ...[
                const SizedBox(height: Spacing.sm),
                FilledButton.tonal(
                  key: const Key('player-submit-section'),
                  onPressed: onSubmitSection,
                  child: const Text('Submit Section & Continue'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
