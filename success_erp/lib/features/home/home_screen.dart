import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('ERP Manager')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.check_circle_outline,
                size: 64,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text(
                'Workspace ready',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Your ERP workspace is set up.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 32),
              FilledButton.icon(
                onPressed: () => context.go('/customers'),
                icon: const Icon(Icons.people),
                label: const Text('Go to Customers'),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () => context.go('/products'),
                icon: const Icon(Icons.inventory_2),
                label: const Text('Go to Products'),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () => context.go('/purchase-orders'),
                icon: const Icon(Icons.receipt_long),
                label: const Text('Purchase Orders'),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () => context.go('/invoices'),
                icon: const Icon(Icons.receipt_outlined),
                label: const Text('Invoices'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
