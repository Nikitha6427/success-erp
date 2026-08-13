import '../services/sheets_service.dart';
import '../exceptions/conflict_exception.dart';

abstract class BaseRepository<T> {
  final SheetsService sheetsService;
  final Map<String, int> _idToRow = {};
  final Map<String, String> _loadedUpdatedAt = {};

  BaseRepository(this.sheetsService);

  String get tabName;
  List<String> get headers;
  T fromRow(List<String> row);
  List<String> toRow(T item);
  String getId(T item);

  /// Column index for updated_at, or null if this entity has no optimistic lock.
  int? get updatedAtColumnIndex => null;

  /// Loads all non-empty rows and rebuilds the in-memory id -> sheet row index.
  Future<List<T>> loadAll() async {
    final rows = await sheetsService.getAllRows(tabName);
    _idToRow.clear();
    _loadedUpdatedAt.clear();
    final items = <T>[];
    for (int i = 0; i < rows.length; i++) {
      final item = fromRow(rows[i]);
      if (getId(item).isNotEmpty) {
        items.add(item);
        _idToRow[getId(item)] = i + 2;
        if (updatedAtColumnIndex != null &&
            rows[i].length > updatedAtColumnIndex! &&
            rows[i][updatedAtColumnIndex!].isNotEmpty) {
          _loadedUpdatedAt[getId(item)] = rows[i][updatedAtColumnIndex!];
        }
      }
    }
    return items;
  }

  /// Insert a new row. Returns the sheet row index it was written to.
  Future<int> save(T item) async {
    return await sheetsService.appendRow(tabName, toRow(item));
  }

  /// Update an existing row with optimistic locking.
  /// Throws [ConflictException] if the row was modified since it was loaded.
  Future<void> update(T item) async {
    final id = getId(item);
    final rowIndex = _idToRow[id];
    if (rowIndex == null) return;

    if (updatedAtColumnIndex != null) {
      final currentRow = await sheetsService.getRow(tabName, rowIndex);
      final currentUpdatedAt =
          currentRow.length > updatedAtColumnIndex!
              ? currentRow[updatedAtColumnIndex!]
              : '';
      final loadedUpdatedAt = _loadedUpdatedAt[id] ?? '';

      if (currentUpdatedAt != loadedUpdatedAt) {
        throw ConflictException(
          'This record was updated from another device. '
          'Reloading the latest version — please redo your last action.',
        );
      }
    }

    final values = toRow(item);
    if (updatedAtColumnIndex != null && values.length > updatedAtColumnIndex!) {
      values[updatedAtColumnIndex!] = DateTime.now().toIso8601String();
    }

    await sheetsService.updateRow(tabName, rowIndex, values);

    if (updatedAtColumnIndex != null && values.length > updatedAtColumnIndex!) {
      _loadedUpdatedAt[id] = values[updatedAtColumnIndex!];
    }
  }

  /// Clear a row's cells (Sheets has no cheap row-delete without reindexing).
  Future<void> delete(String id) async {
    final rowIndex = _idToRow[id];
    if (rowIndex != null) {
      await sheetsService.clearRow(tabName, rowIndex, headers.length);
      _idToRow.remove(id);
      _loadedUpdatedAt.remove(id);
    }
  }

  int? getRowIndex(String id) => _idToRow[id];
}
