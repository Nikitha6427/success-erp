import 'package:success_erp/core/services/workbook_store.dart';

/// In-memory [WorkbookStore] standing in for the whole workbook.
///
/// Mirrors the two contracts every real backend must honour: rows are addressed
/// by 1-based sheet index (header occupies row 1), and deleting BLANKS a row in
/// place rather than removing it, so surviving rows keep their indices.
///
/// Fast enough to use for the business-logic tests. The same behaviour is
/// separately asserted against the real OneDrive service in
/// `onedrive_store_test.dart`, so passing here and failing there would mean the
/// backend has drifted from the contract.
class FakeWorkbookStore implements WorkbookStore {
  /// table -> rows, where null is a blanked (deleted) row.
  final Map<String, List<Map<String, String>?>> tables = {};

  List<Map<String, String>?> _tab(String name) =>
      tables.putIfAbsent(name, () => []);

  /// Rows still present, for assertions.
  List<Map<String, String>> live(String table) =>
      _tab(table).whereType<Map<String, String>>().toList();

  @override
  List<String> headersFor(String table) => WorkbookSchema.headersOf(table);

  @override
  Future<List<Map<String, String>>> getAllRows(String table) async =>
      _tab(table).map((r) => r == null ? <String, String>{} : Map.of(r)).toList();

  @override
  Future<Map<String, String>> getRow(String table, int rowIndex) async {
    final rows = _tab(table);
    final i = rowIndex - 2;
    if (i < 0 || i >= rows.length) return {};
    final row = rows[i];
    return row == null ? {} : Map.of(row);
  }

  @override
  Future<int> appendRow(String table, Map<String, String> row) async {
    final rows = _tab(table);
    rows.add(Map.of(row));
    return rows.length + 1;
  }

  @override
  Future<void> updateRow(
    String table,
    int rowIndex,
    Map<String, String> row,
  ) async {
    _tab(table)[rowIndex - 2] = Map.of(row);
  }

  @override
  Future<void> clearRow(String table, int rowIndex) async {
    _tab(table)[rowIndex - 2] = null;
  }
}
