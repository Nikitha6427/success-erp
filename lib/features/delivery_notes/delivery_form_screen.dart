import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import '../../core/services/invoice_math.dart';
import '../../core/widgets/document_copies_sheet.dart';
import '../../core/widgets/snack_bar_helper.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/conflict_dialog.dart';
import '../customers/customers_notifier.dart';
import '../products/products_notifier.dart';
import '../purchase_orders/po_providers.dart';
import '../purchase_orders/models/purchase_order.dart';
import '../settings/settings_notifier.dart';
import 'models/delivery_note.dart';
import 'dn_providers.dart';
import 'dn_pdf.dart';

class DeliveryFormScreen extends ConsumerStatefulWidget {
  final String poId;

  const DeliveryFormScreen({required this.poId, super.key});

  @override
  ConsumerState<DeliveryFormScreen> createState() => _DeliveryFormScreenState();
}

class _DeliveryFormScreenState extends ConsumerState<DeliveryFormScreen> {
  final Map<String, TextEditingController> _qtyControllers = {};
  final Map<String, TextEditingController> _remarkControllers = {};
  final _transportController = TextEditingController();
  final _vehicleController = TextEditingController();

  DateTime _deliveryDate = DateTime.now();
  bool _isSaving = false;
  bool _loading = true;
  PurchaseOrder? _po;
  List<PurchaseOrderItem> _pendingItems = [];

  @override
  void initState() {
    super.initState();
    // Deferred out of the build phase: notifier.load() mutates provider state
    // synchronously, which Riverpod forbids during initState/build.
    Future.microtask(_loadPoItems);
  }

  Future<void> _loadPoItems() async {
    try {
      final po = await ref.read(poNotifierProvider.notifier).findById(widget.poId);
      final items =
          await ref.read(poItemRepositoryProvider).loadByPoId(widget.poId);
      final pending = items.where((i) => i.pending > 0).toList();

      for (final item in pending) {
        _qtyControllers.putIfAbsent(item.id, () => TextEditingController());
        _remarkControllers.putIfAbsent(item.id, () => TextEditingController());
      }

      if (ref.read(productsNotifierProvider).products.isEmpty) {
        await ref.read(productsNotifierProvider.notifier).load();
      }
      if (ref.read(customersNotifierProvider).customers.isEmpty) {
        await ref.read(customersNotifierProvider.notifier).load();
      }
      if (ref.read(settingsNotifierProvider).profile == null) {
        await ref.read(settingsNotifierProvider.notifier).load();
      }

      if (!mounted) return;
      setState(() {
        _po = po;
        _pendingItems = pending;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      showSnackBar(context, 'Could not load this PO: $e', isError: true);
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
    _transportController.dispose();
    _vehicleController.dispose();
    super.dispose();
  }

  /// Blank means "not delivering this line in this note" — deliveries are
  /// routinely partial across items as well as across quantities.
  String? _qtyError(PurchaseOrderItem item) {
    final raw = _qtyControllers[item.id]?.text.trim() ?? '';
    if (raw.isEmpty) return null;
    final entered = double.tryParse(raw);
    if (entered == null) return 'Enter a number';
    if (entered <= 0) return 'Must be greater than 0';
    if (entered > item.pending) return 'Max ${_n(item.pending)} pending';
    return null;
  }

  double _enteredQty(PurchaseOrderItem item) =>
      double.tryParse(_qtyControllers[item.id]?.text.trim() ?? '') ?? 0;

  List<PurchaseOrderItem> get _selectedItems =>
      _pendingItems.where((i) => _enteredQty(i) > 0).toList();

  bool get _isValid =>
      _selectedItems.isNotEmpty &&
      _pendingItems.every((i) => _qtyError(i) == null);

  Future<void> _save() async {
    if (!_isValid || _isSaving) return;
    setState(() => _isSaving = true);

    final selected = _selectedItems;
    try {
      final now = DateTime.now().toIso8601String();
      final counter = ref.read(counterHelperProvider);
      final dnRepo = ref.read(dnRepositoryProvider);
      final dnItemRepo = ref.read(dnItemRepositoryProvider);
      final poRepo = ref.read(poRepositoryProvider);
      final itemRepo = ref.read(poItemRepositoryProvider);

      final dnId = const Uuid().v4();
      final dnNumber = await counter.nextSimpleNumber('DeliveryNote', 'DN');

      await dnRepo.save(DeliveryNote(
        id: dnId,
        dnNumber: dnNumber,
        poId: widget.poId,
        deliveryDate: _deliveryDate.toIso8601String(),
        transportMode: _transportController.text.trim(),
        vehicleNumber: _vehicleController.text.trim(),
        createdAt: now,
      ));

      for (final item in selected) {
        final enteredQty = _enteredQty(item);

        // This row records the quantity delivered IN THIS NOTE only.
        await dnItemRepo.save(DeliveryNoteItem(
          id: const Uuid().v4(),
          dnId: dnId,
          poItemId: item.id,
          deliveredQty: _n(enteredQty),
          remarks: _remarkControllers[item.id]?.text.trim() ?? '',
        ));

        await itemRepo.update(item.copyWith(
          deliveredQty: _n(item.delivered + enteredQty),
          pendingQty: _n(item.pending - enteredQty),
          updatedAt: now,
        ));
      }

      // Recalculate PO status from the freshly written item rows.
      if (_po != null) {
        final allItems = await itemRepo.loadByPoId(widget.poId);
        final newStatus = InvoiceMath.statusAfterDelivery(allItems);
        if (newStatus != _po!.status) {
          await poRepo.update(_po!.copyWith(status: newStatus, updatedAt: now));
        }
      }

      await ref.read(poNotifierProvider.notifier).load();
      await ref.read(dnListProvider.notifier).load();

      if (!mounted) return;

      // PDFs only after the write succeeded (AGENTS.md §5).
      await _offerDeliveryNoteCopies(dnNumber, selected);

      if (!mounted) return;
      showSnackBar(context, 'Delivery $dnNumber recorded');
      context.pop();
    } catch (e) {
      if (!mounted) return;
      final handled = await handleConflictError(context, e);
      if (!mounted) return;
      if (handled) {
        await _loadPoItems();
      } else {
        showSnackBar(context, 'Save failed: $e', isError: true);
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _offerDeliveryNoteCopies(
    String dnNumber,
    List<PurchaseOrderItem> selected,
  ) async {
    final products = ref.read(productsNotifierProvider).products;
    final productById = {for (final p in products) p.id: p};
    final customer = ref
        .read(customersNotifierProvider)
        .customers
        .where((c) => c.id == _po!.customerId)
        .firstOrNull;
    final company = ref.read(settingsNotifierProvider).profile;

    final lines = selected.map((item) {
      final product = productById[item.productId];
      return DnPdfLine(
        productName: product?.name ?? 'Unknown',
        quantity: _n(_enteredQty(item)),
        unit: product?.unit ?? '',
        remarks: _remarkControllers[item.id]?.text.trim() ?? '',
      );
    }).toList();

    final copies = await DeliveryNotePdf.generate(
      dnNumber: dnNumber,
      deliveryDate: _deliveryDate.toIso8601String(),
      po: _po!,
      customer: customer,
      company: company,
      items: lines,
      transportMode: _transportController.text.trim(),
      vehicleNumber: _vehicleController.text.trim(),
    );

    if (!mounted) return;
    await showDocumentCopiesSheet(
      context,
      title: 'Delivery Note',
      documentNumber: dnNumber,
      copies: copies,
    );
  }

  static String _n(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final products = ref.watch(productsNotifierProvider).products;
    final productById = {for (final p in products) p.id: p};

    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Record Delivery')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_po == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Record Delivery')),
        body: const EmptyState(
          icon: Icons.error_outline,
          message: 'This purchase order could not be found.',
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Record Delivery')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          Text('PO: ${_po!.poNumber}', style: theme.textTheme.titleMedium),
          const SizedBox(height: 16),
          InkWell(
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _deliveryDate,
                firstDate: DateTime(2000),
                lastDate: DateTime(2100),
              );
              if (picked != null) setState(() => _deliveryDate = picked);
            },
            child: InputDecorator(
              decoration: const InputDecoration(
                labelText: 'Delivery date *',
                suffixIcon: Icon(Icons.calendar_today, size: 18),
              ),
              child: Text(DateFormat.yMMMd().format(_deliveryDate)),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _transportController,
            decoration: const InputDecoration(labelText: 'Transportation Mode'),
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _vehicleController,
            decoration: const InputDecoration(labelText: 'Vehicle Number'),
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 16),
          Text(
            'Enter quantities for the items going out in this note. Leave a '
            'line blank to keep it pending.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.outline),
          ),
          const SizedBox(height: 16),
          if (_pendingItems.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: EmptyState(
                icon: Icons.local_shipping_outlined,
                message: 'No pending items to deliver',
              ),
            )
          else
            ..._pendingItems.map((item) {
              final product = productById[item.productId];
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(product?.name ?? 'Unknown',
                          style: theme.textTheme.titleSmall),
                      const SizedBox(height: 4),
                      Text(
                        'Ordered ${_n(item.qty)}  •  '
                        'Delivered ${_n(item.delivered)}  •  '
                        'Pending ${_n(item.pending)} ${product?.unit ?? ''}',
                        style: theme.textTheme.bodySmall,
                      ),
                      if (item.remarks.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          'Order note: ${item.remarks}',
                          style: theme.textTheme.bodySmall
                              ?.copyWith(fontStyle: FontStyle.italic),
                        ),
                      ],
                      const SizedBox(height: 8),
                      TextField(
                        controller: _qtyControllers[item.id],
                        decoration: InputDecoration(
                          labelText: 'Delivering now',
                          errorText: _qtyError(item),
                        ),
                        keyboardType:
                            const TextInputType.numberWithOptions(decimal: true),
                        onChanged: (_) => setState(() {}),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _remarkControllers[item.id],
                        decoration: const InputDecoration(
                          labelText: 'Remarks (optional)',
                        ),
                        textInputAction: TextInputAction.next,
                      ),
                    ],
                  ),
                ),
              );
            }),
          if (_pendingItems.isNotEmpty && _selectedItems.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 8),
              child: Text(
                'Enter a quantity for at least one item.',
                style: TextStyle(color: theme.colorScheme.error, fontSize: 12),
              ),
            ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _isValid && !_isSaving ? _save : null,
            child: _isSaving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Save & Generate DN'),
          ),
        ],
      ),
    );
  }
}
