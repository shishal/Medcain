import 'package:material_ui/material_ui.dart';

/// Paths and helpers for MEDCAIN brand art + Docci comic illustrations.
///
/// Docci is MEDCAIN’s intern mascot — a round comic med student, not a gecko.
///
/// Mark assets come in dark-canvas (white ink) and light-canvas (dark ink)
/// pairs — pick with [markFor] / [badgeFor] / [logoFullFor] from
/// [Theme.of] brightness so logos stay readable in both themes.
abstract final class BrandAssets {
  static const mascotName = 'Docci';
  static const mascotHeroTag = 'docci-mascot';

  /// M + ECG mark only (transparent white ink). Dark splash / dark chrome.
  static const splashLogo = 'assets/branding/splash_logo.png';

  /// M + ECG mark only (transparent dark ink). Light splash / light chrome.
  static const splashLogoLight = 'assets/branding/splash_logo_light.png';

  /// Square launcher art (black field). Readable badge on light UI.
  static const appIcon = 'assets/branding/app_icon.png';

  /// Square badge on light paper field. Readable on dark UI chrome.
  static const appIconLight = 'assets/branding/app_icon_light.png';

  /// Full lockup: mark + MEDCAIN + tagline (white ink, transparent).
  static const logoFull = 'assets/branding/logo_full.png';

  /// Full lockup remapped for light paper (dark ink + blue ECG).
  static const logoFullLight = 'assets/branding/logo_full_light.png';

  static const mascotWave = 'assets/illustrations/mascot_wave.png';
  static const mascotStudy = 'assets/illustrations/mascot_study.png';
  static const mascotAvatar = 'assets/illustrations/mascot_avatar.png';
  static const doodleEquipment = 'assets/illustrations/doodle_equipment.jpg';
  static const yearFirst = 'assets/illustrations/year_first.jpg';
  static const yearSecond = 'assets/illustrations/year_second.jpg';
  static const yearThird = 'assets/illustrations/year_third.jpg';
  static const yearFinal = 'assets/illustrations/year_final.jpg';

  /// Transparent ECG-M mark that contrasts with [brightness]'s canvas.
  static String markFor(Brightness brightness) =>
      brightness == Brightness.dark ? splashLogo : splashLogoLight;

  /// Squared badge for headers — black-field on light, paper-field on dark.
  static String badgeFor(Brightness brightness) =>
      brightness == Brightness.dark ? appIconLight : appIcon;

  /// Full lockup asset for [brightness].
  static String logoFullFor(Brightness brightness) =>
      brightness == Brightness.dark ? logoFull : logoFullLight;

  /// Pick year art from MBBS phase code/name/order. 1st → skull, 2nd → lab,
  /// 3rd → clinics, final → stethoscope.
  static String yearArt({
    required String code,
    required String name,
    required int displayOrder,
  }) {
    final blob = '${code.toLowerCase()} ${name.toLowerCase()}';
    if (_looksFinal(blob, displayOrder)) return yearFinal;
    if (_looksThird(blob, displayOrder)) return yearThird;
    if (_looksSecond(blob, displayOrder)) return yearSecond;
    return yearFirst;
  }

  static bool _looksFinal(String blob, int order) =>
      blob.contains('final') ||
      blob.contains('phase4') ||
      blob.contains('year4') ||
      blob.contains('year 4') ||
      blob.contains('4th') ||
      order >= 4;

  static bool _looksThird(String blob, int order) =>
      blob.contains('third') ||
      blob.contains('phase3') ||
      blob.contains('year3') ||
      blob.contains('year 3') ||
      blob.contains('3rd') ||
      blob.contains('part 1') ||
      order == 3;

  static bool _looksSecond(String blob, int order) =>
      blob.contains('second') ||
      blob.contains('phase2') ||
      blob.contains('year2') ||
      blob.contains('year 2') ||
      blob.contains('2nd') ||
      order == 2;
}
