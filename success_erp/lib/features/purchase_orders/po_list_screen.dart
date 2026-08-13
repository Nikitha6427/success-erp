import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../core/widgets/app_drawer.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/loading_list_skeleton.dart';
import '../../core/widgets/status_pill.dart';
import '../../features/customers/customers_notifier.dart';
import 'models/purchase_order.dart';
import 'po_providers.dart';

class PoListScreen extends ConsumerStatefulWidget {
  const PoListScreen({super.key});

  @override
  ConsumerState<PoListScreen> createState() => _PoListScreenState();
}

class _PoListScreenState extends ConsumerState<PoListScreen> {
  final _searchController = TextEditingController();
  String _query = '';
  String _statusFilter = 'All';

  static const _statuses = [
    'All',
    'Pending',
    'Partially Delivered',
    'Delivered',
    'Invoiced',
  ];

  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(poNotifierProvider.notifier).load());
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(poNotifierProvider);
    final customers = ref.watch(customersNotifierProvider).customers;
    final customerMap = {for (final c in customers) c.id: c.name};

    final q = _query.toLowerCase();
    final filtered = state.orders.where((po) {
      final matchesStatus =
          _statusFilter == 'All' || po.status == _statusFilter;
      final name = customerMap[po.customerId]?.toLowerCase() ?? '';
      final matchesQuery = po.poNumber.toLowerCase().contains(q) || name.contains(q);
      return matchesStatus && matchesQuery;
    }).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Purchase Orders')),
      drawer: AppDrawer(currentPath: '/purchase-orders'),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search by PO number or customer',
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          SizedBox(
            height: 40,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _statuses.length,
              separatorBuilder: (_, context) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                final s = _statuses[i];
                final selected = _statusFilter == s;
                return FilterChip(
                  label: Text(s),
                  selected: selected,
                  onSelected: (_) => setState(() => _statusFilter = s),
                  showCheckmark: false,
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: _buildBody(state, filtered, customerMap),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/purchase-orders/new'),
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildBody(
    PoListState state,
    List<PurchaseOrder> filtered,
    Map<String, String> customerMap,
  ) {
    final theme = Theme.of(context);
    if (state.isLoading && state.orders.isEmpty) {
      return const LoadingListSkeleton();
    }
    if (state.orders.isEmpty) {
      return EmptyState(
        icon: Icons.receipt_long_outlined,
        message: 'No purchase orders yet',
        ctaLabel: 'Create your first PO',
        onCta: () => context.push('/purchase-orders/new'),
      );
    }
    if (filtered.isEmpty) {
      return EmptyState(
        icon: Icons.search_off,
        message: 'No POs match your filter',
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: filtered.length,
      itemBuilder: (context, index) {
        final po = filtered[index];
        final customerName = customerMap[po.customerId] ?? 'Unknown';
        return Card(
          child: ListTile(
            leading: Hero(
              tag: 'po-${po.id}',
              child: CircleAvatar(
                backgroundColor: theme.colorScheme.primaryContainer,
                foregroundColor: theme.colorScheme.onPrimaryContainer,
                child: const Icon(Icons.receipt_long),
              ),
            ),
            title: Text(po.poNumber),
            subtitle: Text('$customerName • ${_formatDate(po.orderDate)}'),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                StatusPill(status: po.status),
              ],
            ),
            onTap: () => context.push('/purchase-orders/${po.id}'),
          ),
        );
      },
    );
  }

  String _formatDate(String isoDate) {
    if (isoDate.isEmpty) return '';
    try {
      return DateFormat.yMMMd().format(DateTime.parse(isoDate));
    } catch (_) {
      return isoDate;
    }
  }
}
