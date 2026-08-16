import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../core/services/address_format.dart';
import '../../core/widgets/responsive_container.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/status_pill.dart';
import '../../core/widgets/snack_bar_helper.dart';
import '../purchase_orders/po_providers.dart';
import '../invoices/invoice_providers.dart';
import 'customers_notifier.dart';

class CustomerDetailScreen extends ConsumerStatefulWidget {
  final String id;

  const CustomerDetailScreen({required this.id, super.key});

  @override
  ConsumerState<CustomerDetailScreen> createState() =>
      _CustomerDetailScreenState();
}

class _CustomerDetailScreenState extends ConsumerState<CustomerDetailScreen> {
  @override
  void initState() {
    super.initState();
    // Order history and the outstanding-balance summary need POs and invoices,
    // which may not have been loaded yet if this screen was deep-linked.
    Future.microtask(() async {
      final notifier = ref.read(customersNotifierProvider.notifier);
      if (notifier.findById(widget.id) == null) await notifier.load();
      if (!mounted) return;
      if (ref.read(poNotifierProvider).orders.isEmpty) {
        await ref.read(poNotifierProvider.notifier).load();
      }
      if (!mounted) return;
      if (ref.read(invoiceListProvider).invoices.isEmpty) {
        await ref.read(invoiceListProvider.notifier).load();
      }
    });
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete customer?'),
        content: const Text(
          'This removes the customer permanently. Deletion is blocked if the '
          'customer has any purchase orders.',
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
    if (confirmed != true || !mounted) return;
    try {
      await ref.read(customersNotifierProvider.notifier).delete(widget.id);
      if (!mounted) return;
      showSnackBar(context, 'Customer deleted');
      context.pop();
    } catch (e) {
      // Referential-integrity blocks land here — must not crash the screen.
      if (mounted) showSnackBar(context, '$e', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final customer = ref
        .watch(customersNotifierProvider)
        .customers
        .where((c) => c.id == widget.id)
        .firstOrNull;
    final allPos = ref.watch(poNotifierProvider).orders;
    final customerPos = allPos
        .where((po) => po.customerId == widget.id)
        .toList();
    final allInvoices = ref.watch(invoiceListProvider).invoices;

    final poIds = customerPos.map((po) => po.id).toSet();
    final customerInvoices = allInvoices
        .where((inv) => poIds.contains(inv.poId))
        .toList();

    double totalInvoiced = 0;
    double totalOutstanding = 0;
    for (final inv in customerInvoices) {
      totalInvoiced += inv.total;
      if (!inv.isPaid) totalOutstanding += inv.total;
    }

    final money = NumberFormat.currency(locale: 'en_IN', symbol: '₹');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Customer'),
        actions: [
          if (customer != null) ...[
            IconButton(
              icon: const Icon(Icons.edit),
              tooltip: 'Edit',
              onPressed: () => context.push('/customers/${widget.id}/edit'),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Delete',
              onPressed: _confirmDelete,
            ),
          ],
        ],
      ),
      body: ResponsiveContainer(
        child: customer == null
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Hero(
                      tag: 'customer-${customer.id}',
                      child: CircleAvatar(
                        radius: 32,
                        backgroundColor: theme.colorScheme.primaryContainer,
                        foregroundColor: theme.colorScheme.onPrimaryContainer,
                        child: Text(
                          customer.name.isNotEmpty
                              ? customer.name[0].toUpperCase()
                              : '?',
                          style: const TextStyle(fontSize: 28),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(customer.name, style: theme.textTheme.headlineSmall),
                    if (customer.customerCode.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        customer.customerCode,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    _field(theme, Icons.phone, 'Phone', customer.phone),
                    _field(theme, Icons.email, 'Email', customer.email),
                    _field(
                      theme,
                      Icons.location_on,
                      'Address',
                      customer.addressLines.join('\n'),
                    ),
                    _field(
                      theme,
                      Icons.receipt_long,
                      'GST',
                      AddressFormat.orNoneBlank(customer.gstNumber),
                    ),
                    _field(
                      theme,
                      Icons.receipt_long,
                      'TIN',
                      AddressFormat.orNoneBlank(customer.tinNumber),
                    ),
                    _field(
                      theme,
                      Icons.receipt_long,
                      'CST',
                      AddressFormat.orNoneBlank(customer.cstNumber),
                    ),
                    const SizedBox(height: 24),

                    // Two-number outstanding summary (AGENTS.md §5).
                    Card(
                      color: theme.colorScheme.surfaceContainerHighest,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Expanded(
                              child: _stat(
                                theme,
                                'Total Invoiced',
                                money.format(totalInvoiced),
                              ),
                            ),
                            Expanded(
                              child: _stat(
                                theme,
                                'Outstanding',
                                money.format(totalOutstanding),
                                color: totalOutstanding > 0
                                    ? theme.colorScheme.error
                                    : null,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    Text('Order history', style: theme.textTheme.titleMedium),
                    const SizedBox(height: 8),
                    if (customerPos.isEmpty)
                      const EmptyState(
                        icon: Icons.receipt_long_outlined,
                        message: 'No orders yet',
                      )
                    else
                      ...customerPos.map(
                        (po) => Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            title: Text(po.poNumber),
                            subtitle: Text(_formatDate(po.orderDate)),
                            trailing: StatusPill(status: po.status),
                            onTap: () =>
                                context.push('/purchase-orders/${po.id}'),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _stat(ThemeData theme, String label, String value, {Color? color}) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      );

  Widget _field(ThemeData theme, IconData icon, String label, String value) {
    if (value.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: theme.colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
                Text(value, style: theme.textTheme.bodyMedium),
              ],
            ),
          ),
        ],
      ),
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
