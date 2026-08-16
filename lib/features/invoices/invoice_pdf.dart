import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../../core/services/pdf_common.dart';
import '../customers/models/customer.dart';
import '../purchase_orders/models/purchase_order.dart';
import '../settings/models/company_profile.dart';
import 'models/invoice.dart';

/// One printed row of the Invoice item table. Flat charges leave
/// hsnSac/quantity/rate empty and carry only a description and an amount.
class InvoicePdfLine {
  final String description;
  final String hsnSac;
  final String quantity;
  final String rate;
  final String amount;
  final String remarks;

  const InvoicePdfLine({
    required this.description,
    required this.amount,
    this.hsnSac = '',
    this.quantity = '',
    this.rate = '',
    this.remarks = '',
  });

  bool get isFlatCharge => quantity.trim().isEmpty && rate.trim().isEmpty;
}

class InvoicePdf {
  /// Builds the tax invoice as three SEPARATE single-copy PDFs — Original,
  /// Duplicate and Triplicate — rather than one three-page file, so each copy
  /// can be saved, sent or printed on its own (AGENTS.md §6).
  static Future<List<GeneratedCopy>> generate({
    required Invoice invoice,
    required PurchaseOrder? po,
    required Customer? customer,
    required CompanyProfile? company,
    required List<InvoicePdfLine> items,
    required List<String> deliveryNoteNumbers,
  }) async {
    // Shared across all three copies, so computed once.
    final logo =
        await PdfCommon.loadLogo(company?.logoAssetPath ?? 'assets/logo.png');
    final hasRemarks = items.any((i) => i.remarks.trim().isNotEmpty);
    final dnRefs =
        deliveryNoteNumbers.isEmpty ? 'N/A' : deliveryNoteNumbers.join(', ');

    final generated = <GeneratedCopy>[];
    for (final copy in DocumentCopy.all) {
      final pdf = pw.Document();
      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(28),
          // Signature block and company footer are pinned to the bottom of
          // every page rather than floated directly under the amount-in-words
          // line — same treatment as the Delivery Note.
          footer: (context) => pw.Column(
            children: [
              pw.SizedBox(height: 16),
              PdfCommon.signatureBlock(company?.companyName ?? ''),
              pw.SizedBox(height: 12),
              PdfCommon.footer(company),
            ],
          ),
          build: (context) => [
            PdfCommon.letterhead(
              company: company,
              logo: logo,
              documentTitle: 'TAX INVOICE',
            ),
            pw.SizedBox(height: 4),
            PdfCommon.copyLabel(copy),
            pw.SizedBox(height: 6),
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(child: PdfCommon.billingAddress(customer)),
                pw.SizedBox(width: 12),
                pw.Expanded(
                  child: PdfCommon.labelledBox('Ours', [
                    ['Invoice #', invoice.invoiceNumber],
                    ['Invoice Date', PdfCommon.formatDate(invoice.invoiceDate)],
                    ['Order #', po?.poNumber ?? 'N/A'],
                    ['Order Date', PdfCommon.formatDate(po?.orderDate ?? '')],
                    ['Delivery Note #', dnRefs],
                  ]),
                ),
                pw.SizedBox(width: 12),
                pw.Expanded(
                  child: PdfCommon.labelledBox('Clients', [
                    [
                      'Order #',
                      (po?.clientPoNumber ?? '').isEmpty
                          ? 'N/A'
                          : po!.clientPoNumber,
                    ],
                    ['Order Date', PdfCommon.formatDate(po?.clientPoDate ?? '')],
                    [
                      'Delivery Note #',
                      (po?.clientDeliveryNoteNumber ?? '').isEmpty
                          ? 'N/A'
                          : po!.clientDeliveryNoteNumber,
                    ],
                    [
                      'Delivery Note Date',
                      PdfCommon.formatDate(po?.clientDeliveryNoteDate ?? ''),
                    ],
                  ]),
                ),
              ],
            ),
            pw.SizedBox(height: 16),
            _itemTable(items, hasRemarks),
            pw.SizedBox(height: 12),
            _taxSection(invoice),
            pw.SizedBox(height: 8),
            pw.Text(
              invoice.amountInWords,
              style: pw.TextStyle(fontSize: 10, fontStyle: pw.FontStyle.italic),
            ),
            pw.SizedBox(height: 6),
            _transportRow(invoice),
          ],
        ),
      );
      generated.add(GeneratedCopy(
        copy: copy,
        bytes: await pdf.save(),
        fileName: copy.fileNameFor(invoice.invoiceNumber),
      ));
    }

    return generated;
  }

  /// Item # | Product Description | HSN/SAC | Qty | Rate | Amount
  /// (+ Remarks only when at least one line has one) — AGENTS.md §6.
  static pw.Widget _itemTable(List<InvoicePdfLine> items, bool hasRemarks) {
    final headers = [
      'Item #',
      'Product Description',
      'HSN/SAC',
      'Qty',
      'Rate',
      'Amount',
      if (hasRemarks) 'Remarks',
    ];

    final columnWidths = <int, pw.TableColumnWidth>{
      0: const pw.FlexColumnWidth(0.4),
      1: pw.FlexColumnWidth(hasRemarks ? 1.8 : 2.4),
      2: const pw.FlexColumnWidth(0.8),
      3: const pw.FlexColumnWidth(0.6),
      4: const pw.FlexColumnWidth(0.7),
      5: const pw.FlexColumnWidth(0.9),
      if (hasRemarks) 6: const pw.FlexColumnWidth(1.2),
    };

    final data = items.asMap().entries.map((entry) {
      final i = entry.key;
      final item = entry.value;
      return [
        '${i + 1}',
        item.description,
        item.isFlatCharge ? '' : item.hsnSac,
        item.isFlatCharge ? '' : item.quantity,
        item.isFlatCharge ? '' : item.rate,
        item.amount,
        if (hasRemarks) item.remarks,
      ];
    }).toList();

    return pw.TableHelper.fromTextArray(
      headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
      headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
      cellStyle: const pw.TextStyle(fontSize: 9),
      cellAlignment: pw.Alignment.centerLeft,
      cellAlignments: {
        0: pw.Alignment.center,
        3: pw.Alignment.center,
        4: pw.Alignment.centerRight,
        5: pw.Alignment.centerRight,
      },
      headerAlignment: pw.Alignment.center,
      columnWidths: columnWidths,
      headers: headers,
      data: data,
    );
  }

  /// CGST and SGST always print as separate lines — never a combined "Tax".
  static pw.Widget _taxSection(Invoice invoice) {
    pw.Widget row(String label, String value, {bool bold = false}) => pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.end,
          children: [
            pw.Text(
              label,
              style: pw.TextStyle(
                fontSize: bold ? 12 : 10,
                fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
              ),
            ),
            pw.SizedBox(
              width: 90,
              child: pw.Text(
                value,
                textAlign: pw.TextAlign.right,
                style: pw.TextStyle(
                  fontSize: bold ? 12 : 10,
                  fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
                ),
              ),
            ),
          ],
        );

    return pw.Container(
      alignment: pw.Alignment.centerRight,
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: [
          row('Subtotal: ', invoice.subtotalAmount),
          row('CGST (${invoice.cgstPercent}%): ', invoice.cgstAmount),
          row('SGST (${invoice.sgstPercent}%): ', invoice.sgstAmount),
          pw.Divider(),
          row('Grand Total: ', invoice.totalAmount, bold: true),
        ],
      ),
    );
  }

  static pw.Widget _transportRow(Invoice invoice) {
    final parts = <String>[
      'Transportation Mode: '
          '${invoice.transportMode.isEmpty ? "N/A" : invoice.transportMode}',
      'Vehicle Number: '
          '${invoice.vehicleNumber.isEmpty ? "N/A" : invoice.vehicleNumber}',
    ];
    return pw.Text(
      parts.join('     |     '),
      style: pw.TextStyle(fontSize: 9, fontStyle: pw.FontStyle.italic),
    );
  }
}
