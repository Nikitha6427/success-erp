import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/widgets/snack_bar_helper.dart';
import '../../core/widgets/conflict_dialog.dart';
import 'customers_notifier.dart';
import 'models/customer.dart';

class CustomerFormScreen extends ConsumerStatefulWidget {
  final String? id;

  const CustomerFormScreen({this.id, super.key});

  @override
  ConsumerState<CustomerFormScreen> createState() =>
      _CustomerFormScreenState();
}

class _CustomerFormScreenState extends ConsumerState<CustomerFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _streetController = TextEditingController();
  final _areaController = TextEditingController();
  final _cityController = TextEditingController();
  final _stateController = TextEditingController(text: 'India');
  final _countryController = TextEditingController(text: 'India');
  final _pincodeController = TextEditingController();
  final _gstController = TextEditingController();
  final _tinController = TextEditingController();
  final _cstController = TextEditingController();

  bool _isSaving = false;
  String? _duplicateError;

  Customer? _existing;

  @override
  void initState() {
    super.initState();
    if (widget.id != null) {
      _existing = ref.read(customersNotifierProvider).customers
          .where((c) => c.id == widget.id)
          .firstOrNull;
      if (_existing != null) {
        _nameController.text = _existing!.name;
        _phoneController.text = _existing!.phone;
        _emailController.text = _existing!.email;
        _gstController.text = _existing!.gstNumber;
        _tinController.text = _existing!.tinNumber;
        _cstController.text = _existing!.cstNumber;
        _streetController.text = _existing!.address;
      } else {
        Future.microtask(
          () => ref.read(customersNotifierProvider.notifier).load(),
        );
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _streetController.dispose();
    _areaController.dispose();
    _cityController.dispose();
    _stateController.dispose();
    _countryController.dispose();
    _pincodeController.dispose();
    _gstController.dispose();
    _tinController.dispose();
    _cstController.dispose();
    super.dispose();
  }

  String? _validateName(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Name is required';
    }
    return null;
  }

  String? _validatePhone(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    if (!RegExp(r'^\d{10}$').hasMatch(value.trim())) {
      return 'Enter a valid 10-digit mobile number';
    }
    return null;
  }

  String? _validateEmail(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value.trim())) {
      return 'Enter a valid email address';
    }
    return null;
  }

  bool get _isValid =>
      _validateName(_nameController.text) == null &&
      _validatePhone(_phoneController.text) == null &&
      _validateEmail(_emailController.text) == null &&
      _duplicateError == null;

  void _checkDuplicate() {
    final name = _nameController.text;
    final phone = _phoneController.text;
    if (name.trim().isEmpty || phone.trim().isEmpty) {
      setState(() => _duplicateError = null);
      return;
    }
    final notifier = ref.read(customersNotifierProvider.notifier);
    final existing = notifier.findDuplicate(
      name,
      phone,
      excludeId: widget.id,
    );
    setState(() {
      _duplicateError = existing != null
          ? 'A customer with this name and phone number already exists.'
          : null;
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_isValid || _isSaving) return;
    setState(() => _isSaving = true);
    try {
      final now = DateTime.now().toIso8601String();
      final notifier = ref.read(customersNotifierProvider.notifier);

      // Build single address string from sub-fields
      final addrParts = <String>[
        _streetController.text.trim(),
        _areaController.text.trim(),
        _cityController.text.trim(),
        _stateController.text.trim(),
        _countryController.text.trim(),
        _pincodeController.text.trim(),
      ].where((p) => p.isNotEmpty);
      final combinedAddress = addrParts.isNotEmpty ? addrParts.join(', ') : '';

      // Final duplicate check before save
      final dup = notifier.findDuplicate(
        _nameController.text,
        _phoneController.text,
        excludeId: widget.id,
      );
      if (dup != null) {
        setState(() {
          _duplicateError = 'A customer with this name and phone number already exists.';
          _isSaving = false;
        });
        return;
      }

      if (_existing != null) {
        await notifier.update(
          _existing!.copyWith(
            name: _nameController.text.trim(),
            phone: _phoneController.text.trim(),
            email: _emailController.text.trim(),
            address: combinedAddress,
            gstNumber: _gstController.text.trim(),
            tinNumber: _tinController.text.trim(),
            cstNumber: _cstController.text.trim(),
            updatedAt: now,
          ),
        );
      } else {
        await notifier.add(
          Customer(
            id: '',
            name: _nameController.text.trim(),
            phone: _phoneController.text.trim(),
            email: _emailController.text.trim(),
            address: combinedAddress,
            gstNumber: _gstController.text.trim(),
            tinNumber: _tinController.text.trim(),
            cstNumber: _cstController.text.trim(),
            createdAt: now,
            updatedAt: now,
          ),
        );
      }
      if (mounted) {
        showSnackBar(context, 'Customer saved');
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
    final isEditing = _existing != null;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(isEditing ? 'Edit Customer' : 'Add Customer')),
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
              onChanged: (_) {
                setState(() {});
                _checkDuplicate();
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _phoneController,
              decoration: const InputDecoration(labelText: 'Phone (10 digits)'),
              validator: _validatePhone,
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.next,
              onChanged: (_) {
                setState(() {});
                _checkDuplicate();
              },
            ),
            if (_phoneController.text.isNotEmpty && _validatePhone(_phoneController.text) != null) ...[
              const SizedBox(height: 4),
              Text(
                _validatePhone(_phoneController.text)!,
                style: TextStyle(color: theme.colorScheme.error, fontSize: 12),
              ),
            ],
            if (_duplicateError != null) ...[
              const SizedBox(height: 4),
              Text(
                _duplicateError!,
                style: TextStyle(
                  color: theme.colorScheme.error,
                  fontSize: 12,
                ),
              ),
            ],
            const SizedBox(height: 16),
            TextFormField(
              controller: _emailController,
              decoration: const InputDecoration(labelText: 'Email'),
              validator: _validateEmail,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              onChanged: (_) => setState(() {}),
            ),
            if (_emailController.text.isNotEmpty && _validateEmail(_emailController.text) != null) ...[
              const SizedBox(height: 4),
              Text(
                _validateEmail(_emailController.text)!,
                style: TextStyle(color: theme.colorScheme.error, fontSize: 12),
              ),
            ],
            const SizedBox(height: 16),
            Text('Address', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            TextFormField(
              controller: _streetController,
              decoration: const InputDecoration(labelText: 'Street'),
              textInputAction: TextInputAction.next,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _areaController,
              decoration: const InputDecoration(labelText: 'Area / Locality'),
              textInputAction: TextInputAction.next,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _cityController,
              decoration: const InputDecoration(labelText: 'City / District'),
              textInputAction: TextInputAction.next,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _stateController,
                    decoration: const InputDecoration(labelText: 'State'),
                    textInputAction: TextInputAction.next,
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _countryController,
                    decoration: const InputDecoration(labelText: 'Country'),
                    textInputAction: TextInputAction.next,
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _pincodeController,
              decoration: const InputDecoration(labelText: 'Pincode'),
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.next,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 16),
            Text('Tax Info', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            TextFormField(
              controller: _gstController,
              decoration: const InputDecoration(labelText: 'GST Number'),
              textInputAction: TextInputAction.next,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _tinController,
              decoration: const InputDecoration(labelText: 'TIN Number'),
              textInputAction: TextInputAction.next,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _cstController,
              decoration: const InputDecoration(labelText: 'CST Number'),
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
                  : Text(isEditing ? 'Save changes' : 'Create customer'),
            ),
          ],
        ),
      ),
    );
  }
}
