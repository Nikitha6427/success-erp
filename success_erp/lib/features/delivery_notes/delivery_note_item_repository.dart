import '../../core/repository/base_repository.dart';
import '../../core/services/sheets_service.dart';
import 'models/delivery_note.dart';

class DeliveryNoteItemRepository extends BaseRepository<DeliveryNoteItem> {
  DeliveryNoteItemRepository(super.sheetsService);

  @override
  String get tabName => 'DeliveryNoteItems';

  @override
  List<String> get headers => SheetsService.tabHeaders['DeliveryNoteItems']!;

  @override
  DeliveryNoteItem fromRow(List<String> row) => DeliveryNoteItem.fromRow(row);

  @override
  List<String> toRow(DeliveryNoteItem item) => item.toRow();

  @override
  String getId(DeliveryNoteItem item) => item.id;

  Future<List<DeliveryNoteItem>> loadByDnId(String dnId) async {
    final all = await loadAll();
    return all.where((item) => item.dnId == dnId).toList();
  }
}
