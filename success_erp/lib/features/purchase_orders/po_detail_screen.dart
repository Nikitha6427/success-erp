import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../core/widgets/status_pill.dart';
import '../../core/widgets/empty_state.dart';
import '../../features/customers/customers_notifier.dart';
import '../../features/products/products_notifier.dart';
import '../../features/delivery_notes/dn_providers.dart';
import '../../features/invoices/invoice_providers.dart';
import 'models/purchase_order.dart';
import 'po_providers.dart';

class PoDetailScreen extends ConsumerStatefulWidget {
  final String id;

  const PoDetailScreen({required this.id, super.key});

  @override
  ConsumerState<PoDetailScreen> createState() => _PoDetailScreenState();
}

class _PoDetailScreenState extends ConsumerState<PoDetailScreen> {
  PurchaseOrder? _po;
  List<PurchaseOrderItem> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
    Future.microtask(() => ref.read(dnListProvider.notifier).load());
    Future.microtask(() => ref.read(invoiceListProvider.notifier).load());
  }

  Future<void> _load() async {
    final po = await ref.read(poNotifierProvider.notifier).findById(widget.id);
    final itemRepo = ref.read(poItemRepositoryProvider);
    final items = await itemRepo.loadByPoId(widget.id);
    if (mounted) setState(() { _po = po; _items = items; _loading = false; });
  }

  bool get _hasPending =>
      _items.any((i) => (double.tryParse(i.pendingQty) ?? 0) > 0);

  bool get _hasInvoiceable {
    for (final item in _items) {
      final delivered = double.tryParse(item.deliveredQty) ?? 0;
      final rate = double.tryParse(item.rate) ?? 0;
      // Ponytail: skip zero-rate items — they don't need invoicing
      if (delivered > 0 && rate > 0) return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final customers = ref.watch(customersNotifierProvider).customers;
    final products = ref.watch(productsNotifierProvider).products;
    final productMap = {for (final p in products) p.id: p.name};
    final customerName = customers
        .where((c) => c.id == (_po?.customerId ?? ''))
        .map((c) => c.name)
        .firstOrNull ?? 'Unknown';

    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Purchase Order')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_po == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Purchase Order')),
        body: const Center(child: Text('PO not found')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_po!.poNumber),
        actions: [
          StatusPill(status: _po!.status),
          const SizedBox(width: 16),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Hero(
            tag: 'po-${_po!.id}',
            child: CircleAvatar(
              radius: 32,
              backgroundColor: theme.colorScheme.primaryContainer,
              foregroundColor: theme.colorScheme.onPrimaryContainer,
              child: const Icon(Icons.receipt_long, size: 28),
            ),
          ),
          const SizedBox(height: 16),
          Text(_po!.poNumber, style: theme.textTheme.headlineSmall),
          const SizedBox(height: 4),
          Text('Customer: $customerName'),
          Text('Date: ${_formatDate(_po!.orderDate)}'),
          Text('Status: ${_po!.status}'),
          const SizedBox(height: 24),

          // ── Record Delivery button ──
          if (_hasPending)
            FilledButton.icon(
              onPressed: () async {
                await context.push('/purchase-orders/${widget.id}/deliver');
                if (mounted) _load();
              },
              icon: const Icon(Icons.local_shipping),
              label: const Text('Record Delivery'),
            ),
          if (_hasPending) const SizedBox(height: 12),

          // ── Generate Invoice button ──
          if (_hasInvoiceable)
            FilledButton.tonalIcon(
              onPressed: () async {
                await context.push('/invoices/new?poId=${widget.id}');
                if (mounted) _load();
              },
              icon: const Icon(Icons.receipt_outlined),
              label: const Text('Generate Invoice'),
            ),
          if (_hasInvoiceable && !_hasPending) const SizedBox(height: 24),

          // ── Line items ──
          Text('Line items', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          if (_items.isEmpty)
            const EmptyState(
              icon: Icons.shopping_cart_outlined,
              message: 'No items',
            )
          else
            ..._items.map((item) {
              final productName = productMap[item.productId] ?? 'Unknown';
              return Card(
                child: ListTile(
                  title: Text(productName),
                  subtitle: Text(
                    'Qty: ${item.quantity}  •  Rate: ${item.rate}',
                  ),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'Delivered: ${item.deliveredQty}',
                        style: theme.textTheme.bodySmall,
                      ),
                      Text(
                        'Pending: ${item.pendingQty}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.error,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),

          // ── Delivery notes ──
          const SizedBox(height: 24),
          Text('Delivery notes', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          _linkedDeliveryNotes(),

          // ── Invoices ──
          const SizedBox(height: 24),
          Text('Invoices', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          _linkedInvoices(),
        ],
      ),
    );
  }

  Widget _linkedDeliveryNotes() {
    final dnState = ref.watch(dnListProvider);
    final linked = dnState.where((d) => d.poId == widget.id).toList();
    if (linked.isEmpty) {
      return const EmptyState(
        icon: Icons.local_shipping_outlined,
        message: 'No delivery notes yet',
      );
    }
    return Column(
      children: linked.map((dn) => Card(
        child: ListTile(
          leading: const Icon(Icons.local_shipping_outlined),
          title: Text(dn.dnNumber),
          subtitle: Text(_formatDate(dn.deliveryDate)),
        ),
      )).toList(),
    );
  }

  Widget _linkedInvoices() {
    final invState = ref.watch(invoiceListProvider);
    final linked = invState.where((i) => i.poId == widget.id).toList();
    if (linked.isEmpty) {
      return const EmptyState(
        icon: Icons.receipt_outlined,
        message: 'No invoices yet',
      );
    }
    return Column(
      children: linked.map((inv) => Card(
        child: ListTile(
          leading: const Icon(Icons.receipt_outlined),
          title: Text(inv.invoiceNumber),
          subtitle: Text('${inv.totalAmount} • ${inv.status}'),
          onTap: () => context.push('/invoices/${inv.id}'),
        ),
      )).toList(),
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
