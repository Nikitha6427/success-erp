import '../../core/repository/base_repository.dart';
import 'models/invoice.dart';

class InvoiceItemRepository extends BaseRepository<InvoiceItem> {
  InvoiceItemRepository(super.store);

  @override
  String get tableName => 'InvoiceItems';

  @override
  InvoiceItem fromMap(Map<String, String> row) => InvoiceItem.fromMap(row);

  @override
  Map<String, String> toMap(InvoiceItem item) => item.toMap();

  @override
  String getId(InvoiceItem item) => item.id;

  Future<List<InvoiceItem>> loadByInvoiceId(String invoiceId) async {
    final all = await loadAll();
    return all.where((item) => item.invoiceId == invoiceId).toList();
  }

  /// Total quantity already invoiced per `po_item_id`, across ALL invoices.
  ///
  /// This is the subtrahend in the invoiceable-quantity derivation
  /// (AGENTS.md §4) and is keyed on the PO line item — NOT the product — so
  /// two PO lines using the same product stay independent.
  Future<Map<String, double>> invoicedQtyByPoItem() async {
    final all = await loadAll();
    final totals = <String, double>{};
    for (final item in all) {
      if (item.poItemId.isEmpty) continue;
      totals[item.poItemId] = (totals[item.poItemId] ?? 0) + item.qty;
    }
    return totals;
  }
}
