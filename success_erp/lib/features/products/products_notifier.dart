import 'dart:developer' as dev;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../app.dart';
import '../../core/exceptions/referential_integrity_exception.dart';
import '../../core/services/bulk_delete.dart';
import '../purchase_orders/po_providers.dart';
import 'models/product.dart';
import 'product_repository.dart';

class ProductListState {
  final List<Product> products;
  final bool isLoading;
  final String? error;

  const ProductListState(this.products, this.isLoading, {this.error});
}

class ProductsNotifier extends StateNotifier<ProductListState> {
  final ProductRepository _repo;
  final Ref _ref;

  ProductsNotifier(this._repo, this._ref)
      : super(const ProductListState([], false));

  Future<void> load() async {
    state = ProductListState(state.products, true);
    try {
      final list = await _repo.loadAll();
      state = ProductListState(list, false);
    } catch (e) {
      dev.log('[Products] load failed: $e');
      state = ProductListState(state.products, false, error: '$e');
    }
  }

  Future<void> add(Product product) async {
    final counter = _ref.read(counterHelperProvider);
    final productCode = await counter.nextSimpleNumber('Product', 'PRD');
    await _repo.save(product.copyWith(
      id: product.id.isEmpty ? const Uuid().v4() : product.id,
      productCode: productCode,
    ));
    await load();
  }

  /// Editing price/tax here must never touch rates already snapshotted on
  /// existing PurchaseOrderItems rows (AGENTS.md §4) — and it doesn't: PO items
  /// carry their own `rate` column and are never re-read from the product.
  Future<void> update(Product product) async {
    await _repo.update(product);
    await load();
  }

  Future<void> delete(String id) async {
    final outcome = await deleteMany([id]);
    final reason = outcome.blocked[id];
    if (reason != null) {
      throw ReferentialIntegrityException(
        'Cannot delete this product — $reason.',
      );
    }
  }

  /// Deletes several products, keeping any that a purchase order line still
  /// references and reporting them back rather than failing the whole batch.
  Future<BulkDeleteOutcome> deleteMany(List<String> ids) async {
    if (ids.isEmpty) return const BulkDeleteOutcome();

    // One pass over the PO items table for the whole batch.
    final rows = await _repo.store.getAllRows('PurchaseOrderItems');
    final poIdsByProduct = <String, Set<String>>{};
    for (final row in rows) {
      final productId = row['product_id'] ?? '';
      final poId = row['po_id'] ?? '';
      if (productId.isEmpty || poId.isEmpty) continue;
      poIdsByProduct.putIfAbsent(productId, () => <String>{}).add(poId);
    }

    final deleted = <String>[];
    final blocked = <String, String>{};
    for (final id in ids) {
      final count = poIdsByProduct[id]?.length ?? 0;
      if (count > 0) {
        blocked[id] = 'it is linked to $count purchase order(s)';
        continue;
      }
      try {
        await _repo.delete(id);
        deleted.add(id);
      } catch (e) {
        dev.log('[Products] delete $id failed: $e');
        blocked[id] = 'it could not be deleted ($e)';
      }
    }

    if (deleted.isNotEmpty) await load();
    return BulkDeleteOutcome(deleted: deleted, blocked: blocked);
  }

  Product? findById(String id) {
    for (final p in state.products) {
      if (p.id == id) return p;
    }
    return null;
  }
}

final productRepositoryProvider = Provider<ProductRepository>((ref) {
  return ProductRepository(ref.watch(workbookStoreProvider));
});

final productsNotifierProvider =
    StateNotifierProvider<ProductsNotifier, ProductListState>((ref) {
  return ProductsNotifier(ref.watch(productRepositoryProvider), ref);
});
