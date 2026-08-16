import '../../core/repository/base_repository.dart';
import 'models/purchase_order.dart';

class PurchaseOrderItemRepository extends BaseRepository<PurchaseOrderItem> {
  PurchaseOrderItemRepository(super.store);

  @override
  String get tableName => 'PurchaseOrderItems';

  @override
  PurchaseOrderItem fromMap(Map<String, String> row) =>
      PurchaseOrderItem.fromMap(row);

  @override
  Map<String, String> toMap(PurchaseOrderItem item) => item.toMap();

  @override
  String getId(PurchaseOrderItem item) => item.id;

  Future<List<PurchaseOrderItem>> loadByPoId(String poId) async {
    final all = await loadAll();
    return all.where((item) => item.poId == poId).toList();
  }
}
