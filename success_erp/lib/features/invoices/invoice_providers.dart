import 'dart:developer' as dev;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app.dart';
import '../../core/services/bulk_delete.dart';
import '../../core/services/invoice_math.dart';
import '../purchase_orders/models/purchase_order.dart';
import '../purchase_orders/po_providers.dart';
import '../purchase_orders/purchase_order_item_repository.dart';
import '../purchase_orders/purchase_order_repository.dart';
import 'models/invoice.dart';
import 'invoice_repository.dart';
import 'invoice_item_repository.dart';

class InvoiceListState {
  final List<Invoice> invoices;
  final bool isLoading;
  final String? error;

  const InvoiceListState(this.invoices, this.isLoading, {this.error});
}

class InvoiceListNotifier extends StateNotifier<InvoiceListState> {
  final InvoiceRepository _repo;
  final Ref _ref;

  InvoiceListNotifier(this._repo, this._ref)
      : super(const InvoiceListState([], false));

  Future<void> load() async {
    state = InvoiceListState(state.invoices, true);
    try {
      final list = await _repo.loadAll();
      state = InvoiceListState(list, false);
    } catch (e) {
      dev.log('[Invoices] load failed: $e');
      state = InvoiceListState(state.invoices, false, error: '$e');
    }
  }

  Future<List<Invoice>> loadByPoId(String poId) => _repo.loadByPoId(poId);

  /// Replaces one invoice in local state after an in-place edit.
  void replace(Invoice invoice) {
    state = InvoiceListState(
      [
        for (final i in state.invoices)
          if (i.id == invoice.id) invoice else i,
      ],
      state.isLoading,
      error: state.error,
    );
  }

  /// What deleting [invoiceIds] involves, for the confirmation dialog.
  Future<InvoiceDeletionImpact> impactFor(List<String> invoiceIds) async {
    if (invoiceIds.isEmpty) {
      return const InvoiceDeletionImpact(
        lineItems: 0,
        paidInvoices: 0,
        affectedOrders: 0,
      );
    }
    final ids = invoiceIds.toSet();
    final invoices = await _repo.loadAll();
    final items = await _ref.read(invoiceItemRepositoryProvider).loadAll();

    final selected = invoices.where((i) => ids.contains(i.id)).toList();
    return InvoiceDeletionImpact(
      lineItems: items.where((i) => ids.contains(i.invoiceId)).length,
      paidInvoices: selected.where((i) => i.isPaid).length,
      affectedOrders: selected
          .map((i) => i.poId)
          .where((id) => id.isNotEmpty)
          .toSet()
          .length,
    );
  }

  Future<void> delete(String id) => deleteMany([id]);

  /// Deletes invoices and their InvoiceItems, then rolls each affected purchase
  /// order's status back to what the delivery state alone justifies.
  ///
  /// Nothing references an invoice, so nothing blocks here — but the quantities
  /// it billed become invoiceable again, which means a PO sitting at `Invoiced`
  /// must not stay there. A Paid invoice is still deletable (the dialog calls
  /// that out) rather than becoming an unremovable dead end.
  Future<BulkDeleteOutcome> deleteMany(List<String> invoiceIds) async {
    if (invoiceIds.isEmpty) return const BulkDeleteOutcome();

    final itemRepo = _ref.read(invoiceItemRepositoryProvider);
    final poRepo = _ref.read(poRepositoryProvider);
    final poItemRepo = _ref.read(poItemRepositoryProvider);

    // One read of each table for the whole batch; deleting blanks rows in place
    // so the indices captured here stay valid throughout.
    final allInvoices = await _repo.loadAll();
    final allItems = await itemRepo.loadAll();

    final byId = {for (final inv in allInvoices) inv.id: inv};
    final deleted = <String>[];
    final blocked = <String, String>{};
    final affectedPoIds = <String>{};

    for (final id in invoiceIds) {
      final invoice = byId[id];
      if (invoice == null) {
        blocked[id] = 'it no longer exists';
        continue;
      }
      try {
        for (final item in allItems.where((i) => i.invoiceId == id)) {
          await itemRepo.delete(item.id);
        }
        await _repo.delete(id);
        deleted.add(id);
        if (invoice.poId.isNotEmpty) affectedPoIds.add(invoice.poId);
      } catch (e) {
        dev.log('[Invoices] delete $id failed: $e');
        blocked[id] = 'it could not be deleted ($e)';
      }
    }

    if (deleted.isNotEmpty) {
      await _recalculateOrderStatuses(affectedPoIds, poRepo, poItemRepo, itemRepo);
      await load();
      await _ref.read(poNotifierProvider.notifier).load();
    }
    return BulkDeleteOutcome(deleted: deleted, blocked: blocked);
  }

  /// Re-derives each affected PO's status now that some billed quantity has
  /// gone back to being invoiceable.
  Future<void> _recalculateOrderStatuses(
    Set<String> poIds,
    PurchaseOrderRepository poRepo,
    PurchaseOrderItemRepository poItemRepo,
    InvoiceItemRepository itemRepo,
  ) async {
    if (poIds.isEmpty) return;
    final invoicedByPoItem = await itemRepo.invoicedQtyByPoItem();
    final orders = await poRepo.loadAll();

    for (final poId in poIds) {
      final po = orders.where((o) => o.id == poId).firstOrNull;
      if (po == null) continue;
      final items = await poItemRepo.loadByPoId(poId);
      if (items.isEmpty) continue;

      final stillFullyInvoiced = InvoiceMath.isFullyInvoiced(
        poItems: items,
        invoicedByPoItem: invoicedByPoItem,
      );
      final newStatus = stillFullyInvoiced
          ? PurchaseOrder.statusInvoiced
          : InvoiceMath.statusAfterDelivery(items);

      if (newStatus != po.status) {
        dev.log('[Invoices] PO ${po.poNumber}: ${po.status} -> $newStatus '
            'after invoice deletion');
        await poRepo.update(po.copyWith(
          status: newStatus,
          updatedAt: DateTime.now().toIso8601String(),
        ));
      }
    }
  }
}

/// Counts describing what an invoice deletion involves.
class InvoiceDeletionImpact {
  final int lineItems;
  final int paidInvoices;
  final int affectedOrders;

  const InvoiceDeletionImpact({
    required this.lineItems,
    required this.paidInvoices,
    required this.affectedOrders,
  });

  List<String> get consequences => [
        if (lineItems > 0)
          '$lineItems invoice line${lineItems == 1 ? '' : 's'} will be removed',
        if (affectedOrders > 0)
          'the billed quantity becomes invoiceable again on '
              '$affectedOrders purchase order${affectedOrders == 1 ? '' : 's'}',
        if (paidInvoices > 0)
          '$paidInvoices ${paidInvoices == 1 ? 'is' : 'are'} marked PAID',
      ];
}

final invoiceRepositoryProvider = Provider<InvoiceRepository>((ref) {
  return InvoiceRepository(ref.watch(workbookStoreProvider));
});

final invoiceItemRepositoryProvider = Provider<InvoiceItemRepository>((ref) {
  return InvoiceItemRepository(ref.watch(workbookStoreProvider));
});

final invoiceListProvider =
    StateNotifierProvider<InvoiceListNotifier, InvoiceListState>((ref) {
  return InvoiceListNotifier(ref.watch(invoiceRepositoryProvider), ref);
});
