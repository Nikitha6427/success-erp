import '../../core/repository/base_repository.dart';
import 'models/delivery_note.dart';

class DeliveryNoteItemRepository extends BaseRepository<DeliveryNoteItem> {
  DeliveryNoteItemRepository(super.store);

  @override
  String get tableName => 'DeliveryNoteItems';

  @override
  DeliveryNoteItem fromMap(Map<String, String> row) =>
      DeliveryNoteItem.fromMap(row);

  @override
  Map<String, String> toMap(DeliveryNoteItem item) => item.toMap();

  @override
  String getId(DeliveryNoteItem item) => item.id;

  Future<List<DeliveryNoteItem>> loadByDnId(String dnId) async {
    final all = await loadAll();
    return all.where((item) => item.dnId == dnId).toList();
  }
}
