class DeliveryNote {
  final String id;
  final String dnNumber;
  final String poId;
  final String deliveryDate;
  final String transportMode;
  final String vehicleNumber;
  final String createdAt;

  const DeliveryNote({
    required this.id,
    required this.dnNumber,
    required this.poId,
    required this.deliveryDate,
    this.transportMode = '',
    this.vehicleNumber = '',
    this.createdAt = '',
  });

  factory DeliveryNote.fromMap(Map<String, String> m) => DeliveryNote(
        id: m['dn_id'] ?? '',
        dnNumber: m['dn_number'] ?? '',
        poId: m['po_id'] ?? '',
        deliveryDate: m['delivery_date'] ?? '',
        transportMode: m['transport_mode'] ?? '',
        vehicleNumber: m['vehicle_number'] ?? '',
        createdAt: m['created_at'] ?? '',
      );

  Map<String, String> toMap() => {
        'dn_id': id,
        'dn_number': dnNumber,
        'po_id': poId,
        'delivery_date': deliveryDate,
        'transport_mode': transportMode,
        'vehicle_number': vehicleNumber,
        'created_at': createdAt,
      };
}

/// AGENTS.md §4 — `delivered_qty` here is the quantity delivered IN THIS NOTE,
/// never a cumulative or overwritten total.
class DeliveryNoteItem {
  final String id;
  final String dnId;
  final String poItemId;
  final String deliveredQty;
  final String remarks;

  const DeliveryNoteItem({
    required this.id,
    required this.dnId,
    required this.poItemId,
    required this.deliveredQty,
    this.remarks = '',
  });

  factory DeliveryNoteItem.fromMap(Map<String, String> m) => DeliveryNoteItem(
        id: m['dn_item_id'] ?? '',
        dnId: m['dn_id'] ?? '',
        poItemId: m['po_item_id'] ?? '',
        deliveredQty: m['delivered_qty'] ?? '0',
        remarks: m['remarks'] ?? '',
      );

  Map<String, String> toMap() => {
        'dn_item_id': id,
        'dn_id': dnId,
        'po_item_id': poItemId,
        'delivered_qty': deliveredQty,
        'remarks': remarks,
      };

  double get qty => double.tryParse(deliveredQty) ?? 0;
}
