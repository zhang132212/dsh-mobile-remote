// 统一文档加载器（v3.2.0，v3.2.11 扩展数据结构家族）——字节 + 文件名 → docs/model.dart 的 Document。
//
// 一处收口的好处：无论是「从电脑工作区下载」「手机本地文件」「分享进来」还是
// 「聊天里的产物」，最终都走同一个分派，格式能力不会各写一遍各漏一处。
//
// v3.2.11：新增 xml / json（树形阅读）、html（就地读网页）、svg（本机矢量渲染）；
// 另外扩展名不认识时按内容嗅探，让拷来的配置片段 / 抓下来的页面也能直接打开。
import 'dart:convert';
import 'dart:typed_data';

import 'docx.dart';
import 'html.dart';
import 'json.dart';
import 'markdown.dart';
import 'model.dart';
import 'svg.dart';
import 'xlsx.dart';
import 'xml.dart';

/// 可打开的最大字节数（防超大文件把手机内存吃满；纯粹是稳妥起见）。
const int kMaxDocBytes = 24 * 1024 * 1024;

/// 字节 + 文件名 → Document。**永不抛异常**：解析失败会得到带 DocRaw 说明的文档。
Document loadDocument(Uint8List bytes, String name) {
  final title = _titleOf(name);
  if (bytes.isEmpty) {
    return Document(title, DocFormat.unknown, const [DocRaw('（文件为空）')]);
  }
  if (bytes.length > kMaxDocBytes) {
    return Document(
      title,
      DocFormat.unknown,
      [DocRaw('（文件过大：${(bytes.length / 1024 / 1024).toStringAsFixed(1)} MB，暂不支持打开）')],
    );
  }

  var fmt = detectFormat(name);

  // 扩展名不认识时按内容嗅探，尽量别让用户吃闭门羹
  if (fmt == DocFormat.unknown) {
    fmt = _sniff(bytes);
  }

  try {
    switch (fmt) {
      case DocFormat.markdown:
        return parseMarkdown(_decodeText(bytes), title);
      case DocFormat.text:
        return parsePlainText(_decodeText(bytes), title);
      case DocFormat.docx:
        return parseDocx(bytes, name);
      case DocFormat.xlsx:
        return parseXlsx(bytes, name);
      case DocFormat.xml:
        return parseXml(_decodeText(bytes), title);
      case DocFormat.json:
        return parseJson(_decodeText(bytes), title);
      case DocFormat.html:
        return parseHtml(_decodeText(bytes), title);
      case DocFormat.svg:
        return parseSvg(_decodeText(bytes), title);
      case DocFormat.pdf:
        // PDF 不做块级解析：阅读页拿到原始字节后交给原生按页渲染（docs/pdf_view.dart）。
        // 这里返回空 blocks 只是为了让「格式判定 → 阅读页分派」保持单一路径。
        return Document(title, DocFormat.pdf, const []);
      case DocFormat.unknown:
        return Document(
          title,
          DocFormat.unknown,
          [
            DocRaw('暂不支持打开该格式（$name）。\n'
                '目前可读：md / txt / csv / json / xml / html / svg / docx / xlsx / pdf。'),
          ],
        );
    }
  } catch (e) {
    // 任何解析器都不该抛，这里是最后一道兜底
    return Document(title, fmt, [DocRaw('解析失败：$e')]);
  }
}

/// 文本解码：优先 UTF-8；失败（含 BOM/GBK 混合的旧文件）退回 latin1 保证不乱码到不可读。
String _decodeText(Uint8List bytes) {
  try {
    var b = bytes;
    // 去 UTF-8 BOM
    if (b.length >= 3 && b[0] == 0xEF && b[1] == 0xBB && b[2] == 0xBF) {
      b = Uint8List.sublistView(b, 3);
    }
    return utf8.decode(b);
  } catch (_) {
    try {
      return utf8.decode(bytes, allowMalformed: true);
    } catch (_) {
      return String.fromCharCodes(bytes);
    }
  }
}

/// 内容嗅探：zip 魔数 → docx / xlsx；PDF 魔数 → pdf；开头像 XML / HTML / SVG / JSON 的直接认；
/// 其余可打印文本 → txt。
DocFormat _sniff(Uint8List bytes) {
  // v3.2.16：%PDF- 魔数（有些分享渠道会把文件名改成 download.bin，扩展名靠不住）
  if (bytes.length >= 5 &&
      bytes[0] == 0x25 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x44 &&
      bytes[3] == 0x46 &&
      bytes[4] == 0x2D) {
    return DocFormat.pdf;
  }
  if (bytes.length >= 4 && bytes[0] == 0x50 && bytes[1] == 0x4B) {
    // 直接扫字节流找特征字符串（比解包便宜，且对损坏包也有效）
    final head = String.fromCharCodes(bytes.sublist(0, bytes.length < 4096 ? bytes.length : 4096));
    if (head.contains('word/')) return DocFormat.docx;
    if (head.contains('xl/')) return DocFormat.xlsx;
  }
  // 文本类格式特征（必须放在「可打印文本 → txt」之前，否则会一律落成 txt）
  final lead = _headText(bytes)
      .replaceFirst(RegExp(r'^\uFEFF'), '')
      .trimLeft();
  if (lead.isNotEmpty) {
    final lower = lead.toLowerCase();
    if (lower.startsWith('<?xml')) {
      return lower.contains('<svg') ? DocFormat.svg : DocFormat.xml;
    }
    if (lower.startsWith('<svg')) return DocFormat.svg;
    if (lower.startsWith('<!doctype html') || lower.startsWith('<html')) {
      return DocFormat.html;
    }
    if (lead.startsWith('<')) return DocFormat.xml;
    if (lead.startsWith('{') || lead.startsWith('[')) return DocFormat.json;
  }
  // 前 512 字节里没有 NUL 且可打印比例高 → 当文本
  final n = bytes.length < 512 ? bytes.length : 512;
  var printable = 0;
  for (var i = 0; i < n; i++) {
    final c = bytes[i];
    if (c == 0) return DocFormat.unknown;
    if (c == 9 || c == 10 || c == 13 || (c >= 32 && c < 127) || c >= 0x80) printable++;
  }
  if (n > 0 && printable / n > 0.9) return DocFormat.text;
  return DocFormat.unknown;
}

/// 取开头 4KB 文本用于格式嗅探（容错解码，永不抛）。
String _headText(Uint8List bytes) {
  final n = bytes.length < 4096 ? bytes.length : 4096;
  return utf8.decode(Uint8List.sublistView(bytes, 0, n), allowMalformed: true);
}

String _titleOf(String name) {
  final base = name.split(RegExp(r'[\\/]')).last;
  final dot = base.lastIndexOf('.');
  return dot > 0 ? base.substring(0, dot) : base;
}

/// 该文档是否含公式（决定「导出 Word 公式」入口是否点亮）。
bool documentHasMath(Document doc) {
  for (final b in doc.blocks) {
    if (b is DocMathBlock) return true;
    if (b is DocPara && b.spans.any((s) => s is DocMathInline)) return true;
    if (b is DocHeading && b.spans.any((s) => s is DocMathInline)) return true;
    if (b is DocList && b.items.any((it) => it.any((s) => s is DocMathInline))) return true;
    if (b is DocQuote && b.spans.any((s) => s is DocMathInline)) return true;
    if (b is DocTable &&
        b.rows.any((r) => r.any((c) => c.spans.any((s) => s is DocMathInline)))) {
      return true;
    }
  }
  return false;
}
/// 该文档是否是树形结构（XML / JSON）——阅读页据此提供「展开/折叠全部」入口。
bool documentHasTree(Document doc) => doc.blocks.any((b) => b is DocTree);
