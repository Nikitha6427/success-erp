import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// Builds a minimal but valid `.xlsx` in memory.
///
/// Graph's workbook endpoints reject a zero-byte file, so the app folder can't
/// simply be given an empty `ERP_App_Data.xlsx` — a real Office Open XML package
/// has to be uploaded before any worksheet or table call will work. This is the
/// smallest package Excel and Graph both accept: one empty sheet, which the
/// service deletes once the entity worksheets exist.
class BlankWorkbook {
  BlankWorkbook._();

  static const String mimeType =
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';

  /// Name of the single placeholder sheet in the freshly created workbook.
  static const String placeholderSheet = 'Sheet1';

  static const String _contentTypes = '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
<Default Extension="xml" ContentType="application/xml"/>
<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
<Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
</Types>''';

  static const String _rootRels = '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
</Relationships>''';

  static const String _workbook = '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
<sheets><sheet name="$placeholderSheet" sheetId="1" r:id="rId1"/></sheets>
</workbook>''';

  static const String _workbookRels = '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
</Relationships>''';

  static const String _sheet = '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
<sheetData/>
</worksheet>''';

  static Uint8List bytes() {
    final archive = Archive();
    // [Content_Types].xml must come first in the package.
    for (final entry in <String, String>{
      '[Content_Types].xml': _contentTypes,
      '_rels/.rels': _rootRels,
      'xl/workbook.xml': _workbook,
      'xl/_rels/workbook.xml.rels': _workbookRels,
      'xl/worksheets/sheet1.xml': _sheet,
    }.entries) {
      final data = utf8.encode(entry.value.trim());
      archive.addFile(ArchiveFile(entry.key, data.length, data));
    }
    final encoded = ZipEncoder().encode(archive);
    return Uint8List.fromList(encoded);
  }
}
