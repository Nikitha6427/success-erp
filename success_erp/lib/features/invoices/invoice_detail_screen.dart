import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/status_pill.dart';
import '../../core/widgets/snack_bar_helper.dart';
import '../../core/widgets/conflict_dialog.dart';
import '../../features/products/products_notifier.dart';
import '../../features/purchase_orders/po_providers.dart';
import '../../features/customers/customers_notifier.dart';
import '../../features/settings/settings_notifier.dart';
import 'models/invoice.dart';
import 'invoice_providers.dart';
import 'invoice_pdf.dart';

class InvoiceDetailScreen extends ConsumerStatefulWidget {
  final String id;

  const InvoiceDetailScreen({required this.id, super.key});

  @override
  ConsumerState<InvoiceDetailScreen> createState() => _InvoiceDetailScreenState();
}

class _InvoiceDetailScreenState extends ConsumerState<InvoiceDetailScreen> {
  Invoice? _invoice;
  List<InvoiceItem> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final invoices = ref.read(invoiceListProvider);
    final invoice = invoices.where((i) => i.id == widget.id).firstOrNull;
    final itemRepo = ref.read(invoiceItemRepositoryProvider);
    final allItems = await itemRepo.loadAll();
    final items = allItems.where((item) => item.invoiceId == widget.id).toList();
    if (mounted) setState(() { _invoice = invoice; _items = items; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final products = ref.watch(productsNotifierProvider).products;
    final productMap = {for (final p in products) p.id: p.name};
    final pos = ref.watch(poNotifierProvider).orders;
    final poNumber = pos.where((po) => po.id == (_invoice?.poId ?? '')).map((po) => po.poNumber).firstOrNull ?? '';

    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Invoice')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_invoice == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Invoice')),
        body: const Center(child: Text('Invoice not found')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Hero(
          tag: 'invoice-${_invoice!.id}',
          child: Text(_invoice!.invoiceNumber),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.print),
            onPressed: _printInvoice,
            tooltip: 'Print / Preview',
          ),
          if (_invoice!.status != 'Paid')
            IconButton(
              icon: const Icon(Icons.check_circle_outline),
              onPressed: _markAsPaid,
              tooltip: 'Mark as Paid',
            ),
          if (_invoice!.status == 'Paid')
            IconButton(
              icon: const Icon(Icons.undo),
              onPressed: _markAsPending,
              tooltip: 'Mark as Pending',
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(_invoice!.invoiceNumber, style: theme.textTheme.headlineSmall),
          const SizedBox(height: 4),
          Text('PO: ${_invoice!.poRefs.isNotEmpty ? _invoice!.poRefs : poNumber}'),
          if (_invoice!.deliveryNoteRefs.isNotEmpty)
            Text('DN: ${_invoice!.deliveryNoteRefs}'),
          Text('Date: ${_formatDate(_invoice!.invoiceDate)}'),
          if (_invoice!.vehicleDetails.isNotEmpty)
            Text('Vehicle: ${_invoice!.vehicleDetails}'),
          if (_invoice!.gstDetails.isNotEmpty)
            Text('GST: ${_invoice!.gstDetails}'),
          Row(
            children: [
              Text('Status: '),
              StatusPill(status: _invoice!.status),
            ],
          ),
          const SizedBox(height: 16),
          Text('Line items', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          if (_items.isEmpty)
            const EmptyState(icon: Icons.receipt_outlined, message: 'No items')
          else
            ..._items.map((item) {
              final productName = productMap[item.productId] ?? 'Unknown';
              return Card(
                child: ListTile(
                  title: Text(productName),
                  subtitle: Text(
                    'Qty: ${item.quantity}  •  Rate: ${item.rate}  •  Tax: ${item.taxPercent}%',
                  ),
                  trailing: Text(
                    item.amount,
                    style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
              );
            }),
          const SizedBox(height: 16),
          Divider(),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  ..._buildTaxLines(theme),
                  const SizedBox(height: 4),
                  Text(
                    'Total: ${_invoice!.totalAmount}',
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _printInvoice() async {
    if (_invoice == null) return;
    final products = ref.read(productsNotifierProvider).products;
    final productMap = {for (final p in products) p.id: p};
    final customers = ref.read(customersNotifierProvider).customers;
    final pos = ref.read(poNotifierProvider).orders;
    final po = pos.where((p) => p.id == _invoice!.poId).firstOrNull;
    final customer = customers.where((c) => c.id == (po?.customerId ?? '')).firstOrNull;
    final poNumber = po?.poNumber ?? '';
    final companyProfile = ref.read(settingsNotifierProvider).profile;

    final pdfItems = _items.map((item) {
      final product = productMap[item.productId];
      return {
        'productName': product?.name ?? 'Unknown',
        'hsnCode': product?.hsnCode ?? '',
        'quantity': item.quantity,
        'rate': item.rate,
        'taxPercent': item.taxPercent,
        'amount': item.amount,
        'remark': item.remark,
      };
    }).toList();

    final subtotal = _items.fold(0.0, (sum, item) {
      final qty = double.tryParse(item.quantity) ?? 0;
      final rate = double.tryParse(item.rate) ?? 0;
      return sum + qty * rate;
    });

    final cgstPct = _invoice!.cgstPercent;
    final sgstPct = _invoice!.sgstPercent;
    final totalTax = double.tryParse(_invoice!.taxAmount) ?? 0;
    final cgstTotal = (totalTax / 2).toStringAsFixed(2);
    final sgstTotal = (totalTax / 2).toStringAsFixed(2);

    final pdf = await InvoicePdf.generate(
      invoiceNumber: _invoice!.invoiceNumber,
      invoiceDate: _invoice!.invoiceDate,
      poNumber: poNumber,
      customerName: customer?.name ?? 'Unknown',
      customerAddress: customer?.address ?? '',
      customerGst: customer?.gstNumber ?? '',
      customerTin: customer?.tinNumber ?? '',
      customerCst: customer?.cstNumber ?? '',
      vehicleDetails: _invoice!.vehicleDetails,
      gstDetails: _invoice!.gstDetails,
      items: pdfItems,
      subtotal: subtotal.toStringAsFixed(2),
      cgstPercent: cgstPct,
      sgstPercent: sgstPct,
      cgstTotal: cgstTotal,
      sgstTotal: sgstTotal,
      grandTotal: _invoice!.totalAmount,
      companyName: companyProfile?.companyName,
      companyAddress: companyProfile?.address,
      companyPhone: companyProfile?.phone,
      companyGst: companyProfile?.gstNumber,
      deliveryNoteRefs: _invoice!.deliveryNoteRefs,
    );

    if (mounted) {
      final pdfBytes = await pdf.save();
      if (!mounted) return;
      await Printing.layoutPdf(
        onLayout: (format) async => pdfBytes,
        name: 'Invoice ${_invoice!.invoiceNumber}',
      );
    }
  }

  String _formatDate(String isoDate) {
    if (isoDate.isEmpty) return '';
    try {
      return DateFormat.yMMMd().format(DateTime.parse(isoDate));
    } catch (_) {
      return isoDate;
    }
  }

  List<Widget> _buildTaxLines(ThemeData theme) {
    final totalTax = double.tryParse(_invoice!.taxAmount) ?? 0;
    final halfTax = totalTax / 2;
    final cgstPct = _invoice!.cgstPercent;
    final sgstPct = _invoice!.sgstPercent;

    return [
      Text('CGST ($cgstPct%): ${halfTax.toStringAsFixed(2)}'),
      Text('SGST ($sgstPct%): ${halfTax.toStringAsFixed(2)}'),
    ];
  }

  Future<void> _markAsPaid() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Mark as Paid?'),
        content: Text('Mark ${_invoice!.invoiceNumber} as paid? This action can be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Mark as Paid'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      try {
        final invoiceRepo = ref.read(invoiceRepositoryProvider);
        final updated = _invoice!.copyWith(status: 'Paid');
        await invoiceRepo.update(updated);
        ref.read(invoiceListProvider.notifier).load();
        if (mounted) {
          setState(() => _invoice = updated);
          showSnackBar(context, '${_invoice!.invoiceNumber} marked as paid');
        }
      } catch (e) {
        if (!mounted) return;
        final handled = await handleConflictError(context, e);
        if (!mounted) return;
        if (!handled) showSnackBar(context, 'Update failed: $e', isError: true);
      }
    }
  }

  Future<void> _markAsPending() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Mark as Pending?'),
        content: Text('Revert ${_invoice!.invoiceNumber} to pending status?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Revert to Pending'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      try {
        final invoiceRepo = ref.read(invoiceRepositoryProvider);
        final updated = _invoice!.copyWith(status: 'Pending');
        await invoiceRepo.update(updated);
        ref.read(invoiceListProvider.notifier).load();
        if (mounted) {
          setState(() => _invoice = updated);
          showSnackBar(context, '${_invoice!.invoiceNumber} reverted to pending');
        }
      } catch (e) {
        if (!mounted) return;
        final handled = await handleConflictError(context, e);
        if (!mounted) return;
        if (!handled) showSnackBar(context, 'Update failed: $e', isError: true);
      }
    }
  }
}
