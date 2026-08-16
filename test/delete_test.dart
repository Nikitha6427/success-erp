import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:success_erp/app.dart';
import 'package:success_erp/core/exceptions/referential_integrity_exception.dart';
import 'package:success_erp/features/customers/customers_notifier.dart';
import 'package:success_erp/features/customers/models/customer.dart';
import 'package:success_erp/features/delivery_notes/models/delivery_note.dart';
import 'package:success_erp/features/invoices/models/invoice.dart';
import 'package:success_erp/features/products/models/product.dart';
import 'package:success_erp/features/products/products_notifier.dart';
import 'package:success_erp/features/purchase_orders/models/purchase_order.dart';
import 'package:success_erp/features/invoices/invoice_providers.dart';
import 'package:success_erp/features/purchase_orders/po_providers.dart';

import 'fake_workbook_store.dart';

late FakeWorkbookStore store;
late ProviderContainer container;

Future<void> seed() async {
  store = FakeWorkbookStore();
  container = ProviderContainer(
    overrides: [workbookStoreProvider.overrideWithValue(store)],
  );

  // Two customers: one ordering, one untouched.
  await store.appendRow('Customers',
      const Customer(id: 'cust-busy', name: 'Acme Metals').toMap());
  await store.appendRow('Customers',
      const Customer(id: 'cust-free', name: 'Nobody Ltd').toMap());

  // Two products: one used on an order, one untouched.
  await store.appendRow('Products',
      const Product(id: 'prod-used', name: 'CNC turning', price: '250').toMap());
  await store.appendRow('Products',
      const Product(id: 'prod-free', name: 'Unused widget', price: '10').toMap());

  // po-clean: delivered, never invoiced -> deletable, cascades.
  await store.appendRow(
    'PurchaseOrders',
    const PurchaseOrder(
      id: 'po-clean',
      poNumber: 'PO/S2026-27/1',
      customerId: 'cust-busy',
      orderDate: '2026-05-04T00:00:00.000',
    ).toMap(),
  );
  await store.appendRow(
    'PurchaseOrderItems',
    const PurchaseOrderItem(
      id: 'poi-clean-1',
      poId: 'po-clean',
      productId: 'prod-used',
      quantity: '10',
      rate: '250',
      deliveredQty: '10',
      pendingQty: '0',
    ).toMap(),
  );
  await store.appendRow(
    'PurchaseOrderItems',
    const PurchaseOrderItem(
      id: 'poi-clean-2',
      poId: 'po-clean',
      productId: 'prod-used',
      quantity: '4',
      rate: '250',
      deliveredQty: '0',
      pendingQty: '4',
    ).toMap(),
  );
  await store.appendRow(
    'DeliveryNotes',
    const DeliveryNote(
      id: 'dn-clean',
      dnNumber: 'DN-0001',
      poId: 'po-clean',
      deliveryDate: '2026-05-10T00:00:00.000',
    ).toMap(),
  );
  await store.appendRow(
    'DeliveryNoteItems',
    const DeliveryNoteItem(
      id: 'dni-clean',
      dnId: 'dn-clean',
      poItemId: 'poi-clean-1',
      deliveredQty: '10',
    ).toMap(),
  );

  // po-billed: has an invoice -> must be protected.
  await store.appendRow(
    'PurchaseOrders',
    const PurchaseOrder(
      id: 'po-billed',
      poNumber: 'PO/S2026-27/2',
      customerId: 'cust-busy',
      orderDate: '2026-05-06T00:00:00.000',
      status: PurchaseOrder.statusInvoiced,
    ).toMap(),
  );
  await store.appendRow(
    'PurchaseOrderItems',
    const PurchaseOrderItem(
      id: 'poi-billed',
      poId: 'po-billed',
      productId: 'prod-used',
      quantity: '2',
      rate: '250',
      deliveredQty: '2',
      pendingQty: '0',
    ).toMap(),
  );
  await store.appendRow(
    'DeliveryNotes',
    const DeliveryNote(
      id: 'dn-billed',
      dnNumber: 'DN-0002',
      poId: 'po-billed',
      deliveryDate: '2026-05-11T00:00:00.000',
    ).toMap(),
  );
  await store.appendRow(
    'Invoices',
    const Invoice(
      id: 'inv-1',
      invoiceNumber: 'INV-0001',
      poId: 'po-billed',
      invoiceDate: '2026-05-12T00:00:00.000',
      subtotalAmount: '500.00',
      cgstAmount: '45.00',
      sgstAmount: '45.00',
      totalAmount: '590.00',
    ).toMap(),
  );
  await store.appendRow(
    'InvoiceItems',
    const InvoiceItem(
      id: 'ii-1',
      invoiceId: 'inv-1',
      poItemId: 'poi-billed',
      productId: 'prod-used',
      description: 'CNC turning',
      quantity: '2',
      rate: '250',
      amount: '500.00',
    ).toMap(),
  );
}

List<String> idsIn(String tab, String key) =>
    store.live(tab).map((r) => r[key] ?? '').toList();

void main() {
  setUp(seed);
  tearDown(() => container.dispose());

  group('purchase order deletion', () {
    test('cascades to line items and delivery notes', () async {
      final notifier = container.read(poNotifierProvider.notifier);
      await notifier.load();

      final outcome = await notifier.deleteMany(['po-clean']);

      expect(outcome.deleted, ['po-clean']);
      expect(outcome.blocked, isEmpty);
      expect(idsIn('PurchaseOrders', 'po_id'), ['po-billed']);
      expect(idsIn('PurchaseOrderItems', 'po_item_id'), ['poi-billed']);
      expect(idsIn('DeliveryNotes', 'dn_id'), ['dn-billed']);
      expect(idsIn('DeliveryNoteItems', 'dn_item_id'), isEmpty);
      // The other order is untouched.
      expect(idsIn('Invoices', 'invoice_id'), ['inv-1']);
    });

    test('is blocked by an invoice and changes nothing', () async {
      final notifier = container.read(poNotifierProvider.notifier);
      await notifier.load();

      final outcome = await notifier.deleteMany(['po-billed']);

      expect(outcome.deleted, isEmpty);
      expect(outcome.blocked.keys, ['po-billed']);
      expect(outcome.blocked['po-billed'], contains('invoice'));
      expect(idsIn('PurchaseOrders', 'po_id'),
          containsAll(['po-clean', 'po-billed']));
      expect(idsIn('PurchaseOrderItems', 'po_item_id'), contains('poi-billed'));
      expect(idsIn('DeliveryNotes', 'dn_id'), contains('dn-billed'));
    });

    test('single delete surfaces the block as an exception', () async {
      final notifier = container.read(poNotifierProvider.notifier);
      await notifier.load();

      await expectLater(
        notifier.delete('po-billed'),
        throwsA(isA<ReferentialIntegrityException>()),
      );
      expect(idsIn('PurchaseOrders', 'po_id'), contains('po-billed'));
    });

    test('a mixed batch deletes what it can and reports the rest', () async {
      final notifier = container.read(poNotifierProvider.notifier);
      await notifier.load();

      final outcome = await notifier.deleteMany(['po-clean', 'po-billed']);

      expect(outcome.deletedCount, 1);
      expect(outcome.blockedCount, 1);
      expect(idsIn('PurchaseOrders', 'po_id'), ['po-billed']);
      expect(
        outcome.summary('purchase order', 'purchase orders'),
        '1 purchase order deleted  •  1 kept — '
        'it has 1 invoice(s); delete those first',
      );
    });

    test('impact counts the cascade only for orders that will actually go',
        () async {
      final notifier = container.read(poNotifierProvider.notifier);
      await notifier.load();

      final impact = await notifier.impactFor(['po-clean', 'po-billed']);

      // po-clean's 2 items and 1 DN; po-billed's item and DN are NOT counted
      // because that order is kept.
      expect(impact.lineItems, 2);
      expect(impact.deliveryNotes, 1);
      expect(impact.blockedOrders, 1);
      expect(impact.isFullyBlocked, isFalse);

      final blockedOnly = await notifier.impactFor(['po-billed']);
      expect(blockedOnly.isFullyBlocked, isTrue);
    });

    test('the list reflects the deletion afterwards', () async {
      final notifier = container.read(poNotifierProvider.notifier);
      await notifier.load();
      expect(container.read(poNotifierProvider).orders, hasLength(2));

      await notifier.deleteMany(['po-clean']);

      expect(container.read(poNotifierProvider).orders.single.id, 'po-billed');
    });
  });

  group('customer deletion', () {
    test('keeps customers linked to an order, deletes the rest', () async {
      final notifier = container.read(customersNotifierProvider.notifier);
      await notifier.load();

      final outcome = await notifier.deleteMany(['cust-busy', 'cust-free']);

      expect(outcome.deleted, ['cust-free']);
      expect(outcome.blocked['cust-busy'], contains('purchase order'));
      expect(idsIn('Customers', 'customer_id'), ['cust-busy']);
    });

    test('a referenced customer becomes deletable once its orders go',
        () async {
      await container.read(poNotifierProvider.notifier).load();
      await container
          .read(poNotifierProvider.notifier)
          .deleteMany(['po-clean', 'po-billed']);

      final customers = container.read(customersNotifierProvider.notifier);
      await customers.load();
      // po-billed survives (invoiced), so the customer is still referenced.
      var outcome = await customers.deleteMany(['cust-busy']);
      expect(outcome.deleted, isEmpty);

      // Remove the invoice, then the order, then the customer.
      await store.clearRow('Invoices', 2);
      await container.read(poNotifierProvider.notifier).deleteMany(['po-billed']);
      await customers.load();
      outcome = await customers.deleteMany(['cust-busy']);

      expect(outcome.deleted, ['cust-busy']);
      // cust-free was never part of this batch, so it must survive.
      expect(idsIn('Customers', 'customer_id'), ['cust-free']);
    });

    test('single delete surfaces the block as an exception', () async {
      final notifier = container.read(customersNotifierProvider.notifier);
      await notifier.load();

      await expectLater(
        notifier.delete('cust-busy'),
        throwsA(isA<ReferentialIntegrityException>()),
      );
    });
  });

  group('product deletion', () {
    test('keeps products used on an order, deletes the rest', () async {
      final notifier = container.read(productsNotifierProvider.notifier);
      await notifier.load();

      final outcome = await notifier.deleteMany(['prod-used', 'prod-free']);

      expect(outcome.deleted, ['prod-free']);
      expect(outcome.blocked['prod-used'], contains('purchase order'));
      expect(idsIn('Products', 'product_id'), ['prod-used']);
    });

    test('counts distinct orders, not line items', () async {
      // prod-used appears on two lines of po-clean plus one of po-billed.
      final notifier = container.read(productsNotifierProvider.notifier);
      await notifier.load();

      final outcome = await notifier.deleteMany(['prod-used']);

      expect(outcome.blocked['prod-used'], contains('2 purchase order(s)'));
    });

    test('single delete surfaces the block as an exception', () async {
      final notifier = container.read(productsNotifierProvider.notifier);
      await notifier.load();

      await expectLater(
        notifier.delete('prod-used'),
        throwsA(isA<ReferentialIntegrityException>()),
      );
    });
  });

  group('invoice deletion', () {
    test('removes the invoice and its line items', () async {
      final notifier = container.read(invoiceListProvider.notifier);
      await notifier.load();

      final outcome = await notifier.deleteMany(['inv-1']);

      expect(outcome.deleted, ['inv-1']);
      expect(idsIn('Invoices', 'invoice_id'), isEmpty);
      expect(idsIn('InvoiceItems', 'invoice_item_id'), isEmpty);
    });

    test('rolls the purchase order status back off Invoiced', () async {
      final pos = container.read(poNotifierProvider.notifier);
      await pos.load();
      expect(
        container.read(poNotifierProvider).orders
            .firstWhere((p) => p.id == 'po-billed')
            .status,
        PurchaseOrder.statusInvoiced,
      );

      await container.read(invoiceListProvider.notifier).load();
      await container.read(invoiceListProvider.notifier).delete('inv-1');

      // Everything ordered was delivered, nothing is billed any more.
      expect(
        container.read(poNotifierProvider).orders
            .firstWhere((p) => p.id == 'po-billed')
            .status,
        PurchaseOrder.statusDelivered,
      );
    });

    test('frees the quantity so it can be invoiced again', () async {
      final itemRepo = container.read(invoiceItemRepositoryProvider);
      expect((await itemRepo.invoicedQtyByPoItem())['poi-billed'], 2);

      await container.read(invoiceListProvider.notifier).load();
      await container.read(invoiceListProvider.notifier).delete('inv-1');

      expect((await itemRepo.invoicedQtyByPoItem())['poi-billed'], isNull);
    });

    test('a Paid invoice is deletable, and the dialog is told so', () async {
      await store.updateRow(
        'Invoices',
        2,
        const Invoice(
          id: 'inv-1',
          invoiceNumber: 'INV-0001',
          poId: 'po-billed',
          invoiceDate: '2026-05-12T00:00:00.000',
          totalAmount: '590.00',
          status: Invoice.statusPaid,
        ).toMap(),
      );

      final notifier = container.read(invoiceListProvider.notifier);
      await notifier.load();

      final impact = await notifier.impactFor(['inv-1']);
      expect(impact.paidInvoices, 1);
      expect(impact.lineItems, 1);
      expect(impact.affectedOrders, 1);
      expect(impact.consequences.join(' '), contains('PAID'));

      expect((await notifier.deleteMany(['inv-1'])).deleted, ['inv-1']);
    });
  });

  group('deleting an invoice unblocks its purchase order', () {
    test('the full chain: PO blocked -> delete invoice -> PO deletes',
        () async {
      final pos = container.read(poNotifierProvider.notifier);
      await pos.load();

      // 1. The order cannot be deleted while it is invoiced.
      var outcome = await pos.deleteMany(['po-billed']);
      expect(outcome.deleted, isEmpty);
      expect(outcome.blocked['po-billed'], contains('invoice'));
      expect(idsIn('PurchaseOrders', 'po_id'), contains('po-billed'));

      // 2. Delete the invoice that was blocking it.
      final invoices = container.read(invoiceListProvider.notifier);
      await invoices.load();
      expect((await invoices.deleteMany(['inv-1'])).deleted, ['inv-1']);

      // 3. Now the same delete succeeds, and cascades as normal.
      await pos.load();
      outcome = await pos.deleteMany(['po-billed']);
      expect(outcome.deleted, ['po-billed']);
      expect(outcome.blocked, isEmpty);
      expect(idsIn('PurchaseOrders', 'po_id'), ['po-clean']);
      expect(idsIn('PurchaseOrderItems', 'po_item_id'),
          ['poi-clean-1', 'poi-clean-2']);
      expect(idsIn('DeliveryNotes', 'dn_id'), ['dn-clean']);
    });

    test('impact stops reporting the order as blocked afterwards', () async {
      final pos = container.read(poNotifierProvider.notifier);
      await pos.load();
      expect((await pos.impactFor(['po-billed'])).isFullyBlocked, isTrue);

      await container.read(invoiceListProvider.notifier).load();
      await container.read(invoiceListProvider.notifier).delete('inv-1');

      final impact = await pos.impactFor(['po-billed']);
      expect(impact.isFullyBlocked, isFalse);
      expect(impact.blockedOrders, 0);
      expect(impact.deletableOrders, 1);
    });
  });

  group('an order with no line items is still deletable', () {
    test('a batch mixing an empty order with an invoiced one deletes the empty '
        'one', () async {
      // Regression: isFullyBlocked was derived from cascade row counts, so an
      // empty-but-deletable order alongside an invoiced one made the whole
      // selection look blocked and nothing was deleted.
      await store.appendRow(
        'PurchaseOrders',
        const PurchaseOrder(
          id: 'po-empty',
          poNumber: 'PO/S2026-27/3',
          customerId: 'cust-busy',
          orderDate: '2026-05-08T00:00:00.000',
        ).toMap(),
      );

      final pos = container.read(poNotifierProvider.notifier);
      await pos.load();

      final impact = await pos.impactFor(['po-empty', 'po-billed']);
      expect(impact.lineItems, 0);
      expect(impact.deliveryNotes, 0);
      expect(impact.blockedOrders, 1);
      expect(impact.deletableOrders, 1);
      expect(impact.isFullyBlocked, isFalse,
          reason: 'po-empty is deletable, so the batch is not fully blocked');

      final outcome = await pos.deleteMany(['po-empty', 'po-billed']);
      expect(outcome.deleted, ['po-empty']);
      expect(outcome.blockedCount, 1);
    });

    test('an empty order on its own deletes cleanly', () async {
      await store.appendRow(
        'PurchaseOrders',
        const PurchaseOrder(
          id: 'po-empty',
          poNumber: 'PO/S2026-27/3',
          customerId: 'cust-free',
          orderDate: '2026-05-08T00:00:00.000',
        ).toMap(),
      );
      final pos = container.read(poNotifierProvider.notifier);
      await pos.load();

      final impact = await pos.impactFor(['po-empty']);
      expect(impact.isFullyBlocked, isFalse);
      expect((await pos.deleteMany(['po-empty'])).deleted, ['po-empty']);
    });
  });

  group('deleting blanks rows in place', () {
    test('surviving rows keep their identity after several deletions',
        () async {
      final notifier = container.read(poNotifierProvider.notifier);
      await notifier.load();

      // Delete the FIRST purchase-order item row, then verify the second one is
      // still addressable — a row-shifting delete would corrupt this.
      await notifier.deleteMany(['po-clean']);
      await notifier.load();

      final items = await container
          .read(poItemRepositoryProvider)
          .loadByPoId('po-billed');
      expect(items.single.id, 'poi-billed');
      expect(items.single.quantity, '2');
    });
  });
}
