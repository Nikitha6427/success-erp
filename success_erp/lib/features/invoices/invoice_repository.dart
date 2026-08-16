import '../../core/repository/base_repository.dart';
import 'models/invoice.dart';

class InvoiceRepository extends BaseRepository<Invoice> {
  InvoiceRepository(super.store);

  @override
  String get tableName => 'Invoices';

  @override
  Invoice fromMap(Map<String, String> row) => Invoice.fromMap(row);

  @override
  Map<String, String> toMap(Invoice item) => item.toMap();

  @override
  String getId(Invoice item) => item.id;

  Future<List<Invoice>> loadByPoId(String poId) async {
    final all = await loadAll();
    return all.where((inv) => inv.poId == poId).toList();
  }
}
