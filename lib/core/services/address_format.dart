/// Address rendering shared by the UI and both PDFs.
///
/// AGENTS.md §6: "Street, then Area, then 'City/District, State, Country -
/// Pincode.'" Empty parts are dropped rather than leaving stray commas.
class AddressFormat {
  AddressFormat._();

  static List<String> lines({
    required String street,
    required String area,
    required String cityDistrict,
    required String state,
    required String country,
    required String pincode,
  }) {
    final out = <String>[];
    if (street.trim().isNotEmpty) out.add(street.trim());
    if (area.trim().isNotEmpty) out.add(area.trim());

    final locality = [
      cityDistrict.trim(),
      state.trim(),
      country.trim(),
    ].where((p) => p.isNotEmpty).join(', ');

    final pin = pincode.trim();
    if (locality.isNotEmpty && pin.isNotEmpty) {
      out.add('$locality - $pin');
    } else if (locality.isNotEmpty) {
      out.add(locality);
    } else if (pin.isNotEmpty) {
      out.add(pin);
    }
    return out;
  }

  /// Literal "None/Blank" for empty tax identifiers on printed documents
  /// (AGENTS.md §6) — never a blank gap.
  static String orNoneBlank(String? value) {
    final v = value?.trim() ?? '';
    return v.isEmpty ? 'None/Blank' : v;
  }
}
