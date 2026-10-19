// HTML 读取器（v3.2.8）——把网页就地读成文档，不再跳浏览器。
//
// 定位：手机上看一眼 HTML（导出的报告、README.html、抓下来的页面、模板片段）
// 不该被甩到浏览器里 —— 那样丢上下文、要等加载、还可能被页面脚本劫持。
// 这里做**容错解析 + 语义映射**：把标签映射到 docs/model.dart 已有的文档块
// （标题 / 段落 / 列表 / 表格 / 引用 / 代码 / 链接 / 图片 / 行内样式），复用
// 同一套渲染与目录跳转，所以「阅读手感」和其他格式完全一致。
//
// 设计取舍：
//   · 不引 `html` 包（离线工具链 + 少一个依赖）：自己写栈式容错解析器，
//     未闭合标签、大小写混写、void 元素、裸 & 都能吃下；
//   · 纯 Dart、不 import Flutter —— 与 docs/ 其余解析器一致，可单测；
//   · script / style / head / meta 一律不产出内容：宁可少显示，也不把 JS
//     和 CSS 糊进正文。
import 'model.dart';

/// 解析 HTML 文本 → Document。**不抛异常**。
Document parseHtml(String text, String title) {
  final body = _extractBody(text);
  if (body.trim().isEmpty) {
    return Document(title, DocFormat.html, const [DocRaw('（HTML 里没有可显示的正文）')]);
  }

  final root = _parse(body);
  final blocks = <DocBlock>[];
  _emitBlocks(root, blocks);

  if (blocks.isEmpty) {
    return Document(title, DocFormat.html, const [DocRaw('（HTML 正文为空）')]);
  }
  return Document(title, DocFormat.html, blocks);
}

/// 只取 `<body>` 内的内容（没有 body 就用全文）。
String _extractBody(String html) {
  final m = RegExp(r'<body[^>]*>([\s\S]*?)</body>', caseSensitive: false).firstMatch(html);
  return m != null ? m.group(1)! : html;
}

// ══════════════════════════════════════════════════════════════════
// 极简 DOM
// ══════════════════════════════════════════════════════════════════

class _Node {
  /// 小写标签名；`#text` 表示文本节点。
  final String tag;
  String? text;
  final Map<String, String> attrs;
  final List<_Node> children = [];

  _Node(this.tag, {this.text, Map<String, String>? attrs}) : attrs = attrs ?? const {};

  bool get isText => tag == '#text';
}

/// void 元素（不产生子节点、不入栈）。
const Set<String> _voidTags = {
  'area', 'base', 'br', 'col', 'embed', 'hr', 'img', 'input',
  'link', 'meta', 'param', 'source', 'track', 'wbr',
};

/// 不产出任何内容的标签（脚本 / 样式 / 元信息）。
const Set<String> _skipTags = {
  'script', 'style', 'head', 'meta', 'link', 'title', 'noscript',
  'iframe', 'svg', 'canvas', 'template', 'base',
};

final RegExp _tokenRe = RegExp(
  r'<!--[\s\S]*?-->|<!\[CDATA\[[\s\S]*?\]\]>|<![^>]*>|</?[a-zA-Z][^>]*>|[^<]+',
);

/// 栈式容错解析：不追求严格 DOM，只求「正文别丢、层级别乱」。
_Node _parse(String html) {
  final root = _Node('#root');
  final stack = <_Node>[root];
  var skipDepth = 0;

  for (final m in _tokenRe.allMatches(html)) {
    final tok = m.group(0)!;
    if (tok.isEmpty) continue;

    // 注释 / CDATA / DOCTYPE：直接丢
    if (tok.startsWith('<!--') || tok.startsWith('<!')) continue;

    if (tok.startsWith('</')) {
      final name = _tagName(tok).toLowerCase();
      if (skipDepth > 0) {
        // 在 script/style 里：只看它自己的结束标签
        if (name == stack.last.tag) {
          skipDepth--;
          if (stack.length > 1) stack.removeLast();
        }
        continue;
      }
      // 向上找最近的同名开始标签；找不到就忽略（容错）
      final idx = stack.lastIndexWhere((n) => n.tag == name);
      if (idx > 0) stack.removeRange(idx, stack.length);
      continue;
    }

    if (tok.startsWith('<')) {
      final name = _tagName(tok).toLowerCase();
      if (name.isEmpty) continue;
      if (skipDepth > 0) {
        if (_skipTags.contains(name) && !tok.endsWith('/>')) skipDepth++;
        continue;
      }
      if (_skipTags.contains(name)) {
        if (!tok.endsWith('/>')) {
          stack.add(_Node(name));
          skipDepth++;
        }
        continue;
      }
      final node = _Node(name, attrs: _parseAttrs(tok));
      stack.last.children.add(node);
      if (!_voidTags.contains(name) && !tok.endsWith('/>')) stack.add(node);
      continue;
    }

    // 文本
    if (skipDepth > 0) continue;
    final txt = _decodeEntities(tok);
    if (txt.trim().isEmpty) continue;
    stack.last.children.add(_Node('#text', text: txt));
  }
  return root;
}

String _tagName(String tok) {
  final m = RegExp(r'^</?\s*([a-zA-Z][a-zA-Z0-9:-]*)').firstMatch(tok);
  return m?.group(1) ?? '';
}

Map<String, String> _parseAttrs(String tok) {
  final out = <String, String>{};
  final re = RegExp(r'''([a-zA-Z_:][-a-zA-Z0-9_:.]*)\s*=\s*("([^"]*)"|'([^']*)'|([^\s"'>]+))''');
  for (final m in re.allMatches(tok)) {
    final key = m.group(1)!.toLowerCase();
    final val = m.group(3) ?? m.group(4) ?? m.group(5) ?? '';
    out[key] = _decodeEntities(val);
  }
  return out;
}

/// 实体解码：命名实体常见的一批 + 数字实体（十进制 / 十六进制）。
String _decodeEntities(String s) {
  if (!s.contains('&')) return s;
  return s.replaceAllMapped(
    RegExp(r'&(#x[0-9a-fA-F]+|#\d+|[a-zA-Z][a-zA-Z0-9]*);'),
    (m) {
      final body = m.group(1)!;
      if (body.startsWith('#x') || body.startsWith('#X')) {
        final v = int.tryParse(body.substring(2), radix: 16);
        return v != null && v > 0 && v <= 0x10FFFF ? String.fromCharCode(v) : m.group(0)!;
      }
      if (body.startsWith('#')) {
        final v = int.tryParse(body.substring(1));
        return v != null && v > 0 && v <= 0x10FFFF ? String.fromCharCode(v) : m.group(0)!;
      }
      return _entities[body.toLowerCase()] ?? m.group(0)!;
    },
  );
}

const Map<String, String> _entities = {
  'amp': '&', 'lt': '<', 'gt': '>', 'quot': '"', 'apos': "'",
  'nbsp': ' ', 'copy': '©', 'reg': '®', 'trade': '™', 'hellip': '…',
  'mdash': '—', 'ndash': '–', 'lsquo': '‘', 'rsquo': '’',
  'ldquo': '“', 'rdquo': '”', 'laquo': '«', 'raquo': '»',
  'times': '×', 'divide': '÷', 'plusmn': '±', 'deg': '°',
  'middot': '·', 'bull': '•', 'dagger': '†', 'sect': '§',
  'para': '¶', 'euro': '€', 'pound': '£', 'yen': '¥', 'cent': '¢',
  'larr': '←', 'rarr': '→', 'uarr': '↑', 'darr': '↓', 'harr': '↔',
  'le': '≤', 'ge': '≥', 'ne': '≠', 'asymp': '≈', 'infin': '∞',
  'alpha': 'α', 'beta': 'β', 'gamma': 'γ', 'delta': 'δ', 'pi': 'π',
  'mu': 'μ', 'sigma': 'σ', 'omega': 'ω', 'lambda': 'λ', 'theta': 'θ',
  'check': '✓', 'cross': '✗', 'star': '★', 'heart': '♥',
};

// ══════════════════════════════════════════════════════════════════
// DOM → 文档块
// ══════════════════════════════════════════════════════════════════

/// 行内样式状态（向下传递）。
class _Inline {
  final bool bold, italic, underline, strike, code;
  const _Inline({
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.strike = false,
    this.code = false,
  });
}

void _emitBlocks(_Node parent, List<DocBlock> out, [_Inline style = const _Inline()]) {
  for (final child in parent.children) {
    if (child.isText) {
      final t = _squash(child.text ?? '');
      if (t.isNotEmpty) out.add(DocPara([_styled(t, style)]));
      continue;
    }
    final tag = child.tag;

    // 标题
    if (tag.length == 2 && tag[0] == 'h' && '123456'.contains(tag[1])) {
      final level = int.parse(tag[1]);
      final spans = _inlineOf(child, style);
      if (spans.isNotEmpty) out.add(DocHeading(level, spans));
      continue;
    }

    switch (tag) {
      case 'p':
      case 'div':
      case 'section':
      case 'article':
      case 'main':
      case 'header':
      case 'footer':
      case 'aside':
      case 'figure':
      case 'figcaption':
      case 'address':
      case 'dd':
      case 'dt':
      case 'caption':
        final spans = _inlineOf(child, style);
        if (spans.isNotEmpty) out.add(DocPara(spans));
        // 容器里还可能有块级子元素（div 套 div），继续下钻
        if (child.children.any((c) => !c.isText && _isBlock(c.tag))) {
          _emitBlocks(child, out, style);
        }
        break;

      case 'ul':
      case 'ol':
        final items = <List<DocInline>>[];
        for (final li in child.children.where((c) => c.tag == 'li')) {
          final spans = _inlineOf(li, style);
          if (spans.isNotEmpty) items.add(spans);
          // 嵌套列表：跟在后面单独成块，不做多级缩进（DocList 只支持一层）
          for (final sub in li.children.where((c) => c.tag == 'ul' || c.tag == 'ol')) {
            _emitBlocks(_wrap(sub), out, style);
          }
        }
        if (items.isNotEmpty) out.add(DocList(items, ordered: tag == 'ol'));
        break;

      case 'li':
        // 裸 li（父级不是 ul/ol）：按普通段落处理
        final spans = _inlineOf(child, style);
        if (spans.isNotEmpty) out.add(DocPara(spans));
        break;

      case 'table':
        final table = _tableOf(child, style);
        if (table != null) out.add(table);
        break;

      case 'pre':
        final code = _collectText(child);
        if (code.trim().isNotEmpty) {
          out.add(DocCode(code.replaceAll(RegExp(r'\s+$'), ''), lang: _langOf(child)));
        }
        break;

      case 'blockquote':
        final spans = _inlineOf(child, style);
        if (spans.isNotEmpty) out.add(DocQuote(spans));
        if (child.children.any((c) => !c.isText && _isBlock(c.tag))) {
          _emitBlocks(child, out, style);
        }
        break;

      case 'hr':
        out.add(const DocRule());
        break;

      case 'br':
        break; // 块级上下文里的 br 无意义

      case 'dl':
        _emitBlocks(child, out, style);
        break;

      default:
        if (_isBlock(tag)) {
          final spans = _inlineOf(child, style);
          if (spans.isNotEmpty) out.add(DocPara(spans));
          _emitBlocks(child, out, style);
        } else {
          // 行内标签直接挂在顶层（少见但别丢）。必须包一层再收集，
          // 否则 <a>/<img> 自身的语义（链接、图片）会在 _inlineOf 里丢掉。
          final spans = _inlineOf(_wrap(child), style);
          if (spans.isNotEmpty) out.add(DocPara(spans));
        }
    }
  }
}

_Node _wrap(_Node n) {
  final w = _Node('#root');
  w.children.add(n);
  return w;
}

const Set<String> _blockTagSet = {
  'p', 'div', 'section', 'article', 'main', 'header', 'footer', 'aside',
  'ul', 'ol', 'li', 'table', 'thead', 'tbody', 'tfoot', 'tr', 'td', 'th',
  'pre', 'blockquote', 'hr', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'dl', 'dt', 'dd',
  'figure', 'figcaption', 'form', 'fieldset', 'details', 'summary', 'nav',
};

bool _isBlock(String tag) => _blockTagSet.contains(tag);

/// 收集一个节点下的行内内容。
List<DocInline> _inlineOf(_Node node, _Inline style) {
  final out = <DocInline>[];
  _collectInline(node, style, out);
  // 去掉首尾空白文本片段
  while (out.isNotEmpty && out.first is DocText && (out.first as DocText).text.trim().isEmpty) {
    out.removeAt(0);
  }
  while (out.isNotEmpty && out.last is DocText && (out.last as DocText).text.trim().isEmpty) {
    out.removeLast();
  }
  return out;
}

void _collectInline(_Node node, _Inline style, List<DocInline> out) {
  for (final child in node.children) {
    if (child.isText) {
      final t = _squash(child.text ?? '');
      if (t.isNotEmpty) out.add(_styled(t, style));
      continue;
    }
    final tag = child.tag;

    // 块级子元素出现在行内收集里：断开，交给块级遍历处理（这里只留个换行）
    if (_isBlock(tag) && tag != 'br') {
      if (out.isNotEmpty && out.last is! DocBreak) out.add(const DocBreak());
      continue;
    }

    switch (tag) {
      case 'br':
        out.add(const DocBreak());
        break;
      case 'strong':
      case 'b':
        _collectInline(child, _copy(style, bold: true), out);
        break;
      case 'em':
      case 'i':
      case 'cite':
      case 'var':
        _collectInline(child, _copy(style, italic: true), out);
        break;
      case 'u':
      case 'ins':
        _collectInline(child, _copy(style, underline: true), out);
        break;
      case 's':
      case 'del':
      case 'strike':
        _collectInline(child, _copy(style, strike: true), out);
        break;
      case 'code':
      case 'kbd':
      case 'samp':
      case 'tt':
        _collectInline(child, _copy(style, code: true), out);
        break;
      case 'a':
        final href = child.attrs['href'];
        final label = _inlineOf(child, style);
        if (label.isNotEmpty) {
          out.add(DocLink(label, (href == null || href.isEmpty || href.startsWith('#')) ? null : href));
        }
        break;
      case 'img':
        final src = child.attrs['src'];
        if (src != null && src.isNotEmpty && !src.startsWith('data:image/svg')) {
          out.add(DocImage(src, alt: child.attrs['alt']));
        }
        break;
      case 'sub':
        out.addAll(_inlineOf(child, style).map((s) =>
            s is DocText ? s.merge(subscript: true) : s));
        break;
      case 'sup':
        out.addAll(_inlineOf(child, style).map((s) =>
            s is DocText ? s.merge(superscript: true) : s));
        break;
      default:
        _collectInline(child, style, out);
    }
  }
}

_Inline _copy(
  _Inline s, {
  bool? bold,
  bool? italic,
  bool? underline,
  bool? strike,
  bool? code,
}) =>
    _Inline(
      bold: bold ?? s.bold,
      italic: italic ?? s.italic,
      underline: underline ?? s.underline,
      strike: strike ?? s.strike,
      code: code ?? s.code,
    );

DocText _styled(String text, _Inline s) => DocText(
      text,
      bold: s.bold,
      italic: s.italic,
      underline: s.underline,
      strike: s.strike,
      code: s.code,
    );

/// 表格：thead/tbody 都摊平进行列表；th 标成表头。
DocTable? _tableOf(_Node table, _Inline style) {
  final rows = <List<DocCell>>[];
  var hasHeader = false;

  void walkRows(_Node n) {
    for (final child in n.children) {
      if (child.isText) continue;
      if (child.tag == 'tr') {
        final cells = <DocCell>[];
        for (final cell in child.children) {
          if (cell.tag != 'td' && cell.tag != 'th') continue;
          final isHeader = cell.tag == 'th';
          if (isHeader) hasHeader = true;
          final spans = _inlineOf(cell, style);
          final align = switch (cell.attrs['align']?.toLowerCase()) {
            'center' => 'center',
            'right' => 'right',
            _ => null,
          };
          cells.add(DocCell(spans, align: align, header: isHeader));
        }
        if (cells.isNotEmpty) rows.add(cells);
      } else if (child.tag == 'thead' || child.tag == 'tbody' || child.tag == 'tfoot') {
        walkRows(child);
      }
    }
  }

  walkRows(table);
  if (rows.isEmpty) return null;
  return DocTable(rows, headerRow: hasHeader);
}

/// 取节点下所有文本（`<pre>` 用；保留原始空白）。
String _collectText(_Node node) {
  final b = StringBuffer();
  void walk(_Node n) {
    for (final c in n.children) {
      if (c.isText) {
        b.write(c.text);
      } else if (c.tag == 'br') {
        b.write('\n');
      } else {
        walk(c);
      }
    }
  }

  walk(node);
  return b.toString();
}

/// `<pre class="language-dart">` / `<code class="lang-js">` 里的语言标记。
String? _langOf(_Node pre) {
  for (final n in [pre, ...pre.children]) {
    final cls = n.attrs['class'];
    if (cls == null) continue;
    final m = RegExp(r'(?:language|lang|highlight)-([a-zA-Z0-9+#]+)').firstMatch(cls);
    if (m != null) return m.group(1);
  }
  return null;
}

/// 折空白：HTML 里为排版而生的换行/缩进不该在正文里留痕。
String _squash(String s) => s.replaceAll(RegExp(r'[ \t\r\n\f]+'), ' ');
