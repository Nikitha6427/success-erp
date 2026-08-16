import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../../core/services/pdf_common.dart';
import '../customers/models/customer.dart';
import '../purchase_orders/models/purchase_order.dart';
import '../settings/models/company_profile.dart';

/// One printed row of the Delivery Note item table.
class DnPdfLine {
  final String productName;
  final String quantity;
  final String unit;
  final String remarks;

  const DnPdfLine({
    required this.productName,
    required this.quantity,
    this.unit = '',
    this.remarks = '',
  });
}

class DeliveryNotePdf {
  /// Builds the Delivery Note as three SEPARATE single-copy PDFs — Original,
  /// Duplicate and Triplicate — rather than one three-page file, so each copy
  /// can be saved, sent or printed on its own (AGENTS.md §6).
  static Future<List<GeneratedCopy>> generate({
    required String dnNumber,
    required String deliveryDate,
    required PurchaseOrder po,
    required Customer? customer,
    required CompanyProfile? company,
    required List<DnPdfLine> items,
    String transportMode = '',
    String vehicleNumber = '',
  }) async {
    // The logo and the remarks decision are identical across copies, so do
    // that work once rather than three times.
    final logo =
        await PdfCommon.loadLogo(company?.logoAssetPath ?? 'assets/logo.png');
    final hasRemarks = items.any((i) => i.remarks.trim().isNotEmpty);

    final generated = <GeneratedCopy>[];
    for (final copy in DocumentCopy.all) {
      final pdf = pw.Document();
      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(28),
          // Signature block and company footer are pinned to the bottom of
          // every page, not floated directly under the item table — the
          // standard position regardless of how many line items fit.
          footer: (context) => pw.Column(
            children: [
              pw.SizedBox(height: 28),
              PdfCommon.signatureBlock(company?.companyName ?? ''),
              pw.SizedBox(height: 16),
              PdfCommon.footer(company),
            ],
          ),
          build: (context) => [
            PdfCommon.letterhead(
              company: company,
              logo: logo,
              documentTitle: 'DELIVERY NOTE',
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
                    ['Delivery Note #', dnNumber],
                    ['Delivery Note Date', PdfCommon.formatDate(deliveryDate)],
                    ['Our Order #', po.poNumber],
                    ['Our Order Date', PdfCommon.formatDate(po.orderDate)],
                  ]),
                ),
                pw.SizedBox(width: 12),
                pw.Expanded(
                  child: PdfCommon.labelledBox('Clients', [
                    [
                      'Order #',
                      po.clientPoNumber.isEmpty ? 'N/A' : po.clientPoNumber,
                    ],
                    ['Order Date', PdfCommon.formatDate(po.clientPoDate)],
                    [
                      'Delivery Note #',
                      po.clientDeliveryNoteNumber.isEmpty
                          ? 'N/A'
                          : po.clientDeliveryNoteNumber,
                    ],
                    [
                      'Delivery Note Date',
                      PdfCommon.formatDate(po.clientDeliveryNoteDate),
                    ],
                  ]),
                ),
              ],
            ),
            pw.SizedBox(height: 16),
            _itemTable(items, hasRemarks),
            pw.SizedBox(height: 12),
            _transportRow(transportMode, vehicleNumber),
          ],
        ),
      );
      generated.add(GeneratedCopy(
        copy: copy,
        bytes: await pdf.save(),
        fileName: copy.fileNameFor(dnNumber),
      ));
    }

    return generated;
  }

  /// Transportation Mode and Vehicle Number, matching the Invoice's placement
  /// (AGENTS.md §4/§6) — both optional, "N/A" when left blank.
  static pw.Widget _transportRow(String transportMode, String vehicleNumber) {
    final parts = <String>[
      'Transportation Mode: '
          '${transportMode.isEmpty ? "N/A" : transportMode}',
      'Vehicle Number: '
          '${vehicleNumber.isEmpty ? "N/A" : vehicleNumber}',
    ];
    return pw.Text(
      parts.join('     |     '),
      style: pw.TextStyle(fontSize: 9, fontStyle: pw.FontStyle.italic),
    );
  }

  /// Item # | Product Details | Qty (with unit) | Remarks (AGENTS.md §6).
  /// The Remarks column only appears when at least one line has one.
  static pw.Widget _itemTable(List<DnPdfLine> items, bool hasRemarks) {
    final headers = hasRemarks
        ? ['Item #', 'Product Details', 'Qty', 'Remarks']
        : ['Item #', 'Product Details', 'Qty'];

    final columnWidths = hasRemarks
        ? <int, pw.TableColumnWidth>{
            0: const pw.FlexColumnWidth(0.5),
            1: const pw.FlexColumnWidth(2.5),
            2: const pw.FlexColumnWidth(1.2),
            3: const pw.FlexColumnWidth(1.8),
          }
        : <int, pw.TableColumnWidth>{
            0: const pw.FlexColumnWidth(0.5),
            1: const pw.FlexColumnWidth(3),
            2: const pw.FlexColumnWidth(1.2),
          };

    final data = items.asMap().entries.map((entry) {
      final i = entry.key;
      final item = entry.value;
      final qtyDisplay = '${item.quantity} ${item.unit}'.trim();
      return [
        '${i + 1}',
        item.productName,
        qtyDisplay,
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
        2: pw.Alignment.center,
      },
      headerAlignment: pw.Alignment.center,
      columnWidths: columnWidths,
      headers: headers,
      data: data,
    );
  }
}
