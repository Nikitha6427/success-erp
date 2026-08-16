import 'package:flutter_test/flutter_test.dart';
import 'package:success_erp/core/services/workbook_store.dart';
import 'package:success_erp/features/customers/models/customer.dart';
import 'package:success_erp/features/delivery_notes/models/delivery_note.dart';
import 'package:success_erp/features/invoices/models/invoice.dart';
import 'package:success_erp/features/products/models/product.dart';
import 'package:success_erp/features/purchase_orders/models/purchase_order.dart';
import 'package:success_erp/features/settings/models/company_profile.dart';

/// Every model must write exactly the columns its table declares. A typo here
/// used to mean a silently blank column or, worse, a value landing in the wrong
/// field.
void expectKeysMatchTable(String tab, Map<String, String> map) {
  final headers = WorkbookSchema.headersOf(tab);
  expect(
    map.keys.toSet(),
    headers.toSet(),
    reason: '$tab: model keys do not match the declared columns',
  );
}

void main() {
  group('models write exactly their declared columns', () {
    test('Customers', () {
      expectKeysMatchTable('Customers', const Customer(id: 'c', name: 'n').toMap());
    });
    test('Products', () {
      expectKeysMatchTable('Products', const Product(id: 'p', name: 'n').toMap());
    });
    test('PurchaseOrders', () {
      expectKeysMatchTable(
        'PurchaseOrders',
        const PurchaseOrder(
          id: 'po',
          poNumber: 'PO/S2026-27/1',
          customerId: 'c',
          orderDate: '',
        ).toMap(),
      );
    });
    test('PurchaseOrderItems', () {
      expectKeysMatchTable(
        'PurchaseOrderItems',
        const PurchaseOrderItem(
          id: 'i',
          poId: 'po',
          productId: 'p',
          quantity: '1',
          rate: '1',
        ).toMap(),
      );
    });
    test('DeliveryNotes', () {
      expectKeysMatchTable(
        'DeliveryNotes',
        const DeliveryNote(
          id: 'd',
          dnNumber: 'DN-0001',
          poId: 'po',
          deliveryDate: '',
        ).toMap(),
      );
    });
    test('DeliveryNoteItems', () {
      expectKeysMatchTable(
        'DeliveryNoteItems',
        const DeliveryNoteItem(
          id: 'di',
          dnId: 'd',
          poItemId: 'i',
          deliveredQty: '1',
        ).toMap(),
      );
    });
    test('Invoices', () {
      expectKeysMatchTable(
        'Invoices',
        const Invoice(
          id: 'inv',
          invoiceNumber: 'INV-0001',
          poId: 'po',
          invoiceDate: '',
        ).toMap(),
      );
    });
    test('InvoiceItems', () {
      expectKeysMatchTable(
        'InvoiceItems',
        const InvoiceItem(
          id: 'ii',
          invoiceId: 'inv',
          description: 'd',
          amount: '0',
        ).toMap(),
      );
    });
    test('CompanyProfile', () {
      expectKeysMatchTable('CompanyProfile', const CompanyProfile().toMap());
    });
  });

  group('round-tripping through the row map preserves every field', () {
    test('Customer keeps the address split and all three tax numbers', () {
      const original = Customer(
        id: 'c1',
        customerCode: 'CUST-0007',
        name: 'Acme Metals',
        phone: '9876543210',
        email: 'buy@acme.example',
        street: '14 Foundry Lane',
        area: 'Peenya',
        cityDistrict: 'Bengaluru',
        state: 'Karnataka',
        country: 'India',
        pincode: '560058',
        gstNumber: 'GST1',
        tinNumber: 'TIN1',
        cstNumber: 'CST1',
        createdAt: 'c',
        updatedAt: 'u',
      );
      final restored = Customer.fromMap(original.toMap());

      expect(restored.street, '14 Foundry Lane');
      expect(restored.area, 'Peenya');
      expect(restored.cityDistrict, 'Bengaluru');
      expect(restored.state, 'Karnataka');
      expect(restored.pincode, '560058');
      expect(restored.gstNumber, 'GST1');
      expect(restored.tinNumber, 'TIN1');
      expect(restored.cstNumber, 'CST1');
      expect(restored.customerCode, 'CUST-0007');
      // The internal id is separate from the display code.
      expect(restored.id, 'c1');
    });

    test('PurchaseOrder keeps the client references', () {
      const original = PurchaseOrder(
        id: 'po1',
        poNumber: 'PO/L2026-27/73',
        customerId: 'c1',
        orderDate: '2026-05-04T00:00:00.000',
        clientPoNumber: 'ACME/PO/912',
        clientPoDate: '2026-05-01T00:00:00.000',
        clientDeliveryNoteNumber: 'ACME/DC/55',
        clientDeliveryNoteDate: '2026-05-02T00:00:00.000',
        status: PurchaseOrder.statusPartiallyDelivered,
      );
      final restored = PurchaseOrder.fromMap(original.toMap());

      expect(restored.clientPoNumber, 'ACME/PO/912');
      expect(restored.clientDeliveryNoteNumber, 'ACME/DC/55');
      expect(restored.status, PurchaseOrder.statusPartiallyDelivered);
    });

    test('Invoice keeps the rate actually used, not just the amounts', () {
      const original = Invoice(
        id: 'inv1',
        invoiceNumber: 'INV-0003',
        poId: 'po1',
        invoiceDate: '2026-06-01T00:00:00.000',
        subtotalAmount: '3818.00',
        cgstPercent: '2.5',
        cgstAmount: '95.45',
        sgstPercent: '2.5',
        sgstAmount: '95.45',
        totalAmount: '4008.90',
        amountInWords: 'Rupees Four Thousand Eight and Ninety Paise Only',
        transportMode: 'By Road',
        vehicleNumber: 'KA01AB1234',
        status: Invoice.statusPaid,
      );
      final restored = Invoice.fromMap(original.toMap());

      expect(restored.cgstPercent, '2.5');
      expect(restored.sgstPercent, '2.5');
      expect(restored.transportMode, 'By Road');
      expect(restored.vehicleNumber, 'KA01AB1234');
      expect(restored.isPaid, isTrue);
    });

    test('InvoiceItem distinguishes normal lines from flat charges', () {
      const normal = InvoiceItem(
        id: 'ii1',
        invoiceId: 'inv1',
        poItemId: 'poi1',
        productId: 'p1',
        description: 'CNC turning',
        hsnSac: '998873',
        quantity: '12',
        rate: '250.50',
        amount: '3006.00',
      );
      const flat = InvoiceItem(
        id: 'ii2',
        invoiceId: 'inv1',
        description: 'Weighment Charges',
        amount: '450.00',
      );

      expect(InvoiceItem.fromMap(normal.toMap()).isFlatCharge, isFalse);
      expect(InvoiceItem.fromMap(flat.toMap()).isFlatCharge, isTrue);
      expect(InvoiceItem.fromMap(normal.toMap()).poItemId, 'poi1');
    });
  });

  group('reading a row from an older workbook', () {
    test('missing columns fall back to defaults instead of throwing', () {
      // A workbook written before client references existed.
      final legacy = PurchaseOrder.fromMap(const {
        'po_id': 'po1',
        'po_number': 'PO-0001',
        'customer_id': 'c1',
        'order_date': '2025-01-01T00:00:00.000',
      });
      expect(legacy.clientPoNumber, '');
      expect(legacy.status, PurchaseOrder.statusPending);

      final legacyProduct = Product.fromMap(const {
        'product_id': 'p1',
        'name': 'Widget',
      });
      expect(legacyProduct.hsnSac, '');
      expect(legacyProduct.price, '0');
    });
  });
}
