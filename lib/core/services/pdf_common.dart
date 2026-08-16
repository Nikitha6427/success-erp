import 'dart:developer' as dev;
import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../../features/customers/models/customer.dart';
import '../../features/settings/models/company_profile.dart';
import 'address_format.dart';

/// The three GST document copies, in order. AGENTS.md §6 — all three are
/// always produced for every Delivery Note and Invoice, not an option the user
/// has to select. Each one is emitted as its own PDF file.
class DocumentCopy {
  final String name;
  final String audience;

  const DocumentCopy(this.name, this.audience);

  /// Printed in the top-right of the page, e.g. "Original (For Recipient)".
  ///
  /// Plain ASCII punctuation only: the PDF base-14 fonts are Latin-1, so an
  /// en dash renders as nothing at all rather than as a dash.
  String get label => '$name ($audience)';

  /// e.g. "DN-0001 - Original (For Recipient).pdf"
  String fileNameFor(String documentNumber) =>
      '${_sanitize(documentNumber)} - $name ($audience).pdf';

  static String _sanitize(String value) =>
      value.replaceAll(RegExp(r'[\\/:*?"<>|]'), '-').trim();

  static const List<DocumentCopy> all = [
    DocumentCopy('Original', 'For Recipient'),
    DocumentCopy('Duplicate', 'For Transporter'),
    DocumentCopy('Triplicate', 'For Supplier'),
  ];
}

/// One rendered copy: its own standalone PDF, ready to save or share.
class GeneratedCopy {
  final DocumentCopy copy;
  final Uint8List bytes;
  final String fileName;

  const GeneratedCopy({
    required this.copy,
    required this.bytes,
    required this.fileName,
  });
}

class PdfCommon {
  PdfCommon._();

  /// Loads the company logo for the PDF letterhead. Returns null (and the
  /// caller falls back to a text-only letterhead) if the asset is missing.
  static Future<pw.MemoryImage?> loadLogo(String assetPath) async {
    try {
      final data = await rootBundle.load(assetPath);
      return pw.MemoryImage(data.buffer.asUint8List());
    } catch (e) {
      dev.log('[Pdf] Logo asset "$assetPath" unavailable: $e');
      return null;
    }
  }

  static String formatDate(String isoDate) {
    if (isoDate.trim().isEmpty) return 'N/A';
    try {
      return DateFormat('dd MMM yyyy').format(DateTime.parse(isoDate));
    } catch (_) {
      return isoDate;
    }
  }

  /// Letterhead: logo top-left, company name, address and tax identifiers,
  /// with the document title boxed on the right (AGENTS.md §6).
  static pw.Widget letterhead({
    required CompanyProfile? company,
    required pw.MemoryImage? logo,
    required String documentTitle,
  }) {
    final name = (company?.companyName ?? '').trim().isNotEmpty
        ? company!.companyName
        : 'Your company name - set this in Settings';
    final addressLines = company?.addressLines ?? const <String>[];

    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        if (logo != null)
          pw.Container(
            width: 58,
            height: 58,
            margin: const pw.EdgeInsets.only(right: 10),
            child: pw.Image(logo, fit: pw.BoxFit.contain),
          ),
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                name,
                style: pw.TextStyle(
                  fontSize: 14,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              for (final line in addressLines)
                pw.Text(line, style: const pw.TextStyle(fontSize: 8)),
              pw.SizedBox(height: 2),
              pw.Text(
                'GSTIN: ${AddressFormat.orNoneBlank(company?.gstNumber)}  |  '
                'TIN: ${AddressFormat.orNoneBlank(company?.tinNumber)}  |  '
                'CST: ${AddressFormat.orNoneBlank(company?.cstNumber)}',
                style: const pw.TextStyle(fontSize: 8),
              ),
              if ((company?.phone ?? '').isNotEmpty ||
                  (company?.email ?? '').isNotEmpty)
                pw.Text(
                  [
                    if ((company?.phone ?? '').isNotEmpty) 'Ph: ${company!.phone}',
                    if ((company?.email ?? '').isNotEmpty) company!.email,
                  ].join('  |  '),
                  style: const pw.TextStyle(fontSize: 8),
                ),
            ],
          ),
        ),
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.black, width: 1.5),
          ),
          child: pw.Text(
            documentTitle,
            style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
          ),
        ),
      ],
    );
  }

  /// Top-right copy label: the copy name ("Original"/"Duplicate"/"Triplicate")
  /// bold, the bracketed audience ("(For Recipient)" etc.) italic normal weight.
  static pw.Widget copyLabel(DocumentCopy copy) => pw.Container(
        alignment: pw.Alignment.centerRight,
        child: pw.RichText(
          text: pw.TextSpan(children: [
            pw.TextSpan(
              text: copy.name,
              style: pw.TextStyle(
                fontSize: 10,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.red,
              ),
            ),
            pw.TextSpan(
              text: ' (${copy.audience})',
              style: pw.TextStyle(
                fontSize: 10,
                fontStyle: pw.FontStyle.italic,
                color: PdfColors.red,
              ),
            ),
          ]),
          textAlign: pw.TextAlign.right,
        ),
      );

  /// Billing party box — GST/TIN/CST always print, "None/Blank" when empty.
  static pw.Widget billingAddress(Customer? customer) {
    final lines = customer?.addressLines ?? const <String>[];
    return pw.Container(
      padding: const pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.black)),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'Billing Address',
            style: pw.TextStyle(
              fontSize: 10,
              fontWeight: pw.FontWeight.bold,
              decoration: pw.TextDecoration.underline,
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            customer?.name ?? 'Unknown',
            style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
          ),
          for (final line in lines)
            pw.Text(line, style: const pw.TextStyle(fontSize: 9)),
          pw.SizedBox(height: 2),
          pw.Text('GSTIN: ${AddressFormat.orNoneBlank(customer?.gstNumber)}',
              style: const pw.TextStyle(fontSize: 9)),
          pw.Text('TIN: ${AddressFormat.orNoneBlank(customer?.tinNumber)}',
              style: const pw.TextStyle(fontSize: 9)),
          pw.Text('CST: ${AddressFormat.orNoneBlank(customer?.cstNumber)}',
              style: const pw.TextStyle(fontSize: 9)),
        ],
      ),
    );
  }

  static pw.Widget labelledBox(String title, List<List<String>> rows) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.black)),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            title,
            style: pw.TextStyle(
              fontSize: 10,
              fontWeight: pw.FontWeight.bold,
              decoration: pw.TextDecoration.underline,
            ),
          ),
          pw.SizedBox(height: 4),
          for (final row in rows)
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('${row[0]}: ',
                    style: pw.TextStyle(
                        fontSize: 9, fontWeight: pw.FontWeight.bold)),
                pw.Expanded(
                  child: pw.Text(row[1], style: const pw.TextStyle(fontSize: 9)),
                ),
              ],
            ),
        ],
      ),
    );
  }

  static pw.Widget signatureBlock(String companyName) => pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('Received the above goods in good condition',
                  style: const pw.TextStyle(fontSize: 9)),
              pw.SizedBox(height: 24),
              pw.Text("Receiver's Signature",
                  style: const pw.TextStyle(fontSize: 9)),
            ],
          ),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('For ${companyName.isEmpty ? "us" : companyName}',
                  style: const pw.TextStyle(fontSize: 9)),
              pw.SizedBox(height: 24),
              pw.Text('Authorised Signatory',
                  style: const pw.TextStyle(fontSize: 9)),
            ],
          ),
        ],
      );

  static pw.Widget footer(CompanyProfile? company) {
    final parts = <String>[
      if (company != null && company.addressOneLine.isNotEmpty)
        company.addressOneLine,
      if ((company?.phone ?? '').isNotEmpty) 'Ph: ${company!.phone}',
      if ((company?.email ?? '').isNotEmpty) company!.email,
      if ((company?.website ?? '').isNotEmpty) company!.website,
    ];
    if (parts.isEmpty) return pw.SizedBox();
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(vertical: 6),
      decoration: const pw.BoxDecoration(
        border: pw.Border(top: pw.BorderSide(color: PdfColors.grey400)),
      ),
      child: pw.Text(
        parts.join('  |  '),
        style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
        textAlign: pw.TextAlign.center,
      ),
    );
  }
}
