/// Operator-owned support destinations. Replace placeholders before launch.
///
/// Profile hides the WhatsApp community and Telegram channel until the
/// groups exist. The URLs stay here so the tiles can come back later.
abstract final class SupportLinks {
  static const whatsAppUrl = 'https://wa.me/910000000000';
  static const telegramUrl = 'https://t.me/medico_community';
  static const supportEmailAddress = 'medcain@shishal.com';
  static const emailUrl = 'mailto:$supportEmailAddress';

  /// Mail the support desk. [phone] goes in the subject so the inbox can
  /// match the message to the account. Built as a string so `@` in the
  /// address stays literal — `Uri` would encode it as `%40`.
  static String supportMailto({String? phone}) {
    final number = phone?.trim();
    final subject = (number == null || number.isEmpty)
        ? 'MEDCAIN support'
        : 'MEDCAIN support $number';
    return 'mailto:$supportEmailAddress?subject=${Uri.encodeComponent(subject)}';
  }
}
