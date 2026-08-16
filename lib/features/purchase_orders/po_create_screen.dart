import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import '../../core/widgets/responsive_container.dart';
import '../../core/widgets/snack_bar_helper.dart';
import '../customers/customers_notifier.dart';
import '../products/models/product.dart';
import '../products/products_notifier.dart';
import 'models/purchase_order.dart';
import 'po_providers.dart';

class _LineItem {
  String productId;
  String quantity;
  String rate;
  String remarks;

  _LineItem({
    required this.productId,
    required this.quantity,
    required this.rate,
    this.remarks = '',
  });

  double get qty => double.tryParse(quantity) ?? 0;
  double get rt => double.tryParse(rate) ?? 0;
  double get lineTotal => qty * rt;
}

class PoCreateScreen extends ConsumerStatefulWidget {
  const PoCreateScreen({super.key});

  @override
  ConsumerState<PoCreateScreen> createState() => _PoCreateScreenState();
}

class _PoCreateScreenState extends ConsumerState<PoCreateScreen> {
  String? _customerId;
  DateTime _orderDate = DateTime.now();

  final _clientPoNumberController = TextEditingController();
  DateTime? _clientPoDate;
  final _clientDnNumberController = TextEditingController();
  DateTime? _clientDnDate;

  final List<_LineItem> _items = [];
  bool _isSaving = false;

  // Inline add-item form.
  String? _newProductId;
  final _newQtyController = TextEditingController();
  final _newRateController = TextEditingController();
  final _newRemarksController = TextEditingController();
  final _productFocusNode = FocusNode();
  final _qtyFocusNode = FocusNode();
  bool _formExpanded = true;
  int? _editingIndex;

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(customersNotifierProvider.notifier).load();
      ref.read(productsNotifierProvider.notifier).load();
    });
  }

  @override
  void dispose() {
    _clientPoNumberController.dispose();
    _clientDnNumberController.dispose();
    _newQtyController.dispose();
    _newRateController.dispose();
    _newRemarksController.dispose();
    _productFocusNode.dispose();
    _qtyFocusNode.dispose();
    super.dispose();
  }

  double get _total => _items.fold(0.0, (s, i) => s + i.lineTotal);

  // ── Line-item entry ───────────────────────────────────────────────────────

  String? get _qtyError {
    final raw = _newQtyController.text.trim();
    if (raw.isEmpty) return null;
    final v = double.tryParse(raw);
    if (v == null) return 'Enter a number';
    if (v <= 0) return 'Quantity must be greater than 0';
    return null;
  }

  /// Rate may legitimately be ₹0 (Labour job-work) — only negatives and
  /// non-numbers are rejected.
  String? get _rateError {
    final raw = _newRateController.text.trim();
    if (raw.isEmpty) return null;
    final v = double.tryParse(raw);
    if (v == null) return 'Enter a number';
    if (v < 0) return 'Rate cannot be negative';
    return null;
  }

  bool get _canAddItem =>
      _newProductId != null &&
      _newQtyController.text.trim().isNotEmpty &&
      _newRateController.text.trim().isNotEmpty &&
      _qtyError == null &&
      _rateError == null;

  void _addOrUpdateItem() {
    if (!_canAddItem) return;
    final item = _LineItem(
      productId: _newProductId!,
      quantity: _newQtyController.text.trim(),
      rate: _newRateController.text.trim(),
      remarks: _newRemarksController.text.trim(),
    );
    setState(() {
      if (_editingIndex != null) {
        _items[_editingIndex!] = item;
        _editingIndex = null;
      } else {
        _items.add(item);
      }
      _newProductId = null;
      _newQtyController.clear();
      _newRateController.clear();
      _newRemarksController.clear();
    });
    // Stay open, focused on the next Product field (AGENTS.md §7).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _productFocusNode.requestFocus();
    });
  }

  void _removeItem(int index) => setState(() {
    _items.removeAt(index);
    // Any removal invalidates a pending edit's index, so cancel the edit
    // rather than let "Update item" overwrite the wrong row.
    if (_editingIndex != null) {
      _editingIndex = null;
      _newProductId = null;
      _newQtyController.clear();
      _newRateController.clear();
      _newRemarksController.clear();
    }
  });

  void _editItem(int index) {
    final item = _items[index];
    setState(() {
      _editingIndex = index;
      _newProductId = item.productId;
      _newQtyController.text = item.quantity;
      _newRateController.text = item.rate;
      _newRemarksController.text = item.remarks;
      _formExpanded = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _productFocusNode.requestFocus();
    });
  }

  // ── Save ──────────────────────────────────────────────────────────────────

  bool get _isValid => _customerId != null && _items.isNotEmpty && !_isSaving;

  /// The PO prefix follows the line items' product category. AGENTS.md §4 says
  /// not to assume a rule for a mixed Sales+Labour PO, so we ask instead.
  Future<String?> _resolveCategory(List<Product> products) async {
    final byId = {for (final p in products) p.id: p};
    final categories = _items
        .map((i) => byId[i.productId]?.category ?? '')
        .where((c) => c.isNotEmpty)
        .toSet();

    if (categories.length == 1) return categories.first;
    if (categories.isEmpty) return Product.categorySales;

    if (!mounted) return null;
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Mixed item categories'),
        content: const Text(
          'This order contains both Sales and Labour items. Which sequence '
          'should the PO number use?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(Product.categoryLabour),
            child: const Text('Labour (L)'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(Product.categorySales),
            child: const Text('Sales (S)'),
          ),
        ],
      ),
    );
  }

  Future<void> _review() async {
    final products = ref.read(productsNotifierProvider).products;
    final byId = {for (final p in products) p.id: p};
    final customer = ref
        .read(customersNotifierProvider)
        .customers
        .where((c) => c.id == _customerId)
        .firstOrNull;

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Review order', style: theme.textTheme.titleLarge),
                const SizedBox(height: 8),
                Text('Customer: ${customer?.name ?? "—"}'),
                Text('Order date: ${DateFormat.yMMMd().format(_orderDate)}'),
                if (_clientPoNumberController.text.trim().isNotEmpty)
                  Text('Client PO: ${_clientPoNumberController.text.trim()}'),
                if (_clientDnNumberController.text.trim().isNotEmpty)
                  Text('Client DC: ${_clientDnNumberController.text.trim()}'),
                const Divider(height: 24),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final item in _items)
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(byId[item.productId]?.name ?? 'Unknown'),
                          subtitle: Text(
                            '${item.quantity} × ${item.rate}'
                            '${item.remarks.isEmpty ? '' : '  •  ${item.remarks}'}',
                          ),
                          trailing: Text(item.lineTotal.toStringAsFixed(2)),
                        ),
                    ],
                  ),
                ),
                const Divider(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Order total', style: theme.textTheme.titleMedium),
                    Text(
                      _total.toStringAsFixed(2),
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(sheetContext).pop(false),
                        child: const Text('Back to edit'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: () => Navigator.of(sheetContext).pop(true),
                        child: const Text('Create PO'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );

    if (confirmed == true) await _save();
  }

  Future<void> _save() async {
    if (!_isValid) return;
    final products = ref.read(productsNotifierProvider).products;
    final category = await _resolveCategory(products);
    if (category == null || !mounted) return;

    setState(() => _isSaving = true);
    try {
      final now = DateTime.now().toIso8601String();
      final counter = ref.read(counterHelperProvider);
      final poRepo = ref.read(poRepositoryProvider);
      final itemRepo = ref.read(poItemRepositoryProvider);

      final poId = const Uuid().v4();
      // The number is drawn as part of this same save, so a failed record save
      // never burns a number without a record (AGENTS.md §5).
      final poNumber = await counter.nextPoNumber(
        category: category,
        orderDate: _orderDate,
      );

      await poRepo.save(
        PurchaseOrder(
          id: poId,
          poNumber: poNumber,
          customerId: _customerId!,
          orderDate: _orderDate.toIso8601String(),
          clientPoNumber: _clientPoNumberController.text.trim(),
          clientPoDate: _clientPoDate?.toIso8601String() ?? '',
          clientDeliveryNoteNumber: _clientDnNumberController.text.trim(),
          clientDeliveryNoteDate: _clientDnDate?.toIso8601String() ?? '',
          status: PurchaseOrder.statusPending,
          createdAt: now,
          updatedAt: now,
        ),
      );

      for (final item in _items) {
        final qty = item.qty;
        await itemRepo.save(
          PurchaseOrderItem(
            id: const Uuid().v4(),
            poId: poId,
            productId: item.productId,
            quantity: _trimNum(qty),
            // Rate snapshotted here; never re-linked to the product master.
            rate: _trimNum(item.rt),
            deliveredQty: '0',
            pendingQty: _trimNum(qty),
            remarks: item.remarks,
            updatedAt: now,
          ),
        );
      }

      await ref.read(poNotifierProvider.notifier).load();

      if (mounted) {
        showSnackBar(context, 'PO $poNumber created');
        // Replace so backing out of the new PO returns to the PO list, not to
        // a half-filled create form.
        context.pushReplacement('/purchase-orders/$poId');
      }
    } catch (e) {
      if (mounted) showSnackBar(context, 'Save failed: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  static String _trimNum(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  // ── UI ────────────────────────────────────────────────────────────────────

  Future<void> _pickDate({
    required DateTime? initial,
    required ValueChanged<DateTime> onPicked,
  }) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: initial ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) onPicked(picked);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final customers = ref.watch(customersNotifierProvider).customers;
    final products = ref.watch(productsNotifierProvider).products;
    final productById = {for (final p in products) p.id: p};

    return Scaffold(
      appBar: AppBar(title: const Text('New Purchase Order')),
      body: ResponsiveContainer(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            DropdownButtonFormField<String>(
              initialValue: _customerId,
              decoration: const InputDecoration(labelText: 'Customer *'),
              isExpanded: true,
              items: customers
                  .map(
                    (c) => DropdownMenuItem(
                      value: c.id,
                      child: Text(c.name, overflow: TextOverflow.ellipsis),
                    ),
                  )
                  .toList(),
              onChanged: (v) => setState(() => _customerId = v),
            ),
            if (_customerId == null)
              Padding(
                padding: const EdgeInsets.only(top: 6, left: 12),
                child: Text(
                  'Select a customer to continue',
                  style: TextStyle(
                    color: theme.colorScheme.error,
                    fontSize: 12,
                  ),
                ),
              ),
            const SizedBox(height: 16),
            _dateField(
              label: 'Order date *',
              value: _orderDate,
              onTap: () => _pickDate(
                initial: _orderDate,
                onPicked: (d) => setState(() => _orderDate = d),
              ),
            ),

            const SizedBox(height: 24),
            Text("Client's references", style: theme.textTheme.titleSmall),
            Text(
              "The client's own PO and delivery-challan numbers, if they gave "
              'you any. Optional.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _clientPoNumberController,
              decoration: const InputDecoration(
                labelText: "Client's PO number",
              ),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            _dateField(
              label: "Client's PO date",
              value: _clientPoDate,
              onTap: () => _pickDate(
                initial: _clientPoDate,
                onPicked: (d) => setState(() => _clientPoDate = d),
              ),
              onClear: _clientPoDate == null
                  ? null
                  : () => setState(() => _clientPoDate = null),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _clientDnNumberController,
              decoration: const InputDecoration(
                labelText: "Client's delivery challan number",
                helperText: 'For material they sent you to process',
              ),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            _dateField(
              label: "Client's delivery challan date",
              value: _clientDnDate,
              onTap: () => _pickDate(
                initial: _clientDnDate,
                onPicked: (d) => setState(() => _clientDnDate = d),
              ),
              onClear: _clientDnDate == null
                  ? null
                  : () => setState(() => _clientDnDate = null),
            ),

            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Line items (${_items.length})',
                  style: theme.textTheme.titleMedium,
                ),
                TextButton(
                  onPressed: () =>
                      setState(() => _formExpanded = !_formExpanded),
                  child: Text(_formExpanded ? 'Hide form' : 'Add item'),
                ),
              ],
            ),
            if (_items.isEmpty && !_formExpanded)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text(
                    'No items yet. Tap "Add item" to start.',
                    style: TextStyle(color: theme.colorScheme.outline),
                  ),
                ),
              ),
            ...List.generate(_items.length, (i) {
              final item = _items[i];
              final product = productById[item.productId];
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  title: Text(product?.name ?? 'Unknown'),
                  subtitle: Text(
                    'Qty: ${item.quantity} ${product?.unit ?? ''}  •  '
                    'Rate: ${item.rate}  •  '
                    'Total: ${item.lineTotal.toStringAsFixed(2)}'
                    '${item.remarks.isEmpty ? '' : '\n${item.remarks}'}',
                  ),
                  isThreeLine: item.remarks.isNotEmpty,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit, size: 20),
                        tooltip: 'Edit item',
                        onPressed: () => _editItem(i),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, size: 20),
                        tooltip: 'Remove item',
                        onPressed: () => _removeItem(i),
                      ),
                    ],
                  ),
                ),
              );
            }),

            if (_formExpanded) ...[
              const SizedBox(height: 8),
              Card(
                color: theme.colorScheme.surfaceContainerHighest,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        _editingIndex != null
                            ? 'Edit item ${_editingIndex! + 1}'
                            : (_items.isEmpty
                                  ? 'Add first item'
                                  : 'Add another item'),
                        style: theme.textTheme.titleSmall,
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: _newProductId,
                        decoration: const InputDecoration(
                          labelText: 'Product *',
                        ),
                        focusNode: _productFocusNode,
                        isExpanded: true,
                        items: products
                            .map(
                              (p) => DropdownMenuItem(
                                value: p.id,
                                child: Text(
                                  '${p.name}${p.partNo.isEmpty ? '' : ' (${p.partNo})'}',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (productId) {
                          setState(() => _newProductId = productId);
                          if (productId == null) return;
                          final product = productById[productId];
                          if (product != null) {
                            // Pre-fill from the product master, still editable.
                            _newRateController.text = product.price;
                          }
                          _qtyFocusNode.requestFocus();
                        },
                      ),
                      const SizedBox(height: 12),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _newQtyController,
                              decoration: InputDecoration(
                                labelText: 'Quantity *',
                                errorText: _qtyError,
                              ),
                              focusNode: _qtyFocusNode,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              textInputAction: TextInputAction.next,
                              onChanged: (_) => setState(() {}),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: _newRateController,
                              decoration: InputDecoration(
                                labelText: 'Rate *',
                                errorText: _rateError,
                              ),
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              textInputAction: TextInputAction.next,
                              onChanged: (_) => setState(() {}),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _newRemarksController,
                        decoration: const InputDecoration(
                          labelText: 'Remarks (optional)',
                        ),
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _addOrUpdateItem(),
                      ),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: _canAddItem ? _addOrUpdateItem : null,
                        child: Text(
                          _editingIndex != null
                              ? 'Update item'
                              : 'Add & continue',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],

            if (_items.isNotEmpty) ...[
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Order total',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    _total.toStringAsFixed(2),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ],

            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _isValid ? _review : null,
              icon: _isSaving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.fact_check_outlined),
              label: const Text('Review & create'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dateField({
    required String label,
    required DateTime? value,
    required VoidCallback onTap,
    VoidCallback? onClear,
  }) {
    return InkWell(
      onTap: onTap,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          suffixIcon: onClear != null
              ? IconButton(
                  icon: const Icon(Icons.clear, size: 18),
                  onPressed: onClear,
                  tooltip: 'Clear',
                )
              : const Icon(Icons.calendar_today, size: 18),
        ),
        child: Text(
          value != null ? DateFormat.yMMMd().format(value) : 'Not set',
        ),
      ),
    );
  }
}
