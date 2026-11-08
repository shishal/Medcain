import 'package:flutter_test/flutter_test.dart';

import 'package:medico/features/auth/domain/whatsapp_challenge.dart';
import 'package:medico/features/auth/domain/whatsapp_phone.dart';

void main() {
  test('normalizes Indian mobiles and explicit country codes', () {
    expect(WhatsAppPhone.normalize('9876543210'), '+919876543210');
    expect(WhatsAppPhone.normalize(' 098765 43210 '), '+919876543210');
    expect(WhatsAppPhone.normalize('+91 98765 43210'), '+919876543210');
    expect(WhatsAppPhone.normalize('919876543210'), '+919876543210');
    expect(WhatsAppPhone.normalize('+1 (415) 555-2671'), '+14155552671');
    expect(WhatsAppPhone.normalize('00919876543210'), '+919876543210');
    expect(WhatsAppPhone.normalize('5876543210'), isNull);
    expect(WhatsAppPhone.normalize('+915876543210'), isNull);
    expect(WhatsAppPhone.normalize('123'), isNull);
    expect(WhatsAppPhone.normalize('call me'), isNull);
  });

  test('hides the internal auth mailbox', () {
    expect(
      isSyntheticAuthEmail('wa.919876543210@auth.medico.internal'),
      isTrue,
    );
    expect(isSyntheticAuthEmail('student@college.edu'), isFalse);
    expect(isSyntheticAuthEmail(null), isFalse);
  });

  test('challenge parse requires every field', () {
    expect(WhatsAppChallenge.tryParse(null), isNull);
    expect(
      WhatsAppChallenge.tryParse({
        'challenge_id': 'id',
        'secret': 'secret',
        'wa_url': 'https://wa.me/911234567890',
        'message': 'MEDCAIN login AB2CD3EF',
        'phone': '+919876543210',
        'expires_at': '2026-11-07T12:00:00Z',
      }),
      isNotNull,
    );
    expect(
      WhatsAppChallenge.tryParse({
        'challenge_id': 'id',
        'secret': 'secret',
      }),
      isNull,
    );
  });
}
