import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../core/widgets/document_copies_sheet.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/selection_app_bar.dart';
import '../../core/widgets/status_pill.dart';
import '../../core/widgets/snack_bar_helper.dart';
import '../../core/widgets/conflict_dialog.dart';
import '../customers/customers_notifier.dart';
import '../delivery_notes/dn_providers.dart';
import '../purchase_orders/po_providers.dart';
import '../purchase_orders/models/purchase_order.dart';
import '../settings/settings_notifier.dart';
import 'models/invoice.dart';
import 'invoice_providers.dart';
import 'invoice_pdf.dart';

class InvoiceDetailScreen extends ConsumerStatefulWidget {
  final String id;

  const InvoiceDetailScreen({required this.id, super.key});

  @override
  ConsumerState<InvoiceDetailScreen> createState() =>
      _InvoiceDetailScreenState();
}

class _InvoiceDetailScreenState extends ConsumerState<InvoiceDetailScreen> {
  Invoice? _invoice;
  List<InvoiceItem> _items = [];
  PurchaseOrder? _po;
  List<String> _dnNumbers = [];
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // Deferred out of the build phase: notifier.load() mutates provider state
    // synchronously, which Riverpod forbids during initState/build.
    Future.microtask(_load);
  }

  Future<void> _load() async {
    try {
      if (ref.read(invoiceListProvider).invoices.isEmpty) {
        await ref.read(invoiceListProvider.notifier).load();
      }
      final invoice = ref
          .read(invoiceListProvider)
          .invoices
          .where((i) => i.id == widget.id)
          .firstOrNull;

      final items = await ref
          .read(invoiceItemRepositoryProvider)
          .loadByInvoiceId(widget.id);

      PurchaseOrder? po;
      var dnNumbers = <String>[];
      if (invoice != null && invoice.poId.isNotEmpty) {
        po = await ref.read(poNotifierProvider.notifier).findById(invoice.poId);
        final dns = await ref.read(dnRepositoryProvider).loadByPoId(invoice.poId);
        final dnItems = await ref.read(dnItemRepositoryProvider).loadAll();
        final poItemIds = items.map((i) => i.poItemId).toSet();
        final linkedDnIds = dnItems
            .where((di) => poItemIds.contains(di.poItemId))
            .map((di) => di.dnId)
            .toSet();
        dnNumbers = dns
            .where((dn) => linkedDnIds.contains(dn.id))
            .map((dn) => dn.dnNumber)
            .toList();
      }

      if (ref.read(customersNotifierProvider).customers.isEmpty) {
        await ref.read(customersNotifierProvider.notifier).load();
      }
      if (ref.read(settingsNotifierProvider).profile == null) {
        await ref.read(settingsNotifierProvider.notifier).load();
      }

      if (!mounted) return;
      setState(() {
        _invoice = invoice;
        _items = items;
        _po = po;
        _dnNumbers = dnNumbers;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      showSnackBar(context, 'Could not load invoice: $e', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final money = NumberFormat.currency(locale: 'en_IN', symbol: '₹');

    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Invoice')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_invoice == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Invoice')),
        body: const EmptyState(
          icon: Icons.error_outline,
          message: 'This invoice could not be found.',
        ),
      );
    }

    final invoice = _invoice!;

    return Scaffold(
      appBar: AppBar(
        title: Hero(
          tag: 'invoice-${invoice.id}',
          child: Material(
            color: Colors.transparent,
            child: Text(invoice.invoiceNumber),
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.picture_as_pdf_outlined),
            tooltip: 'Save / print copies',
            onPressed: _busy ? null : _openCopies,
          ),
          IconButton(
            icon: Icon(invoice.isPaid
                ? Icons.undo
                : Icons.check_circle_outline),
            tooltip: invoice.isPaid ? 'Revert to Pending' : 'Mark as Paid',
            onPressed: _busy
                ? null
                : () => _changeStatus(
                      invoice.isPaid
                          ? Invoice.statusPending
                          : Invoice.statusPaid,
                    ),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Delete invoice',
            onPressed: _busy ? null : _confirmDelete,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          Text(invoice.invoiceNumber, style: theme.textTheme.headlineSmall),
          const SizedBox(height: 8),
          Row(
            children: [
              const Text('Status: '),
              StatusPill(status: invoice.status),
            ],
          ),
          const SizedBox(height: 8),
          _kv('Invoice date', _formatDate(invoice.invoiceDate)),
          _kv('Order', _po?.poNumber ?? '—'),
          if (_dnNumbers.isNotEmpty) _kv('Delivery notes', _dnNumbers.join(', ')),
          _kv('Transportation mode',
              invoice.transportMode.isEmpty ? '—' : invoice.transportMode),
          _kv('Vehicle number',
              invoice.vehicleNumber.isEmpty ? '—' : invoice.vehicleNumber),

          const SizedBox(height: 24),
          Text('Line items', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          if (_items.isEmpty)
            const EmptyState(icon: Icons.receipt_outlined, message: 'No items')
          else
            ..._items.map(
              (item) => Card(
                child: ListTile(
                  title: Text(item.description),
                  subtitle: Text(
                    item.isFlatCharge
                        ? 'Flat charge'
                        : 'Qty ${item.quantity} × ${item.rate}'
                            '${item.hsnSac.isEmpty ? '' : '  •  HSN/SAC ${item.hsnSac}'}'
                            '${item.remarks.isEmpty ? '' : '\n${item.remarks}'}',
                  ),
                  isThreeLine: !item.isFlatCharge && item.remarks.isNotEmpty,
                  trailing: Text(
                    item.amount,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ),

          const SizedBox(height: 16),
          const Divider(),
          _totalRow('Subtotal',
              money.format(double.tryParse(invoice.subtotalAmount) ?? 0)),
          _totalRow('CGST (${invoice.cgstPercent}%)',
              money.format(double.tryParse(invoice.cgstAmount) ?? 0)),
          _totalRow('SGST (${invoice.sgstPercent}%)',
              money.format(double.tryParse(invoice.sgstAmount) ?? 0)),
          const Divider(),
          _totalRow('Total', money.format(invoice.total), bold: true),
          if (invoice.amountInWords.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              invoice.amountInWords,
              style: theme.textTheme.bodySmall
                  ?.copyWith(fontStyle: FontStyle.italic),
            ),
          ],
        ],
      ),
    );
  }

  Widget _kv(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: Text('$label: $value'),
      );

  Widget _totalRow(String label, String value, {bool bold = false}) {
    final style = TextStyle(
      fontWeight: bold ? FontWeight.bold : FontWeight.normal,
      fontSize: bold ? 16 : 14,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [Text(label, style: style), Text(value, style: style)],
      ),
    );
  }

  /// Deleting an invoice frees the quantity it billed and rolls the purchase
  /// order's status back — which is also how an invoiced PO becomes deletable.
  Future<void> _confirmDelete() async {
    final invoice = _invoice;
    if (invoice == null || _busy) return;

    setState(() => _busy = true);
    try {
      final notifier = ref.read(invoiceListProvider.notifier);
      final impact = await notifier.impactFor([invoice.id]);
      if (!mounted) return;

      final confirmed = await confirmBulkDelete(
        context,
        count: 1,
        singular: 'this invoice',
        plural: 'invoices',
        consequences: impact.consequences,
      );
      if (!confirmed || !mounted) return;

      await notifier.delete(invoice.id);
      if (!mounted) return;
      showSnackBar(context, '${invoice.invoiceNumber} deleted');
      context.pop();
    } catch (e) {
      if (mounted) showSnackBar(context, 'Delete failed: $e', isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openCopies() async {
    final invoice = _invoice;
    if (invoice == null) return;
    setState(() => _busy = true);
    try {
      final customer = ref
          .read(customersNotifierProvider)
          .customers
          .where((c) => c.id == (_po?.customerId ?? ''))
          .firstOrNull;
      final company = ref.read(settingsNotifierProvider).profile;

      final copies = await InvoicePdf.generate(
        invoice: invoice,
        po: _po,
        customer: customer,
        company: company,
        deliveryNoteNumbers: _dnNumbers,
        items: [
          for (final item in _items)
            InvoicePdfLine(
              description: item.description,
              hsnSac: item.hsnSac,
              quantity: item.quantity,
              rate: item.rate,
              amount: item.amount,
              remarks: item.remarks,
            ),
        ],
      );
      if (!mounted) return;
      await showDocumentCopiesSheet(
        context,
        title: 'Invoice',
        documentNumber: invoice.invoiceNumber,
        copies: copies,
      );
    } catch (e) {
      if (mounted) {
        showSnackBar(context, 'Could not build the PDFs: $e', isError: true);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Explicit, confirmed status change — there is no automatic transition.
  Future<void> _changeStatus(String newStatus) async {
    final invoice = _invoice!;
    final toPaid = newStatus == Invoice.statusPaid;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(toPaid ? 'Mark as Paid?' : 'Revert to Pending?'),
        content: Text(
          toPaid
              ? 'Mark ${invoice.invoiceNumber} as paid? This can be undone.'
              : 'Move ${invoice.invoiceNumber} back to pending?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(toPaid ? 'Mark as Paid' : 'Revert'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    try {
      final updated = invoice.copyWith(status: newStatus);
      await ref.read(invoiceRepositoryProvider).update(updated);
      ref.read(invoiceListProvider.notifier).replace(updated);
      if (!mounted) return;
      setState(() => _invoice = updated);
      showSnackBar(
        context,
        toPaid
            ? '${updated.invoiceNumber} marked as paid'
            : '${updated.invoiceNumber} reverted to pending',
      );
    } catch (e) {
      if (!mounted) return;
      final handled = await handleConflictError(context, e);
      if (!mounted) return;
      if (handled) {
        await ref.read(invoiceListProvider.notifier).load();
        await _load();
      } else {
        showSnackBar(context, 'Update failed: $e', isError: true);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _formatDate(String isoDate) {
    if (isoDate.isEmpty) return '—';
    try {
      return DateFormat.yMMMd().format(DateTime.parse(isoDate));
    } catch (_) {
      return isoDate;
    }
  }
}
