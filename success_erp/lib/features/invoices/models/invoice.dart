class Invoice {
  final String id;
  final String invoiceNumber;
  final String poId;
  final String invoiceDate;
  final String totalAmount;
  final String taxAmount;
  final String status;
  final String vehicleDetails;
  final String gstDetails;
  final String cgstPercent;
  final String sgstPercent;
  final String deliveryNoteRefs;
  final String poRefs;

  const Invoice({
    required this.id,
    required this.invoiceNumber,
    required this.poId,
    required this.invoiceDate,
    required this.totalAmount,
    required this.taxAmount,
    required this.status,
    this.vehicleDetails = '',
    this.gstDetails = '',
    this.cgstPercent = '9',
    this.sgstPercent = '9',
    this.deliveryNoteRefs = '',
    this.poRefs = '',
  });

  factory Invoice.fromRow(List<String> row) {
    return Invoice(
      id: row.isNotEmpty ? row[0] : '',
      invoiceNumber: row.length > 1 ? row[1] : '',
      poId: row.length > 2 ? row[2] : '',
      invoiceDate: row.length > 3 ? row[3] : '',
      totalAmount: row.length > 4 ? row[4] : '0',
      taxAmount: row.length > 5 ? row[5] : '0',
      status: row.length > 6 ? row[6] : '',
      vehicleDetails: row.length > 7 ? row[7] : '',
      gstDetails: row.length > 8 ? row[8] : '',
      cgstPercent: row.length > 9 ? row[9] : '9',
      sgstPercent: row.length > 10 ? row[10] : '9',
      deliveryNoteRefs: row.length > 11 ? row[11] : '',
      poRefs: row.length > 12 ? row[12] : '',
    );
  }

  List<String> toRow() {
    return [id, invoiceNumber, poId, invoiceDate, totalAmount, taxAmount, status, vehicleDetails, gstDetails, cgstPercent, sgstPercent, deliveryNoteRefs, poRefs];
  }

  Invoice copyWith({
    String? id,
    String? invoiceNumber,
    String? poId,
    String? invoiceDate,
    String? totalAmount,
    String? taxAmount,
    String? status,
    String? vehicleDetails,
    String? gstDetails,
    String? cgstPercent,
    String? sgstPercent,
    String? deliveryNoteRefs,
    String? poRefs,
  }) {
    return Invoice(
      id: id ?? this.id,
      invoiceNumber: invoiceNumber ?? this.invoiceNumber,
      poId: poId ?? this.poId,
      invoiceDate: invoiceDate ?? this.invoiceDate,
      totalAmount: totalAmount ?? this.totalAmount,
      taxAmount: taxAmount ?? this.taxAmount,
      status: status ?? this.status,
      vehicleDetails: vehicleDetails ?? this.vehicleDetails,
      gstDetails: gstDetails ?? this.gstDetails,
      cgstPercent: cgstPercent ?? this.cgstPercent,
      sgstPercent: sgstPercent ?? this.sgstPercent,
      deliveryNoteRefs: deliveryNoteRefs ?? this.deliveryNoteRefs,
      poRefs: poRefs ?? this.poRefs,
    );
  }
}

class InvoiceItem {
  final String id;
  final String invoiceId;
  final String productId;
  final String quantity;
  final String rate;
  final String taxPercent;
  final String amount;
  final String remark;

  const InvoiceItem({
    required this.id,
    required this.invoiceId,
    required this.productId,
    required this.quantity,
    required this.rate,
    required this.taxPercent,
    required this.amount,
    this.remark = '',
  });

  factory InvoiceItem.fromRow(List<String> row) {
    return InvoiceItem(
      id: row.isNotEmpty ? row[0] : '',
      invoiceId: row.length > 1 ? row[1] : '',
      productId: row.length > 2 ? row[2] : '',
      quantity: row.length > 3 ? row[3] : '0',
      rate: row.length > 4 ? row[4] : '0',
      taxPercent: row.length > 5 ? row[5] : '0',
      amount: row.length > 6 ? row[6] : '0',
      remark: row.length > 7 ? row[7] : '',
    );
  }

  List<String> toRow() {
    return [id, invoiceId, productId, quantity, rate, taxPercent, amount, remark];
  }
}
