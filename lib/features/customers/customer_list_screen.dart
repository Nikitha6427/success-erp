import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/widgets/responsive_container.dart';
import '../../core/widgets/app_drawer.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/loading_list_skeleton.dart';
import '../../core/widgets/selection_app_bar.dart';
import '../../core/widgets/snack_bar_helper.dart';
import 'customers_notifier.dart';
import 'models/customer.dart';

class CustomerListScreen extends ConsumerStatefulWidget {
  const CustomerListScreen({super.key});

  @override
  ConsumerState<CustomerListScreen> createState() => _CustomerListScreenState();
}

class _CustomerListScreenState extends ConsumerState<CustomerListScreen> {
  final _searchController = TextEditingController();
  String _query = '';

  final Set<String> _selected = {};
  bool _selecting = false;
  bool _isDeleting = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(customersNotifierProvider.notifier).load());
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

  void _toggleSelectAll(List<Customer> visible) => setState(() {
    if (_selected.length == visible.length) {
      _selected.clear();
      _selecting = false;
    } else {
      _selected
        ..clear()
        ..addAll(visible.map((c) => c.id));
    }
  });

  Future<void> _deleteSelected() async {
    if (_selected.isEmpty || _isDeleting) return;
    final ids = _selected.toList();

    final confirmed = await confirmBulkDelete(
      context,
      count: ids.length,
      singular: 'this customer',
      plural: 'customers',
      consequences: const ['Customers linked to a purchase order will be kept'],
    );
    if (!confirmed || !mounted) return;

    setState(() => _isDeleting = true);
    try {
      final outcome = await ref
          .read(customersNotifierProvider.notifier)
          .deleteMany(ids);
      if (!mounted) return;
      showSnackBar(
        context,
        outcome.summary('customer', 'customers'),
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
    final state = ref.watch(customersNotifierProvider);
    final q = _query.trim().toLowerCase();
    final filtered = state.customers
        .where(
          (c) =>
              c.name.toLowerCase().contains(q) ||
              c.customerCode.toLowerCase().contains(q) ||
              c.phone.contains(q),
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
                onDelete: _selected.isEmpty || _isDeleting
                    ? null
                    : _deleteSelected,
              )
            : AppBar(title: const Text('Customers')),
        drawer: _selecting ? null : const AppDrawer(currentPath: '/customers'),
        body: ResponsiveContainer(
          child: Column(
            children: [
              if (_isDeleting) const LinearProgressIndicator(),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: TextField(
                  controller: _searchController,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Search by name, code or phone',
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
        ),
        floatingActionButton: _selecting
            ? null
            : FloatingActionButton(
                onPressed: () => context.push('/customers/new'),
                tooltip: 'Add customer',
                child: const Icon(Icons.add),
              ),
      ),
    );
  }

  Widget _buildBody(
    CustomerListState state,
    List<Customer> filtered,
    ThemeData theme,
  ) {
    if (state.isLoading && state.customers.isEmpty) {
      return const LoadingListSkeleton();
    }
    if (state.error != null && state.customers.isEmpty) {
      return EmptyState(
        icon: Icons.cloud_off,
        message: "Couldn't load customers.\n${state.error}",
        ctaLabel: 'Retry',
        onCta: () => ref.read(customersNotifierProvider.notifier).load(),
      );
    }
    if (state.customers.isEmpty) {
      return EmptyState(
        icon: Icons.people_outline,
        message: 'No customers yet',
        ctaLabel: 'Add your first customer',
        onCta: () => context.push('/customers/new'),
      );
    }
    if (filtered.isEmpty) {
      return EmptyState(
        icon: Icons.search_off,
        message: 'No customers match "$_query"',
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: filtered.length,
      itemBuilder: (context, index) {
        final customer = filtered[index];
        final selected = _selected.contains(customer.id);
        return Card(
          color: selected ? theme.colorScheme.secondaryContainer : null,
          child: ListTile(
            leading: SelectionLeading(
              selectionMode: _selecting,
              selected: selected,
              child: Hero(
                tag: 'customer-${customer.id}',
                child: CircleAvatar(
                  backgroundColor: theme.colorScheme.primaryContainer,
                  foregroundColor: theme.colorScheme.onPrimaryContainer,
                  child: Text(
                    customer.name.isNotEmpty
                        ? customer.name[0].toUpperCase()
                        : '?',
                  ),
                ),
              ),
            ),
            title: Text(customer.name),
            subtitle: Text(
              [
                if (customer.customerCode.isNotEmpty) customer.customerCode,
                if (customer.phone.isNotEmpty) customer.phone,
              ].where((s) => s.isNotEmpty).join(' • '),
            ),
            trailing: _selecting ? null : const Icon(Icons.chevron_right),
            onTap: () => _selecting
                ? _toggle(customer.id)
                : context.push('/customers/${customer.id}'),
            onLongPress: () => _selecting
                ? _toggle(customer.id)
                : _startSelection(customer.id),
          ),
        );
      },
    );
  }
}
