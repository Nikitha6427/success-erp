import 'dart:developer' as dev;
import '../../core/services/sheets_service.dart';

class CounterHelper {
  final SheetsService _sheetsService;
  CounterHelper(this._sheetsService);

  /// Returns current Indian financial year as "YY-YY" (e.g. "24-25").
  static String currentFiscalYear() {
    final now = DateTime.now();
    final year = now.year;
    final month = now.month;
    if (month >= 4) {
      return '${year.toString().substring(2)}-${(year + 1).toString().substring(2)}';
    } else {
      return '${(year - 1).toString().substring(2)}-${year.toString().substring(2)}';
    }
  }

  /// Reads the Counters tab, increments last_number for [entityName],
  /// writes it back, and returns the formatted number (e.g. "PO-0001").
  ///
  /// If [fiscalYear] is provided the prefix becomes "FY-ENTITY-0001"
  /// (e.g. "24-25-PO-0001") instead of just "PO-0001".
  ///
  /// If the entity row doesn't exist yet it is created with last_number = 1.
  Future<String> nextNumber(String entityName, {String? fiscalYear}) async {
    final rows = await _sheetsService.getAllRows('Counters');

    int rowIndex = -1;
    int lastNumber = 0;

    String key = entityName;
    if (fiscalYear != null) key = '$entityName:$fiscalYear';

    for (int i = 0; i < rows.length; i++) {
      if (rows[i].isNotEmpty && rows[i][0] == key) {
        rowIndex = i + 2;
        lastNumber = int.tryParse(rows[i][1]) ?? 0;
        break;
      }
    }

    final next = lastNumber + 1;
    final short = entityName.substring(0, 2).toUpperCase();
    final formatted = fiscalYear != null
        ? '$fiscalYear-$short-${next.toString().padLeft(4, '0')}'
        : '$short-${next.toString().padLeft(4, '0')}';

    if (rowIndex > 0) {
      await _sheetsService.updateRow(
        'Counters',
        rowIndex,
        [key, next.toString()],
      );
    } else {
      await _sheetsService.appendRow(
        'Counters',
        [key, next.toString()],
      );
    }

    dev.log('[Counter] $key → $formatted');
    return formatted;
  }
}
