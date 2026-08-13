import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';
import '../../core/services/counter_helper.dart';
import '../../core/widgets/snack_bar_helper.dart';
import '../../features/customers/customers_notifier.dart';
import '../../features/products/products_notifier.dart';
import 'models/purchase_order.dart';
import 'po_providers.dart';

// ─── Line-item form model ────────────────────────────────────────────────────

class _LineItem {
  String productId;
  String quantity;
  String rate;

  _LineItem({required this.productId, required this.quantity, required this.rate});

  double get qty => double.tryParse(quantity) ?? 0;
  double get rt  => double.tryParse(rate) ?? 0;
  double get lineTotal => qty * rt;
}

// ─── Screen ──────────────────────────────────────────────────────────────────

class PoCreateScreen extends ConsumerStatefulWidget {
  const PoCreateScreen({super.key});

  @override
  ConsumerState<PoCreateScreen> createState() => _PoCreateScreenState();
}

class _PoCreateScreenState extends ConsumerState<PoCreateScreen> {
  String? _customerId;
  final List<_LineItem> _items = [];
  bool _isSaving = false;

  // Inline add-item form state
  String? _newProductId;
  final _newQtyController = TextEditingController();
  final _newRateController = TextEditingController();
  final _productFocusNode = FocusNode();
  final _qtyFocusNode = FocusNode();
  final _rateFocusNode = FocusNode();
  bool _formExpanded = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(customersNotifierProvider.notifier).load());
    Future.microtask(() => ref.read(productsNotifierProvider.notifier).load());
  }

  @override
  void dispose() {
    _newQtyController.dispose();
    _newRateController.dispose();
    _productFocusNode.dispose();
    _qtyFocusNode.dispose();
    _rateFocusNode.dispose();
    super.dispose();
  }

  double get _total => _items.fold(0.0, (s, i) => s + i.lineTotal);

  void _clearNewItemForm() {
    setState(() {
      _newProductId = null;
      _newQtyController.text = '';
      _newRateController.text = '';
    });
  }

  void _addItem() {
    if (_newProductId == null) return;
    final qty = _newQtyController.text.trim();
    final rate = _newRateController.text.trim();
    if (qty.isEmpty || rate.isEmpty) return;

    setState(() {
      _items.add(_LineItem(
        productId: _newProductId!,
        quantity: qty,
        rate: rate,
      ));
    });

    _clearNewItemForm();
    // Keep form open, refocus product field for next item
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _productFocusNode.requestFocus();
    });
  }

  void _removeItem(int index) => setState(() => _items.removeAt(index));

  void _editItem(int index) {
    final item = _items[index];
    setState(() {
      _newProductId = item.productId;
      _newQtyController.text = item.quantity;
      _newRateController.text = item.rate;
      _items.removeAt(index);
      _formExpanded = true;
      _productFocusNode.requestFocus();
    });
  }

  bool get _isValid => _customerId != null && _items.isNotEmpty && !_isSaving;

  Future<void> _save() async {
    if (!_isValid) return;
    setState(() => _isSaving = true);
    try {
      final now = DateTime.now().toIso8601String();
      final counter = ref.read(counterHelperProvider);
      final poRepo = ref.read(poRepositoryProvider);
      final itemRepo = ref.read(poItemRepositoryProvider);

      final poId = const Uuid().v4();
      final poNumber = await counter.nextNumber('PurchaseOrder', fiscalYear: CounterHelper.currentFiscalYear());

      final po = PurchaseOrder(
        id: poId,
        poNumber: poNumber,
        customerId: _customerId!,
        orderDate: now,
        status: 'Pending',
        createdAt: now,
        updatedAt: now,
      );
      await poRepo.save(po);

      for (final item in _items) {
        final qty = item.qty.toInt().toString();
        await itemRepo.save(PurchaseOrderItem(
          id: const Uuid().v4(),
          poId: poId,
          productId: item.productId,
          quantity: qty,
          rate: item.rt.toString(),
          deliveredQty: '0',
          pendingQty: qty,
          updatedAt: now,
        ));
      }

      ref.read(poNotifierProvider.notifier).addLocal(po);

      if (mounted) {
        showSnackBar(context, 'PO $poNumber created');
        context.push('/purchase-orders/$poId');
      }
    } catch (e) {
      if (mounted) showSnackBar(context, 'Save failed: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final customers = ref.watch(customersNotifierProvider).customers;
    final products = ref.watch(productsNotifierProvider).products;
    final productMap = {for (final p in products) p.id: p.name};

    return Scaffold(
      appBar: AppBar(title: const Text('New Purchase Order')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Customer picker ──
          DropdownButtonFormField<String>(
            initialValue: _customerId,
            decoration: const InputDecoration(labelText: 'Customer *'),
            items: customers.map((c) => DropdownMenuItem(value: c.id, child: Text(c.name))).toList(),
            onChanged: (v) => setState(() => _customerId = v),
          ),
          const SizedBox(height: 24),

          // ── Added items running list ──
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Line items (${_items.length})', style: theme.textTheme.titleMedium),
              if (_items.isNotEmpty)
                TextButton(
                  onPressed: () => setState(() => _formExpanded = !_formExpanded),
                  child: Text(_formExpanded ? 'Hide form' : 'Add another'),
                ),
            ],
          ),
          if (_items.isEmpty && !_formExpanded)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  'No items yet. Tap "Add another" to start.',
                  style: TextStyle(color: theme.colorScheme.outline),
                ),
              ),
            )
          else if (_items.isNotEmpty)
            ...List.generate(_items.length, (i) {
              final item = _items[i];
              final productName = productMap[item.productId] ?? 'Unknown';
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  title: Text(productName),
                  subtitle: Text(
                    'Qty: ${item.quantity}  •  Rate: ${item.rate}  •  Total: ${item.lineTotal.toStringAsFixed(2)}',
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit, size: 20),
                        onPressed: () => _editItem(i),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, size: 20),
                        onPressed: () => _removeItem(i),
                      ),
                    ],
                  ),
                ),
              );
            }),

          // ── Inline add-item form ──
          if (_formExpanded || _items.isEmpty) ...[
            const SizedBox(height: 16),
            Card(
              color: theme.colorScheme.surfaceContainerHighest,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      _items.isEmpty ? 'Add first item' : 'Add another item',
                      style: theme.textTheme.titleSmall,
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: _newProductId,
                      decoration: const InputDecoration(labelText: 'Product *'),
                      focusNode: _productFocusNode,
                      items: products
                          .map((p) => DropdownMenuItem(value: p.id, child: Text(p.name)))
                          .toList(),
                      onChanged: (productId) {
                        setState(() => _newProductId = productId);
                        if (productId != null) {
                          final product = products.where((p) => p.id == productId).firstOrNull;
                          if (product != null) {
                            final price = double.tryParse(product.price);
                            if (price != null && price > 0) {
                              _newRateController.text = price.toString();
                            }
                          }
                          _qtyFocusNode.requestFocus();
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _newQtyController,
                            decoration: const InputDecoration(labelText: 'Quantity *'),
                            focusNode: _qtyFocusNode,
                            keyboardType: TextInputType.number,
                            textInputAction: TextInputAction.next,
                            onChanged: (_) => setState(() {}),
                            onSubmitted: (_) => _rateFocusNode.requestFocus(),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: _newRateController,
                            decoration: const InputDecoration(labelText: 'Rate *'),
                            focusNode: _rateFocusNode,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            textInputAction: TextInputAction.done,
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: (_newProductId != null &&
                              (double.tryParse(_newQtyController.text.trim()) ?? 0) > 0 &&
                              (double.tryParse(_newRateController.text.trim()) ?? 0) > 0)
                          ? _addItem
                          : null,
                      child: const Text('Add & Continue'),
                    ),
                  ],
                ),
              ),
            ),
          ],

          // ── Totals ──
          if (_items.isNotEmpty) ...[
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Total', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                Text(
                  _total.toStringAsFixed(2),
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ],

          // ── Save ──
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _isValid ? _save : null,
            child: _isSaving
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Create PO'),
          ),
        ],
      ),
    );
  }
}
