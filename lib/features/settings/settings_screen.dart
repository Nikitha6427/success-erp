import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app.dart';
import '../../core/widgets/app_drawer.dart';
import '../../core/widgets/snack_bar_helper.dart';
import 'models/company_profile.dart';
import 'settings_notifier.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _companyController = TextEditingController();
  final _streetController = TextEditingController();
  final _areaController = TextEditingController();
  final _cityController = TextEditingController();
  final _stateController = TextEditingController();
  final _countryController = TextEditingController(text: 'India');
  final _pincodeController = TextEditingController();
  final _gstController = TextEditingController();
  final _tinController = TextEditingController();
  final _cstController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _websiteController = TextEditingController();

  bool _isSaving = false;
  bool _populated = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      await ref.read(settingsNotifierProvider.notifier).load();
      if (!mounted) return;
      final profile = ref.read(settingsNotifierProvider).profile;
      if (profile != null) setState(() => _fill(profile));
    });
  }

  void _fill(CompanyProfile p) {
    _populated = true;
    _companyController.text = p.companyName;
    _streetController.text = p.street;
    _areaController.text = p.area;
    _cityController.text = p.cityDistrict;
    _stateController.text = p.state;
    _countryController.text = p.country.isEmpty ? 'India' : p.country;
    _pincodeController.text = p.pincode;
    _gstController.text = p.gstNumber;
    _tinController.text = p.tinNumber;
    _cstController.text = p.cstNumber;
    _phoneController.text = p.phone;
    _emailController.text = p.email;
    _websiteController.text = p.website;
  }

  @override
  void dispose() {
    for (final c in [
      _companyController,
      _streetController,
      _areaController,
      _cityController,
      _stateController,
      _countryController,
      _pincodeController,
      _gstController,
      _tinController,
      _cstController,
      _phoneController,
      _emailController,
      _websiteController,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _validateCompany(String? v) =>
      (v == null || v.trim().isEmpty) ? 'Company name is required' : null;

  String? _validateEmail(String? v) {
    if (v == null || v.trim().isEmpty) return null;
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v.trim())) {
      return 'Enter a valid email address';
    }
    return null;
  }

  String? _validatePincode(String? v) {
    if (v == null || v.trim().isEmpty) return null;
    if (!RegExp(r'^\d{6}$').hasMatch(v.trim())) return 'Pincode must be 6 digits';
    return null;
  }

  bool get _isValid =>
      _validateCompany(_companyController.text) == null &&
      _validateEmail(_emailController.text) == null &&
      _validatePincode(_pincodeController.text) == null;

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (!_isValid || _isSaving) return;
    setState(() => _isSaving = true);
    try {
      final existing = ref.read(settingsNotifierProvider).profile;
      final profile = (existing ?? const CompanyProfile()).copyWith(
        companyName: _companyController.text.trim(),
        street: _streetController.text.trim(),
        area: _areaController.text.trim(),
        cityDistrict: _cityController.text.trim(),
        state: _stateController.text.trim(),
        country: _countryController.text.trim(),
        pincode: _pincodeController.text.trim(),
        gstNumber: _gstController.text.trim(),
        tinNumber: _tinController.text.trim(),
        cstNumber: _cstController.text.trim(),
        phone: _phoneController.text.trim(),
        email: _emailController.text.trim(),
        website: _websiteController.text.trim(),
      );
      await ref.read(settingsNotifierProvider.notifier).save(profile);
      if (mounted) showSnackBar(context, 'Company profile saved');
    } catch (e) {
      if (mounted) showSnackBar(context, 'Save failed: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _confirmSignOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Sign out?'),
        content: Text(
          'You will need to sign in with $storageProviderName again to reach '
          'your data.',
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
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(appStateProvider.notifier).signOut();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = ref.watch(settingsNotifierProvider);

    // Populate once the profile arrives, if it wasn't ready in initState.
    if (!_populated && state.profile != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_populated) setState(() => _fill(state.profile!));
      });
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      drawer: const AppDrawer(currentPath: '/settings'),
      body: Form(
        key: _formKey,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            Text(
              'Company Profile',
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'These details are the letterhead on every Delivery Note and '
              'Invoice.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.outline),
            ),
            const SizedBox(height: 24),
            TextFormField(
              controller: _companyController,
              decoration: const InputDecoration(labelText: 'Company Name *'),
              validator: _validateCompany,
              textInputAction: TextInputAction.next,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 24),
            _sectionLabel(theme, 'Address'),
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
            _sectionLabel(theme, 'Tax Info'),
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
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 24),
            _sectionLabel(theme, 'Contact'),
            TextFormField(
              controller: _phoneController,
              decoration: const InputDecoration(labelText: 'Contact Number'),
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _emailController,
              decoration: const InputDecoration(labelText: 'Email'),
              validator: _validateEmail,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _websiteController,
              decoration: const InputDecoration(labelText: 'Website'),
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _save(),
            ),
            const SizedBox(height: 32),
            FilledButton(
              onPressed: _isValid && !_isSaving ? _save : null,
              child: _isSaving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Save Company Profile'),
            ),
            const SizedBox(height: 32),
            const Divider(),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _confirmSignOut,
              icon: const Icon(Icons.logout),
              label: const Text('Sign out'),
              style: OutlinedButton.styleFrom(
                foregroundColor: theme.colorScheme.error,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(ThemeData theme, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text, style: theme.textTheme.titleSmall),
      );
}
