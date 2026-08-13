import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/widgets/app_drawer.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/loading_list_skeleton.dart';
import '../../core/widgets/snack_bar_helper.dart';
import 'customers_notifier.dart';
import 'models/customer.dart';

class CustomerListScreen extends ConsumerStatefulWidget {
  const CustomerListScreen({super.key});

  @override
  ConsumerState<CustomerListScreen> createState() =>
      _CustomerListScreenState();
}

class _CustomerListScreenState extends ConsumerState<CustomerListScreen> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    Future.microtask(
      () => ref.read(customersNotifierProvider.notifier).load(),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _confirmDelete(Customer customer) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete customer?'),
        content: const Text(
          'This will remove the customer. '
          'If this customer has purchase orders, deletion will be blocked.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      try {
        await ref.read(customersNotifierProvider.notifier).delete(customer.id);
        if (mounted) showSnackBar(context, 'Customer deleted');
      } catch (e) {
        if (mounted) showSnackBar(context, '$e', isError: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = ref.watch(customersNotifierProvider);
    final filtered = state.customers
        .where((c) => c.name.toLowerCase().contains(_query.toLowerCase()))
        .toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Customers')),
      drawer: AppDrawer(currentPath: '/customers'),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search by name',
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
        onPressed: () => context.push('/customers/new'),
        child: const Icon(Icons.add),
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
        return Card(
          child: ListTile(
            leading: Hero(
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
            title: Text(customer.name),
            subtitle: Text(
              [
                if (customer.customerCode.isNotEmpty) customer.customerCode,
                if (customer.phone.isNotEmpty) customer.phone,
              ].where((s) => s.isNotEmpty).join(' • '),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/customers/${customer.id}'),
            onLongPress: () => _confirmDelete(customer),
          ),
        );
      },
    );
  }
}
