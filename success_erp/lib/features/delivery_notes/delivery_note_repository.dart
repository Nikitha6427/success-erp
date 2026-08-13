import '../../core/repository/base_repository.dart';
import '../../core/services/sheets_service.dart';
import 'models/delivery_note.dart';

class DeliveryNoteRepository extends BaseRepository<DeliveryNote> {
  DeliveryNoteRepository(super.sheetsService);

  @override
  String get tabName => 'DeliveryNotes';

  @override
  List<String> get headers => SheetsService.tabHeaders['DeliveryNotes']!;

  @override
  DeliveryNote fromRow(List<String> row) => DeliveryNote.fromRow(row);

  @override
  List<String> toRow(DeliveryNote item) => item.toRow();

  @override
  String getId(DeliveryNote item) => item.id;

  Future<List<DeliveryNote>> loadByPoId(String poId) async {
    final all = await loadAll();
    return all.where((dn) => dn.poId == poId).toList();
  }
}
