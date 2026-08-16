import '../../core/repository/base_repository.dart';
import 'models/purchase_order.dart';

class PurchaseOrderRepository extends BaseRepository<PurchaseOrder> {
  PurchaseOrderRepository(super.store);

  @override
  String get tableName => 'PurchaseOrders';

  @override
  PurchaseOrder fromMap(Map<String, String> row) => PurchaseOrder.fromMap(row);

  @override
  Map<String, String> toMap(PurchaseOrder item) => item.toMap();

  @override
  String getId(PurchaseOrder item) => item.id;

  /// PO ids belonging to a customer — used for referential-integrity checks.
  Future<List<String>> poIdsForCustomer(String customerId) async {
    final all = await loadAll();
    return all
        .where((po) => po.customerId == customerId)
        .map((po) => po.id)
        .toList();
  }

  /// PO ids that reference a product through any PO line item.
  Future<List<String>> poIdsForProduct(String productId) async {
    final rows = await store.getAllRows('PurchaseOrderItems');
    final poIds = <String>{};
    for (final row in rows) {
      if ((row['product_id'] ?? '') == productId) {
        final poId = row['po_id'] ?? '';
        if (poId.isNotEmpty) poIds.add(poId);
      }
    }
    return poIds.toList();
  }
}
