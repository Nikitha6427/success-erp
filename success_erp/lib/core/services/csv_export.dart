import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class CsvExport {
  static Future<void> export({
    required String fileName,
    required List<String> headers,
    required List<List<String>> rows,
  }) async {
    final buffer = StringBuffer();
    buffer.writeln(headers.join(','));
    for (final row in rows) {
      buffer.writeln(row.map((cell) => _escape(cell)).join(','));
    }

    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$fileName.csv');
    await file.writeAsString(buffer.toString());
    await Share.shareXFiles(
      [XFile(file.path)],
      subject: fileName,
    );
  }

  static String _escape(String cell) {
    if (cell.contains(',') || cell.contains('"') || cell.contains('\n')) {
      return '"${cell.replaceAll('"', '""')}"';
    }
    return cell;
  }
}
