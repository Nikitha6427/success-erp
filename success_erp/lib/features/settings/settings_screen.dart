import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
  final _companyController = TextEditingController();
  final _addressController = TextEditingController();
  final _phoneController = TextEditingController();
  final _gstController = TextEditingController();
  final _stateController = TextEditingController();
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(settingsNotifierProvider.notifier).load());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final profile = ref.read(settingsNotifierProvider).profile;
    if (profile != null) {
      _companyController.text = profile.companyName;
      _addressController.text = profile.address;
      _phoneController.text = profile.phone;
      _gstController.text = profile.gstNumber;
      _stateController.text = profile.state;
    }
  }

  @override
  void dispose() {
    _companyController.dispose();
    _addressController.dispose();
    _phoneController.dispose();
    _gstController.dispose();
    _stateController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_companyController.text.trim().isEmpty) {
      showSnackBar(context, 'Company name is required', isError: true);
      return;
    }
    setState(() => _isSaving = true);
    try {
      final now = DateTime.now().toIso8601String();
      final profile = CompanyProfile(
        id: 'company',
        companyName: _companyController.text.trim(),
        address: _addressController.text.trim(),
        phone: _phoneController.text.trim(),
        gstNumber: _gstController.text.trim(),
        state: _stateController.text.trim(),
        updatedAt: now,
      );
      await ref.read(settingsNotifierProvider.notifier).save(profile);
      if (mounted) {
        showSnackBar(context, 'Company profile saved');
      }
    } catch (e) {
      if (mounted) showSnackBar(context, 'Save failed: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      drawer: AppDrawer(currentPath: '/settings'),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Company Profile',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'These details appear as a letterhead on Delivery Notes and Invoices.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.outline,
                ),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _companyController,
            decoration: const InputDecoration(
              labelText: 'Company Name *',
              border: OutlineInputBorder(),
            ),
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _addressController,
            decoration: const InputDecoration(
              labelText: 'Address',
              border: OutlineInputBorder(),
            ),
            maxLines: 3,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _phoneController,
            decoration: const InputDecoration(
              labelText: 'Contact Number',
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _gstController,
            decoration: const InputDecoration(
              labelText: 'GST Number',
              border: OutlineInputBorder(),
            ),
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _stateController,
            decoration: const InputDecoration(
              labelText: 'State (for IGST detection)',
              border: OutlineInputBorder(),
              helperText: 'e.g. Maharashtra, Karnataka',
            ),
            textInputAction: TextInputAction.done,
          ),
          const SizedBox(height: 32),
          FilledButton(
            onPressed: _isSaving ? null : _save,
            child: _isSaving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Save Company Profile'),
          ),
        ],
      ),
    );
  }
}
