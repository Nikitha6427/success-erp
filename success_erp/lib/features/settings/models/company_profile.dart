import '../../../core/services/address_format.dart';

/// AGENTS.md §4 — singular record used as the letterhead on every printed
/// Delivery Note and Invoice.
class CompanyProfile {
  final String companyName;
  final String street;
  final String area;
  final String cityDistrict;
  final String state;
  final String country;
  final String pincode;
  final String gstNumber;
  final String tinNumber;
  final String cstNumber;
  final String phone;
  final String email;
  final String website;
  final String logoAssetPath;
  final String updatedAt;

  const CompanyProfile({
    this.companyName = '',
    this.street = '',
    this.area = '',
    this.cityDistrict = '',
    this.state = '',
    this.country = 'India',
    this.pincode = '',
    this.gstNumber = '',
    this.tinNumber = '',
    this.cstNumber = '',
    this.phone = '',
    this.email = '',
    this.website = '',
    this.logoAssetPath = 'assets/logo.png',
    this.updatedAt = '',
  });

  factory CompanyProfile.fromMap(Map<String, String> m) => CompanyProfile(
        companyName: m['company_name'] ?? '',
        street: m['street'] ?? '',
        area: m['area'] ?? '',
        cityDistrict: m['city_district'] ?? '',
        state: m['state'] ?? '',
        country: m['country'] ?? '',
        pincode: m['pincode'] ?? '',
        gstNumber: m['gst_number'] ?? '',
        tinNumber: m['tin_number'] ?? '',
        cstNumber: m['cst_number'] ?? '',
        phone: m['phone'] ?? '',
        email: m['email'] ?? '',
        website: m['website'] ?? '',
        logoAssetPath: (m['logo_asset_path'] ?? '').isEmpty
            ? 'assets/logo.png'
            : m['logo_asset_path']!,
        updatedAt: m['updated_at'] ?? '',
      );

  Map<String, String> toMap() => {
        'company_name': companyName,
        'street': street,
        'area': area,
        'city_district': cityDistrict,
        'state': state,
        'country': country,
        'pincode': pincode,
        'gst_number': gstNumber,
        'tin_number': tinNumber,
        'cst_number': cstNumber,
        'phone': phone,
        'email': email,
        'website': website,
        'logo_asset_path': logoAssetPath,
        'updated_at': updatedAt,
      };

  List<String> get addressLines => AddressFormat.lines(
        street: street,
        area: area,
        cityDistrict: cityDistrict,
        state: state,
        country: country,
        pincode: pincode,
      );

  String get addressOneLine => addressLines.join(', ');

  bool get isComplete => companyName.trim().isNotEmpty;

  CompanyProfile copyWith({
    String? companyName,
    String? street,
    String? area,
    String? cityDistrict,
    String? state,
    String? country,
    String? pincode,
    String? gstNumber,
    String? tinNumber,
    String? cstNumber,
    String? phone,
    String? email,
    String? website,
    String? logoAssetPath,
    String? updatedAt,
  }) =>
      CompanyProfile(
        companyName: companyName ?? this.companyName,
        street: street ?? this.street,
        area: area ?? this.area,
        cityDistrict: cityDistrict ?? this.cityDistrict,
        state: state ?? this.state,
        country: country ?? this.country,
        pincode: pincode ?? this.pincode,
        gstNumber: gstNumber ?? this.gstNumber,
        tinNumber: tinNumber ?? this.tinNumber,
        cstNumber: cstNumber ?? this.cstNumber,
        phone: phone ?? this.phone,
        email: email ?? this.email,
        website: website ?? this.website,
        logoAssetPath: logoAssetPath ?? this.logoAssetPath,
        updatedAt: updatedAt ?? this.updatedAt,
      );
}
