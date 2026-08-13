import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../features/customers/customers_notifier.dart';
import '../../features/purchase_orders/po_providers.dart';
import '../../features/purchase_orders/models/purchase_order.dart';
import '../../features/invoices/invoice_providers.dart';
import '../../features/products/products_notifier.dart';
import '../../core/services/csv_export.dart';
import '../../core/widgets/empty_state.dart';

class ReportsScreen extends ConsumerWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Reports'),
          bottom: const TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: 'Pending\nDeliveries'),
              Tab(text: 'Sales by\nCustomer'),
              Tab(text: 'Sales by\nProduct'),
              Tab(text: 'Outstanding\nInvoices'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _PendingDeliveriesReport(),
            _SalesByCustomerReport(),
            _SalesByProductReport(),
            _OutstandingInvoicesReport(),
          ],
        ),
      ),
    );
  }
}

// ─── Date Range Filter Widget ────────────────────────────────────────────────

class _DateRangeFilter extends StatefulWidget {
  final DateTime? from;
  final DateTime? to;
  final ValueChanged<DateTime?> onFromChanged;
  final ValueChanged<DateTime?> onToChanged;

  const _DateRangeFilter({
    this.from,
    this.to,
    required this.onFromChanged,
    required this.onToChanged,
  });

  @override
  State<_DateRangeFilter> createState() => _DateRangeFilterState();
}

class _DateRangeFilterState extends State<_DateRangeFilter> {
  Future<void> _pickFrom() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: widget.from ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked != null) widget.onFromChanged(picked);
  }

  Future<void> _pickTo() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: widget.to ?? DateTime.now(),
      firstDate: widget.from ?? DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked != null) widget.onToChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Text('From:'),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton(
            onPressed: _pickFrom,
            child: Text(
              widget.from != null
                  ? DateFormat.yMMMd().format(widget.from!)
                  : 'Start date',
            ),
          ),
        ),
        const SizedBox(width: 8),
        const Text('To:'),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton(
            onPressed: _pickTo,
            child: Text(
              widget.to != null
                  ? DateFormat.yMMMd().format(widget.to!)
                  : 'End date',
            ),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.close, size: 18),
          onPressed: () {
            widget.onFromChanged(null);
            widget.onToChanged(null);
          },
          tooltip: 'Clear filter',
        ),
      ],
    );
  }
}

// ─── Pending Deliveries ──────────────────────────────────────────────────────

class _PendingDeliveriesReport extends ConsumerStatefulWidget {
  const _PendingDeliveriesReport();

  @override
  ConsumerState<_PendingDeliveriesReport> createState() =>
      _PendingDeliveriesReportState();
}

class _PendingDeliveriesReportState
    extends ConsumerState<_PendingDeliveriesReport> {
  DateTime? _from;
  DateTime? _to;

  @override
  Widget build(BuildContext context) {
    final pos = ref.watch(poNotifierProvider).orders;
    final customers = ref.watch(customersNotifierProvider).customers;
    final customerMap = {for (final c in customers) c.id: c.name};

    var pending = pos.where((po) =>
        po.status == 'Pending' || po.status == 'Partially Delivered').toList();

    // Filter by date range
    if (_from != null) {
      pending = pending.where((po) {
        try {
          return !DateTime.parse(po.orderDate).isBefore(_from!);
        } catch (_) {
          return true;
        }
      }).toList();
    }
    if (_to != null) {
      pending = pending.where((po) {
        try {
          return !DateTime.parse(po.orderDate).isAfter(_to!);
        } catch (_) {
          return true;
        }
      }).toList();
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: _DateRangeFilter(
            from: _from,
            to: _to,
            onFromChanged: (d) => setState(() => _from = d),
            onToChanged: (d) => setState(() => _to = d),
          ),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: TextButton.icon(
              onPressed: () => _exportPendingDeliveries(pending, customerMap),
              icon: const Icon(Icons.download, size: 16),
              label: const Text('Export CSV'),
            ),
          ),
        ),
        Expanded(
          child: pending.isEmpty
              ? const EmptyState(
                  icon: Icons.local_shipping_outlined,
                  message: 'No pending deliveries in this range',
                )
              : ListView.builder(
                  itemCount: pending.length,
                  itemBuilder: (context, index) {
                    final po = pending[index];
                    final name = customerMap[po.customerId] ?? 'Unknown';
                    return Card(
                      margin: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 4),
                      child: ListTile(
                        title: Text('${po.poNumber} — $name'),
                        subtitle: Text('Status: ${po.status}'),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  void _exportPendingDeliveries(
      List<PurchaseOrder> pos, Map<String, String> customerMap) {
    CsvExport.export(
      fileName: 'pending_deliveries',
      headers: ['PO Number', 'Customer', 'Status', 'Order Date'],
      rows: pos.map((po) => [
        po.poNumber,
        customerMap[po.customerId] ?? 'Unknown',
        po.status,
        po.orderDate,
      ]).toList(),
    );
  }
}

// ─── Sales by Customer ──────────────────────────────────────────────────────

class _SalesByCustomerReport extends ConsumerStatefulWidget {
  const _SalesByCustomerReport();

  @override
  ConsumerState<_SalesByCustomerReport> createState() =>
      _SalesByCustomerReportState();
}

class _SalesByCustomerReportState extends ConsumerState<_SalesByCustomerReport> {
  DateTime? _from;
  DateTime? _to;

  @override
  Widget build(BuildContext context) {
    final invoices = ref.watch(invoiceListProvider);
    final customers = ref.watch(customersNotifierProvider).customers;
    final pos = ref.watch(poNotifierProvider).orders;

    var filtered = invoices;
    if (_from != null) {
      filtered = filtered.where((inv) {
        try {
          return !DateTime.parse(inv.invoiceDate).isBefore(_from!);
        } catch (_) {
          return true;
        }
      }).toList();
    }
    if (_to != null) {
      filtered = filtered.where((inv) {
        try {
          return !DateTime.parse(inv.invoiceDate).isAfter(_to!);
        } catch (_) {
          return true;
        }
      }).toList();
    }

    final salesByCustomer = <String, double>{};
    for (final inv in filtered) {
      final po = pos.where((p) => p.id == inv.poId).firstOrNull;
      final customer =
          customers.where((c) => c.id == (po?.customerId ?? '')).firstOrNull;
      final name = customer?.name ?? 'Unknown';
      final amount = double.tryParse(inv.totalAmount) ?? 0;
      salesByCustomer[name] = (salesByCustomer[name] ?? 0) + amount;
    }

    final sorted = salesByCustomer.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: _DateRangeFilter(
            from: _from,
            to: _to,
            onFromChanged: (d) => setState(() => _from = d),
            onToChanged: (d) => setState(() => _to = d),
          ),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: TextButton.icon(
              onPressed: () => CsvExport.export(
                fileName: 'sales_by_customer',
                headers: ['Customer', 'Total Sales'],
                rows: sorted.map((e) => [e.key, e.value.toStringAsFixed(2)]).toList(),
              ),
              icon: const Icon(Icons.download, size: 16),
              label: const Text('Export CSV'),
            ),
          ),
        ),
        Expanded(
          child: sorted.isEmpty
              ? const EmptyState(
                  icon: Icons.people_outline,
                  message: 'No sales data in this range',
                )
              : ListView.builder(
                  itemCount: sorted.length,
                  itemBuilder: (context, index) {
                    final entry = sorted[index];
                    return Card(
                      margin: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 4),
                      child: ListTile(
                        title: Text(entry.key),
                        trailing: Text(
                          entry.value.toStringAsFixed(2),
                          style: Theme.of(context)
                              .textTheme
                              .titleSmall
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

// ─── Sales by Product ───────────────────────────────────────────────────────

class _SalesByProductReport extends ConsumerStatefulWidget {
  const _SalesByProductReport();

  @override
  ConsumerState<_SalesByProductReport> createState() =>
      _SalesByProductReportState();
}

class _SalesByProductReportState extends ConsumerState<_SalesByProductReport> {
  DateTime? _from;
  DateTime? _to;

  @override
  Widget build(BuildContext context) {
    final invoices = ref.watch(invoiceListProvider);
    final products = ref.watch(productsNotifierProvider).products;
    final productMap = {for (final p in products) p.id: p.name};

    var filtered = invoices;
    if (_from != null) {
      filtered = filtered.where((inv) {
        try {
          return !DateTime.parse(inv.invoiceDate).isBefore(_from!);
        } catch (_) {
          return true;
        }
      }).toList();
    }
    if (_to != null) {
      filtered = filtered.where((inv) {
        try {
          return !DateTime.parse(inv.invoiceDate).isAfter(_to!);
        } catch (_) {
          return true;
        }
      }).toList();
    }

    final invoiceIds = filtered.map((i) => i.id).toSet();

    return _SalesByProductBody(
      filteredInvoices: filtered,
      invoiceIds: invoiceIds,
      productMap: productMap,
      from: _from,
      to: _to,
      onFromChanged: (d) => setState(() => _from = d),
      onToChanged: (d) => setState(() => _to = d),
    );
  }
}

class _SalesByProductBody extends ConsumerStatefulWidget {
  final List<dynamic> filteredInvoices;
  final Set<String> invoiceIds;
  final Map<String, String> productMap;
  final DateTime? from;
  final DateTime? to;
  final ValueChanged<DateTime?> onFromChanged;
  final ValueChanged<DateTime?> onToChanged;

  const _SalesByProductBody({
    required this.filteredInvoices,
    required this.invoiceIds,
    required this.productMap,
    this.from,
    this.to,
    required this.onFromChanged,
    required this.onToChanged,
  });

  @override
  ConsumerState<_SalesByProductBody> createState() => _SalesByProductBodyState();
}

class _SalesByProductBodyState extends ConsumerState<_SalesByProductBody> {
  List<MapEntry<String, double>> _salesByProduct = [];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final itemRepo = ref.read(invoiceItemRepositoryProvider);
    final allItems = await itemRepo.loadAll();
    final products = ref.read(productsNotifierProvider).products;
    final productMap = {for (final p in products) p.id: p.name};

    final sales = <String, double>{};
    for (final item in allItems) {
      if (widget.invoiceIds.contains(item.invoiceId)) {
        final qty = double.tryParse(item.quantity) ?? 0;
        final rate = double.tryParse(item.rate) ?? 0;
        final amount = qty * rate;
        final name = productMap[item.productId] ?? 'Unknown';
        sales[name] = (sales[name] ?? 0) + amount;
      }
    }

    final sorted = sales.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

    if (mounted) {
      setState(() {
        _salesByProduct = sorted;
        _loaded = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: _DateRangeFilter(
            from: widget.from,
            to: widget.to,
            onFromChanged: widget.onFromChanged,
            onToChanged: widget.onToChanged,
          ),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: TextButton.icon(
              onPressed: () => CsvExport.export(
                fileName: 'sales_by_product',
                headers: ['Product', 'Total Sales'],
                rows: _salesByProduct.map((e) => [e.key, e.value.toStringAsFixed(2)]).toList(),
              ),
              icon: const Icon(Icons.download, size: 16),
              label: const Text('Export CSV'),
            ),
          ),
        ),
        Expanded(
          child: !_loaded
              ? const Center(child: CircularProgressIndicator())
              : _salesByProduct.isEmpty
                  ? const EmptyState(
                      icon: Icons.inventory_2_outlined,
                      message: 'No sales data in this range',
                    )
                  : ListView.builder(
                      itemCount: _salesByProduct.length,
                      itemBuilder: (context, index) {
                        final entry = _salesByProduct[index];
                        return Card(
                          margin: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 4),
                          child: ListTile(
                            title: Text(entry.key),
                            trailing: Text(
                              entry.value.toStringAsFixed(2),
                              style: Theme.of(context)
                                  .textTheme
                                  .titleSmall
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }
}

// ─── Outstanding Invoices ───────────────────────────────────────────────────

class _OutstandingInvoicesReport extends ConsumerStatefulWidget {
  const _OutstandingInvoicesReport();

  @override
  ConsumerState<_OutstandingInvoicesReport> createState() =>
      _OutstandingInvoicesReportState();
}

class _OutstandingInvoicesReportState
    extends ConsumerState<_OutstandingInvoicesReport> {
  DateTime? _from;
  DateTime? _to;

  @override
  Widget build(BuildContext context) {
    final invoices = ref.watch(invoiceListProvider);
    final pos = ref.watch(poNotifierProvider).orders;

    var unpaid = invoices.where((inv) => inv.status != 'Paid').toList();

    if (_from != null) {
      unpaid = unpaid.where((inv) {
        try {
          return !DateTime.parse(inv.invoiceDate).isBefore(_from!);
        } catch (_) {
          return true;
        }
      }).toList();
    }
    if (_to != null) {
      unpaid = unpaid.where((inv) {
        try {
          return !DateTime.parse(inv.invoiceDate).isAfter(_to!);
        } catch (_) {
          return true;
        }
      }).toList();
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: _DateRangeFilter(
            from: _from,
            to: _to,
            onFromChanged: (d) => setState(() => _from = d),
            onToChanged: (d) => setState(() => _to = d),
          ),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: TextButton.icon(
              onPressed: () {
                final rows = unpaid.map((inv) {
                  final po = pos.where((p) => p.id == inv.poId).firstOrNull;
                  return [
                    inv.invoiceNumber,
                    po?.poNumber ?? '',
                    inv.totalAmount,
                    inv.status,
                  ];
                }).toList();
                CsvExport.export(
                  fileName: 'outstanding_invoices',
                  headers: ['Invoice', 'PO Number', 'Amount', 'Status'],
                  rows: rows,
                );
              },
              icon: const Icon(Icons.download, size: 16),
              label: const Text('Export CSV'),
            ),
          ),
        ),
        Expanded(
          child: unpaid.isEmpty
              ? const EmptyState(
                  icon: Icons.receipt_outlined,
                  message: 'No outstanding invoices in this range',
                )
              : ListView.builder(
                  itemCount: unpaid.length,
                  itemBuilder: (context, index) {
                    final inv = unpaid[index];
                    final po = pos.where((p) => p.id == inv.poId).firstOrNull;
                    return Card(
                      margin: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 4),
                      child: ListTile(
                        title: Text('${inv.invoiceNumber} — PO: ${po?.poNumber ?? ''}'),
                        subtitle: Text('Status: ${inv.status}'),
                        trailing: Text(
                          inv.totalAmount,
                          style: Theme.of(context)
                              .textTheme
                              .titleSmall
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
