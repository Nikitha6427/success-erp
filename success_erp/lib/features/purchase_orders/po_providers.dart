import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app.dart';
import '../../core/services/counter_helper.dart';
import 'models/purchase_order.dart';
import 'purchase_order_repository.dart';
import 'purchase_order_item_repository.dart';

class PoListState {
  final List<PurchaseOrder> orders;
  final bool isLoading;

  const PoListState(this.orders, this.isLoading);
}

class PoNotifier extends StateNotifier<PoListState> {
  final PurchaseOrderRepository _poRepo;

  PoNotifier(this._poRepo) : super(const PoListState([], false));

  Future<void> load() async {
    state = PoListState(state.orders, true);
    final list = await _poRepo.loadAll();
    state = PoListState(list, false);
  }

  /// Add a newly created PO to local state without re-fetching the sheet.
  void addLocal(PurchaseOrder po) {
    state = PoListState([...state.orders, po], false);
  }

  Future<PurchaseOrder?> findById(String id) async {
    final found = state.orders.where((po) => po.id == id).firstOrNull;
    if (found != null) return found;
    await load();
    return state.orders.where((po) => po.id == id).firstOrNull;
  }
}

final poRepositoryProvider = Provider<PurchaseOrderRepository>((ref) {
  return PurchaseOrderRepository(ref.read(sheetsServiceProvider));
});

final poItemRepositoryProvider = Provider<PurchaseOrderItemRepository>((ref) {
  return PurchaseOrderItemRepository(ref.read(sheetsServiceProvider));
});

final counterHelperProvider = Provider<CounterHelper>((ref) {
  return CounterHelper(ref.read(sheetsServiceProvider));
});

final poNotifierProvider =
    StateNotifierProvider<PoNotifier, PoListState>((ref) {
  return PoNotifier(ref.read(poRepositoryProvider));
});
