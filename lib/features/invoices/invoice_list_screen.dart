import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../core/widgets/responsive_container.dart';
import '../../core/widgets/app_drawer.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/loading_list_skeleton.dart';
import '../../core/widgets/selection_app_bar.dart';
import '../../core/widgets/snack_bar_helper.dart';
import '../../core/widgets/status_pill.dart';
import '../purchase_orders/po_providers.dart';
import 'models/invoice.dart';
import 'invoice_providers.dart';

class InvoiceListScreen extends ConsumerStatefulWidget {
  const InvoiceListScreen({super.key});

  @override
  ConsumerState<InvoiceListScreen> createState() => _InvoiceListScreenState();
}

class _InvoiceListScreenState extends ConsumerState<InvoiceListScreen> {
  String _statusFilter = 'All';
  final _searchController = TextEditingController();
  String _query = '';

  final Set<String> _selected = {};
  bool _selecting = false;
  bool _isDeleting = false;

  static const _statuses = ['All', Invoice.statusPending, Invoice.statusPaid];

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(invoiceListProvider.notifier).load();
      if (ref.read(poNotifierProvider).orders.isEmpty) {
        ref.read(poNotifierProvider.notifier).load();
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // ── Selection ─────────────────────────────────────────────────────────────

  void _exitSelection() => setState(() {
    _selecting = false;
    _selected.clear();
  });

  void _startSelection(String id) => setState(() {
    _selecting = true;
    _selected.add(id);
  });

  void _toggle(String id) => setState(() {
    if (!_selected.remove(id)) _selected.add(id);
    if (_selected.isEmpty) _selecting = false;
  });

  void _toggleSelectAll(List<Invoice> visible) => setState(() {
    if (_selected.length == visible.length) {
      _selected.clear();
      _selecting = false;
    } else {
      _selected
        ..clear()
        ..addAll(visible.map((i) => i.id));
    }
  });

  Future<void> _deleteSelected() async {
    if (_selected.isEmpty || _isDeleting) return;
    final ids = _selected.toList();
    final notifier = ref.read(invoiceListProvider.notifier);

    setState(() => _isDeleting = true);
    try {
      final impact = await notifier.impactFor(ids);
      if (!mounted) return;

      final confirmed = await confirmBulkDelete(
        context,
        count: ids.length,
        singular: 'this invoice',
        plural: 'invoices',
        consequences: impact.consequences,
      );
      if (!confirmed || !mounted) return;

      final outcome = await notifier.deleteMany(ids);
      if (!mounted) return;
      showSnackBar(
        context,
        outcome.summary('invoice', 'invoices'),
        isError: outcome.deletedCount == 0,
      );
      _exitSelection();
    } catch (e) {
      if (mounted) showSnackBar(context, 'Delete failed: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isDeleting = false);
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = ref.watch(invoiceListProvider);
    final pos = ref.watch(poNotifierProvider).orders;
    final poNumberById = {for (final po in pos) po.id: po.poNumber};

    final q = _query.trim().toLowerCase();
    final filtered = state.invoices.where((inv) {
      final matchesStatus =
          _statusFilter == 'All' || inv.status == _statusFilter;
      if (!matchesStatus) return false;
      if (q.isEmpty) return true;
      final poNum = poNumberById[inv.poId]?.toLowerCase() ?? '';
      return inv.invoiceNumber.toLowerCase().contains(q) || poNum.contains(q);
    }).toList();

    return PopScope(
      canPop: !_selecting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _selecting) _exitSelection();
      },
      child: Scaffold(
        appBar: _selecting
            ? SelectionAppBar(
                selectedCount: _selected.length,
                totalCount: filtered.length,
                onClose: _exitSelection,
                onToggleSelectAll: () => _toggleSelectAll(filtered),
                onDelete: _selected.isEmpty || _isDeleting
                    ? null
                    : _deleteSelected,
              )
            : AppBar(title: const Text('Invoices')),
        drawer: _selecting ? null : const AppDrawer(currentPath: '/invoices'),
        body: ResponsiveContainer(
          child: Column(
            children: [
              if (_isDeleting) const LinearProgressIndicator(),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: TextField(
                  controller: _searchController,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Search by invoice or PO number',
                  ),
                  onChanged: (v) => setState(() => _query = v),
                ),
              ),
              SizedBox(
                height: 40,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _statuses.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (context, i) {
                    final s = _statuses[i];
                    return FilterChip(
                      label: Text(s),
                      selected: _statusFilter == s,
                      onSelected: (_) => setState(() => _statusFilter = s),
                      showCheckmark: false,
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: _buildBody(state, filtered, poNumberById, theme),
                ),
              ),
            ],
          ),
        ),
        floatingActionButton: _selecting
            ? null
            : FloatingActionButton(
                onPressed: () => context.push('/invoices/new'),
                tooltip: 'Create new invoice',
                child: const Icon(Icons.add),
              ),
      ),
    );
  }

  Widget _buildBody(
    InvoiceListState state,
    List<Invoice> filtered,
    Map<String, String> poNumberById,
    ThemeData theme,
  ) {
    if (state.isLoading && state.invoices.isEmpty) {
      return const LoadingListSkeleton();
    }
    if (state.error != null && state.invoices.isEmpty) {
      return EmptyState(
        icon: Icons.cloud_off,
        message: "Couldn't load invoices.\n${state.error}",
        ctaLabel: 'Retry',
        onCta: () => ref.read(invoiceListProvider.notifier).load(),
      );
    }
    if (state.invoices.isEmpty) {
      return EmptyState(
        icon: Icons.receipt_outlined,
        message: 'No invoices yet',
        ctaLabel: 'Create your first invoice',
        onCta: () => context.push('/invoices/new'),
      );
    }
    if (filtered.isEmpty) {
      return const EmptyState(
        icon: Icons.search_off,
        message: 'No invoices match this filter',
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: filtered.length,
      itemBuilder: (context, index) {
        final inv = filtered[index];
        final poNumber = poNumberById[inv.poId] ?? '';
        final selected = _selected.contains(inv.id);
        return Card(
          color: selected ? theme.colorScheme.secondaryContainer : null,
          child: ListTile(
            leading: SelectionLeading(
              selectionMode: _selecting,
              selected: selected,
              child: CircleAvatar(
                backgroundColor: theme.colorScheme.primaryContainer,
                foregroundColor: theme.colorScheme.onPrimaryContainer,
                child: const Icon(Icons.receipt_outlined),
              ),
            ),
            title: Hero(
              tag: 'invoice-${inv.id}',
              child: Material(
                color: Colors.transparent,
                child: Text(inv.invoiceNumber),
              ),
            ),
            subtitle: Text(
              [
                if (poNumber.isNotEmpty) 'PO: $poNumber',
                _formatDate(inv.invoiceDate),
              ].where((s) => s.isNotEmpty).join('  •  '),
            ),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  inv.totalAmount,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                StatusPill(status: inv.status),
              ],
            ),
            onTap: () => _selecting
                ? _toggle(inv.id)
                : context.push('/invoices/${inv.id}'),
            onLongPress: () =>
                _selecting ? _toggle(inv.id) : _startSelection(inv.id),
          ),
        );
      },
    );
  }

  String _formatDate(String isoDate) {
    if (isoDate.isEmpty) return '';
    try {
      return DateFormat.yMMMd().format(DateTime.parse(isoDate));
    } catch (_) {
      return isoDate;
    }
  }
}
