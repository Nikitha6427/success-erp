import 'dart:developer' as dev;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app.dart';
import '../../core/exceptions/referential_integrity_exception.dart';
import '../../core/services/bulk_delete.dart';
import '../../core/services/counter_helper.dart';
import '../delivery_notes/dn_providers.dart';
import '../invoices/invoice_providers.dart';
import 'models/purchase_order.dart';
import 'purchase_order_repository.dart';
import 'purchase_order_item_repository.dart';

class PoListState {
  final List<PurchaseOrder> orders;
  final bool isLoading;
  final String? error;

  const PoListState(this.orders, this.isLoading, {this.error});
}

class PoNotifier extends StateNotifier<PoListState> {
  final PurchaseOrderRepository _poRepo;
  final Ref _ref;

  PoNotifier(this._poRepo, this._ref) : super(const PoListState([], false));

  Future<void> load() async {
    state = PoListState(state.orders, true);
    try {
      final list = await _poRepo.loadAll();
      state = PoListState(list, false);
    } catch (e) {
      dev.log('[PurchaseOrders] load failed: $e');
      state = PoListState(state.orders, false, error: '$e');
    }
  }

  Future<PurchaseOrder?> findById(String id) async {
    final found = state.orders.where((po) => po.id == id).firstOrNull;
    if (found != null) return found;
    await load();
    return state.orders.where((po) => po.id == id).firstOrNull;
  }

  /// What deleting [poIds] would take with it — used to spell out the cascade
  /// in the confirmation dialog before anything is touched. Reads each table
  /// once regardless of how many orders are selected.
  Future<PoDeletionImpact> impactFor(List<String> poIds) async {
    if (poIds.isEmpty) {
      return const PoDeletionImpact(
        lineItems: 0,
        deliveryNotes: 0,
        invoices: 0,
        blockedOrders: 0,
      );
    }
    final ids = poIds.toSet();
    final invoices = await _ref.read(invoiceRepositoryProvider).loadAll();
    final items = await _ref.read(poItemRepositoryProvider).loadAll();
    final dns = await _ref.read(dnRepositoryProvider).loadAll();

    final blockedIds =
        invoices.where((i) => ids.contains(i.poId)).map((i) => i.poId).toSet();
    // Only count the cascade for orders that will actually be deleted.
    final deletableIds = ids.difference(blockedIds);

    return PoDeletionImpact(
      lineItems: items.where((i) => deletableIds.contains(i.poId)).length,
      deliveryNotes: dns.where((d) => deletableIds.contains(d.poId)).length,
      invoices: invoices.where((i) => ids.contains(i.poId)).length,
      blockedOrders: blockedIds.length,
      deletableOrders: deletableIds.length,
    );
  }

  Future<void> delete(String id) async {
    final outcome = await deleteMany([id]);
    final reason = outcome.blocked[id];
    if (reason != null) {
      throw ReferentialIntegrityException(
        'Cannot delete this purchase order — $reason.',
      );
    }
  }

  /// Deletes purchase orders along with their line items and delivery notes.
  ///
  /// Blocked when an invoice references the order: invoices are financial
  /// records, and removing the order beneath them would orphan the documents
  /// and silently change the Sales and Outstanding reports. Delivery notes are
  /// cascaded rather than blocking, because they exist only to describe this
  /// order's shipments — the confirmation dialog states the count first.
  ///
  /// Partial by design: referenced orders are kept and reported, the rest go.
  Future<BulkDeleteOutcome> deleteMany(List<String> poIds) async {
    if (poIds.isEmpty) return const BulkDeleteOutcome();

    final poItemRepo = _ref.read(poItemRepositoryProvider);
    final dnRepo = _ref.read(dnRepositoryProvider);
    final dnItemRepo = _ref.read(dnItemRepositoryProvider);
    final invoiceRepo = _ref.read(invoiceRepositoryProvider);

    // Load each table once for the whole batch rather than once per order.
    // Deleting blanks a row in place without reindexing, so the row indices
    // captured by these loads stay valid for every delete below.
    final allInvoices = await invoiceRepo.loadAll();
    final allPoItems = await poItemRepo.loadAll();
    final allDns = await dnRepo.loadAll();
    final allDnItems = await dnItemRepo.loadAll();

    final deleted = <String>[];
    final blocked = <String, String>{};

    for (final poId in poIds) {
      final invoiceCount = allInvoices.where((i) => i.poId == poId).length;
      if (invoiceCount > 0) {
        blocked[poId] =
            'it has $invoiceCount invoice(s); delete those first';
        continue;
      }

      try {
        final dnIds =
            allDns.where((dn) => dn.poId == poId).map((dn) => dn.id).toSet();
        for (final dnItem in allDnItems.where((di) => dnIds.contains(di.dnId))) {
          await dnItemRepo.delete(dnItem.id);
        }
        for (final dnId in dnIds) {
          await dnRepo.delete(dnId);
        }
        for (final item in allPoItems.where((i) => i.poId == poId)) {
          await poItemRepo.delete(item.id);
        }
        await _poRepo.delete(poId);
        deleted.add(poId);
      } catch (e) {
        dev.log('[PurchaseOrders] delete $poId failed: $e');
        blocked[poId] = 'it could not be deleted ($e)';
      }
    }

    if (deleted.isNotEmpty) {
      await load();
      await _ref.read(dnListProvider.notifier).load();
    }
    return BulkDeleteOutcome(deleted: deleted, blocked: blocked);
  }
}

/// Counts of the records that hang off the selected purchase order(s).
class PoDeletionImpact {
  final int lineItems;
  final int deliveryNotes;
  final int invoices;

  /// Orders in the selection that will be kept because they are invoiced.
  final int blockedOrders;

  /// Orders in the selection that will actually be deleted.
  final int deletableOrders;

  const PoDeletionImpact({
    required this.lineItems,
    required this.deliveryNotes,
    required this.invoices,
    this.blockedOrders = 0,
    this.deletableOrders = 0,
  });

  /// True only when NOTHING in the selection can be deleted.
  ///
  /// This must be counted in ORDERS, not in cascade rows: an order with no line
  /// items and no delivery notes is perfectly deletable, and deriving this from
  /// `lineItems == 0 && deliveryNotes == 0` wrongly reported the whole
  /// selection as blocked whenever the only deletable order happened to be
  /// empty.
  bool get isFullyBlocked => deletableOrders == 0 && blockedOrders > 0;

  List<String> get consequences => [
        if (lineItems > 0)
          '$lineItems line item${lineItems == 1 ? '' : 's'} will be removed',
        if (deliveryNotes > 0)
          '$deliveryNotes delivery note${deliveryNotes == 1 ? '' : 's'} '
              'will also be deleted',
        if (blockedOrders > 0)
          '$blockedOrders order${blockedOrders == 1 ? '' : 's'} will be KEPT '
              '— already invoiced',
      ];
}

final poRepositoryProvider = Provider<PurchaseOrderRepository>((ref) {
  return PurchaseOrderRepository(ref.watch(workbookStoreProvider));
});

final poItemRepositoryProvider = Provider<PurchaseOrderItemRepository>((ref) {
  return PurchaseOrderItemRepository(ref.watch(workbookStoreProvider));
});

final counterHelperProvider = Provider<CounterHelper>((ref) {
  return CounterHelper(ref.watch(workbookStoreProvider));
});

final poNotifierProvider =
    StateNotifierProvider<PoNotifier, PoListState>((ref) {
  return PoNotifier(ref.watch(poRepositoryProvider), ref);
});
