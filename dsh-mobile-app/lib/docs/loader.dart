// 统一文档加载器（v3.2.0）——字节 + 文件名 → docs/model.dart 的 Document。
//
// 一处收口的好处：无论是「从电脑工作区下载」「手机本地文件」「分享进来」还是
// 「聊天里的产物」，最终都走同一个分派，格式能力不会各写一遍各漏一处。
import 'dart:convert';
import 'dart:typed_data';

import 'docx.dart';
import 'markdown.dart';
import 'model.dart';
import 'xlsx.dart';

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
      case DocFormat.unknown:
        return Document(
          title,
          DocFormat.unknown,
          [DocRaw('暂不支持打开该格式（$name）。\n目前可读：md / txt / docx / xlsx。')],
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

/// 内容嗅探：zip 魔数 → 看内部条目名区分 docx / xlsx；看似文本 → txt。
DocFormat _sniff(Uint8List bytes) {
  if (bytes.length >= 4 && bytes[0] == 0x50 && bytes[1] == 0x4B) {
    // 直接扫字节流找特征字符串（比解包便宜，且对损坏包也有效）
    final head = String.fromCharCodes(bytes.sublist(0, bytes.length < 4096 ? bytes.length : 4096));
    if (head.contains('word/')) return DocFormat.docx;
    if (head.contains('xl/')) return DocFormat.xlsx;
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
