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

  static String _convertGroup(int n) {
    if (n == 0) return '';
    if (n < 20) return _ones[n];
    if (n < 100) {
      final t = _tens[n ~/ 10];
      final r = n % 10;
      return r > 0 ? '$t ${_ones[r]}' : t;
    }
    final h = _ones[n ~/ 100];
    final r = n % 100;
    return r > 0 ? '$h Hundred ${_convertGroup(r)}' : '$h Hundred';
  }

  /// Converts a numeric amount to Indian-style words.
  /// e.g. 1234567.50 => "Rupees Twelve Lakh Thirty Four Thousand Five Hundred Sixty Seven and Fifty Paise Only"
  static String convert(double amount) {
    final intPart = amount.floor();
    final paise = ((amount - intPart) * 100).round();

    if (intPart == 0 && paise == 0) return 'Rupees Zero Only';

    final crore = intPart ~/ 10000000;
    final lakh = (intPart ~/ 100000) % 100;
    final thousand = (intPart ~/ 1000) % 100;
    final hundred = intPart % 1000;

    var words = '';
    if (crore > 0) words += '${_convertGroup(crore)} Crore ';
    if (lakh > 0) words += '${_convertGroup(lakh)} Lakh ';
    if (thousand > 0) words += '${_convertGroup(thousand)} Thousand ';
    if (hundred > 0) words += _convertGroup(hundred);

    var result = 'Rupees ${words.trim()}';
    if (paise > 0) {
      result += ' and ${_convertGroup(paise)} Paise';
    }
    result += ' Only';
    return result;
  }
}
