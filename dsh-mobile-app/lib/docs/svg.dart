// SVG 读取器（v3.2.8）——纯 Dart 解析 SVG 常用子集，产出**可渲染的图形模型**，
// 交给 render.dart 的 CustomPainter 画出来：不引 flutter_svg、不开 WebView、
// 不跳浏览器，矢量图形在阅读页里就地显示。
//
// 支持范围（覆盖图标 / 示意图 / 流程图 / 电路图这类绝大多数场景）：
//   · 形状：rect（含圆角 rx/ry）、circle、ellipse、line、polyline、polygon、path
//   · path 命令：M L H V C S Q T A Z（大小写齐全，相对坐标在**解析期**折算成绝对）
//   · 结构：svg / g 嵌套、transform（translate/scale/rotate/matrix/skewX/skewY）
//   · 样式：presentation 属性与内联 style=""，fill / stroke / stroke-width /
//           opacity / fill-opacity / stroke-opacity / stroke-linecap / stroke-linejoin
//   · 文本：text（x / y / font-size / text-anchor / fill）
//   · 颜色：#rgb / #rrggbb / 命名色 / rgb() / none
//
// 明确不支持（遇到即忽略该元素，不报错）：渐变、滤镜、遮罩、clipPath、动画、
// 外部引用（use / image）、CSS 样式表、字体度量。宁可少画，不可画错。
import 'dart:math' as math;

import 'package:xml/xml.dart';

import 'model.dart';

// 图形模型（DocSvg / SvgDoc / SvgNode / SvgGeometry / SvgStyle / SvgTransform）已并入 docs/model.dart：
// DocBlock 是 sealed 类，块类型必须与基类同库；解析器只负责「文本 → 模型」。

// ══════════════════════════════════════════════════════════════════
// 解析
// ══════════════════════════════════════════════════════════════════

/// 图元数量上限（防超大图把手机拖死）。
const int kMaxSvgNodes = 3000;

/// 解析 SVG 文本 → Document。**不抛异常**。
Document parseSvg(String text, String title) {
  XmlDocument xdoc;
  try {
    xdoc = XmlDocument.parse(text);
  } catch (e) {
    return Document(title, DocFormat.svg, [
      DocPara([DocText('SVG 解析失败：$e')]),
      DocCode(text, lang: 'svg'),
    ]);
  }

  final root = xdoc.rootElement;
  if (root.name.local != 'svg') {
    return Document(title, DocFormat.svg, [
      DocPara([DocText('这不是一个 SVG 根元素（根是 <${root.name.local}>）。')]),
      DocCode(text, lang: 'svg'),
    ]);
  }

  // viewBox 优先，其次 width/height；都没有就按 300×150（SVG 规范的默认）
  final vb = _numbers(root.getAttribute('viewBox'));
  final wAttr = _len(root.getAttribute('width'));
  final hAttr = _len(root.getAttribute('height'));
  var vbW = vb.length >= 4 ? vb[2] : null;
  var vbH = vb.length >= 4 ? vb[3] : null;
  var width = wAttr ?? vbW ?? 300;
  var height = hAttr ?? vbH ?? 150;
  if (width <= 0) width = vbW ?? 300;
  if (height <= 0) height = vbH ?? 150;

  final counter = _Counter();
  final nodes = _walkChildren(root, const SvgStyle(), null, counter);

  return Document(title, DocFormat.svg, [
    DocSvg(
      SvgDoc(
        width: width,
        height: height,
        nodes: nodes,
        viewBoxX: vb.length >= 4 ? vb[0] : 0,
        viewBoxY: vb.length >= 4 ? vb[1] : 0,
        viewBoxW: vbW,
        viewBoxH: vbH,
      ),
      text,
    ),
  ], warnings: [
    if (counter.value >= kMaxSvgNodes) '图元过多，仅渲染前 $kMaxSvgNodes 个',
  ]);
}

/// 遍历子元素（跳过 defs / title / desc 等非绘制内容）。
List<SvgNode> _walkChildren(
  XmlElement parent,
  SvgStyle inherited,
  SvgTransform? parentTf,
  _Counter counter,
) {
  final out = <SvgNode>[];
  for (final child in parent.childElements) {
    if (counter.value >= kMaxSvgNodes) break;
    final node = _walk(child, inherited, parentTf, counter);
    if (node != null) out.add(node);
  }
  return out;
}

SvgNode? _walk(
  XmlElement el,
  SvgStyle inherited,
  SvgTransform? parentTf,
  _Counter counter,
) {
  final tag = el.name.local;
  // 这些标签不直接绘制（defs 是模板库，title/desc 是元数据）
  if (tag == 'defs' || tag == 'title' || tag == 'desc' ||
      tag == 'metadata' || tag == 'style' || tag == 'script') {
    return null;
  }

  final style = _styleOf(el, inherited);
  final tf = _combine(parentTf, _transformOf(el.getAttribute('transform')));

  switch (tag) {
    case 'g':
    case 'svg':
      final kids = _walkChildren(el, style, tf, counter);
      return kids.isEmpty ? null : SvgGroup(kids, transform: tf);

    case 'text':
      final txt = el.innerText.trim();
      if (txt.isEmpty) return null;
      counter.value++;
      final anchor = el.getAttribute('text-anchor') ??
          _styleMap(el)['text-anchor'] ??
          'start';
      return SvgTextNode(
        _len(el.getAttribute('x')) ?? 0,
        _len(el.getAttribute('y')) ?? 0,
        txt,
        fontSize: _len(el.getAttribute('font-size')) ??
            double.tryParse(_styleMap(el)['font-size'] ?? '') ??
            16,
        anchor: anchor,
        style: style,
        transform: tf,
      );

    case 'rect':
      counter.value++;
      final w = _len(el.getAttribute('width')) ?? 0;
      final h = _len(el.getAttribute('height')) ?? 0;
      if (w <= 0 || h <= 0) return null;
      final rx = _len(el.getAttribute('rx')) ?? 0;
      final ry = _len(el.getAttribute('ry')) ?? rx;
      return SvgShape(
        SvgRect(_len(el.getAttribute('x')) ?? 0, _len(el.getAttribute('y')) ?? 0, w, h,
            rx: rx, ry: ry),
        style: style,
        transform: tf,
      );

    case 'circle':
      counter.value++;
      final r = _len(el.getAttribute('r')) ?? 0;
      if (r <= 0) return null;
      return SvgShape(
        SvgCircle(_len(el.getAttribute('cx')) ?? 0, _len(el.getAttribute('cy')) ?? 0, r),
        style: style,
        transform: tf,
      );

    case 'ellipse':
      counter.value++;
      final rx = _len(el.getAttribute('rx')) ?? 0;
      final ry = _len(el.getAttribute('ry')) ?? 0;
      if (rx <= 0 || ry <= 0) return null;
      return SvgShape(
        SvgEllipse(_len(el.getAttribute('cx')) ?? 0, _len(el.getAttribute('cy')) ?? 0, rx, ry),
        style: style,
        transform: tf,
      );

    case 'line':
      counter.value++;
      return SvgShape(
        SvgLineGeom(
          _len(el.getAttribute('x1')) ?? 0,
          _len(el.getAttribute('y1')) ?? 0,
          _len(el.getAttribute('x2')) ?? 0,
          _len(el.getAttribute('y2')) ?? 0,
        ),
        style: style,
        transform: tf,
      );

    case 'polyline':
    case 'polygon':
      final pts = _numbers(el.getAttribute('points'));
      if (pts.length < 4) return null;
      counter.value++;
      final pairs = <(double, double)>[];
      for (var i = 0; i + 1 < pts.length; i += 2) {
        pairs.add((pts[i], pts[i + 1]));
      }
      return SvgShape(
        SvgPoly(pairs, close: tag == 'polygon'),
        style: style,
        transform: tf,
      );

    case 'path':
      final d = el.getAttribute('d');
      if (d == null || d.trim().isEmpty) return null;
      final cmds = parsePathData(d);
      if (cmds.isEmpty) return null;
      counter.value++;
      return SvgShape(SvgPathGeom(cmds), style: style, transform: tf);

    default:
      // 未知标签：如果是容器就继续往下走（宽松优先），否则忽略
      final kids = _walkChildren(el, style, tf, counter);
      return kids.isEmpty ? null : SvgGroup(kids, transform: tf);
  }
}

class _Counter {
  int value = 0;
}

// ── 样式 ──────────────────────────────────────────────────────────

/// 解析 style="" 成键值表（只做最朴素的 `k:v;` 切分，够用且不会误伤）。
Map<String, String> _styleMap(XmlElement el) {
  final raw = el.getAttribute('style');
  if (raw == null || raw.isEmpty) return const {};
  final map = <String, String>{};
  for (final part in raw.split(';')) {
    final i = part.indexOf(':');
    if (i <= 0) continue;
    map[part.substring(0, i).trim().toLowerCase()] = part.substring(i + 1).trim();
  }
  return map;
}

/// 元素最终样式：继承父样式，再叠加 presentation 属性与内联 style（后者优先）。
SvgStyle _styleOf(XmlElement el, SvgStyle parent) {
  final sm = _styleMap(el);
  String? pick(String name) => sm[name] ?? el.getAttribute(name);

  final fillRaw = pick('fill');
  final strokeRaw = pick('stroke');
  final fillOpacity = double.tryParse(pick('fill-opacity') ?? '') ?? 1.0;
  final strokeOpacity = double.tryParse(pick('stroke-opacity') ?? '') ?? 1.0;
  final opacity = double.tryParse(pick('opacity') ?? '') ?? 1.0;

  int? fill = parent.fill;
  if (fillRaw != null) {
    fill = _parseColor(fillRaw);
    if (fill != null && fillOpacity < 1) {
      fill = _withAlpha(fill, ((fill >> 24 & 0xFF) * fillOpacity).round());
    }
  }
  int? stroke = parent.stroke;
  if (strokeRaw != null) {
    stroke = _parseColor(strokeRaw);
    if (stroke != null && strokeOpacity < 1) {
      stroke = _withAlpha(stroke, ((stroke >> 24 & 0xFF) * strokeOpacity).round());
    }
  }

  return SvgStyle(
    fill: fill,
    stroke: stroke,
    strokeWidth: _len(pick('stroke-width')) ?? parent.strokeWidth,
    opacity: opacity,
    lineCap: pick('stroke-linecap') ?? parent.lineCap,
    lineJoin: pick('stroke-linejoin') ?? parent.lineJoin,
  );
}

int _withAlpha(int argb, int alpha) =>
    ((alpha.clamp(0, 255)) << 24) | (argb & 0x00FFFFFF);

/// 颜色：none / transparent / #rgb / #rrggbb / rgb() / 常见命名色。
int? _parseColor(String raw) {
  final s = raw.trim().toLowerCase();
  if (s.isEmpty) return null;
  if (s == 'none' || s == 'transparent') return null;
  if (s.startsWith('#')) {
    var h = s.substring(1);
    if (h.length == 3) h = h.split('').map((c) => '$c$c').join();
    if (h.length == 6) {
      final v = int.tryParse(h, radix: 16);
      if (v != null) return 0xFF000000 | v;
    }
    if (h.length == 8) {
      final v = int.tryParse(h, radix: 16);
      if (v != null) return v;
    }
    return null;
  }
  if (s.startsWith('rgb')) {
    final nums = _numbers(s);
    if (nums.length >= 3) {
      final a = nums.length >= 4 ? (nums[3] * 255).round().clamp(0, 255) : 255;
      return (a << 24) |
          ((nums[0].round().clamp(0, 255)) << 16) |
          ((nums[1].round().clamp(0, 255)) << 8) |
          (nums[2].round().clamp(0, 255));
    }
    return null;
  }
  return _namedColors[s];
}

/// 常用命名色（覆盖实际文档里 95% 以上的出现率；其余按不画处理）。
const Map<String, int> _namedColors = {
  'black': 0xFF000000, 'white': 0xFFFFFFFF, 'red': 0xFFFF0000,
  'green': 0xFF008000, 'blue': 0xFF0000FF, 'yellow': 0xFFFFFF00,
  'cyan': 0xFF00FFFF, 'aqua': 0xFF00FFFF, 'magenta': 0xFFFF00FF,
  'fuchsia': 0xFFFF00FF, 'gray': 0xFF808080, 'grey': 0xFF808080,
  'silver': 0xFFC0C0C0, 'maroon': 0xFF800000, 'olive': 0xFF808000,
  'lime': 0xFF00FF00, 'teal': 0xFF008080, 'navy': 0xFF000080,
  'purple': 0xFF800080, 'orange': 0xFFFFA500, 'pink': 0xFFFFC0CB,
  'brown': 0xFFA52A2A, 'gold': 0xFFFFD700, 'darkgray': 0xFFA9A9A9,
  'darkgrey': 0xFFA9A9A9, 'lightgray': 0xFFD3D3D3, 'lightgrey': 0xFFD3D3D3,
  'darkblue': 0xFF00008B, 'darkgreen': 0xFF006400, 'darkred': 0xFF8B0000,
  'lightblue': 0xFFADD8E6, 'lightgreen': 0xFF90EE90, 'skyblue': 0xFF87CEEB,
  'steelblue': 0xFF4682B4, 'tomato': 0xFFFF6347, 'salmon': 0xFFFA8072,
  'khaki': 0xFFF0E68C, 'beige': 0xFFF5F5DC, 'ivory': 0xFFFFFFF0,
  'indigo': 0xFF4B0082, 'violet': 0xFFEE82EE, 'turquoise': 0xFF40E0D0,
};

// ── 变换 ──────────────────────────────────────────────────────────

/// 解析 transform="translate(...) rotate(...)" —— 左乘链，与 SVG 语义一致。
SvgTransform? _transformOf(String? raw) {
  if (raw == null || raw.trim().isEmpty) return null;
  final re = RegExp(r'([a-zA-Z]+)\s*\(([^)]*)\)');
  SvgTransform? acc;
  for (final m in re.allMatches(raw)) {
    final name = m.group(1)!.toLowerCase();
    final args = _numbers(m.group(2)!);
    final t = switch (name) {
      'translate' => SvgTransform(1, 0, 0, 1, args.isNotEmpty ? args[0] : 0,
          args.length > 1 ? args[1] : 0),
      'scale' => SvgTransform(args.isNotEmpty ? args[0] : 1, 0, 0,
          args.length > 1 ? args[1] : (args.isNotEmpty ? args[0] : 1), 0, 0),
      'rotate' => _rotate(args),
      'matrix' when args.length >= 6 =>
        SvgTransform(args[0], args[1], args[2], args[3], args[4], args[5]),
      'skewx' => SvgTransform(1, 0, args.isNotEmpty ? _tan(args[0]) : 0, 1, 0, 0),
      'skewy' => SvgTransform(1, args.isNotEmpty ? _tan(args[0]) : 0, 0, 1, 0, 0),
      _ => SvgTransform.identity,
    };
    acc = acc == null ? t : acc.multiply(t);
  }
  return acc;
}

SvgTransform _rotate(List<double> a) {
  if (a.isEmpty) return SvgTransform.identity;
  final rad = a[0] * 3.1415926535897932 / 180.0;
  final cos = _cos(rad), sin = _sin(rad);
  final r = SvgTransform(cos, sin, -sin, cos, 0, 0);
  if (a.length >= 3) {
    // rotate(angle, cx, cy) = translate(cx,cy) rotate(angle) translate(-cx,-cy)
    return SvgTransform(1, 0, 0, 1, a[1], a[2])
        .multiply(r)
        .multiply(SvgTransform(1, 0, 0, 1, -a[1], -a[2]));
  }
  return r;
}

// dart:math 的 sin/cos/tan —— docs/ 不依赖 Flutter，用 dart:math 即可。
double _sin(double x) => math.sin(x);
double _cos(double x) => math.cos(x);
double _tan(double deg) => math.tan(deg * 3.1415926535897932 / 180.0);

SvgTransform? _combine(SvgTransform? parent, SvgTransform? own) {
  if (parent == null || parent.isIdentity) return own;
  if (own == null || own.isIdentity) return parent;
  return parent.multiply(own);
}

// ── 数值 ──────────────────────────────────────────────────────────

/// 抽出字符串里所有数字（含负数、小数、科学计数法）。
List<double> _numbers(String? raw) {
  if (raw == null || raw.isEmpty) return const [];
  final re = RegExp(r'[-+]?(?:\d*\.\d+|\d+\.?)(?:[eE][-+]?\d+)?');
  return [
    for (final m in re.allMatches(raw))
      if (double.tryParse(m.group(0)!) != null) double.parse(m.group(0)!),
  ];
}

/// 长度：支持无单位与 px（其余单位按 96dpi 粗略折算，够用就好）。
double? _len(String? raw) {
  if (raw == null) return null;
  final s = raw.trim().toLowerCase();
  if (s.isEmpty) return null;
  if (s.endsWith('%')) return null; // 百分比要参照父容器，这里不做，交给调用方兜底
  final m = RegExp(r'^([-+]?(?:\d*\.\d+|\d+\.?)(?:[eE][-+]?\d+)?)\s*([a-z]*)$').firstMatch(s);
  if (m == null) return null;
  final v = double.tryParse(m.group(1)!);
  if (v == null) return null;
  return switch (m.group(2)) {
    '' || 'px' => v,
    'pt' => v * 96 / 72,
    'pc' => v * 16,
    'in' => v * 96,
    'cm' => v * 96 / 2.54,
    'mm' => v * 96 / 25.4,
    _ => v,
  };
}

// ── path 的 d 属性 ────────────────────────────────────────────────

/// 解析 `d` → 命令列表。相对命令在这里就折算成绝对坐标，
/// 渲染端只需照着画，不必再维护 current point。
List<SvgPathCmd> parsePathData(String d) {
  final out = <SvgPathCmd>[];
  final re = RegExp(r'([MmLlHhVvCcSsQqTtAaZz])|([-+]?(?:\d*\.\d+|\d+\.?)(?:[eE][-+]?\d+)?)');

  var cx = 0.0, cy = 0.0; // 当前点
  var sx = 0.0, sy = 0.0; // 子路径起点（Z 回到这里）
  var lastCtrlX = 0.0, lastCtrlY = 0.0; // S/T 的隐式控制点
  String? cmd;
  var args = <double>[];

  void flush() {
    if (cmd == null) return;
    final c = cmd!;
    final upper = c.toUpperCase();
    final rel = c != upper;
    var i = 0;

    // 同一命令可以重复出现多组参数（如 "L 1 2 3 4"）
    void one() {
      switch (upper) {
        case 'M':
          final x = rel ? cx + args[i] : args[i];
          final y = rel ? cy + args[i + 1] : args[i + 1];
          i += 2;
          cx = x; cy = y; sx = x; sy = y;
          out.add(SvgCmdMove(x, y));
          // 后续参数按 L 处理（SVG 规范）
          cmd = rel ? 'l' : 'L';
        case 'L':
          final x = rel ? cx + args[i] : args[i];
          final y = rel ? cy + args[i + 1] : args[i + 1];
          i += 2;
          cx = x; cy = y;
          out.add(SvgCmdLine(x, y));
        case 'H':
          final x = rel ? cx + args[i] : args[i];
          i += 1;
          cx = x;
          out.add(SvgCmdLine(x, cy));
        case 'V':
          final y = rel ? cy + args[i] : args[i];
          i += 1;
          cy = y;
          out.add(SvgCmdLine(cx, y));
        case 'C':
          final x1 = rel ? cx + args[i] : args[i];
          final y1 = rel ? cy + args[i + 1] : args[i + 1];
          final x2 = rel ? cx + args[i + 2] : args[i + 2];
          final y2 = rel ? cy + args[i + 3] : args[i + 3];
          final x = rel ? cx + args[i + 4] : args[i + 4];
          final y = rel ? cy + args[i + 5] : args[i + 5];
          i += 6;
          cx = x; cy = y;
          lastCtrlX = x2; lastCtrlY = y2;
          out.add(SvgCmdCubic(x1, y1, x2, y2, x, y));
        case 'S':
          final x2 = rel ? cx + args[i] : args[i];
          final y2 = rel ? cy + args[i + 1] : args[i + 1];
          final x = rel ? cx + args[i + 2] : args[i + 2];
          final y = rel ? cy + args[i + 3] : args[i + 3];
          i += 4;
          // 第一控制点 = 上一点的镜像（无前置曲线时取当前点）
          final x1 = 2 * cx - lastCtrlX;
          final y1 = 2 * cy - lastCtrlY;
          cx = x; cy = y;
          lastCtrlX = x2; lastCtrlY = y2;
          out.add(SvgCmdCubic(x1, y1, x2, y2, x, y));
        case 'Q':
          final x1 = rel ? cx + args[i] : args[i];
          final y1 = rel ? cy + args[i + 1] : args[i + 1];
          final x = rel ? cx + args[i + 2] : args[i + 2];
          final y = rel ? cy + args[i + 3] : args[i + 3];
          i += 4;
          cx = x; cy = y;
          lastCtrlX = x1; lastCtrlY = y1;
          out.add(SvgCmdQuad(x1, y1, x, y));
        case 'T':
          final x = rel ? cx + args[i] : args[i];
          final y = rel ? cy + args[i + 1] : args[i + 1];
          i += 2;
          final x1 = 2 * cx - lastCtrlX;
          final y1 = 2 * cy - lastCtrlY;
          cx = x; cy = y;
          lastCtrlX = x1; lastCtrlY = y1;
          out.add(SvgCmdQuad(x1, y1, x, y));
        case 'A':
          final rx = args[i], ry = args[i + 1], rot = args[i + 2];
          final large = args[i + 3] != 0, sweep = args[i + 4] != 0;
          final x = rel ? cx + args[i + 5] : args[i + 5];
          final y = rel ? cy + args[i + 6] : args[i + 6];
          i += 7;
          cx = x; cy = y;
          out.add(SvgCmdArc(rx, ry, rot, large, sweep, x, y));
        case 'Z':
          out.add(const SvgCmdClose());
          cx = sx; cy = sy;
          i += 1;
        default:
          i = args.length; // 未知命令：吃光参数，避免死循环
      }
    }

    final need = switch (upper) {
      'M' || 'L' || 'T' => 2,
      'H' || 'V' => 1,
      'C' => 6,
      'S' || 'Q' => 4,
      'A' => 7,
      'Z' => 0,
      _ => 0,
    };
    if (upper == 'Z') {
      out.add(const SvgCmdClose());
      cx = sx; cy = sy;
    } else if (need > 0) {
      var guard = 0;
      while (i + need <= args.length && guard++ < 10000) {
        one();
      }
    }
  }

  for (final m in re.allMatches(d)) {
    final letter = m.group(1);
    if (letter != null) {
      flush();
      cmd = letter;
      args = [];
    } else {
      final v = double.tryParse(m.group(2)!);
      if (v != null) args.add(v);
    }
  }
  flush();
  return out;
}
