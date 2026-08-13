import '../../core/repository/base_repository.dart';
import '../../core/services/sheets_service.dart';
import 'models/purchase_order.dart';

class PurchaseOrderRepository extends BaseRepository<PurchaseOrder> {
  PurchaseOrderRepository(super.sheetsService);

  @override
  String get tabName => 'PurchaseOrders';

  @override
  List<String> get headers => SheetsService.tabHeaders['PurchaseOrders']!;

  @override
  PurchaseOrder fromRow(List<String> row) => PurchaseOrder.fromRow(row);

  @override
  List<String> toRow(PurchaseOrder item) => item.toRow();

  @override
  String getId(PurchaseOrder item) => item.id;

  @override
  int get updatedAtColumnIndex => headers.length - 1;

  /// Returns all PO IDs for a given customer.
  Future<List<String>> poIdsForCustomer(String customerId) async {
    final all = await loadAll();
    return all
        .where((po) => po.customerId == customerId)
        .map((po) => po.id)
        .toList();
  }

  /// Returns all PO IDs that reference a given product (via PO items).
  Future<List<String>> poIdsForProduct(String productId) async {
    final allPoItems = await sheetsService.getAllRows('PurchaseOrderItems');
    final poIds = <String>{};
    for (final row in allPoItems) {
      if (row.length > 2 && row[2] == productId) {
        poIds.add(row[1]); // poId is column index 1
      }
    }
    return poIds.toList();
  }
}
