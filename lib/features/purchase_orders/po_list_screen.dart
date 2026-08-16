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
import '../customers/customers_notifier.dart';
import 'models/purchase_order.dart';
import 'po_providers.dart';

class PoListScreen extends ConsumerStatefulWidget {
  const PoListScreen({super.key});

  @override
  ConsumerState<PoListScreen> createState() => _PoListScreenState();
}

class _PoListScreenState extends ConsumerState<PoListScreen> {
  final _searchController = TextEditingController();
  String _query = '';
  String _statusFilter = 'All';

  final Set<String> _selected = {};
  bool _selecting = false;
  bool _isDeleting = false;

  static const _statuses = ['All', ...PurchaseOrder.statuses];

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(poNotifierProvider.notifier).load();
      if (ref.read(customersNotifierProvider).customers.isEmpty) {
        ref.read(customersNotifierProvider.notifier).load();
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
    // Unselecting the last row leaves selection mode, matching the
    // platform convention.
    if (_selected.isEmpty) _selecting = false;
  });

  void _toggleSelectAll(List<PurchaseOrder> visible) => setState(() {
    if (_selected.length == visible.length) {
      _selected.clear();
      _selecting = false;
    } else {
      _selected
        ..clear()
        ..addAll(visible.map((po) => po.id));
    }
  });

  Future<void> _deleteSelected() async {
    if (_selected.isEmpty || _isDeleting) return;
    final ids = _selected.toList();
    final notifier = ref.read(poNotifierProvider.notifier);

    setState(() => _isDeleting = true);
    try {
      final impact = await notifier.impactFor(ids);
      if (!mounted) return;

      if (impact.isFullyBlocked) {
        showSnackBar(
          context,
          ids.length == 1
              ? 'This order is already invoiced and cannot be deleted.'
              : 'All ${ids.length} selected orders are already invoiced and '
                    'cannot be deleted.',
          isError: true,
        );
        return;
      }

      final confirmed = await confirmBulkDelete(
        context,
        count: ids.length,
        singular: 'this purchase order',
        plural: 'purchase orders',
        consequences: impact.consequences,
      );
      if (!confirmed || !mounted) return;

      final outcome = await notifier.deleteMany(ids);
      if (!mounted) return;
      showSnackBar(
        context,
        outcome.summary('purchase order', 'purchase orders'),
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
    final state = ref.watch(poNotifierProvider);
    final customers = ref.watch(customersNotifierProvider).customers;
    final customerById = {for (final c in customers) c.id: c.name};

    final q = _query.trim().toLowerCase();
    final filtered = state.orders.where((po) {
      final matchesStatus =
          _statusFilter == 'All' || po.status == _statusFilter;
      if (!matchesStatus) return false;
      if (q.isEmpty) return true;
      final name = customerById[po.customerId]?.toLowerCase() ?? '';
      return po.poNumber.toLowerCase().contains(q) || name.contains(q);
    }).toList();

    return PopScope(
      // While selecting, back cancels the selection instead of leaving.
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
            : AppBar(title: const Text('Purchase Orders')),
        drawer: _selecting
            ? null
            : const AppDrawer(currentPath: '/purchase-orders'),
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
                    hintText: 'Search by PO number or customer',
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
                  child: _buildBody(state, filtered, customerById),
                ),
              ),
            ],
          ),
        ),
        floatingActionButton: _selecting
            ? null
            : FloatingActionButton(
                onPressed: () => context.push('/purchase-orders/new'),
                tooltip: 'New purchase order',
                child: const Icon(Icons.add),
              ),
      ),
    );
  }

  Widget _buildBody(
    PoListState state,
    List<PurchaseOrder> filtered,
    Map<String, String> customerById,
  ) {
    final theme = Theme.of(context);
    if (state.isLoading && state.orders.isEmpty) {
      return const LoadingListSkeleton();
    }
    if (state.error != null && state.orders.isEmpty) {
      return EmptyState(
        icon: Icons.cloud_off,
        message: "Couldn't load purchase orders.\n${state.error}",
        ctaLabel: 'Retry',
        onCta: () => ref.read(poNotifierProvider.notifier).load(),
      );
    }
    if (state.orders.isEmpty) {
      return EmptyState(
        icon: Icons.receipt_long_outlined,
        message: 'No purchase orders yet',
        ctaLabel: 'Create your first PO',
        onCta: () => context.push('/purchase-orders/new'),
      );
    }
    if (filtered.isEmpty) {
      return const EmptyState(
        icon: Icons.search_off,
        message: 'No POs match your filter',
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: filtered.length,
      itemBuilder: (context, index) {
        final po = filtered[index];
        final selected = _selected.contains(po.id);
        return Card(
          color: selected ? theme.colorScheme.secondaryContainer : null,
          child: ListTile(
            leading: SelectionLeading(
              selectionMode: _selecting,
              selected: selected,
              child: Hero(
                tag: 'po-${po.id}',
                child: CircleAvatar(
                  backgroundColor: theme.colorScheme.primaryContainer,
                  foregroundColor: theme.colorScheme.onPrimaryContainer,
                  child: const Icon(Icons.receipt_long),
                ),
              ),
            ),
            title: Text(po.poNumber),
            subtitle: Text(
              '${customerById[po.customerId] ?? "Unknown"}'
              '  •  ${_formatDate(po.orderDate)}',
            ),
            trailing: _selecting
                ? null
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [StatusPill(status: po.status)],
                  ),
            onTap: () => _selecting
                ? _toggle(po.id)
                : context.push('/purchase-orders/${po.id}'),
            onLongPress: () =>
                _selecting ? _toggle(po.id) : _startSelection(po.id),
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
