import 'dart:developer' as dev;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../app.dart';
import '../../core/exceptions/referential_integrity_exception.dart';
import '../../core/services/bulk_delete.dart';
import '../purchase_orders/po_providers.dart';
import 'customer_repository.dart';
import 'models/customer.dart';

class CustomerListState {
  final List<Customer> customers;
  final bool isLoading;

  /// Set when the last load failed. Screens surface this with a retry instead
  /// of crashing or showing a misleading "no records" state (AGENTS.md §10).
  final String? error;

  const CustomerListState(this.customers, this.isLoading, {this.error});
}

class CustomersNotifier extends StateNotifier<CustomerListState> {
  final CustomerRepository _repo;
  final Ref _ref;

  CustomersNotifier(this._repo, this._ref)
      : super(const CustomerListState([], false));

  Future<void> load() async {
    state = CustomerListState(state.customers, true);
    try {
      final list = await _repo.loadAll();
      state = CustomerListState(list, false);
    } catch (e) {
      dev.log('[Customers] load failed: $e');
      state = CustomerListState(state.customers, false, error: '$e');
    }
  }

  Future<void> add(Customer customer) async {
    final counter = _ref.read(counterHelperProvider);
    final customerCode = await counter.nextSimpleNumber('Customer', 'CUST');
    await _repo.save(customer.copyWith(
      id: customer.id.isEmpty ? const Uuid().v4() : customer.id,
      customerCode: customerCode,
    ));
    await load();
  }

  Future<void> update(Customer customer) async {
    await _repo.update(customer);
    await load();
  }

  /// Blocked when the customer is referenced by any PO (AGENTS.md §10).
  Future<void> delete(String id) async {
    final outcome = await deleteMany([id]);
    final reason = outcome.blocked[id];
    if (reason != null) {
      throw ReferentialIntegrityException(
        'Cannot delete this customer — $reason.',
      );
    }
  }

  /// Deletes several customers, keeping any that a purchase order still points
  /// at and reporting them back rather than failing the whole batch.
  Future<BulkDeleteOutcome> deleteMany(List<String> ids) async {
    if (ids.isEmpty) return const BulkDeleteOutcome();

    // One pass over the PO table for the whole batch.
    final pos = await _ref.read(poRepositoryProvider).loadAll();
    final poCountByCustomer = <String, int>{};
    for (final po in pos) {
      poCountByCustomer[po.customerId] =
          (poCountByCustomer[po.customerId] ?? 0) + 1;
    }

    final deleted = <String>[];
    final blocked = <String, String>{};
    for (final id in ids) {
      final count = poCountByCustomer[id] ?? 0;
      if (count > 0) {
        blocked[id] = 'it is linked to $count purchase order(s)';
        continue;
      }
      try {
        await _repo.delete(id);
        deleted.add(id);
      } catch (e) {
        dev.log('[Customers] delete $id failed: $e');
        blocked[id] = 'it could not be deleted ($e)';
      }
    }

    if (deleted.isNotEmpty) await load();
    return BulkDeleteOutcome(deleted: deleted, blocked: blocked);
  }

  Customer? findById(String id) {
    for (final c in state.customers) {
      if (c.id == id) return c;
    }
    return null;
  }

  /// A duplicate is blocked only when BOTH name AND phone match
  /// (case-insensitive, trimmed) — AGENTS.md §4.
  Customer? findDuplicate(String name, String phone, {String? excludeId}) {
    final normalizedName = name.trim().toLowerCase();
    final normalizedPhone = phone.trim();
    if (normalizedName.isEmpty || normalizedPhone.isEmpty) return null;
    for (final c in state.customers) {
      if (excludeId != null && c.id == excludeId) continue;
      if (c.name.trim().toLowerCase() == normalizedName &&
          c.phone.trim() == normalizedPhone) {
        return c;
      }
    }
    return null;
  }
}

final customerRepositoryProvider = Provider<CustomerRepository>((ref) {
  return CustomerRepository(ref.watch(workbookStoreProvider));
});

final customersNotifierProvider =
    StateNotifierProvider<CustomersNotifier, CustomerListState>((ref) {
  return CustomersNotifier(ref.watch(customerRepositoryProvider), ref);
});
