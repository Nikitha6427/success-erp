/// AGENTS.md §4 — four-stage status model (deliberate, do not simplify), plus
/// the CLIENT's own PO and delivery-challan references captured at PO creation.
class PurchaseOrder {
  static const String statusPending = 'Pending';
  static const String statusPartiallyDelivered = 'Partially Delivered';
  static const String statusDelivered = 'Delivered';
  static const String statusInvoiced = 'Invoiced';

  static const List<String> statuses = [
    statusPending,
    statusPartiallyDelivered,
    statusDelivered,
    statusInvoiced,
  ];

  final String id;
  final String poNumber;
  final String customerId;
  final String orderDate;

  /// The client's own PO reference for this order.
  final String clientPoNumber;
  final String clientPoDate;

  /// The client's own delivery challan for material they sent us to process —
  /// distinct from our DeliveryNotes, which ship finished goods back.
  final String clientDeliveryNoteNumber;
  final String clientDeliveryNoteDate;

  final String status;
  final String createdAt;
  final String updatedAt;

  const PurchaseOrder({
    required this.id,
    required this.poNumber,
    required this.customerId,
    required this.orderDate,
    this.clientPoNumber = '',
    this.clientPoDate = '',
    this.clientDeliveryNoteNumber = '',
    this.clientDeliveryNoteDate = '',
    this.status = statusPending,
    this.createdAt = '',
    this.updatedAt = '',
  });

  factory PurchaseOrder.fromMap(Map<String, String> m) => PurchaseOrder(
        id: m['po_id'] ?? '',
        poNumber: m['po_number'] ?? '',
        customerId: m['customer_id'] ?? '',
        orderDate: m['order_date'] ?? '',
        clientPoNumber: m['client_po_number'] ?? '',
        clientPoDate: m['client_po_date'] ?? '',
        clientDeliveryNoteNumber: m['client_delivery_note_number'] ?? '',
        clientDeliveryNoteDate: m['client_delivery_note_date'] ?? '',
        status: (m['status'] ?? '').isEmpty ? statusPending : m['status']!,
        createdAt: m['created_at'] ?? '',
        updatedAt: m['updated_at'] ?? '',
      );

  Map<String, String> toMap() => {
        'po_id': id,
        'po_number': poNumber,
        'customer_id': customerId,
        'order_date': orderDate,
        'client_po_number': clientPoNumber,
        'client_po_date': clientPoDate,
        'client_delivery_note_number': clientDeliveryNoteNumber,
        'client_delivery_note_date': clientDeliveryNoteDate,
        'status': status,
        'created_at': createdAt,
        'updated_at': updatedAt,
      };

  PurchaseOrder copyWith({
    String? id,
    String? poNumber,
    String? customerId,
    String? orderDate,
    String? clientPoNumber,
    String? clientPoDate,
    String? clientDeliveryNoteNumber,
    String? clientDeliveryNoteDate,
    String? status,
    String? createdAt,
    String? updatedAt,
  }) =>
      PurchaseOrder(
        id: id ?? this.id,
        poNumber: poNumber ?? this.poNumber,
        customerId: customerId ?? this.customerId,
        orderDate: orderDate ?? this.orderDate,
        clientPoNumber: clientPoNumber ?? this.clientPoNumber,
        clientPoDate: clientPoDate ?? this.clientPoDate,
        clientDeliveryNoteNumber:
            clientDeliveryNoteNumber ?? this.clientDeliveryNoteNumber,
        clientDeliveryNoteDate:
            clientDeliveryNoteDate ?? this.clientDeliveryNoteDate,
        status: status ?? this.status,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
}

/// AGENTS.md §4 — `rate` is snapshotted at PO creation and is NEVER re-linked
/// to the product master afterwards. `remarks` is per line item.
class PurchaseOrderItem {
  final String id;
  final String poId;
  final String productId;
  final String quantity;
  final String rate;
  final String deliveredQty;
  final String pendingQty;
  final String remarks;
  final String updatedAt;

  const PurchaseOrderItem({
    required this.id,
    required this.poId,
    required this.productId,
    required this.quantity,
    required this.rate,
    this.deliveredQty = '0',
    this.pendingQty = '0',
    this.remarks = '',
    this.updatedAt = '',
  });

  factory PurchaseOrderItem.fromMap(Map<String, String> m) => PurchaseOrderItem(
        id: m['po_item_id'] ?? '',
        poId: m['po_id'] ?? '',
        productId: m['product_id'] ?? '',
        quantity: m['quantity'] ?? '0',
        rate: m['rate'] ?? '0',
        deliveredQty: m['delivered_qty'] ?? '0',
        pendingQty: m['pending_qty'] ?? '0',
        remarks: m['remarks'] ?? '',
        updatedAt: m['updated_at'] ?? '',
      );

  Map<String, String> toMap() => {
        'po_item_id': id,
        'po_id': poId,
        'product_id': productId,
        'quantity': quantity,
        'rate': rate,
        'delivered_qty': deliveredQty,
        'pending_qty': pendingQty,
        'remarks': remarks,
        'updated_at': updatedAt,
      };

  double get qty => double.tryParse(quantity) ?? 0;
  double get rt => double.tryParse(rate) ?? 0;
  double get delivered => double.tryParse(deliveredQty) ?? 0;
  double get pending => double.tryParse(pendingQty) ?? 0;

  PurchaseOrderItem copyWith({
    String? id,
    String? poId,
    String? productId,
    String? quantity,
    String? rate,
    String? deliveredQty,
    String? pendingQty,
    String? remarks,
    String? updatedAt,
  }) =>
      PurchaseOrderItem(
        id: id ?? this.id,
        poId: poId ?? this.poId,
        productId: productId ?? this.productId,
        quantity: quantity ?? this.quantity,
        rate: rate ?? this.rate,
        deliveredQty: deliveredQty ?? this.deliveredQty,
        pendingQty: pendingQty ?? this.pendingQty,
        remarks: remarks ?? this.remarks,
        updatedAt: updatedAt ?? this.updatedAt,
      );
}
