import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/widgets/app_drawer.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/loading_list_skeleton.dart';
import 'models/product.dart';
import 'products_notifier.dart';

class ProductListScreen extends ConsumerStatefulWidget {
  const ProductListScreen({super.key});

  @override
  ConsumerState<ProductListScreen> createState() =>
      _ProductListScreenState();
}

class _ProductListScreenState extends ConsumerState<ProductListScreen> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    Future.microtask(
      () => ref.read(productsNotifierProvider.notifier).load(),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = ref.watch(productsNotifierProvider);
    final q = _query.toLowerCase();
    final filtered = state.products
        .where(
          (p) =>
              p.name.toLowerCase().contains(q) ||
              p.partNo.toLowerCase().contains(q),
        )
        .toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Products')),
      drawer: AppDrawer(currentPath: '/products'),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search by name or Part No',
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: _buildBody(state, filtered, theme),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/products/new'),
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildBody(
    ProductListState state,
    List<Product> filtered,
    ThemeData theme,
  ) {
    if (state.isLoading && state.products.isEmpty) {
      return const LoadingListSkeleton();
    }
    if (state.products.isEmpty) {
      return EmptyState(
        icon: Icons.inventory_2_outlined,
        message: 'No products yet',
        ctaLabel: 'Add your first product',
        onCta: () => context.push('/products/new'),
      );
    }
    if (filtered.isEmpty) {
      return EmptyState(
        icon: Icons.search_off,
        message: 'No products match "$_query"',
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: filtered.length,
      itemBuilder: (context, index) {
        final product = filtered[index];
        return Card(
          child: ListTile(
            leading: Hero(
              tag: 'product-${product.id}',
              child: CircleAvatar(
                backgroundColor: theme.colorScheme.secondaryContainer,
                foregroundColor: theme.colorScheme.onSecondaryContainer,
                child: const Icon(Icons.inventory_2_outlined),
              ),
            ),
            title: Text(product.name),
            subtitle: Text(
              [
                if (product.productCode.isNotEmpty) product.productCode,
                if (product.partNo.isNotEmpty) product.partNo,
                if (product.unit.isNotEmpty) product.unit,
              ].where((s) => s.isNotEmpty).join(' • '),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/products/${product.id}/edit'),
          ),
        );
      },
    );
  }
}
