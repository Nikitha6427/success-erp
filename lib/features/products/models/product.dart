/// AGENTS.md §4 — `category` (Sales/Labour) is required; `part_no` is optional
/// free text and NOT unique; `hsn_sac` holds an HSN or SAC code depending on
/// category and has no numeric-only restriction.
class Product {
  static const String categorySales = 'Sales';
  static const String categoryLabour = 'Labour';
  static const List<String> categories = [categorySales, categoryLabour];

  static const List<String> units = [
    'Nos', 'Kgs', 'Pcs', 'Box', 'Litre', 'Metre', 'Other',
  ];

  final String id;
  final String productCode;
  final String name;
  final String partNo;
  final String category;
  final String unit;
  final String price;
  final String taxPercent;
  final String hsnSac;
  final String createdAt;
  final String updatedAt;

  const Product({
    required this.id,
    required this.name,
    this.productCode = '',
    this.partNo = '',
    this.category = '',
    this.unit = '',
    this.price = '0',
    this.taxPercent = '',
    this.hsnSac = '',
    this.createdAt = '',
    this.updatedAt = '',
  });

  factory Product.fromMap(Map<String, String> m) => Product(
        id: m['product_id'] ?? '',
        productCode: m['product_code'] ?? '',
        name: m['name'] ?? '',
        partNo: m['part_no'] ?? '',
        category: m['category'] ?? '',
        unit: m['unit'] ?? '',
        price: m['price'] ?? '0',
        taxPercent: m['tax_percent'] ?? '',
        hsnSac: m['hsn_sac'] ?? '',
        createdAt: m['created_at'] ?? '',
        updatedAt: m['updated_at'] ?? '',
      );

  Map<String, String> toMap() => {
        'product_id': id,
        'product_code': productCode,
        'name': name,
        'part_no': partNo,
        'category': category,
        'unit': unit,
        'price': price,
        'tax_percent': taxPercent,
        'hsn_sac': hsnSac,
        'created_at': createdAt,
        'updated_at': updatedAt,
      };

  bool get isLabour => category == categoryLabour;

  /// Label for the HSN/SAC field: Sales uses HSN, Labour uses SAC.
  static String codeLabelFor(String? category) =>
      category == categoryLabour ? 'SAC Code' : 'HSN Code';

  Product copyWith({
    String? id,
    String? productCode,
    String? name,
    String? partNo,
    String? category,
    String? unit,
    String? price,
    String? taxPercent,
    String? hsnSac,
    String? createdAt,
    String? updatedAt,
  }) =>
      Product(
        id: id ?? this.id,
        productCode: productCode ?? this.productCode,
        name: name ?? this.name,
        partNo: partNo ?? this.partNo,
        category: category ?? this.category,
        unit: unit ?? this.unit,
        price: price ?? this.price,
        taxPercent: taxPercent ?? this.taxPercent,
        hsnSac: hsnSac ?? this.hsnSac,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
}
