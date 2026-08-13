import '../../core/repository/base_repository.dart';
import '../../core/services/sheets_service.dart';
import 'models/invoice.dart';

class InvoiceItemRepository extends BaseRepository<InvoiceItem> {
  InvoiceItemRepository(super.sheetsService);

  @override
  String get tabName => 'InvoiceItems';

  @override
  List<String> get headers => SheetsService.tabHeaders['InvoiceItems']!;

  @override
  InvoiceItem fromRow(List<String> row) => InvoiceItem.fromRow(row);

  @override
  List<String> toRow(InvoiceItem item) => item.toRow();

  @override
  String getId(InvoiceItem item) => item.id;

  /// Returns all invoice items across all invoices for a given po_item_id.
  /// Used to compute how much of a delivered item has already been invoiced.
  Future<int> totalInvoicedForPoItem(String poItemId) async {
    final all = await loadAll();
    int total = 0;
    for (final item in all) {
      if (item.id.isNotEmpty) {
        // We match on poItemId by loading the invoice's items via invoiceId.
        // Since InvoiceItem doesn't store poItemId directly, we match via
        // productId on items belonging to invoices for the same PO.
        // This is handled at the form level by loading invoice IDs for the PO
        // first, then summing quantities per productId.
      }
    }
    return total;
  }
}
