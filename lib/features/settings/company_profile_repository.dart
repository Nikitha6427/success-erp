import '../../core/services/workbook_store.dart';
import 'models/company_profile.dart';

/// The company profile is a singular record, so it always occupies the first
/// data row of its tab.
class CompanyProfileRepository {
  final WorkbookStore _store;
  static const String _tableName = 'CompanyProfile';
  static const int _dataRowIndex = 2;

  CompanyProfileRepository(this._store);

  Future<CompanyProfile?> load() async {
    try {
      final rows = await _store.getAllRows(_tableName);
      if (rows.isEmpty) return null;
      final profile = CompanyProfile.fromMap(rows.first);
      if (profile.companyName.trim().isEmpty) return null;
      return profile;
    } catch (_) {
      // Empty / unreadable tab is treated as "not configured yet".
      return null;
    }
  }

  Future<void> save(CompanyProfile profile) async {
    final toSave =
        profile.copyWith(updatedAt: DateTime.now().toIso8601String());
    final rows = await _store.getAllRows(_tableName);
    if (rows.isEmpty) {
      await _store.appendRow(_tableName, toSave.toMap());
    } else {
      await _store.updateRow(_tableName, _dataRowIndex, toSave.toMap());
    }
  }
}
