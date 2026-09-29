// xlsx 读取器 + 统一加载器测试（v3.2.0）。
//
// 造样本的方式：先用 `excel` 包生成一个正常 xlsx，再**手工往 zip 里注入超链接**
// （超链接是 excel 包不支持写、而用户明确要求要读的能力，只能这样构造真实样本）。
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:excel/excel.dart' as xls;
import 'package:flutter_test/flutter_test.dart';

import 'package:dsh_mobile_app/docs/loader.dart';
import 'package:dsh_mobile_app/docs/model.dart';
import 'package:dsh_mobile_app/docs/xlsx.dart';

/// 造一个含 2 个工作表、多种单元格类型、1 条外链的 xlsx。
Uint8List makeXlsx() {
  final book = xls.Excel.createExcel();
  final s1 = book['Sheet1'];
  s1.appendRow([
    xls.TextCellValue('名称'),
    xls.TextCellValue('链接'),
    xls.TextCellValue('数量'),
  ]);
  s1.appendRow([
    xls.TextCellValue('文档A'),
    xls.TextCellValue('点我'),
    xls.IntCellValue(42),
  ]);
  s1.appendRow([
    xls.TextCellValue('文档B'),
    xls.TextCellValue(''),
    xls.DoubleCellValue(3.5),
  ]);
  book.setDefaultSheet('Sheet1');
  book['Sheet2'].appendRow([xls.TextCellValue('第二表')]);
  final raw = Uint8List.fromList(book.encode() ?? const []);

  // ── 注入超链接（B2 → https://example.com/doc?a=1&b=2） ──
  final src = ZipDecoder().decodeBytes(raw);
  final out = Archive();
  for (final f in src.files) {
    if (f.name == 'xl/worksheets/sheet1.xml') {
      var xml = utf8.decode(f.content as List<int>);
      // 超链接元素必须放在 sheetData 之后（OOXML 顺序要求）
      final close = xml.lastIndexOf('</sheetData>');
      if (close >= 0) {
        final ins = close + '</sheetData>'.length;
        xml = '${xml.substring(0, ins)}'
            '<hyperlinks><hyperlink ref="B2" r:id="rIdHL1"/></hyperlinks>'
            '${xml.substring(ins)}';
      }
      final b = utf8.encode(xml);
      out.addFile(ArchiveFile(f.name, b.length, b));
    } else if (f.name == 'xl/_rels/workbook.xml.rels') {
      var xml = utf8.decode(f.content as List<int>);
      xml = xml.replaceFirst('</Relationships>',
          '<Relationship Id="rIdHL1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/hyperlink" Target="https://example.com/doc?a=1&amp;b=2" TargetMode="External"/></Relationships>');
      final b = utf8.encode(xml);
      out.addFile(ArchiveFile(f.name, b.length, b));
    } else {
      out.addFile(f);
    }
  }
  // sheet1 自己的关系表：rIdHL1 → 目标 URL
  const relsXml = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '<Relationship Id="rIdHL1" '
      'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/hyperlink" '
      'Target="https://example.com/doc?a=1&amp;b=2" TargetMode="External"/>'
      '</Relationships>';
  final rb = utf8.encode(relsXml);
  out.addFile(ArchiveFile('xl/worksheets/_rels/sheet1.xml.rels', rb.length, rb));

  return Uint8List.fromList(ZipEncoder().encode(out) ?? const []);
}

void main() {
  group('XLSX 读取', () {
    test('工作表名与单元格文本正确读出', () {
      final doc = parseXlsx(makeXlsx(), '测试.xlsx');
      expect(doc.format, DocFormat.xlsx);
      final sp = doc.sheet;
      expect(sp, isNotNull);
      expect(sp!.sheets.length, 2);
      expect(sp.sheets[0].name, 'Sheet1');

      final rows = sp.sheets[0].rows;
      expect(rows[0][0].text, '名称');
      expect(rows[1][0].text, '文档A');
      // 关键回归：TextCellValue 的值是 TextSpan，取错会得到 "TextSpan(...)"
      expect(rows[1][0].text.contains('TextSpan'), isFalse);
      // 整数不该带小数点
      expect(rows[1][2].text, '42');
      // 小数保留
      expect(rows[2][2].text, '3.5');
    });

    test('超链接被正确提取并挂到对应单元格', () {
      final doc = parseXlsx(makeXlsx(), '测试.xlsx');
      final rows = doc.sheet!.sheets[0].rows;
      // B2（第 1 行第 1 列）应带链接
      final b2 = rows[1][1];
      expect(b2.url, 'https://example.com/doc?a=1&b=2', reason: 'XML 实体 &amp; 应还原成 &');
      expect(b2.text, '点我');
      // 其它单元格不应被误挂
      expect(rows[0][1].url, isNull);
      expect(rows[1][0].url, isNull);
      expect(rows[2][1].url, isNull);
    });

    test('第二张表也解析出来', () {
      final doc = parseXlsx(makeXlsx(), '测试.xlsx');
      final s2 = doc.sheet!.sheets[1];
      expect(s2.name, 'Sheet2');
      expect(s2.rows[0][0].text, '第二表');
    });

    test('坏字节不抛异常，降级为可读说明', () {
      final doc = parseXlsx(Uint8List.fromList(utf8.encode('这不是 xlsx')), '坏.xlsx');
      expect(doc.blocks.whereType<DocRaw>().isNotEmpty, isTrue);
      expect(doc.warnings.isNotEmpty, isTrue);
    });

    test('单元格引用换算', () {
      expect(cellRef(0, 0), 'A1');
      expect(cellRef(11, 27), 'AB12');
      expect(parseCellRef('A1'), (0, 0));
      expect(parseCellRef('AB12'), (11, 27));
      expect(parseCellRef('Z1'), (0, 25));
    });
  });

  group('统一加载器', () {
    test('按扩展名分派', () {
      expect(loadDocument(Uint8List.fromList(utf8.encode('# 标题')), 'a.md').format,
          DocFormat.markdown);
      expect(loadDocument(Uint8List.fromList(utf8.encode('纯文本')), 'a.txt').format,
          DocFormat.text);
      expect(loadDocument(makeXlsx(), 'a.xlsx').format, DocFormat.xlsx);
    });

    test('空文件给出可读说明', () {
      final doc = loadDocument(Uint8List(0), 'a.md');
      expect(doc.blocks.whereType<DocRaw>().isNotEmpty, isTrue);
    });

    test('未知扩展名按内容嗅探：文本 → text', () {
      final doc = loadDocument(Uint8List.fromList(utf8.encode('hello world\n第二行')), 'unknown.data');
      expect(doc.format, DocFormat.text);
    });

    test('未知扩展名按内容嗅探：zip 魔数且含 xl/ → xlsx', () {
      final doc = loadDocument(makeXlsx(), 'mystery.bin');
      expect(doc.format, DocFormat.xlsx);
    });

    test('完全不认识的二进制 → 明确提示不支持，而不是乱码', () {
      final junk = Uint8List.fromList(List<int>.generate(64, (i) => i == 0 ? 0 : i % 7));
      final doc = loadDocument(junk, 'x.bin');
      expect(doc.format, DocFormat.unknown);
      expect(doc.blocks.whereType<DocRaw>().isNotEmpty, isTrue);
    });

    test('超大文件被挡下', () {
      final big = Uint8List(kMaxDocBytes + 1);
      final doc = loadDocument(big, 'big.md');
      final raw = doc.blocks.whereType<DocRaw>().first;
      expect(raw.text.contains('过大'), isTrue);
    });

    test('UTF-8 BOM 不残留在正文里', () {
      final bytes = Uint8List.fromList([0xEF, 0xBB, 0xBF, ...utf8.encode('正文')]);
      final doc = loadDocument(bytes, 'a.txt');
      final para = doc.blocks.whereType<DocPara>().first;
      final text = para.spans.whereType<DocText>().map((e) => e.text).join();
      expect(text.startsWith('正文'), isTrue);
    });

    test('公式存在性判定（驱动「导出 Word」入口）', () {
      final withMath = loadDocument(
        Uint8List.fromList(utf8.encode(r'公式：$x^2+1$')),
        'a.md',
      );
      expect(documentHasMath(withMath), isTrue);
      final noMath = loadDocument(Uint8List.fromList(utf8.encode('没有公式')), 'a.md');
      expect(documentHasMath(noMath), isFalse);
    });
  });
}
