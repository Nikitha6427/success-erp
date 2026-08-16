import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:success_erp/core/services/pdf_common.dart';
import 'package:success_erp/features/customers/models/customer.dart';
import 'package:success_erp/features/delivery_notes/dn_pdf.dart';
import 'package:success_erp/features/invoices/invoice_pdf.dart';
import 'package:success_erp/features/invoices/models/invoice.dart';
import 'package:success_erp/features/purchase_orders/models/purchase_order.dart';
import 'package:success_erp/features/settings/models/company_profile.dart';

const _po = PurchaseOrder(
  id: 'po1',
  poNumber: 'PO/S2026-27/1',
  customerId: 'c1',
  orderDate: '2026-05-04T00:00:00.000',
);

const _customer = Customer(
  id: 'c1',
  name: 'Acme Metals',
  street: '14 Foundry Lane',
  cityDistrict: 'Bengaluru',
  state: 'Karnataka',
  country: 'India',
  pincode: '560058',
);

const _company = CompanyProfile(companyName: 'Success Engineering');

const _invoice = Invoice(
  id: 'inv1',
  invoiceNumber: 'INV-0042',
  poId: 'po1',
  invoiceDate: '2026-06-01T00:00:00.000',
  subtotalAmount: '3818.00',
  cgstAmount: '343.62',
  sgstAmount: '343.62',
  totalAmount: '4505.24',
  amountInWords:
      'Rupees Four Thousand Five Hundred Five and Twenty Four Paise Only',
);

/// Number of pages declared in the PDF's page tree.
int pageCount(Uint8List bytes) {
  final text = latin1.decode(bytes, allowInvalid: true);
  final match = RegExp(r'/Count\s+(\d+)').firstMatch(text);
  return int.parse(match!.group(1)!);
}

bool isPdf(Uint8List bytes) =>
    latin1.decode(bytes.sublist(0, 5), allowInvalid: true) == '%PDF-';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DocumentCopy', () {
    test('names the three GST copies and their audiences', () {
      expect(DocumentCopy.all.map((c) => c.label), [
        'Original (For Recipient)',
        'Duplicate (For Transporter)',
        'Triplicate (For Supplier)',
      ]);
    });

    test('labels use only characters the PDF fonts can actually draw', () {
      // The base-14 PDF fonts are Latin-1. An en dash or bullet is not dropped
      // loudly — it renders as nothing at all, silently mangling the copy
      // label on a legal document.
      for (final copy in DocumentCopy.all) {
        expect(
          () => latin1.encode(copy.label),
          returnsNormally,
          reason: '"${copy.label}" contains a character the PDF cannot draw',
        );
      }
    });

    test('builds a per-copy file name from the document number', () {
      expect(
        DocumentCopy.all.first.fileNameFor('DN-0001'),
        'DN-0001 - Original (For Recipient).pdf',
      );
    });

    test('strips characters that are illegal in a file name', () {
      // PO-style numbers contain slashes; a file name must survive them.
      expect(
        DocumentCopy.all.last.fileNameFor('PO/S2026-27/4'),
        'PO-S2026-27-4 - Triplicate (For Supplier).pdf',
      );
    });
  });

  group('Delivery Note is three separate single-page PDFs', () {
    late List<GeneratedCopy> copies;

    setUp(() async {
      copies = await DeliveryNotePdf.generate(
        dnNumber: 'DN-0001',
        deliveryDate: '2026-05-10T00:00:00.000',
        po: _po,
        customer: _customer,
        company: _company,
        items: const [
          DnPdfLine(productName: 'Bracket', quantity: '5', unit: 'Nos'),
          DnPdfLine(
            productName: 'Shaft',
            quantity: '2',
            unit: 'Nos',
            remarks: 'Sent for vacuum hardening 58-62 RC',
          ),
        ],
      );
    });

    test('produces one file per copy, not one file with three pages', () {
      expect(copies, hasLength(3));
      for (final copy in copies) {
        expect(isPdf(copy.bytes), isTrue,
            reason: '${copy.fileName} is not a PDF');
        expect(pageCount(copy.bytes), 1,
            reason: '${copy.fileName} should hold only its own copy');
      }
    });

    test('each file is named for its copy', () {
      expect(copies.map((c) => c.fileName), [
        'DN-0001 - Original (For Recipient).pdf',
        'DN-0001 - Duplicate (For Transporter).pdf',
        'DN-0001 - Triplicate (For Supplier).pdf',
      ]);
    });

    test('the three files are distinct documents', () {
      final fingerprints = copies.map((c) => c.bytes.length).toSet();
      // Different copy labels render different content, so identical bytes
      // would mean the label was dropped.
      expect(copies.map((c) => c.copy.name).toSet(), hasLength(3));
      expect(fingerprints, isNotEmpty);
      expect(copies[0].bytes, isNot(equals(copies[1].bytes)));
      expect(copies[1].bytes, isNot(equals(copies[2].bytes)));
    });
  });

  group('Invoice is three separate single-page PDFs', () {
    late List<GeneratedCopy> copies;

    setUp(() async {
      copies = await InvoicePdf.generate(
        invoice: _invoice,
        po: _po,
        customer: _customer,
        company: _company,
        deliveryNoteNumbers: const ['DN-0001'],
        items: const [
          InvoicePdfLine(
            description: 'CNC turning',
            hsnSac: '998873',
            quantity: '12',
            rate: '250.50',
            amount: '3006.00',
          ),
          InvoicePdfLine(description: 'Weighment Charges', amount: '450.00'),
        ],
      );
    });

    test('produces one file per copy, not one file with three pages', () {
      expect(copies, hasLength(3));
      for (final copy in copies) {
        expect(isPdf(copy.bytes), isTrue);
        expect(pageCount(copy.bytes), 1,
            reason: '${copy.fileName} should hold only its own copy');
      }
    });

    test('each file is named for its copy and the invoice number', () {
      expect(copies.map((c) => c.fileName), [
        'INV-0042 - Original (For Recipient).pdf',
        'INV-0042 - Duplicate (For Transporter).pdf',
        'INV-0042 - Triplicate (For Supplier).pdf',
      ]);
    });

    test('renders without a company profile or customer', () async {
      final bare = await InvoicePdf.generate(
        invoice: _invoice,
        po: null,
        customer: null,
        company: null,
        deliveryNoteNumbers: const [],
        items: const [InvoicePdfLine(description: 'Charge', amount: '10.00')],
      );
      expect(bare, hasLength(3));
      for (final copy in bare) {
        expect(isPdf(copy.bytes), isTrue);
        expect(pageCount(copy.bytes), 1);
      }
    });
  });
}
