/// AGENTS.md §4 — the CGST/SGST percentages and amounts ACTUALLY used are
/// stored on the row, so a reprint always shows the rate that applied at the
/// time even if the default changes later.
class Invoice {
  static const String statusPending = 'Pending';
  static const String statusPaid = 'Paid';

  /// Default halves of an 18% GST split, per AGENTS.md §4/§5.
  static const String defaultCgstPercent = '9';
  static const String defaultSgstPercent = '9';

  final String id;
  final String invoiceNumber;
  final String poId;
  final String invoiceDate;
  final String subtotalAmount;
  final String cgstPercent;
  final String cgstAmount;
  final String sgstPercent;
  final String sgstAmount;
  final String totalAmount;
  final String amountInWords;
  final String transportMode;
  final String vehicleNumber;
  final String status;
  final String createdAt;

  const Invoice({
    required this.id,
    required this.invoiceNumber,
    required this.poId,
    required this.invoiceDate,
    this.subtotalAmount = '0',
    this.cgstPercent = defaultCgstPercent,
    this.cgstAmount = '0',
    this.sgstPercent = defaultSgstPercent,
    this.sgstAmount = '0',
    this.totalAmount = '0',
    this.amountInWords = '',
    this.transportMode = '',
    this.vehicleNumber = '',
    this.status = statusPending,
    this.createdAt = '',
  });

  factory Invoice.fromMap(Map<String, String> m) => Invoice(
        id: m['invoice_id'] ?? '',
        invoiceNumber: m['invoice_number'] ?? '',
        poId: m['po_id'] ?? '',
        invoiceDate: m['invoice_date'] ?? '',
        subtotalAmount: m['subtotal_amount'] ?? '0',
        cgstPercent: m['cgst_percent'] ?? defaultCgstPercent,
        cgstAmount: m['cgst_amount'] ?? '0',
        sgstPercent: m['sgst_percent'] ?? defaultSgstPercent,
        sgstAmount: m['sgst_amount'] ?? '0',
        totalAmount: m['total_amount'] ?? '0',
        amountInWords: m['amount_in_words'] ?? '',
        transportMode: m['transport_mode'] ?? '',
        vehicleNumber: m['vehicle_number'] ?? '',
        status: (m['status'] ?? '').isEmpty ? statusPending : m['status']!,
        createdAt: m['created_at'] ?? '',
      );

  Map<String, String> toMap() => {
        'invoice_id': id,
        'invoice_number': invoiceNumber,
        'po_id': poId,
        'invoice_date': invoiceDate,
        'subtotal_amount': subtotalAmount,
        'cgst_percent': cgstPercent,
        'cgst_amount': cgstAmount,
        'sgst_percent': sgstPercent,
        'sgst_amount': sgstAmount,
        'total_amount': totalAmount,
        'amount_in_words': amountInWords,
        'transport_mode': transportMode,
        'vehicle_number': vehicleNumber,
        'status': status,
        'created_at': createdAt,
      };

  double get total => double.tryParse(totalAmount) ?? 0;
  bool get isPaid => status == statusPaid;

  Invoice copyWith({
    String? id,
    String? invoiceNumber,
    String? poId,
    String? invoiceDate,
    String? subtotalAmount,
    String? cgstPercent,
    String? cgstAmount,
    String? sgstPercent,
    String? sgstAmount,
    String? totalAmount,
    String? amountInWords,
    String? transportMode,
    String? vehicleNumber,
    String? status,
    String? createdAt,
  }) =>
      Invoice(
        id: id ?? this.id,
        invoiceNumber: invoiceNumber ?? this.invoiceNumber,
        poId: poId ?? this.poId,
        invoiceDate: invoiceDate ?? this.invoiceDate,
        subtotalAmount: subtotalAmount ?? this.subtotalAmount,
        cgstPercent: cgstPercent ?? this.cgstPercent,
        cgstAmount: cgstAmount ?? this.cgstAmount,
        sgstPercent: sgstPercent ?? this.sgstPercent,
        sgstAmount: sgstAmount ?? this.sgstAmount,
        totalAmount: totalAmount ?? this.totalAmount,
        amountInWords: amountInWords ?? this.amountInWords,
        transportMode: transportMode ?? this.transportMode,
        vehicleNumber: vehicleNumber ?? this.vehicleNumber,
        status: status ?? this.status,
        createdAt: createdAt ?? this.createdAt,
      );
}

/// AGENTS.md §4 — supports two kinds of line item:
///  1. Normal: product + quantity + rate, `amount` = quantity × rate (EX-tax).
///  2. Flat charge: description + amount only, no product/qty/rate/HSN.
///
/// `po_item_id` is carried so invoiceable quantity can be derived per PO line
/// item rather than per product (two PO lines may use the same product).
class InvoiceItem {
  final String id;
  final String invoiceId;
  final String poItemId;
  final String productId;
  final String description;
  final String hsnSac;
  final String quantity;
  final String rate;
  final String amount;
  final String remarks;

  const InvoiceItem({
    required this.id,
    required this.invoiceId,
    required this.description,
    required this.amount,
    this.poItemId = '',
    this.productId = '',
    this.hsnSac = '',
    this.quantity = '',
    this.rate = '',
    this.remarks = '',
  });

  factory InvoiceItem.fromMap(Map<String, String> m) => InvoiceItem(
        id: m['invoice_item_id'] ?? '',
        invoiceId: m['invoice_id'] ?? '',
        poItemId: m['po_item_id'] ?? '',
        productId: m['product_id'] ?? '',
        description: m['description'] ?? '',
        hsnSac: m['hsn_sac'] ?? '',
        quantity: m['quantity'] ?? '',
        rate: m['rate'] ?? '',
        amount: m['amount'] ?? '0',
        remarks: m['remarks'] ?? '',
      );

  Map<String, String> toMap() => {
        'invoice_item_id': id,
        'invoice_id': invoiceId,
        'po_item_id': poItemId,
        'product_id': productId,
        'description': description,
        'hsn_sac': hsnSac,
        'quantity': quantity,
        'rate': rate,
        'amount': amount,
        'remarks': remarks,
      };

  /// A flat charge has no quantity/rate — just a description and an amount.
  bool get isFlatCharge => quantity.trim().isEmpty && rate.trim().isEmpty;

  double get qty => double.tryParse(quantity) ?? 0;
  double get amt => double.tryParse(amount) ?? 0;
}
