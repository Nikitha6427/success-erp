import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import '../../core/services/invoice_math.dart';
import '../../core/services/number_to_words.dart';
import '../../core/widgets/responsive_container.dart';
import '../../core/widgets/document_copies_sheet.dart';
import '../../core/widgets/snack_bar_helper.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/conflict_dialog.dart';
import '../customers/customers_notifier.dart';
import '../products/models/product.dart';
import '../products/products_notifier.dart';
import '../purchase_orders/po_providers.dart';
import '../purchase_orders/models/purchase_order.dart';
import '../delivery_notes/dn_providers.dart';
import '../settings/settings_notifier.dart';
import 'models/invoice.dart';
import 'invoice_providers.dart';
import 'invoice_pdf.dart';

class _InvoiceableLine {
  final PurchaseOrderItem poItem;
  final Product? product;
  final double invoiceableQty;

  const _InvoiceableLine({
    required this.poItem,
    required this.product,
    required this.invoiceableQty,
  });
}

class _FlatCharge {
  final TextEditingController description = TextEditingController();
  final TextEditingController amount = TextEditingController();

  void dispose() {
    description.dispose();
    amount.dispose();
  }

  double get value => double.tryParse(amount.text.trim()) ?? 0;
  bool get isComplete => description.text.trim().isNotEmpty && value > 0;
}

class InvoiceFormScreen extends ConsumerStatefulWidget {
  /// When null the screen first asks which PO to invoice. One invoice covers
  /// one PO — multi-PO consolidation is deferred (AGENTS.md §8).
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
  // AGENTS.md §4/§5: default 9% each, fully editable per invoice.
  final _cgstController = TextEditingController(
    text: Invoice.defaultCgstPercent,
  );
  final _sgstController = TextEditingController(
    text: Invoice.defaultSgstPercent,
  );
  final List<_FlatCharge> _flatCharges = [];

  DateTime _invoiceDate = DateTime.now();
  bool _loading = true;
  bool _isSaving = false;

  PurchaseOrder? _po;
  List<_InvoiceableLine> _lines = [];
  List<PurchaseOrderItem> _allPoItems = [];
  Map<String, double> _invoicedByPoItem = {};

  /// PO-picker mode (widget.poId == null).
  List<PurchaseOrder> _selectablePos = [];

  @override
  void initState() {
    super.initState();
    // Deferred out of the build phase: notifier.load() mutates provider state
    // synchronously, which Riverpod forbids during initState/build — this was
    // the SettingsNotifier "Tried to modify a provider" crash on the invoice
    // screen. Matches the pattern every other screen already uses.
    Future.microtask(_load);
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      if (ref.read(productsNotifierProvider).products.isEmpty) {
        await ref.read(productsNotifierProvider.notifier).load();
      }
      if (ref.read(customersNotifierProvider).customers.isEmpty) {
        await ref.read(customersNotifierProvider.notifier).load();
      }
      if (ref.read(settingsNotifierProvider).profile == null) {
        await ref.read(settingsNotifierProvider.notifier).load();
      }

      final invoicedByPoItem = await ref
          .read(invoiceItemRepositoryProvider)
          .invoicedQtyByPoItem();
      final itemRepo = ref.read(poItemRepositoryProvider);

      if (widget.poId == null) {
        await ref.read(poNotifierProvider.notifier).load();
        final pos = ref.read(poNotifierProvider).orders;
        final allItems = await itemRepo.loadAll();
        final selectable = <PurchaseOrder>[];
        for (final po in pos) {
          final items = allItems.where((i) => i.poId == po.id);
          final any = items.any(
            (i) =>
                InvoiceMath.needsInvoicing(i) &&
                InvoiceMath.invoiceableQty(
                      poItem: i,
                      invoicedByPoItem: invoicedByPoItem,
                    ) >
                    0,
          );
          if (any) selectable.add(po);
        }
        if (!mounted) return;
        setState(() {
          _selectablePos = selectable;
          _invoicedByPoItem = invoicedByPoItem;
          _loading = false;
        });
        return;
      }

      final po = await ref
          .read(poNotifierProvider.notifier)
          .findById(widget.poId!);
      final poItems = await itemRepo.loadByPoId(widget.poId!);
      final products = ref.read(productsNotifierProvider).products;
      final productById = {for (final p in products) p.id: p};

      final lines = <_InvoiceableLine>[];
      for (final item in poItems) {
        // Zero-rate lines never need invoicing (AGENTS.md §4).
        if (!InvoiceMath.needsInvoicing(item)) continue;
        final qty = InvoiceMath.invoiceableQty(
          poItem: item,
          invoicedByPoItem: invoicedByPoItem,
        );
        if (qty <= 0) continue;
        lines.add(
          _InvoiceableLine(
            poItem: item,
            product: productById[item.productId],
            invoiceableQty: qty,
          ),
        );
        _qtyControllers.putIfAbsent(item.id, () => TextEditingController());
        _remarkControllers.putIfAbsent(item.id, () => TextEditingController());
      }

      if (!mounted) return;
      setState(() {
        _po = po;
        _allPoItems = poItems;
        _lines = lines;
        _invoicedByPoItem = invoicedByPoItem;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      showSnackBar(context, 'Could not load invoice data: $e', isError: true);
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
    for (final fc in _flatCharges) {
      fc.dispose();
    }
    _vehicleController.dispose();
    _transportController.dispose();
    _cgstController.dispose();
    _sgstController.dispose();
    super.dispose();
  }

  // ── Derived values ────────────────────────────────────────────────────────

  double _enteredQty(_InvoiceableLine line) =>
      double.tryParse(_qtyControllers[line.poItem.id]?.text.trim() ?? '') ?? 0;

  /// Blank means "not billing this line on this invoice".
  String? _qtyError(_InvoiceableLine line) {
    final raw = _qtyControllers[line.poItem.id]?.text.trim() ?? '';
    if (raw.isEmpty) return null;
    final entered = double.tryParse(raw);
    if (entered == null) return 'Enter a number';
    if (entered <= 0) return 'Must be greater than 0';
    // Validated against INVOICEABLE quantity, not pending quantity.
    if (entered > line.invoiceableQty) {
      return 'Max ${_n(line.invoiceableQty)} invoiceable';
    }
    return null;
  }

  String? _percentError(TextEditingController c) {
    final raw = c.text.trim();
    if (raw.isEmpty) return 'Required';
    final v = double.tryParse(raw);
    if (v == null) return 'Enter a number';
    if (v < 0 || v > 100) return '0–100';
    return null;
  }

  double get _cgstPercent => double.tryParse(_cgstController.text.trim()) ?? 0;
  double get _sgstPercent => double.tryParse(_sgstController.text.trim()) ?? 0;

  List<_InvoiceableLine> get _selectedLines =>
      _lines.where((l) => _enteredQty(l) > 0).toList();

  InvoiceTotals get _totals => InvoiceTotals.from(
    lineAmounts: [
      for (final l in _selectedLines)
        InvoiceMath.lineAmount(_enteredQty(l), l.poItem.rt),
      for (final fc in _flatCharges)
        if (fc.isComplete) fc.value,
    ],
    cgstPercent: _cgstPercent,
    sgstPercent: _sgstPercent,
  );

  bool get _isValid {
    if (_lines.any((l) => _qtyError(l) != null)) return false;
    if (_percentError(_cgstController) != null) return false;
    if (_percentError(_sgstController) != null) return false;
    if (_flatCharges.any(
      (fc) =>
          (fc.description.text.trim().isNotEmpty ||
              fc.amount.text.trim().isNotEmpty) &&
          !fc.isComplete,
    )) {
      return false;
    }
    return _selectedLines.isNotEmpty || _flatCharges.any((fc) => fc.isComplete);
  }

  // ── Save ──────────────────────────────────────────────────────────────────

  Future<void> _save() async {
    if (!_isValid || _isSaving || _po == null) return;
    setState(() => _isSaving = true);

    final selected = _selectedLines;
    final totals = _totals;

    try {
      final now = DateTime.now().toIso8601String();
      final counter = ref.read(counterHelperProvider);
      final invoiceRepo = ref.read(invoiceRepositoryProvider);
      final invoiceItemRepo = ref.read(invoiceItemRepositoryProvider);
      final poRepo = ref.read(poRepositoryProvider);

      final invoiceId = const Uuid().v4();
      final invoiceNumber = await counter.nextSimpleNumber('Invoice', 'INV');

      final invoice = Invoice(
        id: invoiceId,
        invoiceNumber: invoiceNumber,
        poId: _po!.id,
        invoiceDate: _invoiceDate.toIso8601String(),
        subtotalAmount: totals.subtotal.toStringAsFixed(2),
        cgstPercent: _trimPercent(totals.cgstPercent),
        cgstAmount: totals.cgstAmount.toStringAsFixed(2),
        sgstPercent: _trimPercent(totals.sgstPercent),
        sgstAmount: totals.sgstAmount.toStringAsFixed(2),
        totalAmount: totals.total.toStringAsFixed(2),
        amountInWords: NumberToWords.convert(totals.total),
        transportMode: _transportController.text.trim(),
        vehicleNumber: _vehicleController.text.trim(),
        status: Invoice.statusPending,
        createdAt: now,
      );
      await invoiceRepo.save(invoice);

      final savedItems = <InvoiceItem>[];
      for (final line in selected) {
        final qty = _enteredQty(line);
        // amount is quantity × rate, EXCLUDING tax — tax is applied once at
        // invoice level so the item column always sums to the subtotal.
        final item = InvoiceItem(
          id: const Uuid().v4(),
          invoiceId: invoiceId,
          poItemId: line.poItem.id,
          productId: line.poItem.productId,
          description: line.product?.name ?? 'Item',
          hsnSac: line.product?.hsnSac ?? '',
          quantity: _n(qty),
          rate: line.poItem.rate,
          amount: InvoiceMath.lineAmount(
            qty,
            line.poItem.rt,
          ).toStringAsFixed(2),
          remarks: _remarkControllers[line.poItem.id]?.text.trim() ?? '',
        );
        await invoiceItemRepo.save(item);
        savedItems.add(item);
      }

      for (final fc in _flatCharges) {
        if (!fc.isComplete) continue;
        final item = InvoiceItem(
          id: const Uuid().v4(),
          invoiceId: invoiceId,
          description: fc.description.text.trim(),
          amount: fc.value.toStringAsFixed(2),
        );
        await invoiceItemRepo.save(item);
        savedItems.add(item);
      }

      // PO becomes Invoiced only when every rate-bearing line is fully
      // delivered AND fully invoiced.
      final invoicedNow = Map<String, double>.from(_invoicedByPoItem);
      for (final line in selected) {
        invoicedNow[line.poItem.id] =
            (invoicedNow[line.poItem.id] ?? 0) + _enteredQty(line);
      }
      if (InvoiceMath.isFullyInvoiced(
        poItems: _allPoItems,
        invoicedByPoItem: invoicedNow,
      )) {
        await poRepo.update(
          _po!.copyWith(status: PurchaseOrder.statusInvoiced, updatedAt: now),
        );
      }

      await ref.read(poNotifierProvider.notifier).load();
      await ref.read(invoiceListProvider.notifier).load();

      if (!mounted) return;
      await _offerInvoiceCopies(invoice, savedItems, selected);

      if (!mounted) return;
      showSnackBar(context, 'Invoice $invoiceNumber created');
      context.pop();
    } catch (e) {
      if (!mounted) return;
      final handled = await handleConflictError(context, e);
      if (!mounted) return;
      if (handled) {
        await _load();
      } else {
        showSnackBar(context, 'Save failed: $e', isError: true);
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _offerInvoiceCopies(
    Invoice invoice,
    List<InvoiceItem> items,
    List<_InvoiceableLine> selected,
  ) async {
    final customer = ref
        .read(customersNotifierProvider)
        .customers
        .where((c) => c.id == _po!.customerId)
        .firstOrNull;
    final company = ref.read(settingsNotifierProvider).profile;

    // Delivery notes covering the invoiced PO line items.
    final dns = await ref.read(dnRepositoryProvider).loadByPoId(_po!.id);
    final dnItems = await ref.read(dnItemRepositoryProvider).loadAll();
    final invoicedPoItemIds = selected.map((l) => l.poItem.id).toSet();
    final linkedDnIds = dnItems
        .where((di) => invoicedPoItemIds.contains(di.poItemId))
        .map((di) => di.dnId)
        .toSet();
    final dnNumbers = dns
        .where((dn) => linkedDnIds.contains(dn.id))
        .map((dn) => dn.dnNumber)
        .toList();

    final copies = await InvoicePdf.generate(
      invoice: invoice,
      po: _po,
      customer: customer,
      company: company,
      deliveryNoteNumbers: dnNumbers,
      items: [
        for (final item in items)
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
  }

  static String _n(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  static String _trimPercent(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  // ── UI ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Generate Invoice')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (widget.poId == null) return _buildPoPicker();
    if (_po == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Generate Invoice')),
        body: const EmptyState(
          icon: Icons.error_outline,
          message: 'This purchase order could not be found.',
        ),
      );
    }
    return _buildForm();
  }

  Widget _buildPoPicker() {
    final customers = ref.watch(customersNotifierProvider).customers;
    final customerById = {for (final c in customers) c.id: c.name};

    return Scaffold(
      appBar: AppBar(title: const Text('Choose an order to invoice')),
      body: ResponsiveContainer(
        child: _selectablePos.isEmpty
            ? const EmptyState(
                icon: Icons.receipt_outlined,
                message:
                    'Nothing is ready to invoice yet.\n'
                    'Record a delivery first.',
              )
            : ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: _selectablePos.length,
                itemBuilder: (context, index) {
                  final po = _selectablePos[index];
                  return Card(
                    child: ListTile(
                      leading: const Icon(Icons.receipt_long),
                      title: Text(po.poNumber),
                      subtitle: Text(
                        customerById[po.customerId] ?? 'Unknown customer',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.pushReplacement(
                        '/purchase-orders/${po.id}/invoice',
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }

  Widget _buildForm() {
    final theme = Theme.of(context);
    final totals = _totals;
    final money = NumberFormat.currency(locale: 'en_IN', symbol: '₹');

    return Scaffold(
      appBar: AppBar(title: Text('Invoice · ${_po!.poNumber}')),
      body: ResponsiveContainer(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            InkWell(
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _invoiceDate,
                  firstDate: DateTime(2000),
                  lastDate: DateTime(2100),
                );
                if (picked != null) setState(() => _invoiceDate = picked);
              },
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Invoice date *',
                  suffixIcon: Icon(Icons.calendar_today, size: 18),
                ),
                child: Text(DateFormat.yMMMd().format(_invoiceDate)),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _transportController,
              decoration: const InputDecoration(
                labelText: 'Transportation Mode',
              ),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _vehicleController,
              decoration: const InputDecoration(labelText: 'Vehicle Number'),
              textInputAction: TextInputAction.next,
            ),

            const SizedBox(height: 24),
            Text(
              'Delivered & not yet invoiced',
              style: theme.textTheme.titleMedium,
            ),
            Text(
              'Leave a line blank to bill it on a later invoice.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
            const SizedBox(height: 12),
            if (_lines.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: EmptyState(
                  icon: Icons.inbox_outlined,
                  message: 'Nothing left to invoice on this order',
                ),
              )
            else
              ..._lines.map(_lineCard),

            const SizedBox(height: 8),
            Text('Additional charges', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
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
                          controller: fc.description,
                          decoration: const InputDecoration(
                            labelText: 'Charge description',
                            isDense: true,
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 110,
                        child: TextField(
                          controller: fc.amount,
                          decoration: const InputDecoration(
                            labelText: 'Amount',
                            isDense: true,
                          ),
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                      IconButton(
                        icon: Icon(
                          Icons.remove_circle_outline,
                          color: theme.colorScheme.error,
                        ),
                        tooltip: 'Remove charge',
                        onPressed: () {
                          fc.dispose();
                          setState(() => _flatCharges.removeAt(i));
                        },
                      ),
                    ],
                  ),
                ),
              );
            }),
            TextButton.icon(
              onPressed: () => setState(() => _flatCharges.add(_FlatCharge())),
              icon: const Icon(Icons.add),
              label: const Text('Add flat charge (no qty/rate)'),
            ),

            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Tax', style: theme.textTheme.titleSmall),
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _cgstController,
                            decoration: InputDecoration(
                              labelText: 'CGST %',
                              suffixText: '%',
                              isDense: true,
                              errorText: _percentError(_cgstController),
                            ),
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: TextField(
                            controller: _sgstController,
                            decoration: InputDecoration(
                              labelText: 'SGST %',
                              suffixText: '%',
                              isDense: true,
                              errorText: _percentError(_sgstController),
                            ),
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _summaryRow('Subtotal', money.format(totals.subtotal)),
                    _summaryRow(
                      'CGST (${_trimPercent(totals.cgstPercent)}%)',
                      money.format(totals.cgstAmount),
                    ),
                    _summaryRow(
                      'SGST (${_trimPercent(totals.sgstPercent)}%)',
                      money.format(totals.sgstAmount),
                    ),
                    const Divider(),
                    _summaryRow(
                      'Grand Total',
                      money.format(totals.total),
                      bold: true,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      NumberToWords.convert(totals.total),
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),
            FilledButton(
              onPressed: _isValid && !_isSaving ? _save : null,
              child: _isSaving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Create Invoice'),
            ),
            if (!_isValid && !_isSaving)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Enter a quantity for at least one line, or add a flat charge.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: theme.colorScheme.error,
                    fontSize: 12,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _lineCard(_InvoiceableLine line) {
    final theme = Theme.of(context);
    final unit = line.product?.unit ?? '';
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              line.product?.name ?? 'Unknown',
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 2),
            Text(
              'Invoiceable ${_n(line.invoiceableQty)} $unit  •  '
              'Rate ${line.poItem.rate}'
              '${line.product?.hsnSac.isNotEmpty == true ? '  •  HSN/SAC ${line.product!.hsnSac}' : ''}',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: _qtyControllers[line.poItem.id],
                    decoration: InputDecoration(
                      labelText: 'Qty to bill',
                      isDense: true,
                      errorText: _qtyError(line),
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _remarkControllers[line.poItem.id],
                    decoration: const InputDecoration(
                      labelText: 'Remarks',
                      isDense: true,
                    ),
                  ),
                ),
              ],
            ),
            if (_enteredQty(line) > 0)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'Line amount: '
                  '${InvoiceMath.lineAmount(_enteredQty(line), line.poItem.rt).toStringAsFixed(2)}',
                  style: theme.textTheme.bodySmall,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _summaryRow(String label, String value, {bool bold = false}) {
    final style = TextStyle(
      fontWeight: bold ? FontWeight.bold : FontWeight.normal,
      fontSize: bold ? 16 : 14,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: style),
          Text(value, style: style),
        ],
      ),
    );
  }
}
