import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class AppDrawer extends StatelessWidget {
  final String currentPath;

  const AppDrawer({required this.currentPath, super.key});

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
                      errorBuilder: (_, __, ___) => Icon(
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
                      color: theme.colorScheme.onPrimaryContainer.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  _DrawerItem(
                    icon: Icons.dashboard,
                    label: 'Dashboard',
                    selected: currentPath == '/',
                    onTap: () {
                      Navigator.pop(context);
                      context.go('/');
                    },
                  ),
                  _DrawerItem(
                    icon: Icons.people,
                    label: 'Customers',
                    selected: currentPath.startsWith('/customers'),
                    onTap: () {
                      Navigator.pop(context);
                      context.push('/customers');
                    },
                  ),
                  _DrawerItem(
                    icon: Icons.inventory_2,
                    label: 'Products',
                    selected: currentPath.startsWith('/products'),
                    onTap: () {
                      Navigator.pop(context);
                      context.push('/products');
                    },
                  ),
                  _DrawerItem(
                    icon: Icons.receipt_long,
                    label: 'Purchase Orders',
                    selected: currentPath.startsWith('/purchase-orders'),
                    onTap: () {
                      Navigator.pop(context);
                      context.push('/purchase-orders');
                    },
                  ),
                  _DrawerItem(
                    icon: Icons.receipt_outlined,
                    label: 'Invoices',
                    selected: currentPath.startsWith('/invoices'),
                    onTap: () {
                      Navigator.pop(context);
                      context.push('/invoices');
                    },
                  ),
                  const Divider(),
                  _DrawerItem(
                    icon: Icons.assessment,
                    label: 'Reports',
                    selected: currentPath.startsWith('/reports'),
                    onTap: () {
                      Navigator.pop(context);
                      context.push('/reports');
                    },
                  ),
                  const Divider(),
                  _DrawerItem(
                    icon: Icons.settings,
                    label: 'Settings',
                    selected: currentPath.startsWith('/settings'),
                    onTap: () {
                      Navigator.pop(context);
                      context.push('/settings');
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DrawerItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _DrawerItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(label),
      selected: selected,
      selectedTileColor: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3),
      onTap: onTap,
    );
  }
}
