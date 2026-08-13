class DeliveryNote {
  final String id;
  final String dnNumber;
  final String poId;
  final String deliveryDate;
  final String createdAt;

  const DeliveryNote({
    required this.id,
    required this.dnNumber,
    required this.poId,
    required this.deliveryDate,
    required this.createdAt,
  });

  factory DeliveryNote.fromRow(List<String> row) {
    return DeliveryNote(
      id: row.isNotEmpty ? row[0] : '',
      dnNumber: row.length > 1 ? row[1] : '',
      poId: row.length > 2 ? row[2] : '',
      deliveryDate: row.length > 3 ? row[3] : '',
      createdAt: row.length > 4 ? row[4] : '',
    );
  }

  List<String> toRow() => [id, dnNumber, poId, deliveryDate, createdAt];
}

class DeliveryNoteItem {
  final String id;
  final String dnId;
  final String poItemId;
  final String deliveredQty;
  final String remark;

  const DeliveryNoteItem({
    required this.id,
    required this.dnId,
    required this.poItemId,
    required this.deliveredQty,
    this.remark = '',
  });

  factory DeliveryNoteItem.fromRow(List<String> row) {
    return DeliveryNoteItem(
      id: row.isNotEmpty ? row[0] : '',
      dnId: row.length > 1 ? row[1] : '',
      poItemId: row.length > 2 ? row[2] : '',
      deliveredQty: row.length > 3 ? row[3] : '0',
      remark: row.length > 4 ? row[4] : '',
    );
  }

  List<String> toRow() => [id, dnId, poItemId, deliveredQty, remark];
}
