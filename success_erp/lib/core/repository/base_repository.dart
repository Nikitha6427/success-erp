import '../services/workbook_store.dart';
import '../exceptions/conflict_exception.dart';

/// Shared repository behaviour for every entity (AGENTS.md §3).
///
/// Per-row optimistic locking lives here — never copy-pasted per repository.
/// Whether an entity participates is derived from whether its table has an
/// `updated_at` column, so it can't drift out of sync with the schema.
abstract class BaseRepository<T> {
  final WorkbookStore store;

  /// id -> 1-based sheet row index, rebuilt on every [loadAll].
  final Map<String, int> _idToRow = {};

  /// id -> the `updated_at` value seen when the record was last loaded/saved.
  final Map<String, String> _loadedUpdatedAt = {};

  BaseRepository(this.store);

  String get tableName;
  T fromMap(Map<String, String> row);
  Map<String, String> toMap(T item);
  String getId(T item);

  static const String updatedAtKey = 'updated_at';

  bool get hasOptimisticLock =>
      WorkbookSchema.hasColumn(tableName, updatedAtKey);

  Future<List<T>> loadAll() async {
    final rows = await store.getAllRows(tableName);
    _idToRow.clear();
    _loadedUpdatedAt.clear();
    final items = <T>[];
    for (int i = 0; i < rows.length; i++) {
      final item = fromMap(rows[i]);
      final id = getId(item);
      if (id.isEmpty) continue; // blank / cleared row
      items.add(item);
      _idToRow[id] = i + 2; // +1 for header row, +1 for 1-based indexing
      final stamp = rows[i][updatedAtKey] ?? '';
      if (stamp.isNotEmpty) _loadedUpdatedAt[id] = stamp;
    }
    return items;
  }

  /// Inserts a new row. Returns the sheet row index it was written to.
  Future<int> save(T item) async {
    final values = toMap(item);
    final rowIndex = await store.appendRow(tableName, values);
    final id = getId(item);
    if (id.isNotEmpty) {
      _idToRow[id] = rowIndex;
      final stamp = values[updatedAtKey] ?? '';
      if (stamp.isNotEmpty) _loadedUpdatedAt[id] = stamp;
    }
    return rowIndex;
  }

  /// Updates an existing row under optimistic locking.
  ///
  /// Re-reads just this row's `updated_at`; if it changed since load, the write
  /// is abandoned and a [ConflictException] is thrown so the caller can reload
  /// and ask the user to redo their last action (AGENTS.md §3).
  Future<void> update(T item) async {
    final id = getId(item);
    var rowIndex = _idToRow[id];
    if (rowIndex == null) {
      // Not in the index (e.g. loaded by a different repository instance) —
      // rebuild it rather than silently dropping the write.
      await loadAll();
      rowIndex = _idToRow[id];
      if (rowIndex == null) {
        throw StateError('Cannot update $tableName/$id — row not found.');
      }
    }

    final values = toMap(item);

    if (hasOptimisticLock) {
      final currentRow = await store.getRow(tableName, rowIndex);
      final currentUpdatedAt = currentRow[updatedAtKey] ?? '';
      final loadedUpdatedAt = _loadedUpdatedAt[id] ?? '';

      if (currentUpdatedAt != loadedUpdatedAt) {
        throw ConflictException(
          'This record was updated from another device. '
          'Reloading the latest version — please redo your last action.',
        );
      }
      values[updatedAtKey] = DateTime.now().toIso8601String();
    }

    await store.updateRow(tableName, rowIndex, values);

    if (hasOptimisticLock) {
      _loadedUpdatedAt[id] = values[updatedAtKey]!;
    }
  }

  /// Blanks a row's cells rather than removing the row, per the [WorkbookStore]
  /// deletion contract — surviving rows must keep their indices so a bulk
  /// delete can capture them once and stay valid for the whole batch.
  Future<void> delete(String id) async {
    var rowIndex = _idToRow[id];
    if (rowIndex == null) {
      await loadAll();
      rowIndex = _idToRow[id];
    }
    if (rowIndex == null) return;
    await store.clearRow(tableName, rowIndex);
    _idToRow.remove(id);
    _loadedUpdatedAt.remove(id);
  }

  int? getRowIndex(String id) => _idToRow[id];
}
