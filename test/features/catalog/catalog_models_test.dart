import 'package:flutter_test/flutter_test.dart';
import 'package:medico/features/catalog/domain/catalog_models.dart';

void main() {
  test('University equality is by id so the picker checkmark works', () {
    const a = University(
      id: 'u1',
      code: 'KUHS',
      name: 'Kerala University of Health Sciences',
      state: 'Kerala',
      slug: 'kuhs',
    );
    const b = University(
      id: 'u1',
      code: 'KUHS',
      name: 'Kerala University of Health Sciences',
      state: 'Kerala',
      slug: 'kuhs',
    );
    expect(a, equals(b));
  });

  test('statesWithUniversities is unique and sorted A–Z', () {
    const unis = [
      University(
        id: 'u-rguhs',
        code: 'RGUHS',
        name: 'Rajiv Gandhi University of Health Sciences',
        state: 'Karnataka',
        slug: 'rguhs',
      ),
      University(
        id: 'u-kuhs',
        code: 'KUHS',
        name: 'Kerala University of Health Sciences',
        state: 'Kerala',
        slug: 'kuhs',
      ),
      University(
        id: 'u-kuhs-2',
        code: 'KUHS2',
        name: 'Another Kerala university',
        state: 'Kerala',
        slug: 'kuhs2',
      ),
    ];
    expect(statesWithUniversities(unis), ['Karnataka', 'Kerala']);
  });

  test('universitiesInState hides other states until a state is chosen', () {
    const kuhs = University(
      id: 'u-kuhs',
      code: 'KUHS',
      name: 'Kerala University of Health Sciences',
      state: 'Kerala',
      slug: 'kuhs',
    );
    const rguhs = University(
      id: 'u-rguhs',
      code: 'RGUHS',
      name: 'Rajiv Gandhi University of Health Sciences',
      state: 'Karnataka',
      slug: 'rguhs',
    );
    const unis = [kuhs, rguhs];

    expect(universitiesInState(unis, null), isEmpty);
    expect(universitiesInState(unis, 'Kerala'), [kuhs]);
    expect(universitiesInState(unis, 'Karnataka'), [rguhs]);
    expect(universitiesInState(unis, 'Goa'), isEmpty);
  });

  test('College label leads with the short form, like a university code', () {
    const college = College(
      id: 'c1',
      universityId: 'u1',
      name: 'Maulana Azad Medical College, New Delhi',
      shortForm: 'MAMC',
    );
    expect(
      college.label,
      'MAMC · Maulana Azad Medical College, New Delhi',
    );
  });

  test('College label is the full name when no short form is stored', () {
    const college = College(
      id: 'c1',
      universityId: 'u1',
      name: 'Other / not listed',
      shortForm: '',
    );
    expect(college.label, 'Other / not listed');
  });
}
