class Customer {
  final String id;
  final String name;
  final String phone;
  final String email;
  final String address;
  final String gstNumber;
  final String tinNumber;
  final String cstNumber;
  final String createdAt;
  final String updatedAt;
  final String customerCode;

  const Customer({
    required this.id,
    required this.name,
    required this.phone,
    required this.email,
    required this.address,
    required this.gstNumber,
    required this.createdAt,
    required this.updatedAt,
    this.tinNumber = '',
    this.cstNumber = '',
    this.customerCode = '',
  });

  factory Customer.fromRow(List<String> row) {
    return Customer(
      id: row.isNotEmpty ? row[0] : '',
      name: row.length > 1 ? row[1] : '',
      phone: row.length > 2 ? row[2] : '',
      email: row.length > 3 ? row[3] : '',
      address: row.length > 4 ? row[4] : '',
      gstNumber: row.length > 5 ? row[5] : '',
      tinNumber: row.length > 6 ? row[6] : '',
      cstNumber: row.length > 7 ? row[7] : '',
      createdAt: row.length > 8 ? row[8] : '',
      updatedAt: row.length > 9 ? row[9] : '',
      customerCode: row.length > 10 ? row[10] : '',
    );
  }

  List<String> toRow() {
    return [id, name, phone, email, address, gstNumber, tinNumber, cstNumber, createdAt, updatedAt, customerCode];
  }

  Customer copyWith({
    String? id,
    String? name,
    String? phone,
    String? email,
    String? address,
    String? gstNumber,
    String? tinNumber,
    String? cstNumber,
    String? createdAt,
    String? updatedAt,
    String? customerCode,
  }) {
    return Customer(
      id: id ?? this.id,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      address: address ?? this.address,
      gstNumber: gstNumber ?? this.gstNumber,
      tinNumber: tinNumber ?? this.tinNumber,
      cstNumber: cstNumber ?? this.cstNumber,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      customerCode: customerCode ?? this.customerCode,
    );
  }
}
