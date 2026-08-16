import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../core/services/invoice_math.dart';
import '../../core/widgets/responsive_container.dart';
import '../../core/widgets/selection_app_bar.dart';
import '../../core/widgets/snack_bar_helper.dart';
import '../../core/widgets/status_pill.dart';
import '../../core/widgets/empty_state.dart';
import '../customers/customers_notifier.dart';
import '../products/products_notifier.dart';
import '../delivery_notes/dn_providers.dart';
import '../invoices/invoice_providers.dart';
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
  Map<String, double> _invoicedByPoItem = {};
  bool _loading = true;
  bool _deleting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      final po = await ref
          .read(poNotifierProvider.notifier)
          .findById(widget.id);
      final items = await ref
          .read(poItemRepositoryProvider)
          .loadByPoId(widget.id);
      final invoiced = await ref
          .read(invoiceItemRepositoryProvider)
          .invoicedQtyByPoItem();

      await ref.read(dnListProvider.notifier).load();
      await ref.read(invoiceListProvider.notifier).load();
      if (ref.read(customersNotifierProvider).customers.isEmpty) {
        await ref.read(customersNotifierProvider.notifier).load();
      }
      if (ref.read(productsNotifierProvider).products.isEmpty) {
        await ref.read(productsNotifierProvider.notifier).load();
      }

      if (!mounted) return;
      setState(() {
        _po = po;
        _items = items;
        _invoicedByPoItem = invoiced;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _confirmDelete() async {
    if (_deleting) return;
    setState(() => _deleting = true);
    try {
      final notifier = ref.read(poNotifierProvider.notifier);
      final impact = await notifier.impactFor([widget.id]);
      if (!mounted) return;

      if (impact.isFullyBlocked) {
        showSnackBar(
          context,
          'This order has ${impact.invoices} invoice(s) and cannot be '
          'deleted. Delete those invoices first.',
          isError: true,
        );
        return;
      }

      final confirmed = await confirmBulkDelete(
        context,
        count: 1,
        singular: 'this purchase order',
        plural: 'purchase orders',
        consequences: impact.consequences,
      );
      if (!confirmed || !mounted) return;

      await notifier.delete(widget.id);
      if (!mounted) return;
      showSnackBar(context, '${_po?.poNumber ?? "Purchase order"} deleted');
      context.pop();
    } catch (e) {
      if (mounted) showSnackBar(context, '$e', isError: true);
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  bool get _hasPending => _items.any((i) => i.pending > 0);

  /// Invoiceable = delivered − already invoiced, per PO line item, ignoring
  /// zero-rate lines (AGENTS.md §4).
  bool get _hasInvoiceable => _items.any(
    (i) =>
        InvoiceMath.needsInvoicing(i) &&
        InvoiceMath.invoiceableQty(
              poItem: i,
              invoicedByPoItem: _invoicedByPoItem,
            ) >
            0,
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final customers = ref.watch(customersNotifierProvider).customers;
    final products = ref.watch(productsNotifierProvider).products;
    final productById = {for (final p in products) p.id: p};

    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Purchase Order')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_po == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Purchase Order')),
        body: const EmptyState(
          icon: Icons.error_outline,
          message: 'This purchase order could not be found.',
        ),
      );
    }

    final po = _po!;
    final customerName =
        customers
            .where((c) => c.id == po.customerId)
            .map((c) => c.name)
            .firstOrNull ??
        'Unknown';

    return Scaffold(
      appBar: AppBar(
        title: Text(po.poNumber),
        actions: [
          Center(child: StatusPill(status: po.status)),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Delete purchase order',
            onPressed: _deleting ? null : _confirmDelete,
          ),
        ],
      ),
      body: ResponsiveContainer(
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              Hero(
                tag: 'po-${po.id}',
                child: CircleAvatar(
                  radius: 32,
                  backgroundColor: theme.colorScheme.primaryContainer,
                  foregroundColor: theme.colorScheme.onPrimaryContainer,
                  child: const Icon(Icons.receipt_long, size: 28),
                ),
              ),
              const SizedBox(height: 16),
              Text(po.poNumber, style: theme.textTheme.headlineSmall),
              const SizedBox(height: 8),
              _kv('Customer', customerName),
              _kv('Order date', _formatDate(po.orderDate)),
              _kv('Status', po.status),
              if (po.clientPoNumber.isNotEmpty)
                _kv("Client's PO", po.clientPoNumber),
              if (po.clientPoDate.isNotEmpty)
                _kv("Client's PO date", _formatDate(po.clientPoDate)),
              if (po.clientDeliveryNoteNumber.isNotEmpty)
                _kv("Client's delivery challan", po.clientDeliveryNoteNumber),
              if (po.clientDeliveryNoteDate.isNotEmpty)
                _kv(
                  "Client's challan date",
                  _formatDate(po.clientDeliveryNoteDate),
                ),
              const SizedBox(height: 24),

              if (_hasPending)
                FilledButton.icon(
                  onPressed: () async {
                    await context.push('/purchase-orders/${widget.id}/deliver');
                    if (mounted) await _load();
                  },
                  icon: const Icon(Icons.local_shipping),
                  label: const Text('Record Delivery'),
                ),
              if (_hasPending) const SizedBox(height: 12),

              if (_hasInvoiceable)
                FilledButton.tonalIcon(
                  onPressed: () async {
                    await context.push('/purchase-orders/${widget.id}/invoice');
                    if (mounted) await _load();
                  },
                  icon: const Icon(Icons.receipt_outlined),
                  label: const Text('Generate Invoice'),
                ),

              const SizedBox(height: 24),
              Text('Line items', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              if (_items.isEmpty)
                const EmptyState(
                  icon: Icons.shopping_cart_outlined,
                  message: 'No items',
                )
              else
                ..._items.map((item) {
                  final product = productById[item.productId];
                  final unit = product?.unit ?? '';
                  final invoiceable = InvoiceMath.invoiceableQty(
                    poItem: item,
                    invoicedByPoItem: _invoicedByPoItem,
                  );
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Text(
                                  product?.name ?? 'Unknown',
                                  style: theme.textTheme.titleSmall,
                                ),
                              ),
                              Text(
                                (item.qty * item.rt).toStringAsFixed(2),
                                style: theme.textTheme.titleSmall,
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Ordered ${_n(item.qty)} $unit  •  Rate ${item.rate}',
                            style: theme.textTheme.bodySmall,
                          ),
                          Text(
                            'Delivered ${_n(item.delivered)}  •  '
                            'Pending ${_n(item.pending)}  •  '
                            'Invoiceable ${_n(invoiceable)}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: item.pending > 0
                                  ? theme.colorScheme.error
                                  : theme.colorScheme.outline,
                            ),
                          ),
                          if (item.remarks.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              item.remarks,
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                }),

              const SizedBox(height: 24),
              Text('Delivery notes', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              _linkedDeliveryNotes(),

              const SizedBox(height: 24),
              Text('Invoices', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              _linkedInvoices(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _kv(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 2),
    child: Text('$label: $value'),
  );

  Widget _linkedDeliveryNotes() {
    final linked = ref
        .watch(dnListProvider)
        .where((d) => d.poId == widget.id)
        .toList();
    if (linked.isEmpty) {
      return const EmptyState(
        icon: Icons.local_shipping_outlined,
        message: 'No delivery notes yet',
      );
    }
    return Column(
      children: linked
          .map(
            (dn) => Card(
              child: ListTile(
                leading: const Icon(Icons.local_shipping_outlined),
                title: Text(dn.dnNumber),
                subtitle: Text(_formatDate(dn.deliveryDate)),
              ),
            ),
          )
          .toList(),
    );
  }

  Widget _linkedInvoices() {
    final linked = ref
        .watch(invoiceListProvider)
        .invoices
        .where((i) => i.poId == widget.id)
        .toList();
    if (linked.isEmpty) {
      return const EmptyState(
        icon: Icons.receipt_outlined,
        message: 'No invoices yet',
      );
    }
    return Column(
      children: linked
          .map(
            (inv) => Card(
              child: ListTile(
                leading: const Icon(Icons.receipt_outlined),
                title: Text(inv.invoiceNumber),
                subtitle: Text(_formatDate(inv.invoiceDate)),
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(inv.totalAmount),
                    StatusPill(status: inv.status),
                  ],
                ),
                onTap: () async {
                  await context.push('/invoices/${inv.id}');
                  if (mounted) await _load();
                },
              ),
            ),
          )
          .toList(),
    );
  }

  static String _n(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  String _formatDate(String isoDate) {
    if (isoDate.isEmpty) return '—';
    try {
      return DateFormat.yMMMd().format(DateTime.parse(isoDate));
    } catch (_) {
      return isoDate;
    }
  }
}
