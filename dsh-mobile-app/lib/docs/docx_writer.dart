// DOCX 导出器（v3.2.0）——把统一文档模型写成 .docx，**公式写成 Word 原生 OMML**
// （即 Word 里 "Alt+=" 那种可继续编辑的公式，不是图片、也不是 LaTeX 纯文本）。
//
// 为什么自研而不是用 docx 库：导出必须能把**原始 OMML XML** 精确塞进 w:p 里，
// 而通用 docx 库的段落模型不暴露这种「插入任意 OOXML 子树」的口子
// （python-docx 系同样如此）。自己拼 OOXML 反而最直接、可控。
//
// 产物结构（最小可用且被 Word 认可）：
//   [Content_Types].xml
//   _rels/.rels
//   word/document.xml        ← 正文 + OMML 公式 + 超链接
//   word/styles.xml          ← Normal + Heading1..6 + TableGrid
//   word/_rels/document.xml.rels
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../math/omml.dart';
import 'model.dart';

const _wNs = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';
const _rNs = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships';
const _mNs = 'http://schemas.openxmlformats.org/officeDocument/2006/math';

/// XML 文本转义（正文 run 用）。
String _esc(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');

/// 把文档模型导出为 .docx 字节。
Uint8List buildDocx(Document doc, {String? title}) {
  final ctx = _DocxCtx();

  final bodyParts = <String>[];
  for (final b in doc.blocks) {
    bodyParts.add(ctx.block(b));
  }
  // xlsx 的表格也可导出成 Word 表格（只导出第一张表，够用且不炸体积）
  final sheet = doc.sheet;
  if (sheet != null && sheet.sheets.isNotEmpty && doc.blocks.isEmpty) {
    final s = sheet.sheets.first;
    bodyParts.add(_p(_run(s.name, bold: true), style: 'Heading1'));
    final rows = <List<List<DocInline>>>[
      for (final r in s.rows) [for (final c in r) [DocText(c.text)]],
    ];
    bodyParts.add(ctx.table(rows, headerRow: true));
  }

  if (bodyParts.isEmpty) {
    bodyParts.add(_p(_run('（文档为空）')));
  }

  final document = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
      '<w:document xmlns:w="$_wNs" xmlns:r="$_rNs" xmlns:m="$_mNs">'
      '<w:body>${bodyParts.join()}<w:sectPr>'
      '<w:pgSz w:w="11906" w:h="16838"/>' // A4
      '<w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440" '
      'w:header="851" w:footer="992" w:gutter="0"/>'
      '</w:sectPr></w:body></w:document>';

  final archive = Archive();
  void add(String name, String content) {
    final bytes = utf8.encode(content);
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  }

  add('[Content_Types].xml', _contentTypes);
  add('_rels/.rels', _rootRels);
  add('word/document.xml', document);
  add('word/styles.xml', _styles);
  add('word/_rels/document.xml.rels', ctx.relsXml());

  final encoded = ZipEncoder().encode(archive);
  if (encoded == null) {
    // 极端情况下的兜底：不应发生，但不让调用方拿到 null
    return Uint8List.fromList(const <int>[]);
  }
  return Uint8List.fromList(encoded);
}

/// 导出上下文：收集超链接关系，保持 rId 唯一。
class _DocxCtx {
  final Map<String, String> _rels = {};
  int _seq = 0;

  String _relId(String url) {
    final exist = _rels.entries.where((e) => e.value == url).firstOrNull;
    if (exist != null) return exist.key;
    _seq++;
    final id = 'rIdL$_seq';
    _rels[id] = url;
    return id;
  }

  String relsXml() {
    final b = StringBuffer();
    b.write('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n');
    b.write('<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">');
    b.write('<Relationship Id="rIdStyles" '
        'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" '
        'Target="styles.xml"/>');
    for (final e in _rels.entries) {
      b.write('<Relationship Id="${e.key}" '
          'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/hyperlink" '
          'Target="${_esc(e.value)}" TargetMode="External"/>');
    }
    b.write('</Relationships>');
    return b.toString();
  }

  /// 块 → OOXML 片段。
  String block(DocBlock b) {
    switch (b) {
      case DocHeading(:final level, :final spans):
        return _p(inline(spans), style: 'Heading${level.clamp(1, 6)}');

      case DocPara(:final spans, :final align):
        return _p(inline(spans), align: align);

      case DocList(:final items, :final ordered, :final start):
        final out = StringBuffer();
        for (var i = 0; i < items.length; i++) {
          final marker = ordered ? '${start + i}. ' : '• ';
          out.write(_p(_run(marker) + inline(items[i]), indent: 420));
        }
        return out.toString();

      case DocCode(:final text):
        final out = StringBuffer();
        for (final line in text.split('\n')) {
          out.write(_p(_run(line, code: true), shade: 'F5F5F5'));
        }
        return out.toString();

      case DocQuote(:final spans):
        return _p(inline(spans), indent: 420, italicAll: true);

      case DocRule():
        return _p('', bottomBorder: true);

      case DocTable(:final rows):
        return table([
          for (final r in rows) [for (final c in r) c.spans],
        ], headerRow: b.headerRow);

      case DocMathBlock(:final tex):
        // 公式独占一段 → m:oMathPara（Word 里就是显示式公式，可 Alt+= 编辑）
        return '<w:p><m:oMathPara>'
            '<m:oMathParaPr><m:jc m:val="center"/></m:oMathParaPr>'
            '${_ommlInner(tex)}'
            '</m:oMathPara></w:p>';

      case DocRaw(:final text):
        return _p(_run(text));
    }
  }

  /// 行内序列 → run 串。
  String inline(List<DocInline> spans) {
    final b = StringBuffer();
    for (final s in spans) {
      switch (s) {
        case DocText():
          if (s.text.isEmpty) break;
          b.write(_run(s.text,
              bold: s.bold,
              italic: s.italic,
              underline: s.underline,
              strike: s.strike,
              code: s.code,
              color: s.colorHex,
              superscript: s.superscript,
              subscript: s.subscript));
        case DocBreak():
          b.write('<w:r><w:br/></w:r>');
        case DocLink(:final spans, :final url):
          if (url == null) {
            b.write(inline(spans));
          } else {
            b.write('<w:hyperlink r:id="${_relId(url)}">${inline(spans)}</w:hyperlink>');
          }
        case DocMathInline(:final tex):
          // 行内公式：直接内联 m:oMath（与文字同段）
          b.write(_ommlInner(tex));
        case DocImage(:final url, :final alt):
          b.write(_run(alt ?? url ?? '[图片]', italic: true));
      }
    }
    return b.toString();
  }

  /// 表格。
  String table(List<List<List<DocInline>>> rows, {bool headerRow = false}) {
    if (rows.isEmpty) return '';
    final cols = rows.map((r) => r.length).fold<int>(1, (a, c) => c > a ? c : a);
    final gridWidth = (9000 / cols).floor();

    final b = StringBuffer();
    b.write('<w:tbl><w:tblPr>'
        '<w:tblW w:w="0" w:type="auto"/>'
        '<w:tblBorders>'
        '<w:top w:val="single" w:sz="4" w:space="0" w:color="999999"/>'
        '<w:left w:val="single" w:sz="4" w:space="0" w:color="999999"/>'
        '<w:bottom w:val="single" w:sz="4" w:space="0" w:color="999999"/>'
        '<w:right w:val="single" w:sz="4" w:space="0" w:color="999999"/>'
        '<w:insideH w:val="single" w:sz="4" w:space="0" w:color="999999"/>'
        '<w:insideV w:val="single" w:sz="4" w:space="0" w:color="999999"/>'
        '</w:tblBorders></w:tblPr>');
    b.write('<w:tblGrid>');
    for (var c = 0; c < cols; c++) {
      b.write('<w:gridCol w:w="$gridWidth"/>');
    }
    b.write('</w:tblGrid>');

    for (var r = 0; r < rows.length; r++) {
      final isHeader = headerRow && r == 0;
      b.write('<w:tr>');
      for (var c = 0; c < cols; c++) {
        final cell = c < rows[r].length ? rows[r][c] : <DocInline>[];
        b.write('<w:tc><w:tcPr><w:tcW w:w="$gridWidth" w:type="dxa"/>');
        if (isHeader) {
          b.write('<w:shd w:val="clear" w:color="auto" w:fill="EEEEEE"/>');
        }
        b.write('</w:tcPr>');
        // 单元格必须至少含一个 w:p
        final content = inline(cell);
        b.write(content.isEmpty ? _p('') : _p(content));
        b.write('</w:tc>');
      }
      b.write('</w:tr>');
    }
    b.write('</w:tbl>');
    // 两个相邻表格之间必须有段落，否则 Word 会报文档损坏
    b.write(_p(''));
    return b.toString();
  }

  /// TeX → OMML 片段（`texToOmmlElement` 已带 `<m:oMath>` 外壳，直接内联即可）。
  String _ommlInner(String tex) {
    final el = texToOmmlElement(tex);
    final xml = el.toXmlString();
    return xml;
  }
}

// ══════════════════════════════════════════════════════════════════
// 低层片段
// ══════════════════════════════════════════════════════════════════

/// run 属性。**子元素顺序必须符合 CT_RPr schema**：
/// rFonts → b → i → strike → color → sz → u → vertAlign（顺序错 Word 会判损坏）。
String _rpr({
  bool bold = false,
  bool italic = false,
  bool underline = false,
  bool strike = false,
  bool code = false,
  String? color,
  bool superscript = false,
  bool subscript = false,
}) {
  final b = StringBuffer();
  if (code) {
    b.write('<w:rFonts w:ascii="Consolas" w:hAnsi="Consolas" w:eastAsia="Consolas" w:cs="Consolas"/>');
  }
  if (bold) b.write('<w:b/>');
  if (italic) b.write('<w:i/>');
  if (strike) b.write('<w:strike/>');
  if (color != null && RegExp(r'^[0-9A-Fa-f]{6}$').hasMatch(color)) {
    b.write('<w:color w:val="${color.toUpperCase()}"/>');
  }
  if (underline) b.write('<w:u w:val="single"/>');
  if (superscript) b.write('<w:vertAlign w:val="superscript"/>');
  if (subscript) b.write('<w:vertAlign w:val="subscript"/>');
  if (b.isEmpty) return '';
  return '<w:rPr>$b</w:rPr>';
}

String _run(
  String text, {
  bool bold = false,
  bool italic = false,
  bool underline = false,
  bool strike = false,
  bool code = false,
  String? color,
  bool superscript = false,
  bool subscript = false,
}) {
  final rpr = _rpr(
    bold: bold,
    italic: italic,
    underline: underline,
    strike: strike,
    code: code,
    color: color,
    superscript: superscript,
    subscript: subscript,
  );
  return '<w:r>$rpr<w:t xml:space="preserve">${_esc(text)}</w:t></w:r>';
}

/// 段落。`w:pPr` 子元素顺序：pStyle → ... → shd → ... → jc → ... → ind → ... → pBdr
String _p(
  String inner, {
  String? style,
  String? align,
  int? indent,
  String? shade,
  bool italicAll = false,
  bool bottomBorder = false,
}) {
  final p = StringBuffer();
  if (style != null) p.write('<w:pStyle w:val="$style"/>');
  if (shade != null) p.write('<w:shd w:val="clear" w:color="auto" w:fill="$shade"/>');
  if (align != null) {
    final v = switch (align) {
      'center' => 'center',
      'right' => 'right',
      'justify' || 'both' => 'both',
      _ => 'left',
    };
    p.write('<w:jc w:val="$v"/>');
  }
  if (indent != null) p.write('<w:ind w:left="$indent"/>');
  if (bottomBorder) {
    p.write('<w:pBdr><w:bottom w:val="single" w:sz="6" w:space="1" w:color="CCCCCC"/></w:pBdr>');
  }
  final ppr = p.isEmpty ? '' : '<w:pPr>$p</w:pPr>';
  final body = (inner.isEmpty && !italicAll) ? '' : inner;
  return '<w:p>$ppr$body</w:p>';
}

// ══════════════════════════════════════════════════════════════════
// 固定部件
// ══════════════════════════════════════════════════════════════════

const String _contentTypes = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
    '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
    '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
    '<Default Extension="xml" ContentType="application/xml"/>'
    '<Override PartName="/word/document.xml" '
    'ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'
    '<Override PartName="/word/styles.xml" '
    'ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>'
    '</Types>';

const String _rootRels = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
    '<Relationship Id="rId1" '
    'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" '
    'Target="word/document.xml"/>'
    '</Relationships>';

/// 最小样式表：正文 + 标题 1..6 + 表格网格线。
const String _styles = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
    '<w:styles xmlns:w="$_wNs">'
    '<w:docDefaults><w:rPrDefault><w:rPr>'
    '<w:rFonts w:ascii="Calibri" w:hAnsi="Calibri" w:eastAsia="Microsoft YaHei"/>'
    '<w:sz w:val="22"/><w:szCs w:val="22"/>'
    '</w:rPr></w:rPrDefault>'
    '<w:pPrDefault><w:pPr><w:spacing w:after="120" w:line="276" w:lineRule="auto"/></w:pPr></w:pPrDefault>'
    '</w:docDefaults>'
    '<w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/></w:style>'
    '<w:style w:type="paragraph" w:styleId="Heading1"><w:name w:val="heading 1"/>'
    '<w:basedOn w:val="Normal"/><w:pPr><w:outlineLvl w:val="0"/><w:spacing w:before="240" w:after="120"/></w:pPr>'
    '<w:rPr><w:b/><w:sz w:val="36"/></w:rPr></w:style>'
    '<w:style w:type="paragraph" w:styleId="Heading2"><w:name w:val="heading 2"/>'
    '<w:basedOn w:val="Normal"/><w:pPr><w:outlineLvl w:val="1"/><w:spacing w:before="200" w:after="100"/></w:pPr>'
    '<w:rPr><w:b/><w:sz w:val="30"/></w:rPr></w:style>'
    '<w:style w:type="paragraph" w:styleId="Heading3"><w:name w:val="heading 3"/>'
    '<w:basedOn w:val="Normal"/><w:pPr><w:outlineLvl w:val="2"/><w:spacing w:before="160" w:after="80"/></w:pPr>'
    '<w:rPr><w:b/><w:sz w:val="26"/></w:rPr></w:style>'
    '<w:style w:type="paragraph" w:styleId="Heading4"><w:name w:val="heading 4"/>'
    '<w:basedOn w:val="Normal"/><w:pPr><w:outlineLvl w:val="3"/></w:pPr>'
    '<w:rPr><w:b/><w:sz w:val="24"/></w:rPr></w:style>'
    '<w:style w:type="paragraph" w:styleId="Heading5"><w:name w:val="heading 5"/>'
    '<w:basedOn w:val="Normal"/><w:pPr><w:outlineLvl w:val="4"/></w:pPr>'
    '<w:rPr><w:b/><w:sz w:val="22"/></w:rPr></w:style>'
    '<w:style w:type="paragraph" w:styleId="Heading6"><w:name w:val="heading 6"/>'
    '<w:basedOn w:val="Normal"/><w:pPr><w:outlineLvl w:val="5"/></w:pPr>'
    '<w:rPr><w:b/><w:i/><w:sz w:val="22"/></w:rPr></w:style>'
    '</w:styles>';
