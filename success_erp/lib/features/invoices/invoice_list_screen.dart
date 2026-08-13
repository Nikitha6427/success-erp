import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../core/widgets/app_drawer.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/loading_list_skeleton.dart';
import '../../core/widgets/status_pill.dart';
import '../../features/purchase_orders/po_providers.dart';
import '../../features/customers/customers_notifier.dart';
import 'models/invoice.dart';
import 'invoice_providers.dart';

class InvoiceListScreen extends ConsumerStatefulWidget {
  const InvoiceListScreen({super.key});

  @override
  ConsumerState<InvoiceListScreen> createState() => _InvoiceListScreenState();
}

class _InvoiceListScreenState extends ConsumerState<InvoiceListScreen> {
  String _statusFilter = 'All';
  final _searchController = TextEditingController();
  String _query = '';

  static const _statuses = ['All', 'Pending', 'Paid'];

  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(invoiceListProvider.notifier).load());
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = ref.watch(invoiceListProvider);
    final pos = ref.watch(poNotifierProvider).orders;
    final poMap = {for (final po in pos) po.id: po.poNumber};
    final customers = ref.watch(customersNotifierProvider).customers;
    final customerMap = {for (final c in customers) c.id: c.name};

    final isLoading = ref.watch(invoiceListLoadingProvider);

    var filtered = state.where((inv) =>
        _statusFilter == 'All' || inv.status == _statusFilter).toList();

    if (_query.isNotEmpty) {
      filtered = filtered.where((inv) {
        final poNum = poMap[inv.poId]?.toLowerCase() ?? '';
        return inv.invoiceNumber.toLowerCase().contains(_query) ||
               poNum.contains(_query);
      }).toList();
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Invoices')),
      drawer: AppDrawer(currentPath: '/invoices'),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search by invoice or PO number',
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          SizedBox(
            height: 40,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              itemCount: _statuses.length,
              separatorBuilder: (_, context) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                final s = _statuses[i];
                return FilterChip(
                  label: Text(s),
                  selected: _statusFilter == s,
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
              child: _buildBody(state, filtered, poMap, customerMap, theme, isLoading),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/invoices/new'),
        tooltip: 'Create new invoice',
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildBody(
    List<Invoice> all,
    List<Invoice> filtered,
    Map<String, String> poMap,
    Map<String, String> customerMap,
    ThemeData theme,
    bool isLoading,
  ) {
    if (isLoading && all.isEmpty) {
      return const LoadingListSkeleton();
    }
    if (all.isEmpty) {
      return const EmptyState(
        icon: Icons.receipt_outlined,
        message: 'No invoices yet',
      );
    }
    if (filtered.isEmpty) {
      return const EmptyState(
        icon: Icons.search_off,
        message: 'No invoices match this filter',
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: filtered.length,
      itemBuilder: (context, index) {
        final inv = filtered[index];
        final poNumber = poMap[inv.poId] ?? '';
        return Card(
          child: ListTile(
            leading: Hero(
              tag: 'invoice-${inv.id}',
              child: CircleAvatar(
                backgroundColor: theme.colorScheme.primaryContainer,
                foregroundColor: theme.colorScheme.onPrimaryContainer,
                child: const Icon(Icons.receipt_outlined),
              ),
            ),
            title: Text(inv.invoiceNumber),
            subtitle: Text('PO: $poNumber  •  ${_formatDate(inv.invoiceDate)}'),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(inv.totalAmount, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold)),
                StatusPill(status: inv.status),
              ],
            ),
            onTap: () => context.push('/invoices/${inv.id}'),
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
