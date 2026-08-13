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
import '../../features/settings/settings_notifier.dart';
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
  bool _isSaving = false;
  PurchaseOrder? _po;
  List<PurchaseOrderItem> _poItems = [];

  @override
  void initState() {
    super.initState();
    _loadPoItems();
  }

  Future<void> _loadPoItems() async {
    final po = await ref.read(poNotifierProvider.notifier).findById(widget.poId);
    final itemRepo = ref.read(poItemRepositoryProvider);
    final items = await itemRepo.loadByPoId(widget.poId);
    final pendingItems = items.where((i) => (double.tryParse(i.pendingQty) ?? 0) > 0).toList();

    for (final item in pendingItems) {
      _qtyControllers[item.id] = TextEditingController();
      _remarkControllers[item.id] = TextEditingController();
    }

    if (mounted) {
      setState(() {
        _po = po;
        _poItems = pendingItems;
      });
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
    super.dispose();
  }

  String? _validateQty(String? value, PurchaseOrderItem poItem) {
    if (value == null || value.trim().isEmpty) return 'Required';
    final entered = double.tryParse(value.trim());
    if (entered == null || entered <= 0) return 'Must be > 0';
    final pending = double.tryParse(poItem.pendingQty) ?? 0;
    if (entered > pending) return 'Max ${pending.toInt()}';
    return null;
  }

  bool get _isValid {
    for (final item in _poItems) {
      final controller = _qtyControllers[item.id];
      if (controller == null) return false;
      final entered = double.tryParse(controller.text.trim()) ?? 0;
      final pending = double.tryParse(item.pendingQty) ?? 0;
      if (entered <= 0 || entered > pending) return false;
    }
    return true;
  }

  Future<void> _save() async {
    if (!_isValid || _isSaving) return;
    setState(() => _isSaving = true);
    try {
      final now = DateTime.now().toIso8601String();
      final counter = ref.read(counterHelperProvider);
      final dnRepo = ref.read(dnRepositoryProvider);
      final dnItemRepo = ref.read(dnItemRepositoryProvider);
      final poRepo = ref.read(poRepositoryProvider);
      final itemRepo = ref.read(poItemRepositoryProvider);

      final dnId = const Uuid().v4();
      final dnNumber = await counter.nextNumber('DeliveryNote');

      await dnRepo.save(DeliveryNote(
        id: dnId,
        dnNumber: dnNumber,
        poId: widget.poId,
        deliveryDate: now,
        createdAt: now,
      ));

      for (final item in _poItems) {
        final controller = _qtyControllers[item.id]!;
        final remarkController = _remarkControllers[item.id]!;
        final enteredQty = double.tryParse(controller.text.trim()) ?? 0;
        final currentDelivered = double.tryParse(item.deliveredQty) ?? 0;
        final pendingQty = double.tryParse(item.pendingQty) ?? 0;

        await dnItemRepo.save(DeliveryNoteItem(
          id: const Uuid().v4(),
          dnId: dnId,
          poItemId: item.id,
          deliveredQty: enteredQty.toInt().toString(),
          remark: remarkController.text.trim(),
        ));

        final newDelivered = currentDelivered + enteredQty;
        final newPending = pendingQty - enteredQty;

        await itemRepo.update(item.copyWith(
          deliveredQty: newDelivered.toInt().toString(),
          pendingQty: newPending.toInt().toString(),
          updatedAt: now,
        ));
      }

      // Recalculate PO status
      if (_po != null) {
        final allItems = await itemRepo.loadByPoId(widget.poId);
        final anyPending = allItems.any((i) => (double.tryParse(i.pendingQty) ?? 0) > 0);
        final anyDelivered = allItems.any((i) => (double.tryParse(i.deliveredQty) ?? 0) > 0);

        String newStatus;
        if (!anyPending) {
          newStatus = 'Delivered';
        } else if (anyDelivered) {
          newStatus = 'Partially Delivered';
        } else {
          newStatus = _po!.status;
        }

        await poRepo.update(_po!.copyWith(status: newStatus, updatedAt: now));
      }

      ref.read(poNotifierProvider.notifier).load();
      ref.read(dnListProvider.notifier).load();

      // Generate and show PDF
      final customers = ref.read(customersNotifierProvider).customers;
      final products = ref.read(productsNotifierProvider).products;
      final productMap = {for (final p in products) p.id: p.name};
      final customerName = customers
          .where((c) => c.id == _po!.customerId)
          .map((c) => c.name)
          .firstOrNull ?? 'Unknown';
      final companyProfile = ref.read(settingsNotifierProvider).profile;

      final unitMap = {for (final p in products) p.id: p.unit};
      final pdfItems = _poItems.map((item) {
        final controller = _qtyControllers[item.id]!;
        final remarkController = _remarkControllers[item.id]!;
        final enteredQty = double.tryParse(controller.text.trim()) ?? 0;
        final currentDelivered = double.tryParse(item.deliveredQty) ?? 0;
        return {
          'productName': productMap[item.productId] ?? 'Unknown',
          'orderedQty': item.quantity,
          'deliveredNow': enteredQty.toInt().toString(),
          'totalDelivered': (currentDelivered + enteredQty).toInt().toString(),
          'remark': remarkController.text.trim(),
          'unit': unitMap[item.productId] ?? '',
        };
      }).toList();

      final customer = customers
          .where((c) => c.id == _po!.customerId)
          .firstOrNull;
      final customerAddress = customer?.address ?? '';
      final customerGst = customer?.gstNumber ?? '';
      final customerTin = customer?.tinNumber ?? '';
      final customerCst = customer?.cstNumber ?? '';

      final pdf = await DeliveryNotePdf.generate(
        dnNumber: dnNumber,
        poNumber: _po!.poNumber,
        deliveryDate: now,
        customerName: customerName,
        customerAddress: customerAddress,
        customerGst: customerGst,
        customerTin: customerTin,
        customerCst: customerCst,
        orderDate: _po!.orderDate,
        items: pdfItems,
        companyName: companyProfile?.companyName,
        companyAddress: companyProfile?.address,
        companyPhone: companyProfile?.phone,
        companyGst: companyProfile?.gstNumber,
      );

      if (mounted) {
        final pdfBytes = await pdf.save();
        if (!mounted) return;
        await Printing.layoutPdf(
          onLayout: (format) async => pdfBytes,
          name: 'Delivery Note $dnNumber',
        );
        if (!mounted) return;
        showSnackBar(context, 'Delivery $dnNumber recorded');
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

  @override
  Widget build(BuildContext context) {
    final products = ref.watch(productsNotifierProvider).products;
    final productMap = {for (final p in products) p.id: p.name};

    return Scaffold(
      appBar: AppBar(title: const Text('Record Delivery')),
      body: _po == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  'PO: ${_po!.poNumber}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 16),
                Text(
                  'Enter delivered quantities (pending items only)',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.outline,
                      ),
                ),
                const SizedBox(height: 16),
                ..._poItems.map((item) {
                  final productName = productMap[item.productId] ?? 'Unknown';
                  final pending = double.tryParse(item.pendingQty) ?? 0;
                  final controller = _qtyControllers[item.id];
                  final remarkController = _remarkControllers[item.id];
                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(productName, style: Theme.of(context).textTheme.titleSmall),
                          const SizedBox(height: 4),
                          Text(
                            'Pending: ${pending.toInt()}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: controller,
                            decoration: InputDecoration(
                              labelText: 'Delivered qty *',
                              errorText: controller != null && controller.text.isNotEmpty
                                  ? _validateQty(controller.text, item)
                                  : null,
                            ),
                            keyboardType: TextInputType.number,
                            onChanged: (_) => setState(() {}),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: remarkController,
                            decoration: const InputDecoration(labelText: 'Remarks (optional)'),
                            textInputAction: TextInputAction.next,
                          ),
                        ],
                      ),
                    ),
                  );
                }),
                if (_poItems.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 32),
                    child: EmptyState(
                      icon: Icons.local_shipping_outlined,
                      message: 'No pending items to deliver',
                    ),
                  ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _isValid && !_isSaving ? _save : null,
                  child: _isSaving
                      ? const SizedBox(
                          width: 20, height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Save & Generate DN'),
                ),
              ],
            ),
    );
  }
}
