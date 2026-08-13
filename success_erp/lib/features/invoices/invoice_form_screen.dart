import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';
import 'package:printing/printing.dart';
import '../../core/widgets/snack_bar_helper.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/conflict_dialog.dart';
import '../../features/customers/customers_notifier.dart';
import '../../features/products/products_notifier.dart';
import '../../features/purchase_orders/po_providers.dart';
import '../../features/purchase_orders/models/purchase_order.dart';
import '../../features/delivery_notes/dn_providers.dart';
import '../../features/settings/settings_notifier.dart';
import 'models/invoice.dart';
import 'invoice_providers.dart';
import 'invoice_pdf.dart';

class InvoiceFormScreen extends ConsumerStatefulWidget {
  final String? poId;

  const InvoiceFormScreen({this.poId, super.key});

  @override
  ConsumerState<InvoiceFormScreen> createState() => _InvoiceFormScreenState();
}

class _InvoiceFormScreenState extends ConsumerState<InvoiceFormScreen> {
  final Map<String, TextEditingController> _qtyControllers = {};
  final Map<String, TextEditingController> _remarkControllers = {};
  final _vehicleController = TextEditingController();
  final _transportController = TextEditingController();
  final _cgstPercentController = TextEditingController(text: '9');
  final _sgstPercentController = TextEditingController(text: '9');
  bool _isSaving = false;
  bool _loading = true;
  List<PurchaseOrder> _allPos = [];
  List<_InvoiceableItem> _invoiceableItems = [];
  final List<_FlatChargeItem> _flatCharges = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final poRepo = ref.read(poRepositoryProvider);
      final itemRepo = ref.read(poItemRepositoryProvider);
      final products = ref.read(productsNotifierProvider).products;
      final productMap = {for (final p in products) p.id: p};

      // Load all POs or a single PO
      List<PurchaseOrder> allPos;
      if (widget.poId != null) {
        final po = await ref.read(poNotifierProvider.notifier).findById(widget.poId!);
        allPos = po != null ? [po] : [];
      } else {
        allPos = await poRepo.loadAll();
      }

      // Load all existing invoices/items to compute invoiced quantities
      final invoiceRepo = ref.read(invoiceRepositoryProvider);
      final invoiceItemRepo = ref.read(invoiceItemRepositoryProvider);
      final allInvoices = await invoiceRepo.loadAll();
      final allInvoiceItems = await invoiceItemRepo.loadAll();

      final invoicedQtyByProductAndPo = <String, double>{};
      for (final invItem in allInvoiceItems) {
        final inv = allInvoices.where((i) => i.id == invItem.invoiceId).firstOrNull;
        if (inv == null) continue;
        final key = '${inv.poId}:${invItem.productId}';
        invoicedQtyByProductAndPo[key] =
            (invoicedQtyByProductAndPo[key] ?? 0) + (double.tryParse(invItem.quantity) ?? 0);
      }

      final invoiceable = <_InvoiceableItem>[];
      for (final po in allPos) {
        final poItems = await itemRepo.loadByPoId(po.id);
        for (final poItem in poItems) {
          final delivered = double.tryParse(poItem.deliveredQty) ?? 0;
          final rate = double.tryParse(poItem.rate) ?? 0;
          if (rate == 0) continue; // skip zero-rate
          final key = '${po.id}:${poItem.productId}';
          final alreadyInvoiced = invoicedQtyByProductAndPo[key] ?? 0;
          final remaining = delivered - alreadyInvoiced;
          if (remaining > 0) {
            invoiceable.add(_InvoiceableItem(
              poItem: poItem,
              po: po,
              product: productMap[poItem.productId],
              invoiceableQty: remaining,
            ));
            _qtyControllers[poItem.id] = TextEditingController();
            _remarkControllers[poItem.id] = TextEditingController();
          }
        }
      }

      // Pre-fill CGST/SGST from first item's product tax_percent
      if (invoiceable.isNotEmpty) {
        final firstProduct = invoiceable.first.product;
        if (firstProduct != null) {
          final halfRate = (double.tryParse(firstProduct.taxPercent) ?? 18) / 2;
          _cgstPercentController.text = halfRate.toStringAsFixed(1);
          _sgstPercentController.text = halfRate.toStringAsFixed(1);
        }
      }

      if (mounted) {
        setState(() {
          _allPos = allPos;
          _invoiceableItems = invoiceable;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    for (final c in _qtyControllers.values) {
      c.dispose();
    }
    for (final c in _remarkControllers.values) {
      c.dispose();
    }
    _vehicleController.dispose();
    _transportController.dispose();
    _cgstPercentController.dispose();
    _sgstPercentController.dispose();
    for (final fc in _flatCharges) {
      fc.descriptionController.dispose();
      fc.amountController.dispose();
    }
    super.dispose();
  }

  void _addFlatCharge() {
    setState(() {
      _flatCharges.add(_FlatChargeItem(
        descriptionController: TextEditingController(),
        amountController: TextEditingController(),
      ));
    });
  }

  void _removeFlatCharge(int index) {
    final item = _flatCharges[index];
    item.descriptionController.dispose();
    item.amountController.dispose();
    setState(() => _flatCharges.removeAt(index));
  }

  double get _subtotal {
    double total = 0;
    for (final item in _invoiceableItems) {
      final controller = _qtyControllers[item.poItem.id];
      if (controller == null) continue;
      final qty = double.tryParse(controller.text.trim()) ?? 0;
      final rate = double.tryParse(item.poItem.rate) ?? 0;
      total += qty * rate;
    }
    for (final fc in _flatCharges) {
      total += double.tryParse(fc.amountController.text.trim()) ?? 0;
    }
    return total;
  }

  double get _cgstAmount {
    return _subtotal * (double.tryParse(_cgstPercentController.text.trim()) ?? 0) / 100;
  }

  double get _sgstAmount {
    return _subtotal * (double.tryParse(_sgstPercentController.text.trim()) ?? 0) / 100;
  }

  double get _grandTotal => _subtotal + _cgstAmount + _sgstAmount;

  bool get _isValid {
    for (final item in _invoiceableItems) {
      final controller = _qtyControllers[item.poItem.id];
      if (controller == null) continue;
      final entered = double.tryParse(controller.text.trim()) ?? 0;
      if (entered < 0 || entered > item.invoiceableQty) return false;
    }
    return _subtotal > 0;
  }

  String? _validateQty(String? value, _InvoiceableItem item) {
    if (value == null || value.trim().isEmpty) return null;
    final entered = double.tryParse(value.trim());
    if (entered == null || entered < 0) return 'Invalid';
    if (entered > item.invoiceableQty) return 'Max ${item.invoiceableQty.toInt()}';
    return null;
  }

  Future<void> _save() async {
    if (!_isValid || _isSaving) return;
    setState(() => _isSaving = true);
    try {
      final now = DateTime.now().toIso8601String();
      final counter = ref.read(counterHelperProvider);
      final invoiceRepo = ref.read(invoiceRepositoryProvider);
      final invoiceItemRepo = ref.read(invoiceItemRepositoryProvider);
      final poRepo = ref.read(poRepositoryProvider);
      final itemRepo = ref.read(poItemRepositoryProvider);

      final invoiceId = const Uuid().v4();
      final invoiceNumber = await counter.nextNumber('Invoice');

      final cgstPct = double.tryParse(_cgstPercentController.text.trim()) ?? 0;
      final sgstPct = double.tryParse(_sgstPercentController.text.trim()) ?? 0;

      final selectedItems = <_InvoiceableItem>[];
      for (final item in _invoiceableItems) {
        final controller = _qtyControllers[item.poItem.id];
        if (controller == null) continue;
        final qty = double.tryParse(controller.text.trim()) ?? 0;
        if (qty <= 0) continue;
        selectedItems.add(item);

        final rate = double.tryParse(item.poItem.rate) ?? 0;
        final taxPercent = double.tryParse(item.product?.taxPercent ?? '0') ?? 0;
        final lineAmount = qty * rate;
        final lineCgst = lineAmount * cgstPct / 100;
        final lineSgst = lineAmount * sgstPct / 100;
        final lineTotal = lineAmount + lineCgst + lineSgst;

        await invoiceItemRepo.save(InvoiceItem(
          id: const Uuid().v4(),
          invoiceId: invoiceId,
          productId: item.poItem.productId,
          quantity: qty.toInt().toString(),
          rate: rate.toString(),
          taxPercent: taxPercent.toString(),
          amount: lineTotal.toStringAsFixed(2),
          remark: (_remarkControllers[item.poItem.id]?.text.trim() ?? ''),
        ));
      }

      for (final fc in _flatCharges) {
        final desc = fc.descriptionController.text.trim();
        final amt = double.tryParse(fc.amountController.text.trim()) ?? 0;
        if (desc.isEmpty || amt <= 0) continue;
        final lineCgst = amt * cgstPct / 100;
        final lineSgst = amt * sgstPct / 100;
        await invoiceItemRepo.save(InvoiceItem(
          id: const Uuid().v4(),
          invoiceId: invoiceId,
          productId: '',
          quantity: '',
          rate: '',
          taxPercent: '0',
          amount: (amt + lineCgst + lineSgst).toStringAsFixed(2),
          remark: desc,
        ));
      }

      // Build references
      final poIds = selectedItems.map((i) => i.po.id).toSet().toList();
      final poRefs = poIds.join(', ');
      // Look up delivery note numbers for the invoiced PO items
      final dnRepo = ref.read(dnRepositoryProvider);
      final dnItemRepo = ref.read(dnItemRepositoryProvider);
      final allDns = await dnRepo.loadAll();
      final allDnItems = await dnItemRepo.loadAll();
      final invoicedPoItemIds = selectedItems.map((i) => i.poItem.id).toSet();
      final linkedDnIds = <String>{};
      for (final dnItem in allDnItems) {
        if (invoicedPoItemIds.contains(dnItem.poItemId)) {
          linkedDnIds.add(dnItem.dnId);
        }
      }
      final dnRefs = allDns
          .where((dn) => linkedDnIds.contains(dn.id))
          .map((dn) => dn.dnNumber)
          .join(', ');

      // Store poId as first PO for backward compat
      final firstPoId = poIds.isNotEmpty ? poIds.first : '';

      await invoiceRepo.save(Invoice(
        id: invoiceId,
        invoiceNumber: invoiceNumber,
        poId: firstPoId,
        invoiceDate: now,
        totalAmount: _grandTotal.toStringAsFixed(2),
        taxAmount: (_cgstAmount + _sgstAmount).toStringAsFixed(2),
        status: 'Pending',
        vehicleDetails: _vehicleController.text.trim(),
        gstDetails: _transportController.text.trim(),
        cgstPercent: cgstPct.toStringAsFixed(1),
        sgstPercent: sgstPct.toStringAsFixed(1),
        deliveryNoteRefs: dnRefs,
        poRefs: poRefs,
      ));

      // Update PO statuses
      for (final poId in poIds) {
        final allPoItems = await itemRepo.loadByPoId(poId);
        final allInvoices = await invoiceRepo.loadByPoId(poId);
        final allInvItems = await invoiceItemRepo.loadAll();
        final invIds = allInvoices.map((i) => i.id).toSet();
        final invoicedByProduct = <String, double>{};
        for (final item in allInvItems) {
          if (invIds.contains(item.invoiceId)) {
            invoicedByProduct[item.productId] =
                (invoicedByProduct[item.productId] ?? 0) + (double.tryParse(item.quantity) ?? 0);
          }
        }
        bool allFullyInvoiced = true;
        for (final poItem in allPoItems) {
          final delivered = double.tryParse(poItem.deliveredQty) ?? 0;
          final rate = double.tryParse(poItem.rate) ?? 0;
          if (rate == 0) continue;
          final invoiced = invoicedByProduct[poItem.productId] ?? 0;
          if (invoiced < delivered) {
            allFullyInvoiced = false;
            break;
          }
        }
        if (allFullyInvoiced) {
          final po = _allPos.where((p) => p.id == poId).firstOrNull;
          if (po != null) {
            await poRepo.update(po.copyWith(status: 'Invoiced', updatedAt: now));
          }
        }
      }

      ref.read(poNotifierProvider.notifier).load();
      ref.read(invoiceListProvider.notifier).load();

      // Generate PDF
      final customers = ref.read(customersNotifierProvider).customers;
      final firstPo = selectedItems.isNotEmpty ? selectedItems.first.po : null;
      final customer = customers.where((c) => c.id == (firstPo?.customerId ?? '')).firstOrNull;
      final companyProfile = ref.read(settingsNotifierProvider).profile;

      final pdfItems = selectedItems.map((item) {
        final controller = _qtyControllers[item.poItem.id]!;
        final qty = double.tryParse(controller.text.trim()) ?? 0;
        final rate = double.tryParse(item.poItem.rate) ?? 0;
        final lineAmount = qty * rate;
        final lineCgst = lineAmount * cgstPct / 100;
        final lineSgst = lineAmount * sgstPct / 100;
        return {
          'productName': item.product?.name ?? 'Unknown',
          'hsnCode': item.product?.hsnCode ?? '',
          'quantity': qty.toInt().toString(),
          'rate': rate.toStringAsFixed(2),
          'amount': (lineAmount + lineCgst + lineSgst).toStringAsFixed(2),
          'remark': (_remarkControllers[item.poItem.id]?.text.trim() ?? ''),
        };
      }).toList();

      for (final fc in _flatCharges) {
        final desc = fc.descriptionController.text.trim();
        final amt = double.tryParse(fc.amountController.text.trim()) ?? 0;
        if (desc.isEmpty || amt <= 0) continue;
        final lineCgst = amt * cgstPct / 100;
        final lineSgst = amt * sgstPct / 100;
        pdfItems.add({
          'productName': desc,
          'hsnCode': '',
          'quantity': '',
          'rate': '',
          'amount': (amt + lineCgst + lineSgst).toStringAsFixed(2),
          'remark': '',
        });
      }

      final pdf = await InvoicePdf.generate(
        invoiceNumber: invoiceNumber,
        invoiceDate: now,
        poNumber: poRefs,
        customerName: customer?.name ?? 'Unknown',
        customerAddress: customer?.address ?? '',
        customerGst: customer?.gstNumber ?? '',
        customerTin: customer?.tinNumber ?? '',
        customerCst: customer?.cstNumber ?? '',
        vehicleDetails: _vehicleController.text.trim(),
        gstDetails: _transportController.text.trim(),
        items: pdfItems,
        subtotal: _subtotal.toStringAsFixed(2),
        cgstPercent: cgstPct.toStringAsFixed(1),
        sgstPercent: sgstPct.toStringAsFixed(1),
        cgstTotal: _cgstAmount.toStringAsFixed(2),
        sgstTotal: _sgstAmount.toStringAsFixed(2),
        grandTotal: _grandTotal.toStringAsFixed(2),
        companyName: companyProfile?.companyName,
        companyAddress: companyProfile?.address,
        companyPhone: companyProfile?.phone,
        companyGst: companyProfile?.gstNumber,
        deliveryNoteRefs: dnRefs,
      );

      if (mounted) {
        final pdfBytes = await pdf.save();
        if (!mounted) return;
        await Printing.layoutPdf(
          onLayout: (format) async => pdfBytes,
          name: 'Invoice $invoiceNumber',
        );
        if (!mounted) return;
        showSnackBar(context, 'Invoice $invoiceNumber created');
        context.pop();
      }
    } catch (e) {
      if (!mounted) return;
      final handled = await handleConflictError(context, e);
      if (!mounted) return;
      if (!handled) showSnackBar(context, 'Save failed: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // Group items by customer for display
  Map<String, List<_InvoiceableItem>> get _groupedByCustomer {
    final customers = ref.read(customersNotifierProvider).customers;
    final customerMap = {for (final c in customers) c.id: c.name};
    final groups = <String, List<_InvoiceableItem>>{};
    for (final item in _invoiceableItems) {
      final name = customerMap[item.po.customerId] ?? 'Unknown';
      groups.putIfAbsent(name, () => []);
      groups[name]!.add(item);
    }
    return groups;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final products = ref.watch(productsNotifierProvider).products;
    final productMap = {for (final p in products) p.id: p.name};
    final unitMap = {for (final p in products) p.id: p.unit};

    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Generate Invoice')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final groups = _groupedByCustomer;

    return Scaffold(
      appBar: AppBar(title: const Text('Generate Invoice')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _vehicleController,
            decoration: const InputDecoration(labelText: 'Vehicle Number'),
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _transportController,
            decoration: const InputDecoration(labelText: 'Transportation Mode'),
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 16),
          Text(
            'Select items to invoice from delivered quantities',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
          ),
          const SizedBox(height: 16),
          ...groups.entries.map((entry) {
            final customerName = entry.key;
            final items = entry.value;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(customerName, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                ...items.map((item) {
                  final productName = productMap[item.poItem.productId] ?? 'Unknown';
                  final rate = double.tryParse(item.poItem.rate) ?? 0;
                  final unit = unitMap[item.poItem.productId] ?? '';
                  final controller = _qtyControllers[item.poItem.id];
                  final remarkController = _remarkControllers[item.poItem.id];
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(productName, style: theme.textTheme.titleSmall),
                          const SizedBox(height: 2),
                          Text(
                            'PO: ${item.po.poNumber}  •  Avail: ${item.invoiceableQty.toInt()} $unit  •  Rate: ${rate.toStringAsFixed(2)}',
                            style: theme.textTheme.bodySmall,
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: controller,
                                  decoration: InputDecoration(
                                    labelText: 'Qty',
                                    isDense: true,
                                    errorText: controller != null && controller.text.isNotEmpty
                                        ? _validateQty(controller.text, item)
                                        : null,
                                  ),
                                  keyboardType: TextInputType.number,
                                  onChanged: (_) => setState(() {}),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: TextField(
                                  controller: remarkController,
                                  decoration: const InputDecoration(labelText: 'Remarks', isDense: true),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                }),
                const SizedBox(height: 12),
              ],
            );
          }),
          // Flat charges
          ..._flatCharges.asMap().entries.map((entry) {
            final i = entry.key;
            final fc = entry.value;
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: fc.descriptionController,
                        decoration: const InputDecoration(labelText: 'Charge description', isDense: true),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 120,
                      child: TextField(
                        controller: fc.amountController,
                        decoration: const InputDecoration(labelText: 'Amount', isDense: true),
                        keyboardType: TextInputType.number,
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline, color: Colors.red),
                      onPressed: () => _removeFlatCharge(i),
                    ),
                  ],
                ),
              ),
            );
          }),
          TextButton.icon(
            onPressed: _addFlatCharge,
            icon: const Icon(Icons.add),
            label: const Text('Add flat charge (no qty/rate)'),
          ),
          if (_invoiceableItems.isEmpty && _flatCharges.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: EmptyState(
                icon: Icons.receipt_outlined,
                message: 'No items to invoice',
              ),
            ),
          const SizedBox(height: 16),
          // Tax section
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Tax Details', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _cgstPercentController,
                          decoration: const InputDecoration(labelText: 'CGST %', suffixText: '%', isDense: true),
                          keyboardType: TextInputType.number,
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: TextField(
                          controller: _sgstPercentController,
                          decoration: const InputDecoration(labelText: 'SGST %', suffixText: '%', isDense: true),
                          keyboardType: TextInputType.number,
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _summaryRow('Subtotal', _subtotal.toStringAsFixed(2)),
                  _summaryRow('CGST (${_cgstPercentController.text.isNotEmpty ? _cgstPercentController.text : '0'}%)', _cgstAmount.toStringAsFixed(2)),
                  _summaryRow('SGST (${_sgstPercentController.text.isNotEmpty ? _sgstPercentController.text : '0'}%)', _sgstAmount.toStringAsFixed(2)),
                  const Divider(),
                  _summaryRow('Grand Total', _grandTotal.toStringAsFixed(2), bold: true, large: true),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _isValid && !_isSaving ? _save : null,
            child: _isSaving
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Create Invoice'),
          ),
        ],
      ),
    );
  }

  Widget _summaryRow(String label, String value, {bool bold = false, bool large = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontWeight: bold ? FontWeight.bold : FontWeight.normal, fontSize: large ? 16 : 14)),
          Text(value, style: TextStyle(fontWeight: bold ? FontWeight.bold : FontWeight.normal, fontSize: large ? 16 : 14)),
        ],
      ),
    );
  }
}

class _InvoiceableItem {
  final PurchaseOrderItem poItem;
  final PurchaseOrder po;
  final dynamic product;
  final double invoiceableQty;

  const _InvoiceableItem({
    required this.poItem,
    required this.po,
    required this.product,
    required this.invoiceableQty,
  });
}

class _FlatChargeItem {
  final TextEditingController descriptionController;
  final TextEditingController amountController;

  _FlatChargeItem({
    required this.descriptionController,
    required this.amountController,
  });
}
