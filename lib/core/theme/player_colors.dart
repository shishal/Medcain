import 'package:material_ui/material_ui.dart';

/// Answer / palette colors that are not on [ColorScheme] (correct green,
/// review purple). Keep these in one place so the MCQ player, solution review
/// and the PYQ reader all mark a correct answer the same way.
abstract final class PlayerColors {
  static const Color correct = Color(0xFF2E7D32);
  static const Color incorrect = Color(0xFFC62828);
  static const Color review = Color(0xFF6A1B9A);
  static const Color notVisited = Color(0xFF9E9E9E);
}
