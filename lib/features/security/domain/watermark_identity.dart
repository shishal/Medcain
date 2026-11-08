/// Builds the traceability string painted on content screens (Phase 8.2).
///
/// iOS cannot block screenshots, so a leaked photo of a question should still
/// identify whose account it came from. Empty fields are skipped. The
/// WhatsApp number is the usual identifier.
abstract final class WatermarkIdentity {
  static String label({String? fullName, String? phone, String? email}) {
    return [fullName, phone, email]
        .map((part) => part?.trim())
        .whereType<String>()
        .where((part) => part.isNotEmpty)
        .join(' · ');
  }
}
