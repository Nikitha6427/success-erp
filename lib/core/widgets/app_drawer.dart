import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Drawer navigation for the six top-level sections (AGENTS.md §7).
///
/// Every destination except Dashboard is pushed *on top of* a freshly reset
/// Dashboard, so the stack stays exactly two deep no matter how many times the
/// user hops between sections: back always returns to Dashboard, and back from
/// Dashboard leaves the app. Without the reset, section-hopping piled up an
/// unbounded stack the hardware back button had to unwind one screen at a time.
class AppDrawer extends StatelessWidget {
  final String currentPath;

  const AppDrawer({required this.currentPath, super.key});

  static const _destinations = <_Destination>[
    _Destination('/', Icons.dashboard, 'Dashboard'),
    _Destination('/customers', Icons.people, 'Customers'),
    _Destination('/products', Icons.inventory_2, 'Products'),
    _Destination('/purchase-orders', Icons.receipt_long, 'Purchase Orders'),
    _Destination('/invoices', Icons.receipt_outlined, 'Invoices'),
    _Destination('/reports', Icons.assessment, 'Reports'),
    _Destination('/settings', Icons.settings, 'Settings'),
  ];

  void _navigate(BuildContext context, String path) {
    Navigator.pop(context); // close the drawer
    if (path == currentPath) return;
    context.go('/');
    if (path != '/') context.push(path);
  }

  bool _isSelected(String path) {
    if (path == '/') return currentPath == '/';
    return currentPath.startsWith(path);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              color: theme.colorScheme.primaryContainer,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.asset(
                      'assets/logo.png',
                      width: 40,
                      height: 40,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => Icon(
                        Icons.inventory_2,
                        size: 40,
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'ERP Manager',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                  Text(
                    'Order Fulfillment & Billing',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onPrimaryContainer
                          .withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  for (final d in _destinations) ...[
                    if (d.path == '/reports' || d.path == '/settings')
                      const Divider(),
                    ListTile(
                      leading: Icon(d.icon),
                      title: Text(d.label),
                      selected: _isSelected(d.path),
                      selectedTileColor: theme.colorScheme.primaryContainer
                          .withValues(alpha: 0.3),
                      onTap: () => _navigate(context, d.path),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Destination {
  final String path;
  final IconData icon;
  final String label;
  const _Destination(this.path, this.icon, this.label);
}
