import 'package:flutter_test/flutter_test.dart';
import 'package:success_erp/core/services/number_to_words.dart';

void main() {
  group('NumberToWords (Indian numbering)', () {
    test('zero and small amounts', () {
      expect(NumberToWords.convert(0), 'Rupees Zero Only');
      expect(NumberToWords.convert(1), 'Rupees One Only');
      expect(NumberToWords.convert(20), 'Rupees Twenty Only');
      expect(NumberToWords.convert(105), 'Rupees One Hundred Five Only');
    });

    test('lakh and crore grouping', () {
      expect(NumberToWords.convert(100000), 'Rupees One Lakh Only');
      expect(NumberToWords.convert(20000), 'Rupees Twenty Thousand Only');
      // Worked by hand: 12 lakh, 34 thousand, 567.
      expect(
        NumberToWords.convert(1234567.50),
        'Rupees Twelve Lakh Thirty Four Thousand Five Hundred Sixty Seven '
        'and Fifty Paise Only',
      );
      expect(
        NumberToWords.convert(12345678.90),
        'Rupees One Crore Twenty Three Lakh Forty Five Thousand '
        'Six Hundred Seventy Eight and Ninety Paise Only',
      );
    });

    test('the invoice total from the worked example', () {
      // 12 x 250.50 + 8 x 45.25 + 450 flat = 3818.00; +9% +9% = 4505.24
      expect(
        NumberToWords.convert(4505.24),
        'Rupees Four Thousand Five Hundred Five and Twenty Four Paise Only',
      );
    });

    test('paise are rounded, never carried into a bogus "hundred paise"', () {
      // 0.999 must become 1 rupee, not "Zero and One Hundred Paise".
      expect(NumberToWords.convert(0.999), 'Rupees One Only');
      expect(NumberToWords.convert(2.005), 'Rupees Two and One Paise Only');
      expect(NumberToWords.convert(99.995), 'Rupees One Hundred Only');
    });

    test('floating-point noise does not leak into the words', () {
      expect(NumberToWords.convert(0.1 + 0.2), 'Rupees Zero and Thirty Paise Only');
    });

    test('very large amounts stay meaningful', () {
      // The published package returns "Number is too large" here.
      expect(
        NumberToWords.convert(999999999.99),
        'Rupees Ninety Nine Crore Ninety Nine Lakh Ninety Nine Thousand '
        'Nine Hundred Ninety Nine and Ninety Nine Paise Only',
      );
      expect(
        NumberToWords.convert(1000000000),
        'Rupees One Hundred Crore Only',
      );
    });
  });
}
