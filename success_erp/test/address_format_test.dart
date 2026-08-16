import 'package:flutter_test/flutter_test.dart';
import 'package:success_erp/core/services/address_format.dart';

void main() {
  group('AddressFormat.lines (AGENTS.md §6)', () {
    test('street, then area, then "City, State, Country - Pincode"', () {
      expect(
        AddressFormat.lines(
          street: '14 Foundry Lane',
          area: 'Peenya Industrial Area',
          cityDistrict: 'Bengaluru',
          state: 'Karnataka',
          country: 'India',
          pincode: '560058',
        ),
        [
          '14 Foundry Lane',
          'Peenya Industrial Area',
          'Bengaluru, Karnataka, India - 560058',
        ],
      );
    });

    test('empty parts are dropped without leaving stray separators', () {
      expect(
        AddressFormat.lines(
          street: '  ',
          area: '',
          cityDistrict: 'Pune',
          state: '',
          country: 'India',
          pincode: '',
        ),
        ['Pune, India'],
      );
    });

    test('a pincode with no locality still prints', () {
      expect(
        AddressFormat.lines(
          street: '',
          area: '',
          cityDistrict: '',
          state: '',
          country: '',
          pincode: '411001',
        ),
        ['411001'],
      );
    });

    test('a completely empty address yields no lines', () {
      expect(
        AddressFormat.lines(
          street: '',
          area: '',
          cityDistrict: '',
          state: '',
          country: '',
          pincode: '',
        ),
        isEmpty,
      );
    });
  });

  group('AddressFormat.orNoneBlank', () {
    test('prints the literal "None/Blank" rather than a gap', () {
      expect(AddressFormat.orNoneBlank(''), 'None/Blank');
      expect(AddressFormat.orNoneBlank('   '), 'None/Blank');
      expect(AddressFormat.orNoneBlank(null), 'None/Blank');
      expect(AddressFormat.orNoneBlank('29ABCDE1234F1Z5'), '29ABCDE1234F1Z5');
    });
  });
}
