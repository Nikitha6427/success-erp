import '../../../core/services/sheets_service.dart';
import 'models/company_profile.dart';

class CompanyProfileRepository {
  final SheetsService _sheetsService;
  static const String _tabName = 'CompanyProfile';
  static const int _dataRowIndex = 2;

  CompanyProfileRepository(this._sheetsService);

  Future<CompanyProfile?> load() async {
    try {
      final row = await _sheetsService.getRow(_tabName, _dataRowIndex);
      if (row.isEmpty || row[0].isEmpty) return null;
      return CompanyProfile.fromRow(row);
    } catch (_) {
      return null;
    }
  }

  Future<void> save(CompanyProfile profile) async {
    try {
      final existing = await load();
      final now = DateTime.now().toIso8601String();
      final toSave = profile.copyWith(updatedAt: now);

      if (existing == null) {
        await _sheetsService.appendRow(_tabName, toSave.toRow());
      } else {
        await _sheetsService.updateRow(_tabName, _dataRowIndex, toSave.toRow());
      }
    } catch (e) {
      throw Exception('Failed to save company profile: $e');
    }
  }
}
