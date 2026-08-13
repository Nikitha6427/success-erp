class PurchaseOrder {
  final String id;
  final String poNumber;
  final String customerId;
  final String orderDate;
  final String status;
  final String createdAt;
  final String updatedAt;

  const PurchaseOrder({
    required this.id,
    required this.poNumber,
    required this.customerId,
    required this.orderDate,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
  });

  factory PurchaseOrder.fromRow(List<String> row) {
    return PurchaseOrder(
      id: row.isNotEmpty ? row[0] : '',
      poNumber: row.length > 1 ? row[1] : '',
      customerId: row.length > 2 ? row[2] : '',
      orderDate: row.length > 3 ? row[3] : '',
      status: row.length > 4 ? row[4] : 'Pending',
      createdAt: row.length > 5 ? row[5] : '',
      updatedAt: row.length > 6 ? row[6] : '',
    );
  }

  List<String> toRow() {
    return [id, poNumber, customerId, orderDate, status, createdAt, updatedAt];
  }

  PurchaseOrder copyWith({
    String? id,
    String? poNumber,
    String? customerId,
    String? orderDate,
    String? status,
    String? createdAt,
    String? updatedAt,
  }) {
    return PurchaseOrder(
      id: id ?? this.id,
      poNumber: poNumber ?? this.poNumber,
      customerId: customerId ?? this.customerId,
      orderDate: orderDate ?? this.orderDate,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

class PurchaseOrderItem {
  final String id;
  final String poId;
  final String productId;
  final String quantity;
  final String rate;
  final String deliveredQty;
  final String pendingQty;
  final String updatedAt;

  const PurchaseOrderItem({
    required this.id,
    required this.poId,
    required this.productId,
    required this.quantity,
    required this.rate,
    required this.deliveredQty,
    required this.pendingQty,
    required this.updatedAt,
  });

  factory PurchaseOrderItem.fromRow(List<String> row) {
    return PurchaseOrderItem(
      id: row.isNotEmpty ? row[0] : '',
      poId: row.length > 1 ? row[1] : '',
      productId: row.length > 2 ? row[2] : '',
      quantity: row.length > 3 ? row[3] : '0',
      rate: row.length > 4 ? row[4] : '0',
      deliveredQty: row.length > 5 ? row[5] : '0',
      pendingQty: row.length > 6 ? row[6] : '0',
      updatedAt: row.length > 7 ? row[7] : '',
    );
  }

  List<String> toRow() {
    return [id, poId, productId, quantity, rate, deliveredQty, pendingQty, updatedAt];
  }

  PurchaseOrderItem copyWith({
    String? id,
    String? poId,
    String? productId,
    String? quantity,
    String? rate,
    String? deliveredQty,
    String? pendingQty,
    String? updatedAt,
  }) {
    return PurchaseOrderItem(
      id: id ?? this.id,
      poId: poId ?? this.poId,
      productId: productId ?? this.productId,
      quantity: quantity ?? this.quantity,
      rate: rate ?? this.rate,
      deliveredQty: deliveredQty ?? this.deliveredQty,
      pendingQty: pendingQty ?? this.pendingQty,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
