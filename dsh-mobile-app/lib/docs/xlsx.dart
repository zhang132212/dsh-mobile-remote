// XLSX 阅读器（v3.2.0）。
//
// 分工：单元格值/类型/共享字符串这些琐碎但容易出错的活交给经过审计的 `excel` 包
// （SHA256 校验过 pub.dev 官方哈希，源码扫描无网络/无子进程）；而**超链接**是该包
// 不暴露的能力，本文件自己再解一次 zip 从 OOXML 关系里取——这样既复用了成熟解析器，
// 又补上了用户明确要求的「excel 超链接可读可点」。
//
// 注意：`excel` 包导出自己的 `Sheet`/`TextSpan`，与本项目 docs/model.dart 的
// `Sheet` 重名，故一律用 `as xls` 前缀导入，绝不裸导入。
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:excel/excel.dart' as xls;
import 'package:xml/xml.dart';

import 'model.dart';

/// 解析 .xlsx 字节 → 统一文档模型（电子表格分支）。永不抛异常。
Document parseXlsx(Uint8List bytes, String name) {
  final warnings = <String>[];
  try {
    final book = xls.Excel.decodeBytes(bytes);
    final tables = book.tables;

    // 超链接：从 OOXML 关系独立提取（excel 包不提供）
    var links = <String, Map<String, String>>{};
    try {
      links = _extractHyperlinks(bytes);
    } catch (e) {
      warnings.add('超链接解析失败，已按纯文本显示');
    }

    final sheets = <Sheet>[];
    for (final entry in tables.entries) {
      final name0 = entry.key;
      final rowsRaw = entry.value.rows;
      final linkMap = links[name0] ?? (links.length == 1 ? links.values.first : const <String, String>{});

      final rows = <List<SheetCell>>[];
      var maxCol = 0;
      for (var r = 0; r < rowsRaw.length; r++) {
        final src = rowsRaw[r];
        final out = <SheetCell>[];
        for (var c = 0; c < src.length; c++) {
          final data = src[c];
          final ref = _refOf(r, c);
          final url = linkMap[ref];
          if (data == null) {
            out.add(SheetCell('', url: url));
            continue;
          }
          final v = data.value;
          out.add(SheetCell(_cellText(v), url: url, formula: v is xls.FormulaCellValue));
        }
        if (out.length > maxCol) maxCol = out.length;
        rows.add(out);
      }
      sheets.add(Sheet(name0, rows, maxCol));
    }

    if (sheets.isEmpty) {
      warnings.add('工作簿里没有工作表');
    }
    return Document(
      _titleOf(name),
      DocFormat.xlsx,
      const [],
      sheet: Spreadsheet(sheets, title: _titleOf(name)),
      warnings: warnings,
    );
  } catch (e) {
    return Document(
      _titleOf(name),
      DocFormat.xlsx,
      [DocRaw('（无法解析 xlsx：$e）')],
      warnings: ['xlsx 解析失败'],
    );
  }
}

/// 单元格值 → 可读文本。
///
/// 关键坑：`xls.TextCellValue.value` 是 `xls.TextSpan` 而不是 String，
/// 直接 `toString()` 会得到 `TextSpan(...)` 之类的调试串而非正文——必须取 `.text`。
String _cellText(xls.CellValue? v) {
  if (v == null) return '';
  if (v is xls.TextCellValue) return v.value.text ?? '';
  if (v is xls.FormulaCellValue) return v.formula;
  if (v is xls.IntCellValue) return v.value.toString();
  if (v is xls.DoubleCellValue) {
    final d = v.value;
    // 去掉整数小数的尾巴：1.0 → 1
    if (d == d.roundToDouble() && d.abs() < 1e15) return d.toInt().toString();
    return d.toString();
  }
  if (v is xls.BoolCellValue) return v.value ? 'TRUE' : 'FALSE';
  if (v is xls.DateCellValue) {
    return '${v.year}-${_two(v.month)}-${_two(v.day)}';
  }
  if (v is xls.DateTimeCellValue) {
    return '${v.year}-${_two(v.month)}-${_two(v.day)} '
        '${_two(v.hour)}:${_two(v.minute)}:${_two(v.second)}';
  }
  if (v is xls.TimeCellValue) {
    return '${_two(v.hour)}:${_two(v.minute)}:${_two(v.second)}';
  }
  return v.toString();
}

String _two(int n) => n < 10 ? '0$n' : '$n';

String _titleOf(String name) {
  final base = name.split(RegExp(r'[\\/]')).last;
  final dot = base.lastIndexOf('.');
  return dot > 0 ? base.substring(0, dot) : base;
}

/// (row, col) 从 0 起 → Excel 单元格引用（A1 形式）。
String _refOf(int row, int col) {
  var c = col;
  final b = StringBuffer();
  while (true) {
    b.write(String.fromCharCode(65 + (c % 26)));
    c = c ~/ 26 - 1;
    if (c < 0) break;
  }
  return '${b.toString().split('').reversed.join()}${row + 1}';
}

/// "A1" → (row 0, col 0)；"AB12" → (row 11, col 27)
(int, int) _parseRef(String ref) {
  var col = 0;
  var i = 0;
  while (i < ref.length) {
    final u = ref.codeUnitAt(i);
    if (u >= 65 && u <= 90) {
      col = col * 26 + (u - 64);
      i++;
    } else {
      break;
    }
  }
  final rowPart = ref.substring(i).replaceAll(RegExp(r'[^0-9]'), '');
  final row = int.tryParse(rowPart) ?? 1;
  return (row - 1, col - 1);
}

/// 按 **local 名**取属性。
///
/// 坑：package:xml 把 `r:id` 这种带前缀的属性存成 prefix='r' / local='id'，
/// `getAttribute('r:id')` 与 `getAttribute('id', namespace: ...)` 都取不到；
/// 直接扫 attributes 按 local 名匹配，对前缀/无前缀两种写法都成立。
String? _attrByLocal(XmlElement el, String local) {
  for (final a in el.attributes) {
    if (a.name.local == local) return a.value;
  }
  return null;
}

/// 从 xlsx 的 OOXML 关系中提取超链接。
///
/// xlsx 里超链接存两处：
///  1. `xl/worksheets/sheetN.xml` 的 `<hyperlinks><hyperlink ref="A1" r:id="rId3"/></hyperlinks>`
///  2. `xl/worksheets/_rels/sheetN.xml.rels` 里 `rId3` → `Target="https://..."`
/// 内部链接（同工作簿锚点）用 `location` 属性而非 r:id，这里也一并识别。
Map<String, Map<String, String>> _extractHyperlinks(Uint8List bytes) {
  final result = <String, Map<String, String>>{};
  final archive = ZipDecoder().decodeBytes(bytes);

  ArchiveFile? find(String path) {
    for (final f in archive.files) {
      if (f.name == path) return f;
    }
    return null;
  }

  String? textOf(String path) {
    final f = find(path);
    if (f == null) return null;
    try {
      return String.fromCharCodes(f.content as List<int>);
    } catch (_) {
      return null;
    }
  }

  // 工作表顺序 → sheetN.xml 的编号
  final sheetFiles = <String>[];
  for (final f in archive.files) {
    if (RegExp(r'^xl/worksheets/sheet\d+\.xml$').hasMatch(f.name)) sheetFiles.add(f.name);
  }
  sheetFiles.sort();

  // 工作表显示名（xl/workbook.xml 里 sheet 顺序与文件名顺序一致）
  final names = <String>[];
  final wb = textOf('xl/workbook.xml');
  if (wb != null) {
    try {
      for (final el in XmlDocument.parse(wb).findAllElements('sheet')) {
        final n = el.getAttribute('name');
        if (n != null) names.add(n);
      }
    } catch (_) {/* 名字取不到就退回文件名 */}
  }

  for (var i = 0; i < sheetFiles.length; i++) {
    final path = sheetFiles[i];
    final xml = textOf(path);
    if (xml == null) continue;

    // 关系表：xl/worksheets/sheet1.xml → xl/worksheets/_rels/sheet1.xml.rels
    // 注意必须用 replaceFirstMapped——Dart 的 replaceFirst(String) **不解析 $1**，
    // 传 '$1' 只会得到字面量，路径就错了（实测踩中）。
    final relPath = path.replaceFirstMapped(
      RegExp(r'([^/]+)$'),
      (m) => '_rels/${m[1]}.rels',
    );
    final rels = <String, String>{};
    final relXml = textOf(relPath);
    if (relXml != null) {
      try {
        for (final rel in XmlDocument.parse(relXml).findAllElements('Relationship')) {
          final id = rel.getAttribute('Id');
          final target = rel.getAttribute('Target');
          if (id != null && target != null) rels[id] = target;
        }
      } catch (_) {/* 关系解析失败 → 该表无外链 */}
    }

    final map = <String, String>{};
    try {
      for (final h in XmlDocument.parse(xml).findAllElements('hyperlink')) {
        final ref = _attrByLocal(h, 'ref') ?? h.getAttribute('ref');
        if (ref == null) continue;
        final rid = _attrByLocal(h, 'id');
        final loc = _attrByLocal(h, 'location');
        final url = (rid != null ? rels[rid] : null) ?? loc;
        if (url == null || url.isEmpty) continue;
        // 合并区间（如 A1:B1）只挂到左上角，与 Excel 行为一致
        final first = ref.contains(':') ? ref.split(':').first : ref;
        map[first] = url;
      }
    } catch (_) {/* 单表解析失败不影响其它表 */}

    final key = i < names.length ? names[i] : path.split('/').last;
    result[key] = map;
  }
  return result;
}

/// 由 A1 引用直接取超链接（供渲染层按 (row,col) 查表用）。
String? linkAt(Map<String, String> links, int row, int col) => links[_refOf(row, col)];

/// 供测试用：解析单元格引用。
(int, int) parseCellRef(String ref) => _parseRef(ref);

/// 供测试用：生成单元格引用。
String cellRef(int row, int col) => _refOf(row, col);
