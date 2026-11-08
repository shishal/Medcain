/// One in-progress WhatsApp sign-in, returned by the start Edge Function.
///
/// [secret] stays on this device. The server stores only a hash of it, and
/// will hand back a Supabase session only to a poll that presents it.
class WhatsAppChallenge {
  const WhatsAppChallenge({
    required this.challengeId,
    required this.secret,
    required this.waUrl,
    required this.message,
    required this.phone,
    required this.expiresAt,
  });

  final String challengeId;
  final String secret;
  final String waUrl;
  final String message;
  final String phone;
  final DateTime expiresAt;

  static WhatsAppChallenge? tryParse(Map<String, dynamic>? json) {
    if (json == null) return null;
    final id = json['challenge_id'];
    final secret = json['secret'];
    final waUrl = json['wa_url'];
    final message = json['message'];
    final phone = json['phone'];
    final expiresRaw = json['expires_at'];
    if (id is! String ||
        secret is! String ||
        waUrl is! String ||
        message is! String ||
        phone is! String ||
        expiresRaw is! String) {
      return null;
    }
    final expires = DateTime.tryParse(expiresRaw);
    if (expires == null) return null;
    if (id.isEmpty ||
        secret.isEmpty ||
        waUrl.isEmpty ||
        message.isEmpty ||
        phone.isEmpty) {
      return null;
    }
    return WhatsAppChallenge(
      challengeId: id,
      secret: secret,
      waUrl: waUrl,
      message: message,
      phone: phone,
      expiresAt: expires.toLocal(),
    );
  }
}
