/// A code issued to this student so other people can get a percent off.
///
/// Checkout ignores this object when charging. The website asks Postgres
/// (`checkout_quote`) what to charge.
class ReferralCode {
  const ReferralCode({required this.code, required this.percentOff});

  final String code;
  final int percentOff;
}
