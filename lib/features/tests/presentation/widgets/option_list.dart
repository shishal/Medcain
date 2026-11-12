import 'package:material_ui/material_ui.dart';

import '../../../../core/theme/spacing.dart';
import '../../domain/player_session_state.dart';
import '../../domain/question_option.dart';
import '../../../../core/theme/player_colors.dart';

class OptionList extends StatelessWidget {
  const OptionList({super.key, required this.session, required this.onSelect});

  final PlayerSessionState session;
  final ValueChanged<QuestionOption> onSelect;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final option in QuestionOption.values) ...[
          OptionTile(
            letter: option.label,
            text: session.currentQuestion.textFor(option),
            visual: session.visualFor(option),
            locked: session.isCurrentAnswerLocked,
            onTap: () => onSelect(option),
          ),
          const SizedBox(height: Spacing.sm),
        ],
      ],
    );
  }
}

class OptionTile extends StatelessWidget {
  const OptionTile({
    super.key,
    required this.letter,
    required this.text,
    required this.visual,
    required this.locked,
    required this.onTap,
  });

  final String letter;
  final String text;
  final OptionVisual visual;
  final bool locked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final (border, fill, fg, icon) = _style(colorScheme);

    return Material(
      color: fill,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Spacing.sm),
        side: BorderSide(
          color: border,
          width: visual == OptionVisual.idle ? 1 : 2,
        ),
      ),
      child: InkWell(
        key: Key('option-$letter'),
        onTap: locked ? null : onTap,
        borderRadius: BorderRadius.circular(Spacing.sm),
        child: Padding(
          padding: const EdgeInsets.all(Spacing.md),
          child: Row(
            children: [
              _LetterBadge(
                letter: letter,
                background: visual == OptionVisual.idle
                    ? colorScheme.onSurfaceVariant
                    : border,
              ),
              const SizedBox(width: Spacing.md),
              Expanded(
                child: Text(
                  text,
                  style: Theme.of(context).textTheme.bodyLarge
                      ?.copyWith(color: fg),
                ),
              ),
              if (icon != null) Icon(icon, color: border),
            ],
          ),
        ),
      ),
    );
  }

  /// Dart 3 record — a typed tuple so border, fill, text color, and icon
  /// return together without a one-off class.
  (Color, Color, Color, IconData?) _style(ColorScheme scheme) {
    return switch (visual) {
      OptionVisual.idle => (
        scheme.outlineVariant,
        scheme.surface,
        scheme.onSurface,
        null,
      ),
      OptionVisual.selected => (
        scheme.primary,
        scheme.primaryContainer,
        scheme.onPrimaryContainer,
        Icons.radio_button_checked,
      ),
      OptionVisual.chosenCorrect || OptionVisual.revealedCorrect => (
        PlayerColors.correct,
        PlayerColors.correct.withValues(alpha: 0.12),
        scheme.onSurface,
        Icons.check_circle,
      ),
      OptionVisual.chosenIncorrect => (
        PlayerColors.incorrect,
        PlayerColors.incorrect.withValues(alpha: 0.12),
        scheme.onSurface,
        Icons.cancel,
      ),
    };
  }
}

class _LetterBadge extends StatelessWidget {
  const _LetterBadge({required this.letter, required this.background});

  final String letter;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: 16,
      backgroundColor: background,
      child: Text(
        letter,
        style: Theme.of(context).textTheme.labelLarge
            ?.copyWith(color: Colors.white, fontWeight: FontWeight.w700),
      ),
    );
  }
}
