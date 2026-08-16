import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/widgets/responsive_container.dart';
import '../../core/widgets/app_drawer.dart';
import '../../features/customers/customers_notifier.dart';
import '../../features/products/products_notifier.dart';
import '../../features/purchase_orders/po_providers.dart';
import '../../features/purchase_orders/models/purchase_order.dart';
import '../../features/delivery_notes/dn_providers.dart';
import '../../features/invoices/invoice_providers.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(customersNotifierProvider.notifier).load();
      ref.read(productsNotifierProvider.notifier).load();
      ref.read(poNotifierProvider.notifier).load();
      ref.read(dnListProvider.notifier).load();
      ref.read(invoiceListProvider.notifier).load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final customers = ref.watch(customersNotifierProvider).customers;
    final products = ref.watch(productsNotifierProvider).products;
    final pos = ref.watch(poNotifierProvider).orders;
    final invoices = ref.watch(invoiceListProvider).invoices;

    final pendingPOs = pos
        .where((po) => po.status == PurchaseOrder.statusPending)
        .length;
    final pendingDeliveries = pos
        .where(
          (po) =>
              po.status == PurchaseOrder.statusPending ||
              po.status == PurchaseOrder.statusPartiallyDelivered,
        )
        .length;
    final unpaidInvoices = invoices.where((inv) => !inv.isPaid).length;

    return Scaffold(
      appBar: AppBar(title: const Text('Dashboard')),
      drawer: AppDrawer(currentPath: '/'),
      body: ResponsiveContainer(
        child: SafeArea(
          child: RefreshIndicator(
            onRefresh: () async {
              ref.read(customersNotifierProvider.notifier).load();
              ref.read(productsNotifierProvider.notifier).load();
              ref.read(poNotifierProvider.notifier).load();
              ref.read(dnListProvider.notifier).load();
              ref.read(invoiceListProvider.notifier).load();
            },
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [
                Text(
                  'Overview',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                _SummaryRow(
                  cards: [
                    _SummaryCard(
                      icon: Icons.people,
                      label: 'Customers',
                      count: customers.length,
                      color: theme.colorScheme.primary,
                      onTap: () => context.push('/customers'),
                    ),
                    _SummaryCard(
                      icon: Icons.inventory_2,
                      label: 'Products',
                      count: products.length,
                      color: theme.colorScheme.secondary,
                      onTap: () => context.push('/products'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _SummaryRow(
                  cards: [
                    _SummaryCard(
                      icon: Icons.receipt_long,
                      label: 'Pending POs',
                      count: pendingPOs,
                      color: theme.colorScheme.error,
                      onTap: () => context.push('/purchase-orders'),
                    ),
                    _SummaryCard(
                      icon: Icons.local_shipping,
                      label: 'Pending\nDeliveries',
                      count: pendingDeliveries,
                      color: theme.colorScheme.tertiary,
                      onTap: () => context.push('/purchase-orders'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _SummaryRow(
                  cards: [
                    _SummaryCard(
                      icon: Icons.receipt_outlined,
                      label: 'Unpaid\nInvoices',
                      count: unpaidInvoices,
                      color: theme.colorScheme.secondary,
                      onTap: () => context.push('/invoices'),
                    ),
                    _SummaryCard(
                      icon: Icons.shopping_cart,
                      label: 'Total POs',
                      count: pos.length,
                      color: theme.colorScheme.tertiary,
                      onTap: () => context.push('/purchase-orders'),
                    ),
                  ],
                ),
                const SizedBox(height: 32),
                Text(
                  'Quick actions',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                _QuickAction(
                  icon: Icons.person_add,
                  label: 'Add Customer',
                  onTap: () => context.push('/customers/new'),
                ),
                _QuickAction(
                  icon: Icons.add_box,
                  label: 'Add Product',
                  onTap: () => context.push('/products/new'),
                ),
                _QuickAction(
                  icon: Icons.add_shopping_cart,
                  label: 'New Purchase Order',
                  onTap: () => context.push('/purchase-orders/new'),
                ),
                _QuickAction(
                  icon: Icons.assessment,
                  label: 'View Reports',
                  onTap: () => context.push('/reports'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final List<_SummaryCard> cards;
  const _SummaryRow({required this.cards});

  @override
  Widget build(BuildContext context) {
    return Row(children: cards.map((card) => Expanded(child: card)).toList());
  }
}

class _SummaryCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final int count;
  final Color color;
  final VoidCallback? onTap;

  const _SummaryCard({
    required this.icon,
    required this.label,
    required this.count,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: color, size: 28),
              const SizedBox(height: 8),
              Text(
                '$count',
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _QuickAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(icon),
        title: Text(label),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
