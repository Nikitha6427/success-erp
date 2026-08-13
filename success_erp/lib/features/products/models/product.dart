class Product {
  final String id;
  final String name;
  final String partNo;
  final String unit;
  final String price;
  final String taxPercent;
  final String createdAt;
  final String updatedAt;
  final String hsnCode;
  final String productCode;
  final String category;

  const Product({
    required this.id,
    required this.name,
    required this.partNo,
    required this.unit,
    required this.price,
    required this.taxPercent,
    required this.createdAt,
    required this.updatedAt,
    this.hsnCode = '',
    this.productCode = '',
    this.category = '',
  });

  factory Product.fromRow(List<String> row) {
    return Product(
      id: row.isNotEmpty ? row[0] : '',
      name: row.length > 1 ? row[1] : '',
      partNo: row.length > 2 ? row[2] : '',
      unit: row.length > 3 ? row[3] : '',
      price: row.length > 4 ? row[4] : '',
      taxPercent: row.length > 5 ? row[5] : '',
      createdAt: row.length > 6 ? row[6] : '',
      updatedAt: row.length > 7 ? row[7] : '',
      hsnCode: row.length > 8 ? row[8] : '',
      productCode: row.length > 9 ? row[9] : '',
      category: row.length > 10 ? row[10] : '',
    );
  }

  List<String> toRow() {
    return [id, name, partNo, unit, price, taxPercent, createdAt, updatedAt, hsnCode, productCode, category];
  }

  Product copyWith({
    String? id,
    String? name,
    String? partNo,
    String? unit,
    String? price,
    String? taxPercent,
    String? createdAt,
    String? updatedAt,
    String? hsnCode,
    String? productCode,
    String? category,
  }) {
    return Product(
      id: id ?? this.id,
      name: name ?? this.name,
      partNo: partNo ?? this.partNo,
      unit: unit ?? this.unit,
      price: price ?? this.price,
      taxPercent: taxPercent ?? this.taxPercent,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      hsnCode: hsnCode ?? this.hsnCode,
      productCode: productCode ?? this.productCode,
      category: category ?? this.category,
    );
  }
}
