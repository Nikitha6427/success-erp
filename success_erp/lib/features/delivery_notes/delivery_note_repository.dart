import '../../core/repository/base_repository.dart';
import 'models/delivery_note.dart';

class DeliveryNoteRepository extends BaseRepository<DeliveryNote> {
  DeliveryNoteRepository(super.store);

  @override
  String get tableName => 'DeliveryNotes';

  @override
  DeliveryNote fromMap(Map<String, String> row) => DeliveryNote.fromMap(row);

  @override
  Map<String, String> toMap(DeliveryNote item) => item.toMap();

  @override
  String getId(DeliveryNote item) => item.id;

  Future<List<DeliveryNote>> loadByPoId(String poId) async {
    final all = await loadAll();
    return all.where((dn) => dn.poId == poId).toList();
  }
}
