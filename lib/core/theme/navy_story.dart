import 'package:flutter/material.dart';

/// Navy story chrome: dusk sky, night sheet, one purple pill.
///
/// The MEDCAIN mark stays brand blue (`AppTheme.seedColor`). These colors
/// are the screen treatment, not a second logo.
abstract final class NavyStory {
  static const Color cta = Color(0xFF6D28D9);
  static const Color railStart = Color(0xFF7C3AED);
  static const Color railEnd = Color(0xFF0891B2);

  static const Color canvasLight = Color(0xFFF3F0FA);
  static const Color canvasDark = Color(0xFF070B14);
  static const Color sheetLight = Color(0xFFFFFBFF);
  static const Color sheetDark = Color(0xFF101628);
  static const Color sheetLiftLight = Color(0xFFF4F1FA);
  static const Color sheetLiftDark = Color(0xFF1A2238);

  static Color canvas(Brightness brightness) =>
      brightness == Brightness.dark ? canvasDark : canvasLight;

  static Color sheet(Brightness brightness) =>
      brightness == Brightness.dark ? sheetDark : sheetLight;

  /// Top-to-bottom sky. Paint this once on the scaffold so a rounded
  /// sheet below can reveal the same gradient in its corners.
  static LinearGradient sky(Brightness brightness) {
    if (brightness == Brightness.dark) {
      return const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF3A2A78), Color(0xFF24356E), Color(0xFF070B14)],
        stops: [0, 0.42, 1],
      );
    }
    return const LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xFFB9A6F2), Color(0xFFF0C9E4), Color(0xFFF3F0FA)],
      stops: [0, 0.48, 1],
    );
  }
}
