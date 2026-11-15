/// Phone rules shared with `supabase/functions/_shared/whatsapp_auth.ts`.
///
/// A 10-digit Indian mobile (starts with 6–9) is treated as +91. Any other
/// country must be entered with a leading +.
abstract final class WhatsAppPhone {
  static final _lettersRe = RegExp('[a-zA-Z]');
  static final _nonDigitsRe = RegExp(r'\D');
  static final _indian10Re = RegExp(r'^[6-9]\d{9}$');
  static final _indian010Re = RegExp(r'^0[6-9]\d{9}$');
  static final _indian91Re = RegExp(r'^91[6-9]\d{9}$');
  static final _e164DigitsRe = RegExp(r'^[1-9]\d{7,14}$');

  static String? normalize(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty || trimmed.length > 32) return null;
    if (_lettersRe.hasMatch(trimmed)) return null;

    final digits = trimmed.replaceAll(_nonDigitsRe, '');
    if (trimmed.startsWith('+')) return _toE164(digits);
    if (_indian10Re.hasMatch(digits)) {
      return _toE164('91$digits');
    }
    if (_indian010Re.hasMatch(digits)) {
      return _toE164('91${digits.substring(1)}');
    }
    if (_indian91Re.hasMatch(digits)) return _toE164(digits);
    if (digits.startsWith('00') && digits.length > 4) {
      return _toE164(digits.substring(2));
    }
    return null;
  }

  static String? _toE164(String digits) {
    if (!_e164DigitsRe.hasMatch(digits)) return null;
    if (digits.startsWith('91') && !_indian91Re.hasMatch(digits)) {
      return null;
    }
    return '+$digits';
  }

  static String? validator(String? value) {
    if (normalize(value ?? '') == null) {
      return 'Enter a 10-digit Indian mobile number, or a full international number starting with +.';
    }
    return null;
  }
}

/// Mailbox created only so GoTrue can mint a session. Students never see it.
const whatsAppSyntheticEmailDomain = 'auth.medico.internal';

bool isSyntheticAuthEmail(String? email) {
  if (email == null || email.isEmpty) return false;
  return email.toLowerCase().endsWith('@$whatsAppSyntheticEmailDomain');
}
