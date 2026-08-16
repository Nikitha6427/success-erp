import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/widgets/responsive_container.dart';
import '../../core/widgets/snack_bar_helper.dart';
import '../../core/widgets/conflict_dialog.dart';
import 'customers_notifier.dart';
import 'models/customer.dart';

class CustomerFormScreen extends ConsumerStatefulWidget {
  final String? id;

  const CustomerFormScreen({this.id, super.key});

  @override
  ConsumerState<CustomerFormScreen> createState() => _CustomerFormScreenState();
}

class _CustomerFormScreenState extends ConsumerState<CustomerFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _streetController = TextEditingController();
  final _areaController = TextEditingController();
  final _cityController = TextEditingController();
  final _stateController = TextEditingController();
  // AGENTS.md §4: Country defaults to "India" — State does not.
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
      _existing = ref
          .read(customersNotifierProvider.notifier)
          .findById(widget.id!);
      if (_existing != null) {
        _fill(_existing!);
      } else {
        // Deep-linked or reloaded: fetch, then populate.
        Future.microtask(() async {
          await ref.read(customersNotifierProvider.notifier).load();
          if (!mounted) return;
          final found = ref
              .read(customersNotifierProvider.notifier)
              .findById(widget.id!);
          if (found != null) setState(() => _fill(found));
        });
      }
    }
  }

  void _fill(Customer c) {
    _existing = c;
    _nameController.text = c.name;
    _phoneController.text = c.phone;
    _emailController.text = c.email;
    _streetController.text = c.street;
    _areaController.text = c.area;
    _cityController.text = c.cityDistrict;
    _stateController.text = c.state;
    _countryController.text = c.country.isEmpty ? 'India' : c.country;
    _pincodeController.text = c.pincode;
    _gstController.text = c.gstNumber;
    _tinController.text = c.tinNumber;
    _cstController.text = c.cstNumber;
  }

  @override
  void dispose() {
    for (final c in [
      _nameController,
      _phoneController,
      _emailController,
      _streetController,
      _areaController,
      _cityController,
      _stateController,
      _countryController,
      _pincodeController,
      _gstController,
      _tinController,
      _cstController,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _validateName(String? value) =>
      (value == null || value.trim().isEmpty) ? 'Name is required' : null;

  /// Optional, but must be exactly 10 digits when filled in (AGENTS.md §4).
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

  String? _validatePincode(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    if (!RegExp(r'^\d{6}$').hasMatch(value.trim())) {
      return 'Pincode must be 6 digits';
    }
    return null;
  }

  bool get _isValid =>
      _validateName(_nameController.text) == null &&
      _validatePhone(_phoneController.text) == null &&
      _validateEmail(_emailController.text) == null &&
      _validatePincode(_pincodeController.text) == null &&
      _duplicateError == null;

  void _checkDuplicate() {
    final existing = ref
        .read(customersNotifierProvider.notifier)
        .findDuplicate(
          _nameController.text,
          _phoneController.text,
          excludeId: widget.id,
        );
    setState(() {
      _duplicateError = existing != null
          ? 'A customer with this name and phone number already exists.'
          : null;
    });
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (!_isValid || _isSaving) return;

    final notifier = ref.read(customersNotifierProvider.notifier);
    final dup = notifier.findDuplicate(
      _nameController.text,
      _phoneController.text,
      excludeId: widget.id,
    );
    if (dup != null) {
      setState(
        () => _duplicateError =
            'A customer with this name and phone number already exists.',
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      final now = DateTime.now().toIso8601String();
      final base = (_existing ?? Customer(id: '', name: '', createdAt: now))
          .copyWith(
            name: _nameController.text.trim(),
            phone: _phoneController.text.trim(),
            email: _emailController.text.trim(),
            street: _streetController.text.trim(),
            area: _areaController.text.trim(),
            cityDistrict: _cityController.text.trim(),
            state: _stateController.text.trim(),
            country: _countryController.text.trim(),
            pincode: _pincodeController.text.trim(),
            gstNumber: _gstController.text.trim(),
            tinNumber: _tinController.text.trim(),
            cstNumber: _cstController.text.trim(),
            updatedAt: now,
          );

      if (_existing != null) {
        await notifier.update(base);
      } else {
        await notifier.add(base);
      }
      if (mounted) {
        showSnackBar(context, 'Customer saved');
        context.pop();
      }
    } catch (e) {
      if (!mounted) return;
      final handled = await handleConflictError(context, e);
      if (!mounted) return;
      if (handled) {
        await ref.read(customersNotifierProvider.notifier).load();
        if (mounted) context.pop();
      } else {
        showSnackBar(context, 'Save failed: $e', isError: true);
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = _existing != null;
    return Scaffold(
      appBar: AppBar(title: Text(isEditing ? 'Edit Customer' : 'Add Customer')),
      body: ResponsiveContainer(
        child: Form(
          key: _formKey,
          autovalidateMode: AutovalidateMode.onUserInteraction,
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
                decoration: InputDecoration(
                  labelText: 'Phone (10 digits)',
                  errorText: _duplicateError,
                ),
                validator: _validatePhone,
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.next,
                onChanged: (_) {
                  setState(() {});
                  _checkDuplicate();
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _emailController,
                decoration: const InputDecoration(labelText: 'Email'),
                validator: _validateEmail,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 24),
              _sectionLabel(context, 'Address'),
              TextFormField(
                controller: _streetController,
                decoration: const InputDecoration(labelText: 'Street'),
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _areaController,
                decoration: const InputDecoration(labelText: 'Area / Locality'),
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _cityController,
                decoration: const InputDecoration(labelText: 'City / District'),
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _stateController,
                      decoration: const InputDecoration(labelText: 'State'),
                      textInputAction: TextInputAction.next,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _countryController,
                      decoration: const InputDecoration(labelText: 'Country'),
                      textInputAction: TextInputAction.next,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _pincodeController,
                decoration: const InputDecoration(labelText: 'Pincode'),
                validator: _validatePincode,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.next,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 24),
              _sectionLabel(context, 'Tax Info'),
              TextFormField(
                controller: _gstController,
                decoration: const InputDecoration(labelText: 'GST Number'),
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _tinController,
                decoration: const InputDecoration(labelText: 'TIN Number'),
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _cstController,
                decoration: const InputDecoration(labelText: 'CST Number'),
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _submit(),
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
      ),
    );
  }

  Widget _sectionLabel(BuildContext context, String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(text, style: Theme.of(context).textTheme.titleSmall),
  );
}
