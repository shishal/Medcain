import 'package:flutter_test/flutter_test.dart';
import 'package:medico/core/support.dart';

void main() {
  test('supportMailto puts the phone number in the subject', () {
    final uri = Uri.parse(
      SupportLinks.supportMailto(phone: ' +919876543210 '),
    );

    expect(uri.scheme, 'mailto');
    expect(uri.path, SupportLinks.supportEmailAddress);
    expect(
      uri.queryParameters['subject'],
      'MEDCAIN support +919876543210',
    );
  });

  test('supportMailto still addresses support when the phone is missing', () {
    final uri = Uri.parse(SupportLinks.supportMailto(phone: '  '));

    expect(uri.path, SupportLinks.supportEmailAddress);
    expect(uri.queryParameters['subject'], 'MEDCAIN support');
  });
}
