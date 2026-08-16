import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/widgets/snack_bar_helper.dart';
import '../../core/widgets/conflict_dialog.dart';
import 'models/product.dart';
import 'products_notifier.dart';

class ProductFormScreen extends ConsumerStatefulWidget {
  final String? id;

  const ProductFormScreen({this.id, super.key});

  @override
  ConsumerState<ProductFormScreen> createState() => _ProductFormScreenState();
}

class _ProductFormScreenState extends ConsumerState<ProductFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _partNoController = TextEditingController();
  final _priceController = TextEditingController();
  final _taxController = TextEditingController();
  final _hsnSacController = TextEditingController();
  final _otherUnitController = TextEditingController();
  String? _selectedCategory;
  String? _selectedUnit;

  bool _isSaving = false;
  Product? _existing;

  @override
  void initState() {
    super.initState();
    if (widget.id != null) {
      final found =
          ref.read(productsNotifierProvider.notifier).findById(widget.id!);
      if (found != null) {
        _fill(found);
      } else {
        Future.microtask(() async {
          await ref.read(productsNotifierProvider.notifier).load();
          if (!mounted) return;
          final p =
              ref.read(productsNotifierProvider.notifier).findById(widget.id!);
          if (p != null) setState(() => _fill(p));
        });
      }
    }
  }

  void _fill(Product p) {
    _existing = p;
    _nameController.text = p.name;
    _partNoController.text = p.partNo;
    _priceController.text = p.price;
    _taxController.text = p.taxPercent;
    _hsnSacController.text = p.hsnSac;
    _selectedCategory =
        Product.categories.contains(p.category) ? p.category : null;
    if (Product.units.contains(p.unit)) {
      _selectedUnit = p.unit;
    } else if (p.unit.isNotEmpty) {
      _selectedUnit = 'Other';
      _otherUnitController.text = p.unit;
    }
  }

  @override
  void dispose() {
    for (final c in [
      _nameController,
      _partNoController,
      _priceController,
      _taxController,
      _hsnSacController,
      _otherUnitController,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _validateName(String? value) =>
      (value == null || value.trim().isEmpty) ? 'Name is required' : null;

  /// Labour job-work lines are frequently ₹0, so zero is valid — only a
  /// missing/negative/non-numeric price is rejected.
  String? _validatePrice(String? value) {
    if (value == null || value.trim().isEmpty) return 'Price is required';
    final v = double.tryParse(value.trim());
    if (v == null) return 'Enter a valid number';
    if (v < 0) return 'Price cannot be negative';
    return null;
  }

  String? _validateTax(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final v = double.tryParse(value.trim());
    if (v == null) return 'Enter a valid number';
    if (v < 0 || v > 100) return 'Must be between 0 and 100';
    return null;
  }

  String? _validateOtherUnit(String? value) {
    if (_selectedUnit != 'Other') return null;
    if (value == null || value.trim().isEmpty) return 'Specify the unit';
    return null;
  }

  bool get _isValid =>
      _validateName(_nameController.text) == null &&
      _validatePrice(_priceController.text) == null &&
      _validateTax(_taxController.text) == null &&
      _validateOtherUnit(_otherUnitController.text) == null &&
      _selectedCategory != null;

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (!_isValid || _isSaving) return;
    setState(() => _isSaving = true);
    try {
      final now = DateTime.now().toIso8601String();
      final notifier = ref.read(productsNotifierProvider.notifier);
      final unit = _selectedUnit == 'Other'
          ? _otherUnitController.text.trim()
          : (_selectedUnit ?? '');

      final base = (_existing ?? Product(id: '', name: '', createdAt: now))
          .copyWith(
        name: _nameController.text.trim(),
        partNo: _partNoController.text.trim(),
        category: _selectedCategory!,
        unit: unit,
        price: _priceController.text.trim(),
        taxPercent: _taxController.text.trim(),
        hsnSac: _hsnSacController.text.trim(),
        updatedAt: now,
      );

      if (_existing != null) {
        await notifier.update(base);
      } else {
        await notifier.add(base);
      }
      if (mounted) {
        showSnackBar(context, 'Product saved');
        context.pop();
      }
    } catch (e) {
      if (!mounted) return;
      final handled = await handleConflictError(context, e);
      if (!mounted) return;
      if (handled) {
        await ref.read(productsNotifierProvider.notifier).load();
        if (mounted) context.pop();
      } else {
        showSnackBar(context, 'Save failed: $e', isError: true);
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete product?'),
        content: const Text(
          'This removes the product permanently. Deletion is blocked if any '
          'purchase order references it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await ref.read(productsNotifierProvider.notifier).delete(widget.id!);
      if (!mounted) return;
      showSnackBar(context, 'Product deleted');
      context.pop();
    } catch (e) {
      if (mounted) showSnackBar(context, '$e', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = _existing != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? 'Edit Product' : 'Add Product'),
        actions: [
          if (isEditing)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Delete',
              onPressed: _confirmDelete,
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (isEditing) ...[
              Center(
                child: Hero(
                  tag: 'product-${_existing!.id}',
                  child: CircleAvatar(
                    radius: 28,
                    backgroundColor:
                        Theme.of(context).colorScheme.secondaryContainer,
                    foregroundColor:
                        Theme.of(context).colorScheme.onSecondaryContainer,
                    child: const Icon(Icons.inventory_2_outlined),
                  ),
                ),
              ),
              if (_existing!.productCode.isNotEmpty) ...[
                const SizedBox(height: 8),
                Center(
                  child: Text(
                    _existing!.productCode,
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: Theme.of(context).colorScheme.primary),
                  ),
                ),
              ],
              const SizedBox(height: 16),
            ],
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Name *'),
              validator: _validateName,
              textInputAction: TextInputAction.next,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _partNoController,
              decoration: const InputDecoration(
                labelText: 'Part No',
                helperText: 'Optional — does not have to be unique',
              ),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _selectedCategory,
              decoration: const InputDecoration(
                labelText: 'Category *',
                helperText: 'Sales = goods sold outright · '
                    'Labour = job-work on customer material',
              ),
              items: Product.categories
                  .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                  .toList(),
              onChanged: (v) => setState(() => _selectedCategory = v),
              validator: (v) => v == null ? 'Category is required' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _hsnSacController,
              decoration: InputDecoration(
                labelText: Product.codeLabelFor(_selectedCategory),
              ),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _selectedUnit,
              decoration: const InputDecoration(labelText: 'Unit'),
              items: Product.units
                  .map((u) => DropdownMenuItem(value: u, child: Text(u)))
                  .toList(),
              onChanged: (v) => setState(() => _selectedUnit = v),
            ),
            if (_selectedUnit == 'Other') ...[
              const SizedBox(height: 12),
              TextFormField(
                controller: _otherUnitController,
                decoration: const InputDecoration(labelText: 'Specify unit *'),
                validator: _validateOtherUnit,
                textInputAction: TextInputAction.next,
                onChanged: (_) => setState(() {}),
              ),
            ],
            const SizedBox(height: 16),
            TextFormField(
              controller: _priceController,
              decoration: const InputDecoration(
                labelText: 'Price *',
                helperText: 'Labour lines are often ₹0 — that is allowed',
              ),
              validator: _validatePrice,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              textInputAction: TextInputAction.next,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _taxController,
              decoration: const InputDecoration(labelText: 'Tax %'),
              validator: _validateTax,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _submit(),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _isValid && !_isSaving ? _submit : null,
              child: _isSaving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(isEditing ? 'Save changes' : 'Create product'),
            ),
          ],
        ),
      ),
    );
  }
}
