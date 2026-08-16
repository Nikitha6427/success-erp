import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:success_erp/app.dart';
import 'package:success_erp/core/exceptions/conflict_exception.dart';
import 'package:success_erp/core/services/counter_helper.dart';
import 'package:success_erp/core/services/invoice_math.dart';
import 'package:success_erp/core/services/microsoft_auth.dart';
import 'package:success_erp/core/services/onedrive_excel_service.dart';
import 'package:success_erp/core/services/workbook_store.dart';
import 'package:success_erp/features/customers/customer_repository.dart';
import 'package:success_erp/features/customers/customers_notifier.dart';
import 'package:success_erp/features/customers/models/customer.dart';
import 'package:success_erp/features/delivery_notes/models/delivery_note.dart';
import 'package:success_erp/features/invoices/invoice_providers.dart';
import 'package:success_erp/features/invoices/models/invoice.dart';
import 'package:success_erp/features/products/models/product.dart';
import 'package:success_erp/features/products/products_notifier.dart';
import 'package:success_erp/features/purchase_orders/models/purchase_order.dart';
import 'package:success_erp/features/delivery_notes/dn_providers.dart';
import 'package:success_erp/features/purchase_orders/po_providers.dart';

import 'fake_graph.dart';

/// The repository layer and business logic, driven over the real
/// [OneDriveExcelService]. The migration was left until last so this could be
/// proved rather than assumed: nothing above the store interface should be able
/// to tell which cloud it is talking to.
late FakeGraph graph;
late OneDriveExcelService store;
late ProviderContainer container;

Future<void> boot() async {
  graph = FakeGraph();
  graph.seedExistingWorkbook({
    for (final t in WorkbookSchema.tableNames) t: WorkbookSchema.headersOf(t),
  });
  store = OneDriveExcelService(
    httpClient: graph.client,
    auth: MicrosoftAuth(
      httpClient: graph.client,
      secrets: InMemorySecretStore({'ms_refresh_token': 'STORED'}),
    ),
  );
  await store.restoreSession();
  container = ProviderContainer(
    overrides: [workbookStoreProvider.overrideWithValue(store)],
  );
}

Future<List<String>> idsIn(String table, String key) async {
  final rows = await store.getAllRows(table);
  return rows
      .map((r) => r[key] ?? '')
      .where((id) => id.isNotEmpty)
      .toList();
}

void main() {
  setUp(boot);
  tearDown(() => container.dispose());

  group('repository round-trip over OneDrive', () {
    test('saves and reloads every field', () async {
      final repo = CustomerRepository(store);
      const customer = Customer(
        id: 'c1',
        customerCode: 'CUST-0001',
        name: 'Acme Metals',
        phone: '9876543210',
        street: '14 Foundry Lane',
        cityDistrict: 'Bengaluru',
        state: 'Karnataka',
        country: 'India',
        pincode: '560058',
        gstNumber: 'GST1',
        updatedAt: 'stamp-1',
      );

      expect(await repo.save(customer), 2);

      final loaded = (await repo.loadAll()).single;
      expect(loaded.name, 'Acme Metals');
      expect(loaded.street, '14 Foundry Lane');
      expect(loaded.pincode, '560058');
      expect(loaded.gstNumber, 'GST1');
    });

    test('the id -> row index survives blanked rows', () async {
      final repo = CustomerRepository(store);
      await repo.save(const Customer(id: 'a', name: 'Ann', updatedAt: 's'));
      await repo.save(const Customer(id: 'b', name: 'Bob', updatedAt: 's'));
      await repo.save(const Customer(id: 'c', name: 'Cat', updatedAt: 's'));

      await repo.delete('b');
      await repo.loadAll();

      // Cat is physically the third data row; the index must still find it.
      expect(repo.getRowIndex('c'), 4);
      await repo.update(const Customer(id: 'c', name: 'Cathy', updatedAt: 's'));

      final names = (await repo.loadAll()).map((c) => c.name).toList();
      expect(names, ['Ann', 'Cathy']);
    });
  });

  group('optimistic locking over OneDrive (AGENTS.md §3)', () {
    test('a clean update succeeds and refreshes the stamp', () async {
      final repo = CustomerRepository(store);
      await repo.save(const Customer(id: 'c1', name: 'Acme', updatedAt: 's1'));
      await repo.loadAll();

      await repo.update(const Customer(id: 'c1', name: 'Acme Renamed'));

      final loaded = (await repo.loadAll()).single;
      expect(loaded.name, 'Acme Renamed');
      expect(loaded.updatedAt, isNot('s1'));
      expect(loaded.updatedAt, isNotEmpty);
    });

    test('a concurrent edit from another device is refused', () async {
      final repo = CustomerRepository(store);
      await repo.save(const Customer(id: 'c1', name: 'Acme', updatedAt: 's1'));
      await repo.loadAll();

      // Another device writes the same row behind our back.
      final headers = store.headersFor('Customers');
      final row = List<String>.from(graph.rowsOf('Customers')[0]);
      row[headers.indexOf('updated_at')] = 'someone-else';
      row[headers.indexOf('name')] = 'Changed Elsewhere';
      graph.tableRows['Customers']![0] = row;

      await expectLater(
        repo.update(const Customer(id: 'c1', name: 'My Edit')),
        throwsA(isA<ConflictException>()),
      );

      // The other device's write must be intact — ours was abandoned.
      expect((await repo.loadAll()).single.name, 'Changed Elsewhere');
    });

    test('tables with no updated_at column are not locked', () async {
      // DeliveryNotes has no updated_at, so it must not attempt a lock check.
      final dnRepo = container.read(dnRepositoryProvider);
      await dnRepo.save(const DeliveryNote(
        id: 'dn1',
        dnNumber: 'DN-0001',
        poId: 'po1',
        deliveryDate: '2026-05-10T00:00:00.000',
      ));
      await dnRepo.loadAll();
      expect(dnRepo.hasOptimisticLock, isFalse);
    });
  });

  group('counters over OneDrive', () {
    test('PO numbering keeps independent per-(category, FY) sequences',
        () async {
      final counter = CounterHelper(store);

      expect(
        await counter.nextPoNumber(
            category: 'Sales', orderDate: DateTime(2026, 5, 4)),
        'PO/S2026-27/1',
      );
      expect(
        await counter.nextPoNumber(
            category: 'Sales', orderDate: DateTime(2026, 6, 1)),
        'PO/S2026-27/2',
      );
      expect(
        await counter.nextPoNumber(
            category: 'Labour', orderDate: DateTime(2026, 6, 1)),
        'PO/L2026-27/1',
      );
      expect(
        await counter.nextPoNumber(
            category: 'Sales', orderDate: DateTime(2027, 4, 1)),
        'PO/S2027-28/1',
      );

      // Three distinct counter rows, updated in place rather than appended.
      expect(await idsIn('Counters', 'entity_name'), hasLength(3));
    });
  });

  group('order-to-cash over OneDrive', () {
    Future<void> seedOrder() async {
      final customers = container.read(customersNotifierProvider.notifier);
      final products = container.read(productsNotifierProvider.notifier);
      await customers.add(const Customer(id: 'c1', name: 'Acme Metals'));
      await products.add(const Product(
        id: 'p1',
        name: 'CNC turning',
        category: Product.categorySales,
        price: '250',
      ));

      final poRepo = container.read(poRepositoryProvider);
      final poItemRepo = container.read(poItemRepositoryProvider);
      await poRepo.save(const PurchaseOrder(
        id: 'po1',
        poNumber: 'PO/S2026-27/1',
        customerId: 'c1',
        orderDate: '2026-05-04T00:00:00.000',
      ));
      await poItemRepo.save(const PurchaseOrderItem(
        id: 'poi1',
        poId: 'po1',
        productId: 'p1',
        quantity: '10',
        rate: '250',
        pendingQty: '10',
        updatedAt: 's',
      ));
    }

    test('delivering part of an order updates quantities and status', () async {
      await seedOrder();
      final poRepo = container.read(poRepositoryProvider);
      final poItemRepo = container.read(poItemRepositoryProvider);

      final item = (await poItemRepo.loadByPoId('po1')).single;
      await poItemRepo.update(item.copyWith(deliveredQty: '4', pendingQty: '6'));

      final items = await poItemRepo.loadByPoId('po1');
      expect(InvoiceMath.statusAfterDelivery(items),
          PurchaseOrder.statusPartiallyDelivered);

      final po = (await poRepo.loadAll()).single;
      await poRepo.update(
          po.copyWith(status: PurchaseOrder.statusPartiallyDelivered));
      expect((await poRepo.loadAll()).single.status,
          PurchaseOrder.statusPartiallyDelivered);
    });

    test('invoiceable quantity is delivered minus invoiced, per line item',
        () async {
      await seedOrder();
      final poItemRepo = container.read(poItemRepositoryProvider);
      final invoiceItemRepo = container.read(invoiceItemRepositoryProvider);

      final item = (await poItemRepo.loadByPoId('po1')).single;
      await poItemRepo.update(item.copyWith(deliveredQty: '6', pendingQty: '4'));

      await invoiceItemRepo.save(const InvoiceItem(
        id: 'ii1',
        invoiceId: 'inv1',
        poItemId: 'poi1',
        productId: 'p1',
        description: 'CNC turning',
        quantity: '2',
        rate: '250',
        amount: '500.00',
      ));

      final invoiced = await invoiceItemRepo.invoicedQtyByPoItem();
      final refreshed = (await poItemRepo.loadByPoId('po1')).single;

      expect(
        InvoiceMath.invoiceableQty(
            poItem: refreshed, invoicedByPoItem: invoiced),
        4,
      );
      // Distinct from pending quantity, which is also 4 here by coincidence of
      // the numbers — check the derivation, not the value.
      expect(invoiced['poi1'], 2);
      expect(refreshed.delivered, 6);
    });

    test('deleting an invoice rolls the order status back', () async {
      await seedOrder();
      final poRepo = container.read(poRepositoryProvider);
      final poItemRepo = container.read(poItemRepositoryProvider);
      final invoiceRepo = container.read(invoiceRepositoryProvider);
      final invoiceItemRepo = container.read(invoiceItemRepositoryProvider);

      // Fully delivered and fully invoiced.
      final item = (await poItemRepo.loadByPoId('po1')).single;
      await poItemRepo.update(item.copyWith(deliveredQty: '10', pendingQty: '0'));
      final po = (await poRepo.loadAll()).single;
      await poRepo.update(po.copyWith(status: PurchaseOrder.statusInvoiced));

      await invoiceRepo.save(const Invoice(
        id: 'inv1',
        invoiceNumber: 'INV-0001',
        poId: 'po1',
        invoiceDate: '2026-06-01T00:00:00.000',
        totalAmount: '2950.00',
      ));
      await invoiceItemRepo.save(const InvoiceItem(
        id: 'ii1',
        invoiceId: 'inv1',
        poItemId: 'poi1',
        productId: 'p1',
        description: 'CNC turning',
        quantity: '10',
        rate: '250',
        amount: '2500.00',
      ));

      final invoices = container.read(invoiceListProvider.notifier);
      await invoices.load();
      await container.read(poNotifierProvider.notifier).load();

      await invoices.delete('inv1');

      expect(await idsIn('Invoices', 'invoice_id'), isEmpty);
      expect(await idsIn('InvoiceItems', 'invoice_item_id'), isEmpty);
      expect(
        container.read(poNotifierProvider).orders.single.status,
        PurchaseOrder.statusDelivered,
      );
    });

    test('deleting an order cascades and blanks rows rather than shifting them',
        () async {
      await seedOrder();
      final poItemRepo = container.read(poItemRepositoryProvider);
      await poItemRepo.save(const PurchaseOrderItem(
        id: 'poi2',
        poId: 'po1',
        productId: 'p1',
        quantity: '5',
        rate: '250',
        pendingQty: '5',
        updatedAt: 's',
      ));

      final dnRepo = container.read(dnRepositoryProvider);
      await dnRepo.save(const DeliveryNote(
        id: 'dn1',
        dnNumber: 'DN-0001',
        poId: 'po1',
        deliveryDate: '2026-05-10T00:00:00.000',
      ));

      final pos = container.read(poNotifierProvider.notifier);
      await pos.load();
      final outcome = await pos.deleteMany(['po1']);

      expect(outcome.deleted, ['po1']);
      expect(await idsIn('PurchaseOrders', 'po_id'), isEmpty);
      expect(await idsIn('PurchaseOrderItems', 'po_item_id'), isEmpty);
      expect(await idsIn('DeliveryNotes', 'dn_id'), isEmpty);

      // The rows are still physically there, blanked — never DELETEd, which
      // would have shifted indices mid-cascade.
      expect(graph.rowsOf('PurchaseOrderItems'), hasLength(2));
      expect(
        graph.requestLog.any((r) => r.startsWith('DELETE') && r.contains('rows')),
        isFalse,
      );
    });

    test('a customer with an order cannot be deleted, and can be after',
        () async {
      await seedOrder();
      final customers = container.read(customersNotifierProvider.notifier);
      await customers.load();

      var outcome = await customers.deleteMany(['c1']);
      expect(outcome.deleted, isEmpty);
      expect(outcome.blocked['c1'], contains('purchase order'));

      final pos = container.read(poNotifierProvider.notifier);
      await pos.load();
      await pos.deleteMany(['po1']);

      await customers.load();
      outcome = await customers.deleteMany(['c1']);
      expect(outcome.deleted, ['c1']);
    });
  });
}
