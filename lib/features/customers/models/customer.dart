import '../../../core/services/address_format.dart';

/// AGENTS.md §4 — address is stored as separate fields, never a single blob;
/// GST / TIN / CST are three independent optional fields.
class Customer {
  final String id;
  final String customerCode;
  final String name;
  final String phone;
  final String email;
  final String street;
  final String area;
  final String cityDistrict;
  final String state;
  final String country;
  final String pincode;
  final String gstNumber;
  final String tinNumber;
  final String cstNumber;
  final String createdAt;
  final String updatedAt;

  const Customer({
    required this.id,
    required this.name,
    this.customerCode = '',
    this.phone = '',
    this.email = '',
    this.street = '',
    this.area = '',
    this.cityDistrict = '',
    this.state = '',
    this.country = 'India',
    this.pincode = '',
    this.gstNumber = '',
    this.tinNumber = '',
    this.cstNumber = '',
    this.createdAt = '',
    this.updatedAt = '',
  });

  factory Customer.fromMap(Map<String, String> m) => Customer(
        id: m['customer_id'] ?? '',
        customerCode: m['customer_code'] ?? '',
        name: m['name'] ?? '',
        phone: m['phone'] ?? '',
        email: m['email'] ?? '',
        street: m['street'] ?? '',
        area: m['area'] ?? '',
        cityDistrict: m['city_district'] ?? '',
        state: m['state'] ?? '',
        country: m['country'] ?? '',
        pincode: m['pincode'] ?? '',
        gstNumber: m['gst_number'] ?? '',
        tinNumber: m['tin_number'] ?? '',
        cstNumber: m['cst_number'] ?? '',
        createdAt: m['created_at'] ?? '',
        updatedAt: m['updated_at'] ?? '',
      );

  Map<String, String> toMap() => {
        'customer_id': id,
        'customer_code': customerCode,
        'name': name,
        'phone': phone,
        'email': email,
        'street': street,
        'area': area,
        'city_district': cityDistrict,
        'state': state,
        'country': country,
        'pincode': pincode,
        'gst_number': gstNumber,
        'tin_number': tinNumber,
        'cst_number': cstNumber,
        'created_at': createdAt,
        'updated_at': updatedAt,
      };

  /// Multi-line postal address per AGENTS.md §6.
  List<String> get addressLines => AddressFormat.lines(
        street: street,
        area: area,
        cityDistrict: cityDistrict,
        state: state,
        country: country,
        pincode: pincode,
      );

  String get addressOneLine => addressLines.join(', ');

  Customer copyWith({
    String? id,
    String? customerCode,
    String? name,
    String? phone,
    String? email,
    String? street,
    String? area,
    String? cityDistrict,
    String? state,
    String? country,
    String? pincode,
    String? gstNumber,
    String? tinNumber,
    String? cstNumber,
    String? createdAt,
    String? updatedAt,
  }) =>
      Customer(
        id: id ?? this.id,
        customerCode: customerCode ?? this.customerCode,
        name: name ?? this.name,
        phone: phone ?? this.phone,
        email: email ?? this.email,
        street: street ?? this.street,
        area: area ?? this.area,
        cityDistrict: cityDistrict ?? this.cityDistrict,
        state: state ?? this.state,
        country: country ?? this.country,
        pincode: pincode ?? this.pincode,
        gstNumber: gstNumber ?? this.gstNumber,
        tinNumber: tinNumber ?? this.tinNumber,
        cstNumber: cstNumber ?? this.cstNumber,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
}
