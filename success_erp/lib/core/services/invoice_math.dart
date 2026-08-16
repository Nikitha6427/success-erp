import '../../features/purchase_orders/models/purchase_order.dart';

/// Pure calculation helpers for the order-to-cash flow.
///
/// Kept free of Flutter/IO so the rules in AGENTS.md §4/§5 can be verified
/// directly in unit tests (see `test/invoice_math_test.dart`).
class InvoiceMath {
  InvoiceMath._();

  /// Money rounded to paise. All totals go through this so the printed figures
  /// always add up exactly.
  static double round2(double v) => (v * 100).round() / 100;

  /// Invoiceable quantity for one PO line item (AGENTS.md §4):
  ///   delivered_qty − sum(already invoiced quantities for that po_item_id)
  ///
  /// This is DERIVED at screen-load time and never stored. It is a different
  /// number from the PO's `pending_qty` — do not conflate them.
  static double invoiceableQty({
    required PurchaseOrderItem poItem,
    required Map<String, double> invoicedByPoItem,
  }) {
    final already = invoicedByPoItem[poItem.id] ?? 0;
    final remaining = poItem.delivered - already;
    return remaining > 0 ? remaining : 0;
  }

  /// Zero-rate lines never need invoicing (AGENTS.md §4) — a PO can be fully
  /// invoiced while zero-rate lines remain un-invoiced.
  static bool needsInvoicing(PurchaseOrderItem poItem) => poItem.rt > 0;

  /// True when every rate-bearing line of a PO has been fully invoiced.
  static bool isFullyInvoiced({
    required List<PurchaseOrderItem> poItems,
    required Map<String, double> invoicedByPoItem,
  }) {
    for (final item in poItems) {
      if (!needsInvoicing(item)) continue;
      // Anything ordered but not yet delivered still has to be invoiced later.
      if (item.pending > 0) return false;
      final already = invoicedByPoItem[item.id] ?? 0;
      if (already + 1e-9 < item.delivered) return false;
    }
    return true;
  }

  /// PO status after a delivery (AGENTS.md §5).
  static String statusAfterDelivery(List<PurchaseOrderItem> items) {
    final anyPending = items.any((i) => i.pending > 0);
    final anyDelivered = items.any((i) => i.delivered > 0);
    if (!anyPending) return PurchaseOrder.statusDelivered;
    if (anyDelivered) return PurchaseOrder.statusPartiallyDelivered;
    return PurchaseOrder.statusPending;
  }

  /// Line amount for a normal item: quantity × rate, EXCLUDING tax.
  static double lineAmount(double qty, double rate) => round2(qty * rate);
}

/// Ex-tax subtotal plus the CGST/SGST split, computed once and reused by the
/// form, the stored row and the PDF so they can never disagree.
class InvoiceTotals {
  final double subtotal;
  final double cgstPercent;
  final double cgstAmount;
  final double sgstPercent;
  final double sgstAmount;
  final double total;

  const InvoiceTotals({
    required this.subtotal,
    required this.cgstPercent,
    required this.cgstAmount,
    required this.sgstPercent,
    required this.sgstAmount,
    required this.total,
  });

  /// [lineAmounts] are ex-tax amounts (quantity × rate for normal lines, the
  /// charge amount for flat charges).
  factory InvoiceTotals.from({
    required Iterable<double> lineAmounts,
    required double cgstPercent,
    required double sgstPercent,
  }) {
    final subtotal = InvoiceMath.round2(
      lineAmounts.fold<double>(0, (sum, a) => sum + a),
    );
    final cgst = InvoiceMath.round2(subtotal * cgstPercent / 100);
    final sgst = InvoiceMath.round2(subtotal * sgstPercent / 100);
    return InvoiceTotals(
      subtotal: subtotal,
      cgstPercent: cgstPercent,
      cgstAmount: cgst,
      sgstPercent: sgstPercent,
      sgstAmount: sgst,
      total: InvoiceMath.round2(subtotal + cgst + sgst),
    );
  }
}
