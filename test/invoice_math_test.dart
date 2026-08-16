import 'package:flutter_test/flutter_test.dart';
import 'package:success_erp/core/services/invoice_math.dart';
import 'package:success_erp/features/purchase_orders/models/purchase_order.dart';

PurchaseOrderItem item({
  required String id,
  double ordered = 0,
  double delivered = 0,
  double pending = 0,
  double rate = 0,
}) =>
    PurchaseOrderItem(
      id: id,
      poId: 'po-1',
      productId: 'prod-$id',
      quantity: ordered.toString(),
      rate: rate.toString(),
      deliveredQty: delivered.toString(),
      pendingQty: pending.toString(),
    );

void main() {
  group('invoiceable quantity (AGENTS.md §4)', () {
    test('is delivered minus already invoiced — NOT pending', () {
      // Ordered 100, delivered 60 (so pending 40), of which 25 already billed.
      final poItem =
          item(id: 'a', ordered: 100, delivered: 60, pending: 40, rate: 10);

      final invoiceable = InvoiceMath.invoiceableQty(
        poItem: poItem,
        invoicedByPoItem: {'a': 25},
      );

      expect(invoiceable, 35);
      // The two numbers must not be conflated.
      expect(invoiceable, isNot(poItem.pending));
      expect(poItem.pending, 40);
    });

    test('is keyed per PO line item, so duplicate products stay independent',
        () {
      final lineA =
          item(id: 'a', ordered: 10, delivered: 10, rate: 5);
      final lineB =
          item(id: 'b', ordered: 10, delivered: 10, rate: 5);
      // Same product on both lines, but only line A has been invoiced.
      const invoiced = {'a': 10.0};

      expect(
        InvoiceMath.invoiceableQty(poItem: lineA, invoicedByPoItem: invoiced),
        0,
      );
      expect(
        InvoiceMath.invoiceableQty(poItem: lineB, invoicedByPoItem: invoiced),
        10,
      );
    });

    test('never goes negative', () {
      final poItem = item(id: 'a', ordered: 10, delivered: 5, rate: 5);
      expect(
        InvoiceMath.invoiceableQty(
            poItem: poItem, invoicedByPoItem: {'a': 8}),
        0,
      );
    });
  });

  group('zero-rate lines (AGENTS.md §4)', () {
    test('do not need invoicing', () {
      expect(InvoiceMath.needsInvoicing(item(id: 'a', rate: 0)), isFalse);
      expect(InvoiceMath.needsInvoicing(item(id: 'b', rate: 0.5)), isTrue);
    });

    test('a PO is fully invoiced even with un-invoiced zero-rate lines', () {
      final items = [
        item(id: 'paid', ordered: 10, delivered: 10, pending: 0, rate: 100),
        item(id: 'free', ordered: 5, delivered: 5, pending: 0, rate: 0),
      ];
      expect(
        InvoiceMath.isFullyInvoiced(
          poItems: items,
          invoicedByPoItem: {'paid': 10},
        ),
        isTrue,
      );
    });

    test('a PO with undelivered quantity is not fully invoiced', () {
      final items = [
        item(id: 'a', ordered: 10, delivered: 6, pending: 4, rate: 100),
      ];
      expect(
        InvoiceMath.isFullyInvoiced(
          poItems: items,
          invoicedByPoItem: {'a': 6},
        ),
        isFalse,
      );
    });

    test('a PO with delivered-but-unbilled quantity is not fully invoiced', () {
      final items = [
        item(id: 'a', ordered: 10, delivered: 10, pending: 0, rate: 100),
      ];
      expect(
        InvoiceMath.isFullyInvoiced(
          poItems: items,
          invoicedByPoItem: {'a': 7},
        ),
        isFalse,
      );
    });
  });

  group('PO status after a delivery (AGENTS.md §5)', () {
    test('Delivered when nothing is pending', () {
      expect(
        InvoiceMath.statusAfterDelivery([
          item(id: 'a', ordered: 10, delivered: 10, pending: 0),
          item(id: 'b', ordered: 5, delivered: 5, pending: 0),
        ]),
        PurchaseOrder.statusDelivered,
      );
    });

    test('Partially Delivered when some pending but some delivered', () {
      expect(
        InvoiceMath.statusAfterDelivery([
          item(id: 'a', ordered: 10, delivered: 4, pending: 6),
          item(id: 'b', ordered: 5, delivered: 0, pending: 5),
        ]),
        PurchaseOrder.statusPartiallyDelivered,
      );
    });

    test('stays Pending when nothing has been delivered', () {
      expect(
        InvoiceMath.statusAfterDelivery([
          item(id: 'a', ordered: 10, delivered: 0, pending: 10),
        ]),
        PurchaseOrder.statusPending,
      );
    });
  });

  group('invoice totals (AGENTS.md §5)', () {
    test('worked example: two lines plus a flat charge at 9% + 9%', () {
      // 12 x 250.50 = 3006.00
      // 8  x  45.25 =  362.00
      // Weighment charges (flat) = 450.00
      // Subtotal                 = 3818.00
      // CGST 9%                  =  343.62
      // SGST 9%                  =  343.62
      // Total                    = 4505.24
      final lineA = InvoiceMath.lineAmount(12, 250.50);
      final lineB = InvoiceMath.lineAmount(8, 45.25);
      expect(lineA, 3006.00);
      expect(lineB, 362.00);

      final totals = InvoiceTotals.from(
        lineAmounts: [lineA, lineB, 450.00],
        cgstPercent: 9,
        sgstPercent: 9,
      );

      expect(totals.subtotal, 3818.00);
      expect(totals.cgstAmount, 343.62);
      expect(totals.sgstAmount, 343.62);
      expect(totals.total, 4505.24);
      // The tax split must never be collapsed into one number.
      expect(totals.cgstAmount + totals.sgstAmount, 687.24);
    });

    test('line amounts exclude tax so they sum to the subtotal', () {
      final amounts = [
        InvoiceMath.lineAmount(3, 199.99),
        InvoiceMath.lineAmount(7, 12.5),
      ];
      final totals = InvoiceTotals.from(
        lineAmounts: amounts,
        cgstPercent: 9,
        sgstPercent: 9,
      );
      expect(amounts.reduce((a, b) => a + b), totals.subtotal);
      expect(totals.subtotal, 599.97 + 87.5);
    });

    test('non-default and asymmetric rates are honoured', () {
      final totals = InvoiceTotals.from(
        lineAmounts: const [1000.00],
        cgstPercent: 2.5,
        sgstPercent: 2.5,
      );
      expect(totals.cgstAmount, 25.00);
      expect(totals.sgstAmount, 25.00);
      expect(totals.total, 1050.00);

      final asymmetric = InvoiceTotals.from(
        lineAmounts: const [1000.00],
        cgstPercent: 6,
        sgstPercent: 12,
      );
      expect(asymmetric.cgstAmount, 60.00);
      expect(asymmetric.sgstAmount, 120.00);
      expect(asymmetric.total, 1180.00);
    });

    test('zero tax leaves the total equal to the subtotal', () {
      final totals = InvoiceTotals.from(
        lineAmounts: const [500.00],
        cgstPercent: 0,
        sgstPercent: 0,
      );
      expect(totals.total, 500.00);
    });

    test('rounding is to paise, not to floating-point noise', () {
      // 1/3 of a rupee three times must not drift.
      final totals = InvoiceTotals.from(
        lineAmounts: const [0.33, 0.33, 0.34],
        cgstPercent: 9,
        sgstPercent: 9,
      );
      expect(totals.subtotal, 1.00);
      expect(totals.cgstAmount, 0.09);
      expect(totals.total, 1.18);
    });
  });
}
