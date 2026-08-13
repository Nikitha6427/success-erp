import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:intl/intl.dart';
import '../../core/services/number_to_words.dart';

class InvoicePdf {
  static Future<pw.Document> generate({
    required String invoiceNumber,
    required String invoiceDate,
    required String poNumber,
    required String customerName,
    required String customerAddress,
    required String customerGst,
    required String customerTin,
    required String customerCst,
    required String vehicleDetails,
    required String gstDetails,
    required List<Map<String, dynamic>> items,
    required String subtotal,
    required String cgstPercent,
    required String sgstPercent,
    required String cgstTotal,
    required String sgstTotal,
    required String grandTotal,
    String? companyName,
    String? companyAddress,
    String? companyPhone,
    String? companyGst,
    String? companyEmail,
    String? companyWebsite,
    String? deliveryNoteRefs,
  }) async {
    final pdf = pw.Document();

    final grandTotalValue = double.tryParse(grandTotal) ?? 0;
    final amountInWords = NumberToWords.convert(grandTotalValue);

    final hasRemarks = items.any((item) => (item['remark'] ?? '').isNotEmpty);

    for (final copyLabel in ['Original', 'Duplicate', 'Triplicate']) {
      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: pw.EdgeInsets.all(28),
          build: (context) => [
            _buildHeader(companyName, companyGst),
            pw.SizedBox(height: 4),
            _buildCopyLabel(copyLabel),
            pw.SizedBox(height: 4),
            _buildOursBox(invoiceNumber, invoiceDate, poNumber, vehicleDetails, gstDetails, deliveryNoteRefs: deliveryNoteRefs),
            pw.SizedBox(height: 6),
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(child: _buildBillingAddress(customerName, customerAddress, customerGst, customerTin, customerCst)),
                pw.SizedBox(width: 16),
                pw.Expanded(child: _buildClientsBox(poNumber, invoiceDate, invoiceNumber, invoiceDate, deliveryNoteRefs: deliveryNoteRefs)),
              ],
            ),
            pw.SizedBox(height: 16),
            _buildItemTable(items, hasRemarks),
            pw.SizedBox(height: 12),
            _buildTaxSection(subtotal, cgstPercent, sgstPercent, cgstTotal, sgstTotal, grandTotal),
            pw.SizedBox(height: 8),
            pw.Text(amountInWords, style: pw.TextStyle(fontSize: 10, fontStyle: pw.FontStyle.italic)),
            pw.SizedBox(height: 4),
            _buildTransportRow(vehicleDetails, gstDetails),
            pw.SizedBox(height: 12),
            _buildSignatureBlock(companyName ?? ''),
            pw.SizedBox(height: 12),
            _buildFooter(companyName, companyAddress, companyPhone, companyEmail, companyWebsite),
          ],
        ),
      );
    }

    return pdf;
  }

  static pw.Widget _buildCopyLabel(String label) {
    return pw.Container(
      alignment: pw.Alignment.centerRight,
      child: pw.Text(label,
          style: pw.TextStyle(
              fontSize: 11,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.red)),
    );
  }

  static pw.Widget _buildHeader(String? companyName, String? companyGst) {
    final name = companyName ?? '';
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Container(
              width: 60, height: 60,
              decoration: pw.BoxDecoration(
                color: PdfColors.grey300,
                borderRadius: pw.BorderRadius.all(pw.Radius.circular(8)),
              ),
              child: pw.Center(child: pw.Text('Logo', style: pw.TextStyle(fontSize: 8, color: PdfColors.grey600))),
            ),
            pw.SizedBox(height: 4),
            pw.Text(name, style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
          ],
        ),
        pw.Spacer(),
        pw.Container(
          padding: pw.EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.black, width: 1.5),
          ),
          child: pw.Text('INVOICE', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
        ),
      ],
    );
  }

  static pw.Widget _buildOursBox(String invoiceNumber, String invoiceDate, String poNumber, String vehicleDetails, String gstDetails, {String? deliveryNoteRefs}) {
    return pw.Container(
      padding: pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.black),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('Ours:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
          pw.SizedBox(height: 2),
          pw.Row(
            children: [
              pw.Text('Invoice #: ', style: pw.TextStyle(fontSize: 10)),
              pw.Text(invoiceNumber, style: pw.TextStyle(fontSize: 10, color: PdfColors.red, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(width: 16),
              pw.Text('Invoice Date: ', style: pw.TextStyle(fontSize: 10)),
              pw.Text(DateFormat.yMMMd().format(DateTime.parse(invoiceDate)), style: pw.TextStyle(fontSize: 10)),
            ],
          ),
          pw.Row(
            children: [
              pw.Text('Delivery Note #: ${deliveryNoteRefs ?? poNumber}', style: pw.TextStyle(fontSize: 10)),
              pw.SizedBox(width: 16),
              if (vehicleDetails.isNotEmpty)
                pw.Text('Vehicle: $vehicleDetails', style: pw.TextStyle(fontSize: 10)),
            ],
          ),
          if (gstDetails.isNotEmpty)
            pw.Text('Transport: $gstDetails', style: pw.TextStyle(fontSize: 10)),
        ],
      ),
    );
  }

  static pw.Widget _buildBillingAddress(String customerName, String customerAddress, String customerGst, String customerTin, String customerCst) {
    final gstin = customerGst.isNotEmpty ? customerGst : 'None/Blank';
    final tin = customerTin.isNotEmpty ? customerTin : 'None/Blank';
    final cst = customerCst.isNotEmpty ? customerCst : 'None/Blank';
    return pw.Container(
      padding: pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.black),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('Billing Address', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, decoration: pw.TextDecoration.underline)),
          pw.SizedBox(height: 4),
          pw.Text(customerName, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
          pw.Text('GSTIN: $gstin', style: pw.TextStyle(fontSize: 9)),
          pw.Text('TIN: $tin', style: pw.TextStyle(fontSize: 9)),
          pw.Text('CST: $cst', style: pw.TextStyle(fontSize: 9)),
          if (customerAddress.isNotEmpty)
            pw.Text(customerAddress, style: pw.TextStyle(fontSize: 9)),
        ],
      ),
    );
  }

  static pw.Widget _buildClientsBox(String poNumber, String invoiceDate, String invoiceNumber, String deliveryDate, {String? deliveryNoteRefs}) {
    return pw.Container(
      padding: pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.black),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('Clients', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, decoration: pw.TextDecoration.underline)),
          pw.SizedBox(height: 4),
          _clientsRow('Order Date', invoiceDate.isNotEmpty ? DateFormat.yMMMd().format(DateTime.parse(invoiceDate)) : 'N/A'),
          _clientsRow('Order #', poNumber),
          _clientsRow('Delivery Note #', deliveryNoteRefs ?? invoiceNumber),
          _clientsRow('Delivery Note Date', deliveryDate.isNotEmpty ? DateFormat.yMMMd().format(DateTime.parse(deliveryDate)) : 'N/A'),
        ],
      ),
    );
  }

  static pw.Widget _clientsRow(String label, String value) {
    return pw.Row(
      children: [
        pw.Text('$label: ', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
        pw.Text(value, style: pw.TextStyle(fontSize: 9)),
      ],
    );
  }

  static pw.Widget _buildItemTable(List<Map<String, dynamic>> items, bool hasRemarks) {
    List<String> headers;
    Map<int, pw.TableColumnWidth> columnWidths;

    if (hasRemarks) {
      headers = ['Item #', 'Product Description', 'HSN/SAC', 'Qty', 'Rate', 'Amount', 'Remarks'];
      columnWidths = {
        0: pw.FlexColumnWidth(0.4),
        1: pw.FlexColumnWidth(1.8),
        2: pw.FlexColumnWidth(0.8),
        3: pw.FlexColumnWidth(0.6),
        4: pw.FlexColumnWidth(0.6),
        5: pw.FlexColumnWidth(0.8),
        6: pw.FlexColumnWidth(1),
      };
    } else {
      headers = ['Item #', 'Product Description', 'HSN/SAC', 'Qty', 'Rate', 'Amount'];
      columnWidths = {
        0: pw.FlexColumnWidth(0.4),
        1: pw.FlexColumnWidth(2),
        2: pw.FlexColumnWidth(1),
        3: pw.FlexColumnWidth(0.6),
        4: pw.FlexColumnWidth(0.6),
        5: pw.FlexColumnWidth(1),
      };
    }

    final data = items.asMap().entries.map((entry) {
      final i = entry.key;
      final item = entry.value;
      final isFlat = (item['quantity'] ?? '').isEmpty;
      if (hasRemarks) {
        return [
          '${i + 1}',
          item['productName'] ?? '',
          isFlat ? '' : (item['hsnCode'] ?? ''),
          isFlat ? '' : (item['quantity'] ?? ''),
          isFlat ? '' : (item['rate'] ?? ''),
          item['amount'] ?? '',
          item['remark'] ?? '',
        ];
      }
      return [
        '${i + 1}',
        item['productName'] ?? '',
        isFlat ? '' : (item['hsnCode'] ?? ''),
        isFlat ? '' : (item['quantity'] ?? ''),
        isFlat ? '' : (item['rate'] ?? ''),
        item['amount'] ?? '',
      ];
    }).toList();

    return pw.TableHelper.fromTextArray(
      headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
      headerDecoration: pw.BoxDecoration(color: PdfColors.grey300),
      cellAlignment: pw.Alignment.centerLeft,
      cellAlignments: hasRemarks
          ? {0: pw.Alignment.center, 3: pw.Alignment.center, 4: pw.Alignment.centerRight, 5: pw.Alignment.centerRight}
          : {0: pw.Alignment.center, 3: pw.Alignment.center, 4: pw.Alignment.centerRight, 5: pw.Alignment.centerRight},
      headerAlignment: pw.Alignment.center,
      columnWidths: columnWidths,
      headers: headers,
      data: data,
    );
  }

  static pw.Widget _buildTaxSection(String subtotal, String cgstPercent, String sgstPercent, String cgstTotal, String sgstTotal, String grandTotal) {
    return pw.Container(
      alignment: pw.Alignment.centerRight,
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.end,
            children: [
              pw.Text('Subtotal: ', style: pw.TextStyle(fontSize: 10)),
              pw.SizedBox(width: 80, child: pw.Text(subtotal, textAlign: pw.TextAlign.right, style: pw.TextStyle(fontSize: 10))),
            ],
          ),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.end,
            children: [
              pw.Text('CGST ($cgstPercent%): ', style: pw.TextStyle(fontSize: 10)),
              pw.SizedBox(width: 80, child: pw.Text(cgstTotal, textAlign: pw.TextAlign.right, style: pw.TextStyle(fontSize: 10))),
            ],
          ),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.end,
            children: [
              pw.Text('SGST ($sgstPercent%): ', style: pw.TextStyle(fontSize: 10)),
              pw.SizedBox(width: 80, child: pw.Text(sgstTotal, textAlign: pw.TextAlign.right, style: pw.TextStyle(fontSize: 10))),
            ],
          ),
          pw.Divider(),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.end,
            children: [
              pw.Text('Grand Total: ', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12)),
              pw.SizedBox(width: 80, child: pw.Text(grandTotal, textAlign: pw.TextAlign.right, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12))),
            ],
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildTransportRow(String vehicleDetails, String gstDetails) {
    final parts = <String>[];
    if (vehicleDetails.isNotEmpty) parts.add('Vehicle: $vehicleDetails');
    if (gstDetails.isNotEmpty) parts.add('Transport: $gstDetails');
    if (parts.isEmpty) return pw.SizedBox.shrink();
    return pw.Row(
      children: [
        pw.Text(parts.join('  •  '), style: pw.TextStyle(fontSize: 9, fontStyle: pw.FontStyle.italic)),
      ],
    );
  }

  static pw.Widget _buildSignatureBlock(String companyName) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('Received the above goods in good condition', style: pw.TextStyle(fontSize: 9)),
            pw.SizedBox(height: 24),
            pw.Text('Receivers Signature', style: pw.TextStyle(fontSize: 9)),
          ],
        ),
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('For $companyName', style: pw.TextStyle(fontSize: 9)),
            pw.SizedBox(height: 24),
            pw.Text('Authorised Signatory', style: pw.TextStyle(fontSize: 9)),
          ],
        ),
      ],
    );
  }

  static pw.Widget _buildFooter(String? companyName, String? companyAddress, String? companyPhone, String? companyEmail, String? companyWebsite) {
    final parts = <String>[
      if (companyAddress != null && companyAddress.isNotEmpty) companyAddress,
      if (companyPhone != null && companyPhone.isNotEmpty) 'Ph: $companyPhone',
      if (companyEmail != null && companyEmail.isNotEmpty) companyEmail,
      if (companyWebsite != null && companyWebsite.isNotEmpty) companyWebsite,
    ];
    return pw.Container(
      padding: pw.EdgeInsets.symmetric(vertical: 6),
      decoration: pw.BoxDecoration(
        border: pw.Border(top: pw.BorderSide(color: PdfColors.grey400)),
      ),
      child: pw.Text(
        parts.join('  |  '),
        style: pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
        textAlign: pw.TextAlign.center,
      ),
    );
  }
}
