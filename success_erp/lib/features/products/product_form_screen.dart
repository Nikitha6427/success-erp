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
  ConsumerState<ProductFormScreen> createState() =>
      _ProductFormScreenState();
}

class _ProductFormScreenState extends ConsumerState<ProductFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _partNoController = TextEditingController();
  final _priceController = TextEditingController();
  final _taxController = TextEditingController();
  final _hsnController = TextEditingController();
  String? _selectedCategory;
  String? _selectedUnit;
  final _otherUnitController = TextEditingController();

  static const _categories = ['Sales', 'Labour'];
  static const _units = ['Nos', 'Kgs', 'Pcs', 'Box', 'Litre', 'Metre', 'Other'];

  bool _isSaving = false;
  Product? _existing;

  @override
  void initState() {
    super.initState();
    if (widget.id != null) {
      _existing = ref.read(productsNotifierProvider).products
          .where((p) => p.id == widget.id)
          .firstOrNull;
      if (_existing != null) {
        _nameController.text = _existing!.name;
        _partNoController.text = _existing!.partNo;
        _priceController.text = _existing!.price;
        _taxController.text = _existing!.taxPercent;
        _hsnController.text = _existing!.hsnCode;
        _selectedCategory = _existing!.category;
        if (_units.contains(_existing!.unit)) {
          _selectedUnit = _existing!.unit;
        } else if (_existing!.unit.isNotEmpty) {
          _selectedUnit = 'Other';
          _otherUnitController.text = _existing!.unit;
        }
      } else {
        Future.microtask(
          () => ref.read(productsNotifierProvider.notifier).load(),
        );
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _partNoController.dispose();
    _priceController.dispose();
    _taxController.dispose();
    _hsnController.dispose();
    _otherUnitController.dispose();
    super.dispose();
  }

  String? _validateName(String? value) =>
      (value == null || value.trim().isEmpty) ? 'Name is required' : null;

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

  bool get _isValid =>
      _validateName(_nameController.text) == null &&
      _validatePrice(_priceController.text) == null &&
      _validateTax(_taxController.text) == null &&
      _selectedCategory != null;

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_isValid || _isSaving) return;
    setState(() => _isSaving = true);
    try {
      final now = DateTime.now().toIso8601String();
      final notifier = ref.read(productsNotifierProvider.notifier);
      final unit = _selectedUnit == 'Other'
          ? _otherUnitController.text.trim()
          : (_selectedUnit ?? '');

      if (_existing != null) {
        await notifier.update(
          _existing!.copyWith(
            name: _nameController.text.trim(),
            partNo: _partNoController.text.trim(),
            unit: unit,
            price: _priceController.text.trim(),
            taxPercent: _taxController.text.trim(),
            hsnCode: _hsnController.text.trim(),
            category: _selectedCategory!,
            updatedAt: now,
          ),
        );
      } else {
        await notifier.add(
          Product(
            id: '',
            name: _nameController.text.trim(),
            partNo: _partNoController.text.trim(),
            unit: unit,
            price: _priceController.text.trim(),
            taxPercent: _taxController.text.trim(),
            createdAt: now,
            updatedAt: now,
            hsnCode: _hsnController.text.trim(),
            category: _selectedCategory!,
          ),
        );
      }
      if (mounted) {
        showSnackBar(context, 'Product saved');
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

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete product?'),
        content: const Text(
          'This will remove the product. (Purchase-order referential '
          'integrity checks are added in a later phase.)',
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
    if (confirmed == true && mounted) {
      await ref.read(productsNotifierProvider.notifier).delete(widget.id!);
      if (mounted) {
        showSnackBar(context, 'Product deleted');
        context.pop();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = _existing != null;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Hero(
          tag: widget.id != null ? 'product-${widget.id}' : 'product-new',
          child: Text(isEditing ? 'Edit Product' : 'Add Product'),
        ),
        actions: [
          if (isEditing)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: _confirmDelete,
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
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
              decoration: const InputDecoration(labelText: 'Part No'),
              textInputAction: TextInputAction.next,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _selectedCategory,
              decoration: const InputDecoration(labelText: 'Category *'),
              items: _categories.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
              onChanged: (v) => setState(() => _selectedCategory = v),
              validator: (v) => v == null ? 'Category is required' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _hsnController,
              decoration: InputDecoration(
                labelText: _selectedCategory == 'Labour' ? 'SAC Code' : 'HSN Code',
              ),
              textInputAction: TextInputAction.next,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _selectedUnit,
              decoration: const InputDecoration(labelText: 'Unit'),
              items: _units.map((u) => DropdownMenuItem(value: u, child: Text(u))).toList(),
              onChanged: (v) => setState(() => _selectedUnit = v),
            ),
            if (_selectedUnit == 'Other') ...[
              const SizedBox(height: 12),
              TextFormField(
                controller: _otherUnitController,
                decoration: const InputDecoration(labelText: 'Specify unit'),
                textInputAction: TextInputAction.next,
              ),
            ],
            const SizedBox(height: 16),
            TextFormField(
              controller: _priceController,
              decoration: const InputDecoration(labelText: 'Price *'),
              validator: _validatePrice,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              textInputAction: TextInputAction.next,
              onChanged: (_) => setState(() {}),
            ),
            if (_priceController.text.isNotEmpty && _validatePrice(_priceController.text) != null) ...[
              const SizedBox(height: 4),
              Text(
                _validatePrice(_priceController.text)!,
                style: TextStyle(color: theme.colorScheme.error, fontSize: 12),
              ),
            ],
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
            if (_taxController.text.isNotEmpty && _validateTax(_taxController.text) != null) ...[
              const SizedBox(height: 4),
              Text(
                _validateTax(_taxController.text)!,
                style: TextStyle(color: theme.colorScheme.error, fontSize: 12),
              ),
            ],
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
