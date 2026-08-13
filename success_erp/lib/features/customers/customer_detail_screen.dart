import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/status_pill.dart';
import '../../core/widgets/snack_bar_helper.dart';
import '../../features/purchase_orders/po_providers.dart';
import '../../features/invoices/invoice_providers.dart';
import 'customers_notifier.dart';

class CustomerDetailScreen extends ConsumerStatefulWidget {
  final String id;

  const CustomerDetailScreen({required this.id, super.key});

  @override
  ConsumerState<CustomerDetailScreen> createState() =>
      _CustomerDetailScreenState();
}

class _CustomerDetailScreenState
    extends ConsumerState<CustomerDetailScreen> {
  @override
  void initState() {
    super.initState();
    final notifier = ref.read(customersNotifierProvider.notifier);
    if (notifier.findById(widget.id) == null) {
      Future.microtask(() => notifier.load());
    }
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete customer?'),
        content: const Text(
          'This will remove the customer. (Purchase-order referential '
          'integrity checks are added in a later phase.)',
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
      await ref.read(customersNotifierProvider.notifier).delete(widget.id);
      if (mounted) {
        showSnackBar(context, 'Customer deleted');
        context.pop();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final customer = ref.watch(customersNotifierProvider).customers
        .where((c) => c.id == widget.id)
        .firstOrNull;
    final allPos = ref.watch(poNotifierProvider).orders;
    final customerPos = allPos.where((po) => po.customerId == widget.id).toList();
    final allInvoices = ref.watch(invoiceListProvider);

    // Compute outstanding balance
    final poIds = customerPos.map((po) => po.id).toSet();
    final customerInvoices = allInvoices.where((inv) => poIds.contains(inv.poId)).toList();
    double totalInvoiced = 0;
    double totalOutstanding = 0;
    for (final inv in customerInvoices) {
      final amount = double.tryParse(inv.totalAmount) ?? 0;
      totalInvoiced += amount;
      if (inv.status != 'Paid') {
        totalOutstanding += amount;
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Customer'),
        actions: [
          if (customer != null)
            IconButton(
              icon: const Icon(Icons.edit),
              onPressed: () => context.push('/customers/${widget.id}/edit'),
            ),
          if (customer != null)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: _confirmDelete,
            ),
        ],
      ),
      body: customer == null
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
                  Text(
                    customer.name,
                    style: theme.textTheme.headlineSmall,
                  ),
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
                  _field(theme, Icons.location_on, 'Address', customer.address),
                  if (customer.gstNumber.isNotEmpty)
                    _field(theme, Icons.receipt_long, 'GST', customer.gstNumber),
                  if (customer.tinNumber.isNotEmpty)
                    _field(theme, Icons.receipt_long, 'TIN', customer.tinNumber),
                  if (customer.cstNumber.isNotEmpty)
                    _field(theme, Icons.receipt_long, 'CST', customer.cstNumber),
                  const SizedBox(height: 24),

                  // ── Outstanding balance summary ──
                  if (customerInvoices.isNotEmpty) ...[
                    Card(
                      color: theme.colorScheme.surfaceContainerHighest,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Total Invoiced',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.outline,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    totalInvoiced.toStringAsFixed(2),
                                    style: theme.textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Outstanding',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.outline,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    totalOutstanding.toStringAsFixed(2),
                                    style: theme.textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      color: totalOutstanding > 0
                                          ? theme.colorScheme.error
                                          : theme.colorScheme.onSurface,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],

                  Text(
                    'Order history',
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  if (customerPos.isEmpty)
                    const EmptyState(
                      icon: Icons.receipt_long_outlined,
                      message: 'No orders yet',
                    )
                  else
                    ...customerPos.map((po) => Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        title: Text(po.poNumber),
                        subtitle: Text(_formatDate(po.orderDate)),
                        trailing: StatusPill(status: po.status),
                        onTap: () => context.push('/purchase-orders/${po.id}'),
                      ),
                    )),
                ],
              ),
            ),
    );
  }

  Widget _field(
    ThemeData theme,
    IconData icon,
    String label,
    String value,
  ) {
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
