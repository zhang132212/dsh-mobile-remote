// Markdown / 纯文本读取器（v3.2.0）——把文本类内容归一成 docs/model.dart 的块模型，
// 交给统一的阅读页渲染，从而在只读前提下保住各自的「格式特色」：
//   · Markdown：标题/列表/引用/代码块/表格/分隔线/行内样式/链接/公式
//   · 纯文本：段落原样保留 + URL 自动识别成可点链接 + CSV 自动成表
//
// 与 lib/md.dart（聊天消息渲染器）是**两条独立路径**：聊天流追求流式与紧凑，
// 文档阅读页追求保真与目录；两者共用同一套公式探测（math/tex.dart）与渲染
// （math/view.dart），所以公式表现一致。
import 'model.dart';
import '../math/tex.dart';

// ── 块级判定（与 md.dart 同规则，这里独立实现以保持 docs/ 不依赖 Flutter） ──
final _headingRe = RegExp(r'^(#{1,6})\s+(.*)$');
final _hrRe = RegExp(r'^\s*(-{3,}|\*{3,}|_{3,})\s*$');
final _bulletRe = RegExp(r'^(\s*)[-*+]\s+(.*)$');
final _orderedRe = RegExp(r'^(\s*)(\d+)[.)]\s+(.*)$');
final _quoteRe = RegExp(r'^\s*>\s?(.*)$');
final _tableSepRe = RegExp(r'^\s*\|?[\s:|-]+\|?\s*$');

/// 解析 Markdown → Document。
Document parseMarkdown(String text, String title) {
  final blocks = <DocBlock>[];
  final lines = text.split('\n');
  var i = 0;

  List<DocInline> para = [];
  var pendingList = <List<DocInline>>[];
  var listOrdered = false;
  var listStart = 1;

  void flushPara() {
    if (para.isEmpty) return;
    blocks.add(DocPara(List.of(para)));
    para = [];
  }

  void flushList() {
    if (pendingList.isEmpty) return;
    blocks.add(DocList(List.of(pendingList), ordered: listOrdered, start: listStart));
    pendingList = [];
    listOrdered = false;
    listStart = 1;
  }

  void flushAll() {
    flushPara();
    flushList();
  }

  while (i < lines.length) {
    final raw = lines[i];

    // 代码围栏
    final fence = _fenceOpenCount(raw);
    if (fence != null) {
      flushAll();
      final lang = raw.trim().substring(fence).trim();
      final buf = <String>[];
      i++;
      while (i < lines.length && !_isFenceClose(lines[i], fence)) {
        buf.add(lines[i]);
        i++;
      }
      i++; // 跳过闭合行
      blocks.add(DocCode(buf.join('\n'), lang: lang.isEmpty ? null : lang));
      continue;
    }

    // 块级公式：显式标记整行（见 docs/formula-markup.md）或 $$...$$ 独占若干行
    final wholeLineTex = formulaMarkupWholeLine(raw);
    if (wholeLineTex != null) {
      flushAll();
      blocks.add(DocMathBlock(wholeLineTex));
      i++;
      continue;
    }
    if (raw.trimLeft().startsWith(r'$$')) {
      flushAll();
      final after = raw.trimLeft().substring(2);
      // 同一行闭合？
      final closeInLine = after.indexOf(r'$$');
      if (closeInLine >= 0) {
        final tex = after.substring(0, closeInLine).trim();
        if (tex.isNotEmpty) blocks.add(DocMathBlock(tex));
        i++;
        continue;
      }
      final buf = <String>[after];
      i++;
      var closed = false;
      while (i < lines.length) {
        final idx = lines[i].indexOf(r'$$');
        if (idx >= 0) {
          buf.add(lines[i].substring(0, idx));
          closed = true;
          i++;
          break;
        }
        buf.add(lines[i]);
        i++;
      }
      final tex = buf.join(' ').trim();
      if (tex.isNotEmpty) blocks.add(DocMathBlock(tex));
      if (!closed) {
        // 未闭合：按普通段落处理，避免吞掉后文
        blocks.add(DocRaw('（公式未闭合）${tex.isEmpty ? '' : tex}'));
      }
      continue;
    }

    // 表格
    if (raw.trimLeft().startsWith('|') &&
        i + 1 < lines.length &&
        _tableSepRe.hasMatch(lines[i + 1]) &&
        lines[i + 1].contains('-')) {
      flushAll();
      final rows = <List<DocCell>>[];
      final headCells = _splitRow(raw);
      rows.add([for (final c in headCells) DocCell(parseInline(c), header: true)]);
      // 对齐信息
      final aligns = _splitRow(lines[i + 1])
          .map((s) {
            final t = s.trim();
            final l = t.startsWith(':');
            final r = t.endsWith(':');
            if (l && r) return 'center';
            if (r) return 'right';
            if (l) return 'left';
            return null;
          })
          .toList();
      i += 2;
      while (i < lines.length && lines[i].trimLeft().startsWith('|')) {
        final cells = _splitRow(lines[i]);
        rows.add([
          for (var c = 0; c < cells.length; c++)
            DocCell(parseInline(cells[c]), align: c < aligns.length ? aligns[c] : null),
        ]);
        i++;
      }
      blocks.add(DocTable(rows, headerRow: true));
      continue;
    }

    // 标题
    final h = _headingRe.firstMatch(raw);
    if (h != null) {
      flushAll();
      blocks.add(DocHeading(h.group(1)!.length, parseInline(h.group(2)!.trim())));
      i++;
      continue;
    }

    // 分隔线
    if (_hrRe.hasMatch(raw)) {
      flushAll();
      blocks.add(const DocRule());
      i++;
      continue;
    }

    // 引用
    final q = _quoteRe.firstMatch(raw);
    if (q != null) {
      flushAll();
      blocks.add(DocQuote(parseInline(q.group(1)!)));
      i++;
      continue;
    }

    // 列表
    final b = _bulletRe.firstMatch(raw);
    final o = _orderedRe.firstMatch(raw);
    if (b != null || o != null) {
      flushPara();
      final isOrdered = o != null;
      if (pendingList.isEmpty) {
        listOrdered = isOrdered;
        listStart = isOrdered ? (int.tryParse(o.group(2)!) ?? 1) : 1;
      }
      pendingList.add(parseInline(b != null ? b.group(2)! : o!.group(3)!));
      i++;
      continue;
    }

    // 空行结束当前块
    if (raw.trim().isEmpty) {
      flushAll();
      i++;
      continue;
    }

    if (pendingList.isNotEmpty) flushList();
    para.addAll(parseInline(raw));
    para.add(const DocBreak());
    i++;
  }
  flushAll();

  // 去掉每段末尾多余的 DocBreak
  for (var k = 0; k < blocks.length; k++) {
    final blk = blocks[k];
    if (blk is DocPara && blk.spans.isNotEmpty && blk.spans.last is DocBreak) {
      final spans = List<DocInline>.of(blk.spans)..removeLast();
      blocks[k] = DocPara(spans, align: blk.align);
    }
  }

  return Document(title, DocFormat.markdown, blocks);
}

/// 解析纯文本 → Document：保留原始换行，自动识别 URL，CSV 自动成表。
Document parsePlainText(String text, String title) {
  // CSV 嗅探：连续多行且含逗号分隔、列数一致 → 当表格
  final csv = _tryParseCsv(text);
  if (csv != null) {
    return Document(title, DocFormat.text, [csv]);
  }

  final blocks = <DocBlock>[];
  final lines = text.split('\n');
  var buf = <String>[];

  void flush() {
    if (buf.isEmpty) return;
    blocks.add(DocPara(parseInline(buf.join('\n'))));
    buf = [];
  }

  for (final line in lines) {
    if (line.trim().isEmpty) {
      flush();
      // 保留空行形成的段落间隔（不产出空块）
      continue;
    }
    buf.add(line);
  }
  flush();

  if (blocks.isEmpty) blocks.add(const DocRaw('（空文件）'));
  return Document(title, DocFormat.text, blocks);
}

/// CSV 嗅探：≥2 行、每行 ≥2 列、列数一致且不是散文。
DocBlock? _tryParseCsv(String text) {
  final lines = text.split('\n').where((l) => l.trim().isNotEmpty).toList();
  if (lines.length < 2) return null;
  final counts = <int, int>{};
  for (final l in lines.take(50)) {
    // 简单计数（不处理引号内的逗号——嗅探足够）
    final n = l.split(',').length;
    counts[n] = (counts[n] ?? 0) + 1;
  }
  if (counts.isEmpty) return null;
  final best = counts.entries.reduce((a, b) => a.value >= b.value ? a : b);
  if (best.key < 2) return null; // 至少两列
  if (best.value < lines.length * 0.7) return null; // 列数不一致 → 不是表
  // 中文散文里逗号很常见：要求「逗号数量多」且行长较短
  final avgLen = lines.map((l) => l.length).reduce((a, b) => a + b) / lines.length;
  if (avgLen > 120) return null;

  final rows = <List<DocCell>>[];
  for (final l in lines) {
    rows.add([for (final c in l.split(',')) DocCell(parseInline(c.trim()))]);
  }
  return DocTable(rows, headerRow: true);
}

// ══════════════════════════════════════════════════════════════════
// 行内解析
// ══════════════════════════════════════════════════════════════════

final _inlineRe = RegExp(
  // v3.2.4：`![alt](src)` 必须排在链接前面 —— 否则 `[...](...)` 会先把 `!` 之后的部分吃掉，
  // 图片就永远解析不出来（这正是「文档里图片只显示占位」的第一个原因）。
  r'(!\[[^\]]*\]\([^)\s]+\)|\*\*[^*]+\*\*|\*[^*\s][^*]*\*|`[^`]+`|\[[^\]]*\]\([^)\s]+\)|https?://[^\s<>()\[\]{}"“”‘’]+)',
);

/// 行内解析（三层优先级：行内代码 → 公式 → 粗斜体/链接）。
///
/// 顺序很关键，踩过坑：**行内代码必须最先切**。写公式语法说明时正文里常出现
/// 「反引号包着 $$…$$」，若先做公式探测，`$$` 会被当成显示式公式、反引号反而
/// 变成字面量（实测：正文显示成「用 ` `…` ` 包裹」）。代码块内的 `$` 同理不探测。
List<DocInline> parseInline(String text) {
  if (text.isEmpty) return const [];
  final out = <DocInline>[];
  var last = 0;
  for (final m in _codeSpanRe.allMatches(text)) {
    if (m.start > last) out.addAll(_mathAndMd(text.substring(last, m.start)));
    out.add(DocText(m.group(1)!, code: true));
    last = m.end;
  }
  if (last < text.length) out.addAll(_mathAndMd(text.substring(last)));
  return out;
}

final _codeSpanRe = RegExp(r'`([^`]+)`');

/// 第二层：切公式；剩下的交给 Markdown 行内规则。
List<DocInline> _mathAndMd(String text) {
  if (text.isEmpty) return const [];
  final segs = findMathSegments(text);
  if (segs.isEmpty) return _mdInline(text);
  final out = <DocInline>[];
  var last = 0;
  for (final s in segs) {
    if (s.start > last) out.addAll(_mdInline(text.substring(last, s.start)));
    out.add(DocMathInline(s.tex));
    last = s.end;
  }
  if (last < text.length) out.addAll(_mdInline(text.substring(last)));
  return out;
}

List<DocInline> _mdInline(String text) {
  final out = <DocInline>[];
  var last = 0;
  for (final m in _inlineRe.allMatches(text)) {
    if (m.start > last) out.add(DocText(text.substring(last, m.start)));
    final tok = m.group(0)!;
    if (tok.startsWith('![')) {
      // v3.2.4：图片 `![alt](src)` → DocImage（渲染器会按路径/URL 真取图）
      final im = RegExp(r'^!\[([^\]]*)\]\(([^)]*)\)$').firstMatch(tok);
      if (im != null) {
        final src = im.group(2)!.trim();
        final alt = im.group(1)!.trim();
        out.add(DocImage(src.isEmpty ? null : src, alt: alt.isEmpty ? null : alt));
      } else {
        out.add(DocText(tok));
      }
    } else if (tok.startsWith('**')) {
      out.add(DocText(tok.substring(2, tok.length - 2), bold: true));
    } else if (tok.startsWith('`')) {
      out.add(DocText(tok.substring(1, tok.length - 1), code: true));
    } else if (tok.startsWith('[')) {
      final mm = RegExp(r'^\[([^\]]*)\]\(([^)]*)\)$').firstMatch(tok);
      if (mm != null) {
        final url = mm.group(2)!.trim();
        out.add(DocLink([DocText(mm.group(1)!)], url.isEmpty ? null : url));
      } else {
        out.add(DocText(tok));
      }
    } else if (tok.startsWith('http')) {
      out.add(DocLink([DocText(tok)], tok));
    } else {
      out.add(DocText(tok.substring(1, tok.length - 1), italic: true));
    }
    last = m.end;
  }
  if (last < text.length) out.add(DocText(text.substring(last)));
  // 合并相邻的纯文本片段，减少 widget 数量
  return _mergeText(out);
}

List<DocInline> _mergeText(List<DocInline> spans) {
  final out = <DocInline>[];
  for (final s in spans) {
    if (s is DocText && out.isNotEmpty) {
      final prev = out.last;
      if (prev is DocText &&
          prev.bold == s.bold &&
          prev.italic == s.italic &&
          prev.underline == s.underline &&
          prev.strike == s.strike &&
          prev.code == s.code &&
          prev.colorHex == s.colorHex &&
          prev.sizeScale == s.sizeScale &&
          prev.superscript == s.superscript &&
          prev.subscript == s.subscript) {
        out[out.length - 1] = DocText(prev.text + s.text,
            bold: s.bold,
            italic: s.italic,
            underline: s.underline,
            strike: s.strike,
            code: s.code,
            superscript: s.superscript,
            subscript: s.subscript,
            sizeScale: s.sizeScale,
            colorHex: s.colorHex);
        continue;
      }
    }
    out.add(s);
  }
  return out;
}

/// `| a | b |` → ['a','b']
List<String> _splitRow(String line) {
  var t = line.trim();
  if (t.startsWith('|')) t = t.substring(1);
  if (t.endsWith('|')) t = t.substring(0, t.length - 1);
  return t.split('|');
}

int? _fenceOpenCount(String line) {
  final t = line.trim();
  if (!t.startsWith('```')) return null;
  var n = 0;
  while (n < t.length && t.codeUnitAt(n) == 0x60) {
    n++;
  }
  if (n < 3) return null;
  if (t.substring(n).contains('`')) return null;
  return n;
}

bool _isFenceClose(String line, int openCount) {
  final t = line.trim();
  if (t.isEmpty || !t.startsWith('`')) return false;
  var n = 0;
  while (n < t.length && t.codeUnitAt(n) == 0x60) {
    n++;
  }
  if (n < openCount) return false;
  return t.substring(n).trim().isEmpty;
}

/// 文档里所有一级/二级标题（阅读页目录用）。
List<(int, String)> outlineOf(List<DocBlock> blocks) {
  final out = <(int, String)>[];
  for (final b in blocks) {
    if (b is DocHeading && b.level <= 3) {
      final text = b.spans
          .map((s) => switch (s) {
                DocText(:final text) => text,
                DocMathInline(:final tex) => tex,
                _ => '',
              })
          .join()
          .trim();
      if (text.isNotEmpty) out.add((b.level, text));
    }
  }
  return out;
}
