import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/widgets/app_drawer.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/loading_list_skeleton.dart';
import '../../core/widgets/selection_app_bar.dart';
import '../../core/widgets/snack_bar_helper.dart';
import 'models/product.dart';
import 'products_notifier.dart';

class ProductListScreen extends ConsumerStatefulWidget {
  const ProductListScreen({super.key});

  @override
  ConsumerState<ProductListScreen> createState() => _ProductListScreenState();
}

class _ProductListScreenState extends ConsumerState<ProductListScreen> {
  final _searchController = TextEditingController();
  String _query = '';

  final Set<String> _selected = {};
  bool _selecting = false;
  bool _isDeleting = false;

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

  // ── Selection ─────────────────────────────────────────────────────────────

  void _exitSelection() => setState(() {
        _selecting = false;
        _selected.clear();
      });

  void _startSelection(String id) => setState(() {
        _selecting = true;
        _selected.add(id);
      });

  void _toggle(String id) => setState(() {
        if (!_selected.remove(id)) _selected.add(id);
        if (_selected.isEmpty) _selecting = false;
      });

  void _toggleSelectAll(List<Product> visible) => setState(() {
        if (_selected.length == visible.length) {
          _selected.clear();
          _selecting = false;
        } else {
          _selected
            ..clear()
            ..addAll(visible.map((p) => p.id));
        }
      });

  Future<void> _deleteSelected() async {
    if (_selected.isEmpty || _isDeleting) return;
    final ids = _selected.toList();

    final confirmed = await confirmBulkDelete(
      context,
      count: ids.length,
      singular: 'this product',
      plural: 'products',
      consequences: const [
        'Products used on a purchase order will be kept',
      ],
    );
    if (!confirmed || !mounted) return;

    setState(() => _isDeleting = true);
    try {
      final outcome =
          await ref.read(productsNotifierProvider.notifier).deleteMany(ids);
      if (!mounted) return;
      showSnackBar(
        context,
        outcome.summary('product', 'products'),
        isError: outcome.deletedCount == 0,
      );
      _exitSelection();
    } catch (e) {
      if (mounted) showSnackBar(context, 'Delete failed: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isDeleting = false);
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = ref.watch(productsNotifierProvider);
    final q = _query.trim().toLowerCase();
    final filtered = state.products
        .where(
          (p) =>
              p.name.toLowerCase().contains(q) ||
              p.partNo.toLowerCase().contains(q) ||
              p.productCode.toLowerCase().contains(q),
        )
        .toList();

    return PopScope(
      canPop: !_selecting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _selecting) _exitSelection();
      },
      child: Scaffold(
        appBar: _selecting
            ? SelectionAppBar(
                selectedCount: _selected.length,
                totalCount: filtered.length,
                onClose: _exitSelection,
                onToggleSelectAll: () => _toggleSelectAll(filtered),
                onDelete:
                    _selected.isEmpty || _isDeleting ? null : _deleteSelected,
              )
            : AppBar(title: const Text('Products')),
        drawer: _selecting ? null : const AppDrawer(currentPath: '/products'),
        body: Column(
          children: [
            if (_isDeleting) const LinearProgressIndicator(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: TextField(
                controller: _searchController,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Search by name, code or Part No',
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
        floatingActionButton: _selecting
            ? null
            : FloatingActionButton(
                onPressed: () => context.push('/products/new'),
                tooltip: 'Add product',
                child: const Icon(Icons.add),
              ),
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
    if (state.error != null && state.products.isEmpty) {
      return EmptyState(
        icon: Icons.cloud_off,
        message: "Couldn't load products.\n${state.error}",
        ctaLabel: 'Retry',
        onCta: () => ref.read(productsNotifierProvider.notifier).load(),
      );
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
        final selected = _selected.contains(product.id);
        return Card(
          color: selected ? theme.colorScheme.secondaryContainer : null,
          child: ListTile(
            leading: SelectionLeading(
              selectionMode: _selecting,
              selected: selected,
              child: Hero(
                tag: 'product-${product.id}',
                child: CircleAvatar(
                  backgroundColor: theme.colorScheme.secondaryContainer,
                  foregroundColor: theme.colorScheme.onSecondaryContainer,
                  child: const Icon(Icons.inventory_2_outlined),
                ),
              ),
            ),
            title: Text(product.name),
            subtitle: Text(
              [
                if (product.productCode.isNotEmpty) product.productCode,
                if (product.category.isNotEmpty) product.category,
                if (product.partNo.isNotEmpty) product.partNo,
                if (product.unit.isNotEmpty) product.unit,
              ].where((s) => s.isNotEmpty).join(' • '),
            ),
            trailing: _selecting ? null : const Icon(Icons.chevron_right),
            onTap: () => _selecting
                ? _toggle(product.id)
                : context.push('/products/${product.id}/edit'),
            onLongPress: () => _selecting
                ? _toggle(product.id)
                : _startSelection(product.id),
          ),
        );
      },
    );
  }
}
