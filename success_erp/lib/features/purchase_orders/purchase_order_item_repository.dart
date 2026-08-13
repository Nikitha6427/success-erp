import '../../core/repository/base_repository.dart';
import '../../core/services/sheets_service.dart';
import 'models/purchase_order.dart';

class PurchaseOrderItemRepository extends BaseRepository<PurchaseOrderItem> {
  PurchaseOrderItemRepository(super.sheetsService);

  @override
  String get tabName => 'PurchaseOrderItems';

  @override
  List<String> get headers => SheetsService.tabHeaders['PurchaseOrderItems']!;

  @override
  PurchaseOrderItem fromRow(List<String> row) => PurchaseOrderItem.fromRow(row);

  @override
  List<String> toRow(PurchaseOrderItem item) => item.toRow();

  @override
  String getId(PurchaseOrderItem item) => item.id;

  @override
  int get updatedAtColumnIndex => headers.length - 1;

  /// Returns all items belonging to a specific PO.
  Future<List<PurchaseOrderItem>> loadByPoId(String poId) async {
    final all = await loadAll();
    return all.where((item) => item.poId == poId).toList();
  }
}
