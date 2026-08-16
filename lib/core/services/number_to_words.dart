/// Indian-numbering (lakh / crore) amount-to-words conversion for the
/// `amount_in_words` line on invoices.
///
/// AGENTS.md originally asked for a package here. The only published Dart
/// package for Indian numbering (`indian_currency_to_word` 1.0.0) emits
/// malformed strings ("One   Rupees", "Twenty Thousands") and returns the
/// literal "Number is too large" above ₹99,99,99,999 — unacceptable on a GST
/// document — so this local implementation is used instead and is covered by
/// unit tests in `test/number_to_words_test.dart`.
class NumberToWords {
  static const _ones = [
    '', 'One', 'Two', 'Three', 'Four', 'Five', 'Six', 'Seven', 'Eight',
    'Nine', 'Ten', 'Eleven', 'Twelve', 'Thirteen', 'Fourteen', 'Fifteen',
    'Sixteen', 'Seventeen', 'Eighteen', 'Nineteen',
  ];

  static const _tens = [
    '', '', 'Twenty', 'Thirty', 'Forty', 'Fifty', 'Sixty', 'Seventy',
    'Eighty', 'Ninety',
  ];

  /// Converts 0–999 to words.
  static String _group(int n) {
    if (n == 0) return '';
    if (n < 20) return _ones[n];
    if (n < 100) {
      final t = _tens[n ~/ 10];
      final r = n % 10;
      return r > 0 ? '$t ${_ones[r]}' : t;
    }
    final h = _ones[n ~/ 100];
    final r = n % 100;
    return r > 0 ? '$h Hundred ${_group(r)}' : '$h Hundred';
  }

  /// Converts a whole number to Indian-grouped words (crore / lakh / thousand).
  static String _whole(int value) {
    if (value == 0) return 'Zero';
    final parts = <String>[];

    final crore = value ~/ 10000000;
    final lakh = (value ~/ 100000) % 100;
    final thousand = (value ~/ 1000) % 100;
    final rest = value % 1000;

    if (crore > 0) {
      // Crores above 99 keep grouping in Indian style: "One Thousand Crore".
      parts.add('${crore >= 1000 ? _whole(crore) : _group(crore)} Crore');
    }
    if (lakh > 0) parts.add('${_group(lakh)} Lakh');
    if (thousand > 0) parts.add('${_group(thousand)} Thousand');
    if (rest > 0) parts.add(_group(rest));

    return parts.join(' ');
  }

  /// e.g. 1234567.50 =>
  /// "Rupees Twelve Lakh Thirty Four Thousand Five Hundred Sixty Seven and
  ///  Fifty Paise Only"
  static String convert(double amount) {
    if (amount.isNaN || amount.isInfinite) return 'Rupees Zero Only';

    final negative = amount < 0;
    // Work in whole paise so 0.1 + 0.2 style float error can't leak through.
    final totalPaise = (amount.abs() * 100).round();
    final rupees = totalPaise ~/ 100;
    final paise = totalPaise % 100;

    final buffer = StringBuffer('Rupees ');
    if (negative && totalPaise > 0) buffer.write('Minus ');
    buffer.write(_whole(rupees));
    if (paise > 0) {
      buffer.write(' and ${_group(paise)} Paise');
    }
    buffer.write(' Only');
    return buffer.toString();
  }
}
