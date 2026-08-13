import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../app.dart';
import '../../features/purchase_orders/po_providers.dart';
import 'models/product.dart';
import 'product_repository.dart';

class ProductListState {
  final List<Product> products;
  final bool isLoading;

  const ProductListState(this.products, this.isLoading);
}

class ProductsNotifier extends StateNotifier<ProductListState> {
  final ProductRepository _repo;
  final Ref _ref;

  ProductsNotifier(this._repo, this._ref) : super(const ProductListState([], false));

  Future<void> load() async {
    state = ProductListState(state.products, true);
    final list = await _repo.loadAll();
    state = ProductListState(list, false);
  }

  Future<void> add(Product product) async {
    final counter = _ref.read(counterHelperProvider);
    final productCode = await counter.nextNumber('Product');
    final toSave = product.copyWith(
      id: product.id.isEmpty ? const Uuid().v4() : product.id,
      productCode: productCode,
    );
    await _repo.save(toSave);
    await load();
  }

  Future<void> update(Product product) async {
    await _repo.update(product);
    await load();
  }

  Future<void> delete(String id) async {
    final poRepo = _ref.read(poRepositoryProvider);
    final poIds = await poRepo.poIdsForProduct(id);
    if (poIds.isNotEmpty) {
      throw Exception('Cannot delete this product — it is linked to ${poIds.length} purchase order(s). Delete those first.');
    }
    await _repo.delete(id);
    await load();
  }

  Product? findById(String id) {
    for (final p in state.products) {
      if (p.id == id) return p;
    }
    return null;
  }

}

final productRepositoryProvider = Provider<ProductRepository>((ref) {
  return ProductRepository(ref.read(sheetsServiceProvider));
});

final productsNotifierProvider =
    StateNotifierProvider<ProductsNotifier, ProductListState>((ref) {
  return ProductsNotifier(ref.read(productRepositoryProvider), ref);
});
