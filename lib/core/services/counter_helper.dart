import 'dart:developer' as dev;
import 'workbook_store.dart';

/// Human-readable sequential numbers (AGENTS.md §4 / §5).
///
/// The Counters table is keyed on (entity_name, category, financial_year) so
/// each combination has its own independent sequence. Entities that don't need
/// splitting leave category/financial_year blank.
class CounterHelper {
  final WorkbookStore _store;
  CounterHelper(this._store);

  static const String _tab = 'Counters';

  /// Indian financial year (April–March) for [date], formatted "2026-27".
  /// A date in Jan–Mar 2027 belongs to FY "2026-27".
  static String financialYearFor(DateTime date) {
    final startYear = date.month >= 4 ? date.year : date.year - 1;
    final endShort = ((startYear + 1) % 100).toString().padLeft(2, '0');
    return '$startYear-$endShort';
  }

  /// Reads, increments and writes back the counter for the compound key.
  /// Returns the new sequence value.
  Future<int> _nextSequence(
    String entityName,
    String category,
    String financialYear,
  ) async {
    final rows = await _store.getAllRows(_tab);

    int rowIndex = -1;
    int lastNumber = 0;
    for (int i = 0; i < rows.length; i++) {
      final r = rows[i];
      if ((r['entity_name'] ?? '') == entityName &&
          (r['category'] ?? '') == category &&
          (r['financial_year'] ?? '') == financialYear) {
        rowIndex = i + 2;
        lastNumber = int.tryParse(r['last_number'] ?? '') ?? 0;
        break;
      }
    }

    final next = lastNumber + 1;
    final row = {
      'entity_name': entityName,
      'category': category,
      'financial_year': financialYear,
      'last_number': next.toString(),
    };

    if (rowIndex > 0) {
      await _store.updateRow(_tab, rowIndex, row);
    } else {
      await _store.appendRow(_tab, row);
    }
    return next;
  }

  /// `PO/{S|L}{FY}/{sequence}` — e.g. `PO/S2026-27/4`, `PO/L2026-27/73`.
  ///
  /// [category] must be `Sales` or `Labour`; the financial year is derived from
  /// [orderDate]. The sequence is independent per (category, FY).
  Future<String> nextPoNumber({
    required String category,
    required DateTime orderDate,
  }) async {
    final fy = financialYearFor(orderDate);
    final letter = category == 'Labour' ? 'L' : 'S';
    final seq = await _nextSequence('PurchaseOrder', category, fy);
    final number = 'PO/$letter$fy/$seq';
    dev.log('[Counter] PurchaseOrder/$category/$fy -> $number');
    return number;
  }

  /// A simple zero-padded sequence for entities with no category/FY split,
  /// e.g. `CUST-0001`, `DN-0007`, `INV-0042`.
  Future<String> nextSimpleNumber(String entityName, String prefix) async {
    final seq = await _nextSequence(entityName, '', '');
    final number = '$prefix-${seq.toString().padLeft(4, '0')}';
    dev.log('[Counter] $entityName -> $number');
    return number;
  }
}
