import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../app.dart';
import '../../features/purchase_orders/po_providers.dart';
import 'customer_repository.dart';
import 'models/customer.dart';

class CustomerListState {
  final List<Customer> customers;
  final bool isLoading;

  const CustomerListState(this.customers, this.isLoading);
}

class CustomersNotifier extends StateNotifier<CustomerListState> {
  final CustomerRepository _repo;
  final Ref _ref;

  CustomersNotifier(this._repo, this._ref)
      : super(const CustomerListState([], false));

  Future<void> load() async {
    state = CustomerListState(state.customers, true);
    final list = await _repo.loadAll();
    state = CustomerListState(list, false);
  }

  Future<void> add(Customer customer) async {
    final counter = _ref.read(counterHelperProvider);
    final customerCode = await counter.nextNumber('Customer');
    final toSave = customer.copyWith(
      id: customer.id.isEmpty ? const Uuid().v4() : customer.id,
      customerCode: customerCode,
    );
    await _repo.save(toSave);
    await load();
  }

  Future<void> update(Customer customer) async {
    await _repo.update(customer);
    await load();
  }

  Future<void> delete(String id) async {
    final poRepo = _ref.read(poRepositoryProvider);
    final poIds = await poRepo.poIdsForCustomer(id);
    if (poIds.isNotEmpty) {
      throw Exception('Cannot delete this customer — it is linked to ${poIds.length} purchase order(s). Delete those first.');
    }
    await _repo.delete(id);
    await load();
  }

  Customer? findById(String id) {
    for (final c in state.customers) {
      if (c.id == id) return c;
    }
    return null;
  }

  /// Returns the existing customer with matching name+phone, or null.
  /// Excludes [excludeId] when editing.
  Customer? findDuplicate(String name, String phone, {String? excludeId}) {
    final normalizedName = name.trim().toLowerCase();
    final normalizedPhone = phone.trim();
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
  return CustomerRepository(ref.read(sheetsServiceProvider));
});

final customersNotifierProvider =
    StateNotifierProvider<CustomersNotifier, CustomerListState>((ref) {
  return CustomersNotifier(ref.read(customerRepositoryProvider), ref);
});
