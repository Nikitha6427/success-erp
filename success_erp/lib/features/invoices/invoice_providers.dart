import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app.dart';
import 'models/invoice.dart';
import 'invoice_repository.dart';
import 'invoice_item_repository.dart';

class InvoiceListNotifier extends StateNotifier<List<Invoice>> {
  final InvoiceRepository _repo;
  bool _isLoading = false;
  bool get isLoading => _isLoading;

  InvoiceListNotifier(this._repo) : super(const []);

  Future<void> load() async {
    _isLoading = true;
    state = await _repo.loadAll();
    _isLoading = false;
  }

  Future<List<Invoice>> loadByPoId(String poId) async {
    return await _repo.loadByPoId(poId);
  }
}

final invoiceRepositoryProvider = Provider<InvoiceRepository>((ref) {
  return InvoiceRepository(ref.read(sheetsServiceProvider));
});

final invoiceItemRepositoryProvider = Provider<InvoiceItemRepository>((ref) {
  return InvoiceItemRepository(ref.read(sheetsServiceProvider));
});

final invoiceListProvider =
    StateNotifierProvider<InvoiceListNotifier, List<Invoice>>((ref) {
  return InvoiceListNotifier(ref.read(invoiceRepositoryProvider));
});

final invoiceListLoadingProvider = Provider<bool>((ref) {
  return ref.watch(invoiceListProvider.notifier).isLoading;
});
