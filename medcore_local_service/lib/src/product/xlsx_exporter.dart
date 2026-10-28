import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';

/// Lightweight, 100% pure Dart OpenXML (.xlsx) Spreadsheet Generator.
/// Creates fully compliant multi-sheet Excel workbooks with zero native DLL dependencies.
class XlsxWorkbookBuilder {
  final Map<String, List<List<dynamic>>> _sheets = {};

  void addSheet(String title, List<String> headers, List<List<dynamic>> rows) {
    // Excel sheet names cannot exceed 31 chars and cannot contain: \ / ? * : [ ]
    var safeTitle = title.replaceAll(RegExp(r'[\\/?*:[\]]'), '_');
    if (safeTitle.length > 31) {
      safeTitle = safeTitle.substring(0, 31);
    }
    // Prevent duplicate sheet names
    var finalTitle = safeTitle;
    var counter = 1;
    while (_sheets.containsKey(finalTitle)) {
      final suffix = '_$counter';
      final base = safeTitle.length + suffix.length > 31
          ? safeTitle.substring(0, 31 - suffix.length)
          : safeTitle;
      finalTitle = '$base$suffix';
      counter++;
    }

    final table = <List<dynamic>>[headers, ...rows];
    _sheets[finalTitle] = table;
  }

  Uint8List build() {
    final archive = Archive();

    // 1. [Content_Types].xml
    final sheetOverrides = StringBuffer();
    var sheetIndex = 1;
    for (final _ in _sheets.keys) {
      sheetOverrides.write(
        '<Override PartName="/xl/worksheets/sheet$sheetIndex.xml" '
        'ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>',
      );
      sheetIndex++;
    }

    final contentTypesXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
  <Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>
  $sheetOverrides
</Types>''';
    _addFile(archive, '[Content_Types].xml', contentTypesXml);

    // 2. _rels/.rels
    const rootRelsXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
</Relationships>''';
    _addFile(archive, '_rels/.rels', rootRelsXml);

    // 3. xl/_rels/workbook.xml.rels
    final wbRels = StringBuffer();
    wbRels.write(
      '<Relationship Id="rIdStyles" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>',
    );
    sheetIndex = 1;
    for (final _ in _sheets.keys) {
      wbRels.write(
        '<Relationship Id="rIdSheet$sheetIndex" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet$sheetIndex.xml"/>',
      );
      sheetIndex++;
    }
    final wbRelsXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  $wbRels
</Relationships>''';
    _addFile(archive, 'xl/_rels/workbook.xml.rels', wbRelsXml);

    // 4. xl/styles.xml (Simple styles with header bold style)
    const stylesXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
  <fonts count="2">
    <font><name val="Calibri"/><sz val="11"/></font>
    <font><b/><name val="Calibri"/><sz val="11"/></font>
  </fonts>
  <fills count="2">
    <fill><patternFill patternType="none"/></fill>
    <fill><patternFill patternType="gray125"/></fill>
  </fills>
  <borders count="1">
    <border><left/><right/><top/><bottom/></border>
  </borders>
  <cellStyleXfs count="1">
    <xf numFmtId="0" fontId="0" fillId="0" borderId="0"/>
  </cellStyleXfs>
  <cellXfs count="2">
    <xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>
    <xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1"/>
  </cellXfs>
</styleSheet>''';
    _addFile(archive, 'xl/styles.xml', stylesXml);

    // 5. xl/workbook.xml
    final sheetsXml = StringBuffer();
    sheetIndex = 1;
    for (final entry in _sheets.entries) {
      final safeName = _escapeXml(entry.key);
      sheetsXml.write(
        '<sheet name="$safeName" sheetId="$sheetIndex" r:id="rIdSheet$sheetIndex"/>',
      );
      sheetIndex++;
    }
    final workbookXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
  <sheets>
    $sheetsXml
  </sheets>
</workbook>''';
    _addFile(archive, 'xl/workbook.xml', workbookXml);

    // 6. xl/worksheets/sheetX.xml
    sheetIndex = 1;
    for (final rows in _sheets.values) {
      final sheetData = StringBuffer();
      for (var r = 0; r < rows.length; r++) {
        final rowNum = r + 1;
        sheetData.write('<row r="$rowNum">');
        final rowCells = rows[r];
        for (var c = 0; c < rowCells.length; c++) {
          final colLetter = _columnLetter(c);
          final cellRef = '$colLetter$rowNum';
          final val = rowCells[c];
          final styleAttr = (r == 0) ? ' s="1"' : '';

          if (val == null) {
            sheetData.write('<c r="$cellRef"$styleAttr/>');
          } else if (val is num) {
            sheetData.write('<c r="$cellRef" t="n"$styleAttr><v>$val</v></c>');
          } else if (val is bool) {
            sheetData.write('<c r="$cellRef" t="b"$styleAttr><v>${val ? 1 : 0}</v></c>');
          } else {
            final str = _escapeXml(val.toString());
            sheetData.write('<c r="$cellRef" t="inlineStr"$styleAttr><is><t>$str</t></is></c>');
          }
        }
        sheetData.write('</row>');
      }

      final worksheetXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
  <sheetData>
    $sheetData
  </sheetData>
</worksheet>''';
      _addFile(archive, 'xl/worksheets/sheet$sheetIndex.xml', worksheetXml);
      sheetIndex++;
    }

    final encodedZip = ZipEncoder().encode(archive);
    return Uint8List.fromList(encodedZip);
  }

  void _addFile(Archive archive, String path, String content) {
    final bytes = utf8.encode(content);
    archive.addFile(ArchiveFile(path, bytes.length, bytes));
  }

  static String _columnLetter(int index) {
    var result = '';
    var temp = index;
    while (temp >= 0) {
      result = String.fromCharCode((temp % 26) + 65) + result;
      temp = (temp ~/ 26) - 1;
    }
    return result;
  }

  static String _escapeXml(String input) {
    return input
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
  }
}
