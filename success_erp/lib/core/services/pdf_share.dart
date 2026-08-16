import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'pdf_common.dart';

/// Saving and sharing the generated document copies.
///
/// Each copy is written as its own file so the share sheet (and anything the
/// user forwards it to) sees three distinct PDFs rather than one bundle.
class PdfShare {
  PdfShare._();

  /// Writes [copies] to the temp directory and returns them as shareable files.
  static Future<List<XFile>> writeFiles(List<GeneratedCopy> copies) async {
    final dir = await getTemporaryDirectory();
    final files = <XFile>[];
    for (final copy in copies) {
      final file = File('${dir.path}/${copy.fileName}');
      await file.writeAsBytes(copy.bytes, flush: true);
      files.add(XFile(file.path, mimeType: 'application/pdf', name: copy.fileName));
    }
    return files;
  }

  /// Opens the share sheet with every copy attached as a separate PDF.
  static Future<void> shareAll(
    List<GeneratedCopy> copies, {
    required String subject,
  }) async {
    if (copies.isEmpty) return;
    final files = await writeFiles(copies);
    await Share.shareXFiles(files, subject: subject);
  }

  /// Opens the share sheet with just one copy.
  static Future<void> shareOne(
    GeneratedCopy copy, {
    required String subject,
  }) async {
    final files = await writeFiles([copy]);
    await Share.shareXFiles(files, subject: subject);
  }
}
