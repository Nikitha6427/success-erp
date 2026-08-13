import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:intl/intl.dart';

class DeliveryNotePdf {
  static Future<pw.Document> generate({
    required String dnNumber,
    required String poNumber,
    required String deliveryDate,
    required String customerName,
    required String customerAddress,
    required String customerGst,
    required String customerTin,
    required String customerCst,
    required String orderDate,
    required List<Map<String, dynamic>> items,
    String? companyName,
    String? companyAddress,
    String? companyPhone,
    String? companyGst,
    String? companyEmail,
    String? companyWebsite,
  }) async {
    final pdf = pw.Document();

    final hasAnyRemark = items.any((item) => (item['remark'] ?? '').isNotEmpty);

    for (final copyLabel in ['Original', 'Duplicate', 'Triplicate']) {
      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: pw.EdgeInsets.all(28),
          build: (context) => [
            _buildHeader(companyName, companyAddress, companyPhone, companyGst, companyEmail, companyWebsite),
            pw.SizedBox(height: 4),
            _buildCopyLabel(copyLabel),
            pw.SizedBox(height: 4),
            _buildOursBox(dnNumber, deliveryDate),
            pw.SizedBox(height: 6),
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(child: _buildBillingAddress(customerName, customerAddress, customerGst, customerTin, customerCst)),
                pw.SizedBox(width: 16),
                pw.Expanded(child: _buildClientsBox(poNumber, orderDate, dnNumber, deliveryDate)),
              ],
            ),
            pw.SizedBox(height: 16),
            _buildItemTable(items, hasAnyRemark),
            pw.SizedBox(height: 24),
            _buildSignatureBlock(companyName ?? ''),
            pw.SizedBox(height: 16),
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

  static pw.Widget _buildHeader(String? companyName, String? companyAddress, String? companyPhone, String? companyGst, String? companyEmail, String? companyWebsite) {
    final name = companyName ?? 'Success Engineering Enterprises';
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
          child: pw.Text('DELIVERY NOTE', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
        ),
      ],
    );
  }

  static pw.Widget _buildOursBox(String dnNumber, String deliveryDate) {
    return pw.Container(
      padding: pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.black),
      ),
      child: pw.Row(
        children: [
          pw.Text('Ours: ', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
          pw.Text('Delivery Note #: ', style: pw.TextStyle(fontSize: 10)),
          pw.Text(dnNumber, style: pw.TextStyle(fontSize: 10, color: PdfColors.red, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(width: 16),
          pw.Text('Date: ', style: pw.TextStyle(fontSize: 10)),
          pw.Text(DateFormat.yMMMd().format(DateTime.parse(deliveryDate)), style: pw.TextStyle(fontSize: 10)),
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

  static pw.Widget _buildClientsBox(String poNumber, String orderDate, String dnNumber, String deliveryDate) {
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
          _clientsRow('Order Date', orderDate.isNotEmpty ? DateFormat.yMMMd().format(DateTime.parse(orderDate)) : 'N/A'),
          _clientsRow('Order #', poNumber),
          _clientsRow('Delivery Note #', dnNumber),
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

  static pw.Widget _buildItemTable(List<Map<String, dynamic>> items, bool hasAnyRemark) {
    final headers = hasAnyRemark
        ? ['Item #', 'Product Details', 'Qty', 'Remarks']
        : ['Item #', 'Product Details', 'Qty'];

    final columnWidths = hasAnyRemark
        ? <int, pw.TableColumnWidth>{
            0: pw.FlexColumnWidth(0.5),
            1: pw.FlexColumnWidth(2.5),
            2: pw.FlexColumnWidth(1.2),
            3: pw.FlexColumnWidth(1.5),
          }
        : <int, pw.TableColumnWidth>{
            0: pw.FlexColumnWidth(0.5),
            1: pw.FlexColumnWidth(3),
            2: pw.FlexColumnWidth(1.2),
          };

    final data = items.asMap().entries.map((entry) {
      final i = entry.key;
      final item = entry.value;
      final qty = item['deliveredNow'] ?? '';
      final unit = item['unit'] ?? '';
      final qtyDisplay = '$qty ${unit.isNotEmpty ? unit : ''}'.trim();
      if (hasAnyRemark) {
        return [
          '${i + 1}',
          item['productName'] ?? '',
          qtyDisplay,
          item['remark'] ?? '',
        ];
      }
      return [
        '${i + 1}',
        item['productName'] ?? '',
        qtyDisplay,
      ];
    }).toList();

    return pw.TableHelper.fromTextArray(
      headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
      headerDecoration: pw.BoxDecoration(color: PdfColors.grey300),
      cellAlignment: pw.Alignment.centerLeft,
      cellAlignments: hasAnyRemark
          ? {0: pw.Alignment.center, 2: pw.Alignment.center}
          : {0: pw.Alignment.center, 2: pw.Alignment.center},
      headerAlignment: pw.Alignment.center,
      columnWidths: columnWidths,
      headers: headers,
      data: data,
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
