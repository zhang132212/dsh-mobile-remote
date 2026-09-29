// DOCX 读取器（v3.2.0）——.docx（OOXML 压缩包）→ docs/model.dart 的统一模型。
//
// 为什么自研：本 App 不引第三方 docx 包——「写」类的包（docx_template）帮不上读，
// 纯文本抽取类的包又会把标题/列表/表格/超链接/公式这些**特色**全丢掉，而阅读器的
// 价值恰恰在保留它们。故按 OOXML 规范直接解包解析。
// 公式不在这里实现：OMML 的读取通道只有 math/omml.dart 一处，两套解析会打架。
//
// 三层结构：
//   压缩包层  ZipDecoder → word/document.xml（外加 rels / styles / numbering 三个辅助部件）
//   块级层    w:body 的 w:p / w:tbl → DocPara / DocHeading / DocList / DocTable / DocMathBlock
//   行内层    w:r 的 rPr 样式 + w:t / w:br / w:tab / w:hyperlink / m:oMath → DocInline
//
// 健壮性契约（调用方按此依赖）：**永不抛异常**。坏压缩包 → 一条 DocRaw；
// 单个段落坏 → 只跳过该段并记进 Document.warnings，其余照常渲染。
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

import '../math/omml.dart';
import 'model.dart';

/// 解析 .docx 字节 → 统一文档模型。永不抛异常：任何异常降级为 DocRaw。
Document parseDocx(Uint8List bytes, String name) {
  final warnings = <String>[];
  final reader = _DocxReader(_titleFrom(name), warnings);
  try {
    return reader.parse(bytes);
  } catch (e) {
    // 下面每个环节其实都各自 catch 过了；这里是最后一道网，只为守住「绝不抛给调用方」。
    warnings.add('docx 解析异常：$e');
    return Document(reader.title, DocFormat.docx, <DocBlock>[DocRaw('（无法识别的 docx：$e）')],
        warnings: warnings);
  }
}

// ══════════════════════════════════════════════════════════════════
// XML 小工具
//
// 全部按**本地名**匹配，绝不假设前缀。理由有两条：
//   1) package:xml 的 findAllElements('w:p') 比的是「限定名」，换个前缀（ns0:p）就落空，
//      而 OOXML 只规定命名空间、不规定前缀；
//   2) 属性同理：w:val 在 package:xml 里存成 prefix+local，`getAttribute('w:val')` 靠限定名
//      去比，混用前缀的文档会取不到（与 math/omml.dart 的 _mVal 同一处理）。
// ══════════════════════════════════════════════════════════════════

/// 子元素按本地名取第一个。
XmlElement? _child(XmlElement? el, String local) {
  if (el == null) {
    return null;
  }
  for (final c in el.childElements) {
    if (c.name.local == local) {
      return c;
    }
  }
  return null;
}

/// 子元素按本地名取全部（保持文档顺序）。
List<XmlElement> _children(XmlElement el, String local) =>
    el.childElements.where((c) => c.name.local == local).toList();

/// 属性按本地名取第一个（前缀无关）。
String? _attr(XmlElement? el, String local) {
  if (el == null) {
    return null;
  }
  for (final a in el.attributes) {
    if (a.name.local == local) {
      return a.value;
    }
  }
  return null;
}

/// OOXML 布尔开关（w:b / w:i / w:tblHeader …）→ 三态。
///
/// 为什么必须是三态而不是 bool：docx 的样式是继承来的，`<w:b w:val="0"/>` 的语义是
/// 「显式关闭上文（段落样式）带来的粗体」，与「压根没提」完全不同——只有区分二者，
/// 「取消粗体」的 run 才不会被渲染成粗体。null = 没提到。
bool? _toggle(XmlElement? el) {
  if (el == null) {
    return null;
  }
  final v = _attr(el, 'val')?.trim().toLowerCase();
  if (v == null) {
    return true; // 裸元素 <w:b/> 就是「开」
  }
  return !(v == '0' || v == 'false' || v == 'off');
}

/// 开关按「存在且不为假」判真（不需要三态时的便捷写法）。
bool _on(XmlElement? el) => _toggle(el) == true;

/// 下划线：w:u 的 val 是**线型**（single/double/wave/dotted…），
/// 只有 "none" 表示没有下划线，所以不能拿 val 当布尔读。
bool? _underlineOn(XmlElement? el) {
  if (el == null) {
    return null;
  }
  final v = _attr(el, 'val')?.trim().toLowerCase();
  if (v == null) {
    return true;
  }
  return v != 'none';
}

/// 颜色：只接受 6 位十六进制；'auto' 与主题色（themeColor）交回主题处理。
String? _hexColor(String? raw) {
  final v = raw?.trim() ?? '';
  if (v.length != 6) {
    return null;
  }
  for (var i = 0; i < 6; i++) {
    final c = v.codeUnitAt(i);
    final isDigit = c >= 0x30 && c <= 0x39;
    final isUpper = c >= 0x41 && c <= 0x46;
    final isLower = c >= 0x61 && c <= 0x66;
    if (!isDigit && !isUpper && !isLower) {
      return null;
    }
  }
  return v.toUpperCase(); // 统一大写，渲染层不必再考虑大小写
}

/// 文件名 → 文档标题：去掉目录部分与扩展名。
String _titleFrom(String raw) {
  var s = raw.trim();
  final slash = s.lastIndexOf('/');
  final back = s.lastIndexOf('\\');
  final cut = slash > back ? slash : back;
  if (cut >= 0) {
    s = s.substring(cut + 1);
  }
  final dot = s.lastIndexOf('.');
  if (dot > 0) {
    s = s.substring(0, dot);
  }
  return s.isEmpty ? '未命名文档' : s;
}

/// 标题样式 id 归一化后的匹配式（heading1 / 标题1 / h1）。
final RegExp _kHeadingRe = RegExp(r'^(?:heading|标题|h)([1-6])$');

/// 纯数字样式 id（"1"）。
final RegExp _kHeadingDigitRe = RegExp(r'^[1-6]$');

/// 标题样式 id 里要抹掉的噪音：空白、不换行空格、连字符、下划线。
final RegExp _kStyleNoiseRe = RegExp(r'[\s\u00A0_-]');

// ══════════════════════════════════════════════════════════════════
// 段落切片（行内序列 / 显示式公式）
// ══════════════════════════════════════════════════════════════════

/// 一个段落的局部内容。
///
/// 为什么需要「切片」：`m:oMathPara`（独占一行的显示式公式）语义上是**块**，
/// 但它物理上嵌在 `w:p` 里，还可能夹在前后文字之间。只有把段落切成
/// 「行内片段 … 公式块 … 行内片段」的序列，才能既保持文档顺序，
/// 又让两块各自按自己的层级（块 / 行内）交给模型。
sealed class _Seg {
  const _Seg();
}

/// 行内片段：DocText / DocLink / DocMathInline / DocImage / DocBreak 的序列。
class _InlineSeg extends _Seg {
  final List<DocInline> spans;
  const _InlineSeg(this.spans);
}

/// 独占一行的公式（TeX 源码）。
class _MathSeg extends _Seg {
  final String tex;
  const _MathSeg(this.tex);
}

/// 段落切片累积器：按遍历顺序把元素喂进来，遇到显示式公式就切一刀。
class _SegBuilder {
  final List<_Seg> _segs = <_Seg>[];
  final List<DocInline> _current = <DocInline>[];

  void add(DocInline item) => _current.add(item);

  /// 把「行内序列到此为止」落成一段（空片段不落，避免产出空 DocPara）。
  void _cut() {
    if (_current.isNotEmpty) {
      _segs.add(_InlineSeg(List<DocInline>.of(_current)));
      _current.clear();
    }
  }

  void addMathBlock(String tex) {
    _cut();
    _segs.add(_MathSeg(tex));
  }

  List<_Seg> get segments {
    _cut();
    return List<_Seg>.of(_segs);
  }
}

// ══════════════════════════════════════════════════════════════════
// 样式快照
// ══════════════════════════════════════════════════════════════════

/// run 样式快照：字段全可空 = 三态（null 未提及 / true / false 显式关闭）。
class _RunStyle {
  final bool? bold;
  final bool? italic;
  final bool? underline;
  final bool? strike;
  final bool? superscript;
  final bool? subscript;

  /// w:sz 原值（半磅：24 = 12pt）。换算成 sizeScale 需要正文磅数，故此处只存原值。
  final int? szHalf;
  final String? colorHex;

  const _RunStyle({
    this.bold,
    this.italic,
    this.underline,
    this.strike,
    this.superscript,
    this.subscript,
    this.szHalf,
    this.colorHex,
  });

  /// 读一层 `w:rPr`（没提到的字段留 null，交给上层继承）。
  static _RunStyle fromRPr(XmlElement? rPr) {
    if (rPr == null) {
      return const _RunStyle();
    }
    final vertAlign = _attr(_child(rPr, 'vertAlign'), 'val')?.trim().toLowerCase();
    return _RunStyle(
      bold: _toggle(_child(rPr, 'b')),
      italic: _toggle(_child(rPr, 'i')),
      underline: _underlineOn(_child(rPr, 'u')),
      // w:strike 单删除线、w:dstrike 双删除线，模型只有一种删除线，先看单线
      strike: _toggle(_child(rPr, 'strike')) ?? _toggle(_child(rPr, 'dstrike')),
      superscript: vertAlign == null ? null : vertAlign == 'superscript',
      subscript: vertAlign == null ? null : vertAlign == 'subscript',
      szHalf: int.tryParse(_attr(_child(rPr, 'sz'), 'val')?.trim() ?? ''),
      colorHex: _hexColor(_attr(_child(rPr, 'color'), 'val')),
    );
  }

  /// 继承：[over] 是「下文」（run 自身），它显式设置过的字段赢。
  _RunStyle inherit(_RunStyle over) => _RunStyle(
        bold: over.bold ?? bold,
        italic: over.italic ?? italic,
        underline: over.underline ?? underline,
        strike: over.strike ?? strike,
        superscript: over.superscript ?? superscript,
        subscript: over.subscript ?? subscript,
        szHalf: over.szHalf ?? szHalf,
        colorHex: over.colorHex ?? colorHex,
      );
}

/// 一级列表的编号格式。
class _LvlFmt {
  final bool ordered;
  final int start;
  const _LvlFmt(this.ordered, this.start);

  /// 从 `w:lvl` 读格式：numFmt=bullet/none 是无序，其余（decimal/lowerLetter/
  /// upperRoman…）都算有序；numFmt 读不到就按无序——保底是「进列表」而非「丢成段落」。
  static _LvlFmt fromLvl(XmlElement lvl) {
    final fmt = _attr(_child(lvl, 'numFmt'), 'val')?.trim().toLowerCase();
    final start = int.tryParse(_attr(_child(lvl, 'start'), 'val')?.trim() ?? '') ?? 1;
    final ordered = fmt != null && fmt != 'bullet' && fmt != 'none';
    return _LvlFmt(ordered, start < 1 ? 1 : start);
  }
}

// ══════════════════════════════════════════════════════════════════
// 解析器
// ══════════════════════════════════════════════════════════════════

/// 解析状态。rels / 样式表 / 编号表在整篇文档里是共享的，攒在一个对象里
/// 比一路传参数清楚；warnings 也顺带在这里累积。
class _DocxReader {
  _DocxReader(this.title, this.warnings);

  final String title;
  final List<String> warnings;

  /// r:id → Target（超链接目标）。
  final Map<String, String> _rels = <String, String>{};

  /// styleId → w:style 元素（只用来读样式上挂的 numPr）。
  final Map<String, XmlElement> _styles = <String, XmlElement>{};

  /// numId → (ilvl → 格式)，来自 word/numbering.xml。
  final Map<String, Map<int, _LvlFmt>> _numbering = <String, Map<int, _LvlFmt>>{};

  /// 正文字号（磅）：sizeScale 的分母。读不准就按 Word 默认的 11pt。
  double _bodyPt = 11;

  // ── 入口 ────────────────────────────────────────────────────────

  Document parse(Uint8List bytes) {
    if (bytes.isEmpty) {
      return _fallback('（无法识别的 docx：文件内容为空）', '文件内容为空');
    }

    Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (e) {
      return _fallback('（无法识别的 docx：压缩包解析失败）', '压缩包解析失败：$e');
    }

    final docXml = _entry(archive, 'word/document.xml');
    if (docXml == null) {
      // 契约点名的降级文本，别改（调用方/测试按这句话识别）
      return _fallback('（无法识别的 docx：缺少 word/document.xml）', '缺少 word/document.xml');
    }

    // 三个辅助部件都是「有则更好」：坏了只记告警，正文照常解析
    _safe(() => _loadRels(archive), '关系表');
    _safe(() => _loadStyles(archive), '样式表');
    _safe(() => _loadNumbering(archive), '编号表');

    XmlDocument doc;
    try {
      doc = XmlDocument.parse(docXml);
    } catch (e) {
      return _fallback('（无法识别的 docx：word/document.xml 解析失败）', 'document.xml 解析失败：$e');
    }

    final body = _descendant(doc.rootElement, 'body');
    if (body == null) {
      return _fallback('（无法识别的 docx：缺少 w:body）', '缺少 w:body');
    }

    final blocks = <DocBlock>[];
    try {
      _parseBody(body, blocks);
    } catch (e) {
      // 段落/表格各自都 catch 过了，这里是块级遍历的最后一道网：
      // 已经解析出来的块照样交出去，比整篇报废强。
      warnings.add('正文解析中断（已保留已解析内容）：$e');
    }
    return Document(title, DocFormat.docx, blocks, warnings: warnings);
  }

  /// 统一降级产物：一条 DocRaw（至少让用户看见一句话）+ 一条告警。
  Document _fallback(String raw, String warning) => Document(
        title,
        DocFormat.docx,
        <DocBlock>[DocRaw(raw)],
        warnings: <String>[...warnings, warning],
      );

  /// 辅助部件统一包一层：坏了只记告警。
  void _safe(void Function() action, String what) {
    try {
      action();
    } catch (e) {
      warnings.add('$what解析失败（已跳过）：$e');
    }
  }

  // ── 压缩包部件 ──────────────────────────────────────────────────

  /// 读压缩包内某个部件的文本。
  ///
  /// 先精确匹配，再按规范化名兜底：有些工具会写成 `./word/…` 或大写条目名，
  /// 精确匹配会整篇读不到。解码用 allowMalformed——坏字节不该让整篇打不开。
  String? _entry(Archive archive, String name) {
    try {
      final file = archive.findFile(name) ?? _entryByName(archive, name);
      if (file == null) {
        return null;
      }
      final content = file.content;
      if (content is Uint8List) {
        return utf8.decode(content, allowMalformed: true);
      }
      if (content is List<int>) {
        return utf8.decode(content, allowMalformed: true);
      }
      return null;
    } catch (e) {
      warnings.add('读取 $name 失败（已跳过）：$e');
      return null;
    }
  }

  ArchiveFile? _entryByName(Archive archive, String name) {
    final want = _normalizeEntryName(name);
    for (final f in archive.files) {
      if (_normalizeEntryName(f.name) == want) {
        return f;
      }
    }
    return null;
  }

  static String _normalizeEntryName(String p) {
    var s = p.replaceAll('\\', '/').toLowerCase();
    while (s.startsWith('./')) {
      s = s.substring(2);
    }
    if (s.startsWith('/')) {
      s = s.substring(1);
    }
    return s;
  }

  /// 关系表：超链接的 r:id → Target。
  /// 非超链接关系（图片/样式）也一并收下——Target 是相对路径时无从区分，
  /// 而超链接只会按自己的 r:id 来查，不会误用。
  void _loadRels(Archive archive) {
    final xml = _entry(archive, 'word/_rels/document.xml.rels');
    if (xml == null) {
      return;
    }
    for (final rel in XmlDocument.parse(xml).rootElement.childElements) {
      if (rel.name.local != 'Relationship') {
        continue;
      }
      final id = _attr(rel, 'Id');
      final target = _attr(rel, 'Target');
      if (id != null && id.isNotEmpty && target != null && target.isNotEmpty) {
        _rels[id] = target;
      }
    }
  }

  /// 样式表：只需要两件事——正文默认字号（sizeScale 的分母），以及
  /// 段落样式上挂的 numPr（docx 常把列表定义在样式里而不是段落上）。
  void _loadStyles(Archive archive) {
    final xml = _entry(archive, 'word/styles.xml');
    if (xml == null) {
      return;
    }
    final root = XmlDocument.parse(xml).rootElement;

    // 正文默认字号：w:docDefaults/w:rPrDefault/w:rPr/w:sz（退化取段落的默认 rPr）
    final defaults = _child(root, 'docDefaults');
    final sz = _child(_child(_child(defaults, 'rPrDefault'), 'rPr'), 'sz') ??
        _child(_child(_child(defaults, 'pPrDefault'), 'rPr'), 'sz');
    final half = int.tryParse(_attr(sz, 'val')?.trim() ?? '');
    if (half != null && half > 0) {
      _bodyPt = half / 2;
    }

    for (final style in _children(root, 'style')) {
      final id = _attr(style, 'styleId');
      if (id != null && id.isNotEmpty) {
        _styles[id] = style;
      }
    }
  }

  /// 编号表：只为回答一个问题——这段的 numId/ilvl 是「有序」还是「无序」。
  /// 只认 w:num → w:abstractNumId → w:abstractNum 这条主线；w:lvlOverride
  /// 这类少见覆盖不追（追不到就退化成无序列表，内容不会丢）。
  void _loadNumbering(Archive archive) {
    final xml = _entry(archive, 'word/numbering.xml');
    if (xml == null) {
      return;
    }
    final root = XmlDocument.parse(xml).rootElement;

    final abstracts = <String, Map<int, _LvlFmt>>{};
    for (final abs in _children(root, 'abstractNum')) {
      final id = _attr(abs, 'abstractNumId');
      if (id == null) {
        continue;
      }
      final lvls = <int, _LvlFmt>{};
      for (final lvl in _children(abs, 'lvl')) {
        final ilvl = int.tryParse(_attr(lvl, 'ilvl')?.trim() ?? '') ?? 0;
        lvls[ilvl] = _LvlFmt.fromLvl(lvl);
      }
      abstracts[id] = lvls;
    }

    for (final num in _children(root, 'num')) {
      final numId = _attr(num, 'numId');
      final absId = _attr(_child(num, 'abstractNumId'), 'val');
      final lvls = absId == null ? null : abstracts[absId];
      if (numId != null && lvls != null) {
        _numbering[numId] = lvls;
      }
    }
  }

  // ── 块级 ────────────────────────────────────────────────────────

  /// 遍历 body 的块级元素，按文档顺序产出 DocBlock。
  void _parseBody(XmlElement body, List<DocBlock> out) {
    final items = <XmlElement>[];
    _collectNamed(body, const <String>{'p', 'tbl'}, items);

    var skippedPara = 0;
    var skippedTable = 0;

    // 正在累积的列表：连续且「有序性」相同的列表段落合并成一个 DocList。
    var listOrdered = false;
    var listStart = 1;
    final listItems = <List<DocInline>>[];

    void flushList() {
      if (listItems.isNotEmpty) {
        out.add(DocList(List<List<DocInline>>.of(listItems), ordered: listOrdered, start: listStart));
        listItems.clear();
      }
    }

    for (final el in items) {
      if (el.name.local == 'tbl') {
        // 表格会打断列表：DocList 的项必须连续，跨表格合并会读出一条假列表
        flushList();
        try {
          final table = _parseTable(el);
          if (table != null) {
            out.add(table);
          }
        } catch (e) {
          skippedTable++;
        }
        continue;
      }

      // 单段失败只跳过该段：docx 里一段古怪的 XML 不该让整篇读不出来
      try {
        final segs = _paragraphSegments(el);
        final heading = _headingLevel(el);
        final align = _paraAlign(el);
        final lvl = _listLevel(el);

        if (heading != null) {
          // 标题优先于列表：带编号的标题仍然是标题
          flushList();
          for (final seg in segs) {
            if (seg is _InlineSeg) {
              if (_visible(seg.spans)) {
                out.add(DocHeading(heading, seg.spans));
              }
            } else if (seg is _MathSeg && seg.tex.trim().isNotEmpty) {
              out.add(DocMathBlock(seg.tex));
            }
          }
          continue;
        }

        if (lvl != null) {
          if (listItems.isNotEmpty && listOrdered != lvl.ordered) {
            flushList();
          }
          listOrdered = lvl.ordered;
          if (listItems.isEmpty) {
            listStart = lvl.start;
          }
          // 一段只产出一个列表项：行内片段（被显示式公式切开的）用硬换行接起来——
          // DocList 的一「项」就是一串行内元素，没有块级槽位。
          final joined = <DocInline>[];
          for (final seg in segs) {
            if (seg is! _InlineSeg || !_visible(seg.spans)) {
              continue;
            }
            if (joined.isNotEmpty) {
              joined.add(const DocBreak());
            }
            joined.addAll(seg.spans);
          }
          if (_visible(joined)) {
            listItems.add(joined);
          }
          continue;
        }

        flushList();
        for (final seg in segs) {
          if (seg is _InlineSeg) {
            if (_visible(seg.spans)) {
              out.add(DocPara(seg.spans, align: align));
            }
          } else if (seg is _MathSeg && seg.tex.trim().isNotEmpty) {
            out.add(DocMathBlock(seg.tex));
          }
        }
      } catch (e) {
        skippedPara++;
      }
    }
    flushList();

    if (skippedPara > 0) {
      warnings.add('跳过 $skippedPara 个无法解析的段落');
    }
    if (skippedTable > 0) {
      warnings.add('跳过 $skippedTable 个无法解析的表格');
    }
  }

  /// 深度优先收集命中 [names] 的元素（保持文档顺序），命中即不再下钻。
  ///
  /// 为什么要下钻又要在命中处停：w:sdt（内容控件，目录/封面常用）会把段落包在
  /// w:sdtContent 里，只扫直接子元素会整块丢掉；而命中的 p/tbl/tr/tc 一旦继续
  /// 下钻，就会把嵌套表格的行列算进外层。跳过 *Pr 是因为属性树里的同名子元素
  /// 不是内容（例如 w:pPr 里可能再出现 w:rPr）。
  static void _collectNamed(XmlElement el, Set<String> names, List<XmlElement> out) {
    for (final c in el.childElements) {
      final local = c.name.local;
      if (names.contains(local)) {
        out.add(c);
        continue;
      }
      if (local == 'sectPr' ||
          local == 'tblPr' ||
          local == 'tblPrEx' ||
          local == 'trPr' ||
          local == 'tcPr' ||
          local == 'pPr' ||
          local == 'rPr') {
        continue;
      }
      _collectNamed(c, names, out);
    }
  }

  /// 按本地名找第一个后代元素（不限定前缀）。
  static XmlElement? _descendant(XmlElement root, String local) {
    if (root.name.local == local) {
      return root;
    }
    for (final c in root.childElements) {
      final found = _descendant(c, local);
      if (found != null) {
        return found;
      }
    }
    return null;
  }

  // ── 段落属性 ────────────────────────────────────────────────────

  /// 标题级别：`w:pPr/w:pStyle` 的 styleId 归一化后判断。
  /// 兼容 Heading1 / "Heading 1" / 标题1 / "标题 2" / h3 / "1"；Title 视为 1 级。
  int? _headingLevel(XmlElement p) {
    final id = _attr(_child(_child(p, 'pPr'), 'pStyle'), 'val');
    if (id == null) {
      return null;
    }
    final key = id.replaceAll(_kStyleNoiseRe, '').toLowerCase();
    if (key.isEmpty) {
      return null;
    }
    if (key == 'title' || key == '标题') {
      return 1;
    }
    final m = _kHeadingRe.firstMatch(key);
    if (m != null) {
      return int.parse(m.group(1)!);
    }
    if (_kHeadingDigitRe.hasMatch(key)) {
      return int.parse(key);
    }
    return null;
  }

  /// 段落对齐（'left' | 'center' | 'right' | 'justify' | null）。
  String? _paraAlign(XmlElement p) => _jcToAlign(_attr(_child(_child(p, 'pPr'), 'jc'), 'val'));

  /// w:jc 的值 → 模型的对齐值。
  /// 'both' 是两端对齐（映射为 'justify'）；start/end 是 RTL 语境下的左右，按 left/right 处理。
  static String? _jcToAlign(String? raw) {
    switch (raw?.trim().toLowerCase()) {
      case 'center':
        return 'center';
      case 'right':
      case 'end':
        return 'right';
      case 'both':
      case 'justify':
      case 'distribute':
        return 'justify';
      case 'left':
      case 'start':
        return 'left';
      default:
        return null;
    }
  }

  /// 该段是否属于列表，以及有序/无序。
  ///
  /// 只要出现 `w:numPr` 就当成列表项（契约的保底要求：宁可退化成无序列表，
  /// 也绝不能丢成普通段落）。查不到编号定义时按无序处理。
  _LvlFmt? _listLevel(XmlElement p) {
    final pPr = _child(p, 'pPr');
    // 段落自己没写 numPr 时，看它引用的样式（docx 常把列表定义在样式上）
    final numPr = _child(pPr, 'numPr') ?? _child(_paragraphStylePPr(p), 'numPr');
    if (numPr == null) {
      return null;
    }
    final numId = _attr(_child(numPr, 'numId'), 'val')?.trim();
    final ilvl = int.tryParse(_attr(_child(numPr, 'ilvl'), 'val')?.trim() ?? '') ?? 0;
    final lvls = numId == null ? null : _numbering[numId];
    // 段落写的 ilvl 没定义时退到 0 级：多数文档只定义 0 级
    final fmt = lvls == null ? null : (lvls[ilvl] ?? lvls[0]);
    return fmt ?? const _LvlFmt(false, 1);
  }

  /// 段落引用样式（w:pStyle）的 `w:pPr`。
  /// 不追 w:basedOn 链：多一层间接就多一层出错机会，而列表定义几乎都挂在直接样式上。
  XmlElement? _paragraphStylePPr(XmlElement p) {
    final id = _attr(_child(_child(p, 'pPr'), 'pStyle'), 'val');
    if (id == null) {
      return null;
    }
    final style = _styles[id];
    return style == null ? null : _child(style, 'pPr');
  }

  // ── 行内 ────────────────────────────────────────────────────────

  /// 解析一个 `w:p` 的行内内容（含切片，供块级与单元格两处复用）。
  List<_Seg> _paragraphSegments(XmlElement p) {
    final pPr = _child(p, 'pPr');
    // 段落级 rPr 是段内所有 run 的样式底，run 再往它上面盖
    final base = _RunStyle.fromRPr(_child(pPr, 'rPr'));
    final builder = _SegBuilder();
    _walk(p, base, builder.add, blockMath: builder.addMathBlock);
    return builder.segments;
  }

  /// 段落/容器级遍历：按文档顺序把 run、超链接、公式喂给 [emit]。
  ///
  /// [blockMath] 为 null 时 `m:oMathPara` 退化为行内公式：表格单元格与超链接内部
  /// 没有「块」的槽位，只能这么降级（内容不丢，只是不独占一行）。
  void _walk(XmlElement parent, _RunStyle base, void Function(DocInline) emit,
      {void Function(String tex)? blockMath}) {
    for (final c in parent.childElements) {
      switch (c.name.local) {
        case 'r':
          _parseRun(c, base, emit);

        case 'hyperlink':
          _parseHyperlink(c, base, emit);

        case 'oMath':
          final tex = _mathTex(c, container: false);
          if (tex.isNotEmpty) {
            emit(DocMathInline(tex));
          }

        case 'oMathPara':
          final tex = _mathTex(c, container: true);
          if (tex.trim().isEmpty) {
            break;
          }
          if (blockMath == null) {
            emit(DocMathInline(tex));
          } else {
            blockMath(tex);
          }

        // 图片偶尔直接挂在段落上（不符合规范但确实存在），和 run 里一样给占位
        case 'drawing':
        case 'pict':
          emit(_image(c));

        // 属性树与标记类元素：没有可见内容
        case 'pPr':
        case 'rPr':
        case 'bookmarkStart':
        case 'bookmarkEnd':
        case 'proofErr':
        case 'commentRangeStart':
        case 'commentRangeEnd':
        case 'commentReference':
        case 'lastRenderedPageBreak':
          break;

        // 修订删除的内容不该出现在只读视图里
        case 'del':
          break;

        default:
          // 未知容器（w:ins / w:smartTag / w:sdt / w:sdtContent / w:fldSimple …）
          // 一律下钻：绝不丢字。
          _walk(c, base, emit, blockMath: blockMath);
      }
    }
  }

  /// 一个 `w:r`：按子元素顺序吐出行内元素。
  /// 连续的文字（w:t/w:tab）合并成一个 DocText，避免碎成一堆 span。
  void _parseRun(XmlElement r, _RunStyle base, void Function(DocInline) emit) {
    final style = base.inherit(_RunStyle.fromRPr(_child(r, 'rPr')));
    final buf = StringBuffer();

    void flush() {
      if (buf.isEmpty) {
        return;
      }
      emit(_text(buf.toString(), style));
      buf.clear();
    }

    for (final c in r.childElements) {
      switch (c.name.local) {
        case 't':
          // 绝不 trim：xml:space="preserve" 的首尾空格是排版的一部分
          buf.write(c.innerText);

        case 'tab':
          buf.write('\t');

        case 'br':
          // 分页符在只读视图里没有意义（契约要求忽略），只有换行才产出 DocBreak
          if (_attr(c, 'type')?.trim().toLowerCase() == 'page') {
            break;
          }
          flush();
          emit(const DocBreak());

        case 'cr':
          flush();
          emit(const DocBreak());

        case 'drawing':
        case 'pict':
          flush();
          emit(_image(c));

        case 'oMath':
          final tex = _mathTex(c, container: false);
          if (tex.isNotEmpty) {
            flush();
            emit(DocMathInline(tex));
          }

        case 'oMathPara':
          final tex = _mathTex(c, container: true);
          if (tex.trim().isNotEmpty) {
            // run 内部没有块级槽位，显示式公式降级为行内
            flush();
            emit(DocMathInline(tex));
          }

        case 'noBreakHyphen':
          buf.write('\u2011');

        case 'softHyphen':
        case 'sym':
        case 'instrText':
        case 'fldChar':
        case 'delText':
        case 'rPr':
          // 软连字符/私用区符号不可见；域代码、属性、删除的文本都不是正文
          break;

        default:
          break;
      }
    }
    flush();
  }

  /// 超链接：`r:id` → rels 里的 Target；只有 `w:anchor`（同文档锚点）时没有 URL，
  /// 但仍包成 DocLink——模型规定 url 为 null 时按普通文本渲染。
  void _parseHyperlink(XmlElement link, _RunStyle base, void Function(DocInline) emit) {
    final spans = <DocInline>[];
    _walk(link, base, spans.add); // 内部 run 照常解析样式；链接里没有块级槽位
    if (spans.isEmpty) {
      return;
    }
    emit(DocLink(spans, _linkUrl(link)));
  }

  /// 链接目标。r:id 的前缀可能是 r/ns1/rel，所以按本地名 'id' 取。
  String? _linkUrl(XmlElement link) {
    final id = _attr(link, 'id');
    if (id == null || id.isEmpty) {
      return null;
    }
    final target = _rels[id];
    if (target == null || target.trim().isEmpty) {
      return null;
    }
    // 关系表里 External/Internal 之分对超链接没意义：Target 就是作者想跳的地方
    return target;
  }

  /// 组装 DocText。
  DocText _text(String text, _RunStyle st) => DocText(
        text,
        bold: st.bold ?? false,
        italic: st.italic ?? false,
        underline: st.underline ?? false,
        strike: st.strike ?? false,
        superscript: st.superscript ?? false,
        subscript: st.subscript ?? false,
        sizeScale: _sizeScale(st.szHalf),
        colorHex: st.colorHex,
      );

  /// 字号倍数 = 该 run 的字号 / 正文字号，clamp 到 0.6~2.0。
  ///
  /// 分母取 styles.xml 的默认正文磅数（读不到就 11pt，Word 的默认值）。
  /// 结果落在 1.0 附近时返回 null：让渲染层用主题字号，避免无意义的视觉抖动。
  double? _sizeScale(int? halfPoints) {
    if (halfPoints == null || halfPoints <= 0) {
      return null;
    }
    final scale = ((halfPoints / 2) / _bodyPt).clamp(0.6, 2.0).toDouble();
    if ((scale - 1).abs() < 0.02) {
      return null;
    }
    return scale;
  }

  /// 公式 → TeX。omml.dart 是唯一的公式读取通道，这里不重复实现 OMML 解析。
  /// 单条公式失败只影响这一处：返回空串，调用方当作「没有内容」跳过。
  String _mathTex(XmlElement el, {required bool container}) {
    try {
      return container ? ommlContainerToTex(el) : ommlToTex(el);
    } catch (e) {
      warnings.add('公式解析失败（已跳过）：$e');
      return '';
    }
  }

  /// 图片占位：不解出字节（渲染层没有内嵌图片通道），只保留 alt，
  /// 让用户至少知道「这里原本有一张图」。
  /// alt 依次取 wp:docPr 的 descr/name（DrawingML）或 v:shape 的 alt/title（VML）。
  DocImage _image(XmlElement host) {
    String? alt;
    for (final el in host.descendants.whereType<XmlElement>()) {
      final local = el.name.local;
      if (local == 'docPr' || local == 'shape') {
        alt = _firstNonEmpty(<String?>[
          _attr(el, 'descr'),
          _attr(el, 'alt'),
          _attr(el, 'name'),
          _attr(el, 'title'),
        ]);
        if (alt != null) {
          break;
        }
      }
    }
    return DocImage(null, alt: alt);
  }

  static String? _firstNonEmpty(List<String?> candidates) {
    for (final c in candidates) {
      if (c != null && c.trim().isNotEmpty) {
        return c;
      }
    }
    return null;
  }

  /// 是否「有可见内容」。空的 DocPara/空 DocCell 会让阅读器出现莫名其妙的空行，
  /// 而 DocBreak 单独存在不算（Word 里常见「空段落 + 换行」的排版手法）。
  static bool _visible(List<DocInline> spans) {
    for (final s in spans) {
      if (s case DocText(:final text)) {
        if (text.trim().isNotEmpty) {
          return true;
        }
      } else if (s case DocMathInline(:final tex)) {
        if (tex.trim().isNotEmpty) {
          return true;
        }
      } else if (s case DocLink(:final spans)) {
        if (_visible(spans)) {
          return true;
        }
      } else if (s is DocImage) {
        return true; // 图片占位本身就是要让用户看见的
      }
    }
    return false;
  }

  // ── 表格 ────────────────────────────────────────────────────────

  /// `w:tbl` → DocTable。嵌套表格会被展平（模型没有嵌套表格的表达能力），
  /// 但格内文字不丢。
  DocTable? _parseTable(XmlElement tbl) {
    final trs = <XmlElement>[];
    _collectNamed(tbl, const <String>{'tr'}, trs);
    if (trs.isEmpty) {
      return null;
    }

    var header = false;
    var cols = 0;
    final rows = <List<DocCell>>[];

    for (var i = 0; i < trs.length; i++) {
      final tr = trs[i];
      // 表头只看第一行：docx 没有 markdown 那种表头语法，但 Word 的
      //「重复标题行」开关（w:tblHeader）就是作者的显式意图。
      final isHeader = i == 0 && _rowIsHeader(tr);
      if (i == 0) {
        header = isHeader;
      }

      final cells = <DocCell>[];
      final tcs = <XmlElement>[];
      _collectNamed(tr, const <String>{'tc'}, tcs);
      for (final tc in tcs) {
        cells.add(DocCell(_cellSpans(tc), align: _cellAlign(tc), header: isHeader));
        // 横向合并：模型没有 colspan 字段，把被覆盖的列补成空单元格，
        // 后续行的列数才对得上（首格的文字照旧保留）。
        final span = _gridSpan(tc);
        for (var k = 1; k < span; k++) {
          cells.add(DocCell.empty);
        }
      }
      if (cells.length > cols) {
        cols = cells.length;
      }
      rows.add(cells);
    }

    // 各行补齐到最大列数：渲染层按列宽算布局，长短不一会错位
    for (final row in rows) {
      while (row.length < cols) {
        row.add(DocCell.empty);
      }
    }
    return DocTable(rows, headerRow: header);
  }

  /// 单元格内容 = 格内所有 `w:p` 的行内内容，段落之间用 DocBreak 连接
  /// （DocCell 只有一行行内序列，段间只能靠硬换行表达）。
  /// 嵌套表格里的段落也在内——宁可展平，也别把字丢了。
  List<DocInline> _cellSpans(XmlElement tc) {
    final paras = <XmlElement>[];
    _collectNamed(tc, const <String>{'p'}, paras);

    final out = <DocInline>[];
    for (final p in paras) {
      final spans = <DocInline>[];
      for (final seg in _paragraphSegments(p)) {
        if (seg is _InlineSeg) {
          spans.addAll(seg.spans);
        } else if (seg is _MathSeg && seg.tex.trim().isNotEmpty) {
          // 单元格里没有块级槽位：显示式公式降级为行内公式
          spans.add(DocMathInline(seg.tex));
        }
      }
      if (!_visible(spans)) {
        continue; // 空段落不产生空行
      }
      if (out.isNotEmpty) {
        out.add(const DocBreak());
      }
      out.addAll(spans);
    }
    return out;
  }

  /// 行是否标记为标题行。标准写法是 `w:trPr/w:tblHeader`；
  /// 少数生成器挂在单元格的 `w:tcPr/w:tblHeader` 上，两种都认。
  bool _rowIsHeader(XmlElement tr) {
    if (_on(_child(_child(tr, 'trPr'), 'tblHeader'))) {
      return true;
    }
    final tcs = <XmlElement>[];
    _collectNamed(tr, const <String>{'tc'}, tcs);
    if (tcs.isEmpty) {
      return false;
    }
    for (final tc in tcs) {
      if (!_on(_child(_child(tc, 'tcPr'), 'tblHeader'))) {
        return false;
      }
    }
    return true;
  }

  /// 横向合并列数（`w:tcPr/w:gridSpan`）；缺失或非正数按 1 列。
  int _gridSpan(XmlElement tc) {
    final v = int.tryParse(_attr(_child(_child(tc, 'tcPr'), 'gridSpan'), 'val')?.trim() ?? '');
    return (v == null || v < 1) ? 1 : v;
  }

  /// 单元格对齐：优先 `w:tcPr/w:jc`，退而取格内第一段自己的对齐。
  String? _cellAlign(XmlElement tc) {
    final direct = _jcToAlign(_attr(_child(_child(tc, 'tcPr'), 'jc'), 'val'));
    if (direct != null) {
      return direct;
    }
    final paras = <XmlElement>[];
    _collectNamed(tc, const <String>{'p'}, paras);
    for (final p in paras) {
      final a = _paraAlign(p);
      if (a != null) {
        return a;
      }
    }
    return null;
  }
}
