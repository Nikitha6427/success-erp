import '../../core/repository/base_repository.dart';
import '../../core/services/sheets_service.dart';
import 'models/invoice.dart';

class InvoiceRepository extends BaseRepository<Invoice> {
  InvoiceRepository(super.sheetsService);

  @override
  String get tabName => 'Invoices';

  @override
  List<String> get headers => SheetsService.tabHeaders['Invoices']!;

  @override
  Invoice fromRow(List<String> row) => Invoice.fromRow(row);

  @override
  List<String> toRow(Invoice item) => item.toRow();

  @override
  String getId(Invoice item) => item.id;

  Future<List<Invoice>> loadByPoId(String poId) async {
    final all = await loadAll();
    return all.where((inv) => inv.poId == poId).toList();
  }
}
