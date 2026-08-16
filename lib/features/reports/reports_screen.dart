import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/services/csv_export.dart';
import '../../core/widgets/responsive_container.dart';
import '../../core/widgets/app_drawer.dart';
import '../../core/widgets/empty_state.dart';
import '../customers/customers_notifier.dart';
import '../invoices/invoice_providers.dart';
import '../invoices/models/invoice.dart';
import '../products/products_notifier.dart';
import '../purchase_orders/models/purchase_order.dart';
import '../purchase_orders/po_providers.dart';

/// Inclusive date range. Reports default to the current month (AGENTS.md §5).
class DateRange {
  final DateTime from;
  final DateTime to;

  const DateRange(this.from, this.to);

  factory DateRange.currentMonth() {
    final now = DateTime.now();
    return DateRange(
      DateTime(now.year, now.month, 1),
      DateTime(now.year, now.month + 1, 0),
    );
  }

  /// Inclusive of the whole `to` day, so an invoice raised this afternoon is
  /// not filtered out by a range ending today.
  bool contains(String isoDate) {
    if (isoDate.trim().isEmpty) return false;
    final parsed = DateTime.tryParse(isoDate);
    if (parsed == null) return false;
    final day = DateTime(parsed.year, parsed.month, parsed.day);
    final start = DateTime(from.year, from.month, from.day);
    final end = DateTime(to.year, to.month, to.day);
    return !day.isBefore(start) && !day.isAfter(end);
  }
}

class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  @override
  void initState() {
    super.initState();
    // Reports are computed in-memory from repository data, so make sure that
    // data is actually present even when this screen is opened directly.
    Future.microtask(() async {
      await ref.read(customersNotifierProvider.notifier).load();
      await ref.read(productsNotifierProvider.notifier).load();
      await ref.read(poNotifierProvider.notifier).load();
      await ref.read(invoiceListProvider.notifier).load();
      final items = await ref.read(invoiceItemRepositoryProvider).loadAll();
      if (mounted) ref.read(invoiceItemsCacheProvider.notifier).state = items;
    });
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Reports'),
          bottom: const TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: 'Pending Deliveries'),
              Tab(text: 'Sales by Customer'),
              Tab(text: 'Sales by Product'),
              Tab(text: 'Outstanding Invoices'),
            ],
          ),
        ),
        drawer: const AppDrawer(currentPath: '/reports'),
        body: ResponsiveContainer(
          child: const TabBarView(
            children: [
              _PendingDeliveriesReport(),
              _SalesByCustomerReport(),
              _SalesByProductReport(),
              _OutstandingInvoicesReport(),
            ],
          ),
        ),
      ),
    );
  }
}

/// InvoiceItems loaded once for the Sales-by-Product report.
final invoiceItemsCacheProvider = StateProvider<List<InvoiceItem>>(
  (ref) => const [],
);

// ─── Shared scaffolding ──────────────────────────────────────────────────────

class _ReportShell extends StatelessWidget {
  final DateRange range;
  final ValueChanged<DateRange> onRangeChanged;
  final VoidCallback onExport;
  final Widget child;

  const _ReportShell({
    required this.range,
    required this.onRangeChanged,
    required this.onExport,
    required this.child,
  });

  Future<void> _pick(BuildContext context, {required bool isFrom}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isFrom ? range.from : range.to,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    onRangeChanged(
      isFrom ? DateRange(picked, range.to) : DateRange(range.from, picked),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _pick(context, isFrom: true),
                  icon: const Icon(Icons.calendar_today, size: 16),
                  label: Text(DateFormat.yMMMd().format(range.from)),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Text('to'),
              ),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _pick(context, isFrom: false),
                  icon: const Icon(Icons.calendar_today, size: 16),
                  label: Text(DateFormat.yMMMd().format(range.to)),
                ),
              ),
            ],
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            TextButton.icon(
              onPressed: () => onRangeChanged(DateRange.currentMonth()),
              icon: const Icon(Icons.restart_alt, size: 16),
              label: const Text('This month'),
            ),
            TextButton.icon(
              onPressed: onExport,
              icon: const Icon(Icons.download, size: 16),
              label: const Text('Export CSV'),
            ),
          ],
        ),
        Expanded(child: child),
      ],
    );
  }
}

Widget _amountList(
  BuildContext context,
  List<MapEntry<String, double>> entries,
  String emptyMessage,
  IconData emptyIcon,
) {
  if (entries.isEmpty) {
    return EmptyState(icon: emptyIcon, message: emptyMessage);
  }
  final money = NumberFormat.currency(locale: 'en_IN', symbol: '₹');
  return ListView.builder(
    itemCount: entries.length,
    itemBuilder: (context, index) {
      final entry = entries[index];
      return Card(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: ListTile(
          title: Text(entry.key),
          trailing: Text(
            money.format(entry.value),
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
          ),
        ),
      );
    },
  );
}

// ─── Pending deliveries ──────────────────────────────────────────────────────

class _PendingDeliveriesReport extends ConsumerStatefulWidget {
  const _PendingDeliveriesReport();

  @override
  ConsumerState<_PendingDeliveriesReport> createState() =>
      _PendingDeliveriesReportState();
}

class _PendingDeliveriesReportState
    extends ConsumerState<_PendingDeliveriesReport> {
  DateRange _range = DateRange.currentMonth();

  @override
  Widget build(BuildContext context) {
    final customers = ref.watch(customersNotifierProvider).customers;
    final customerById = {for (final c in customers) c.id: c.name};

    final pending = ref
        .watch(poNotifierProvider)
        .orders
        .where(
          (po) =>
              (po.status == PurchaseOrder.statusPending ||
                  po.status == PurchaseOrder.statusPartiallyDelivered) &&
              _range.contains(po.orderDate),
        )
        .toList();

    return _ReportShell(
      range: _range,
      onRangeChanged: (r) => setState(() => _range = r),
      onExport: () => CsvExport.export(
        fileName: 'pending_deliveries',
        headers: ['PO Number', 'Customer', 'Status', 'Order Date'],
        rows: pending
            .map(
              (po) => [
                po.poNumber,
                customerById[po.customerId] ?? 'Unknown',
                po.status,
                po.orderDate,
              ],
            )
            .toList(),
      ),
      child: pending.isEmpty
          ? const EmptyState(
              icon: Icons.local_shipping_outlined,
              message: 'No pending deliveries in this range',
            )
          : ListView.builder(
              itemCount: pending.length,
              itemBuilder: (context, index) {
                final po = pending[index];
                return Card(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 4,
                  ),
                  child: ListTile(
                    title: Text(
                      '${po.poNumber} — '
                      '${customerById[po.customerId] ?? "Unknown"}',
                    ),
                    subtitle: Text('Status: ${po.status}'),
                  ),
                );
              },
            ),
    );
  }
}

// ─── Sales by customer ───────────────────────────────────────────────────────

class _SalesByCustomerReport extends ConsumerStatefulWidget {
  const _SalesByCustomerReport();

  @override
  ConsumerState<_SalesByCustomerReport> createState() =>
      _SalesByCustomerReportState();
}

class _SalesByCustomerReportState
    extends ConsumerState<_SalesByCustomerReport> {
  DateRange _range = DateRange.currentMonth();

  @override
  Widget build(BuildContext context) {
    final invoices = ref.watch(invoiceListProvider).invoices;
    final customers = ref.watch(customersNotifierProvider).customers;
    final pos = ref.watch(poNotifierProvider).orders;
    final customerById = {for (final c in customers) c.id: c.name};
    final poById = {for (final po in pos) po.id: po};

    final totals = <String, double>{};
    for (final inv in invoices) {
      if (!_range.contains(inv.invoiceDate)) continue;
      final po = poById[inv.poId];
      final name = customerById[po?.customerId ?? ''] ?? 'Unknown';
      totals[name] = (totals[name] ?? 0) + inv.total;
    }
    final sorted = totals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return _ReportShell(
      range: _range,
      onRangeChanged: (r) => setState(() => _range = r),
      onExport: () => CsvExport.export(
        fileName: 'sales_by_customer',
        headers: ['Customer', 'Total Sales'],
        rows: sorted.map((e) => [e.key, e.value.toStringAsFixed(2)]).toList(),
      ),
      child: _amountList(
        context,
        sorted,
        'No sales data in this range',
        Icons.people_outline,
      ),
    );
  }
}

// ─── Sales by product ────────────────────────────────────────────────────────

class _SalesByProductReport extends ConsumerStatefulWidget {
  const _SalesByProductReport();

  @override
  ConsumerState<_SalesByProductReport> createState() =>
      _SalesByProductReportState();
}

class _SalesByProductReportState extends ConsumerState<_SalesByProductReport> {
  DateRange _range = DateRange.currentMonth();

  @override
  Widget build(BuildContext context) {
    final invoices = ref.watch(invoiceListProvider).invoices;
    final items = ref.watch(invoiceItemsCacheProvider);
    final products = ref.watch(productsNotifierProvider).products;
    final productById = {for (final p in products) p.id: p.name};

    final invoiceIdsInRange = invoices
        .where((inv) => _range.contains(inv.invoiceDate))
        .map((inv) => inv.id)
        .toSet();

    final totals = <String, double>{};
    for (final item in items) {
      if (!invoiceIdsInRange.contains(item.invoiceId)) continue;
      final name = item.productId.isEmpty
          ? item
                .description // flat charge
          : (productById[item.productId] ?? 'Unknown');
      totals[name] = (totals[name] ?? 0) + item.amt;
    }
    final sorted = totals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return _ReportShell(
      range: _range,
      onRangeChanged: (r) => setState(() => _range = r),
      onExport: () => CsvExport.export(
        fileName: 'sales_by_product',
        headers: ['Product', 'Total Sales'],
        rows: sorted.map((e) => [e.key, e.value.toStringAsFixed(2)]).toList(),
      ),
      child: _amountList(
        context,
        sorted,
        'No sales data in this range',
        Icons.inventory_2_outlined,
      ),
    );
  }
}

// ─── Outstanding invoices ────────────────────────────────────────────────────

class _OutstandingInvoicesReport extends ConsumerStatefulWidget {
  const _OutstandingInvoicesReport();

  @override
  ConsumerState<_OutstandingInvoicesReport> createState() =>
      _OutstandingInvoicesReportState();
}

class _OutstandingInvoicesReportState
    extends ConsumerState<_OutstandingInvoicesReport> {
  DateRange _range = DateRange.currentMonth();

  @override
  Widget build(BuildContext context) {
    final pos = ref.watch(poNotifierProvider).orders;
    final poById = {for (final po in pos) po.id: po};
    final money = NumberFormat.currency(locale: 'en_IN', symbol: '₹');

    final unpaid = ref
        .watch(invoiceListProvider)
        .invoices
        .where((inv) => !inv.isPaid && _range.contains(inv.invoiceDate))
        .toList();
    final outstandingTotal = unpaid.fold<double>(
      0,
      (sum, inv) => sum + inv.total,
    );

    return _ReportShell(
      range: _range,
      onRangeChanged: (r) => setState(() => _range = r),
      onExport: () => CsvExport.export(
        fileName: 'outstanding_invoices',
        headers: ['Invoice', 'PO Number', 'Amount', 'Status', 'Invoice Date'],
        rows: unpaid
            .map(
              (inv) => [
                inv.invoiceNumber,
                poById[inv.poId]?.poNumber ?? '',
                inv.totalAmount,
                inv.status,
                inv.invoiceDate,
              ],
            )
            .toList(),
      ),
      child: unpaid.isEmpty
          ? const EmptyState(
              icon: Icons.receipt_outlined,
              message: 'No outstanding invoices in this range',
            )
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Total outstanding'),
                      Text(
                        money.format(outstandingTotal),
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: unpaid.length,
                    itemBuilder: (context, index) {
                      final inv = unpaid[index];
                      return Card(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 4,
                        ),
                        child: ListTile(
                          title: Text(
                            '${inv.invoiceNumber} — '
                            'PO: ${poById[inv.poId]?.poNumber ?? ""}',
                          ),
                          subtitle: Text('Status: ${inv.status}'),
                          trailing: Text(
                            money.format(inv.total),
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}
