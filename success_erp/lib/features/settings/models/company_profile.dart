class CompanyProfile {
  final String id;
  final String companyName;
  final String address;
  final String phone;
  final String gstNumber;
  final String state;
  final String updatedAt;

  const CompanyProfile({
    required this.id,
    required this.companyName,
    required this.address,
    required this.phone,
    required this.gstNumber,
    this.state = '',
    required this.updatedAt,
  });

  factory CompanyProfile.fromRow(List<String> row) {
    return CompanyProfile(
      id: row.isNotEmpty ? row[0] : '',
      companyName: row.length > 1 ? row[1] : '',
      address: row.length > 2 ? row[2] : '',
      phone: row.length > 3 ? row[3] : '',
      gstNumber: row.length > 4 ? row[4] : '',
      state: row.length > 5 ? row[5] : '',
      updatedAt: row.length > 6 ? row[6] : '',
    );
  }

  List<String> toRow() {
    return [id, companyName, address, phone, gstNumber, state, updatedAt];
  }

  CompanyProfile copyWith({
    String? id,
    String? companyName,
    String? address,
    String? phone,
    String? gstNumber,
    String? state,
    String? updatedAt,
  }) {
    return CompanyProfile(
      id: id ?? this.id,
      companyName: companyName ?? this.companyName,
      address: address ?? this.address,
      phone: phone ?? this.phone,
      gstNumber: gstNumber ?? this.gstNumber,
      state: state ?? this.state,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  bool get isComplete => companyName.isNotEmpty && address.isNotEmpty;
}
