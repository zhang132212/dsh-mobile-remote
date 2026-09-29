// OMML 双通道（v3.2.0）——Word 原生公式（"Alt+=" 那种）的**导出**与**导入**。
//
// 为什么自研：LaTeX ⇄ OMML 在整个 Dart/Flutter 生态里**没有可用库**
// （mathml2omml 是 JS、tex2word 走 pandoc/Python、MML2OMML.XSL 需要 XSLT 引擎，
// 服务器上也没有 pandoc）。故此处按 OOXML 规范手写，元素映射对齐 Word 自身输出的
// OMML 结构（<m:f>/<m:sSup>/<m:nary>/<m:d>/<m:borderBox> …）。
//
// 导出：TeX 源码 → tex.dart 的 AST → <m:oMath> XML（写进 .docx 后 Word 里可直接
//       Alt+= 编辑，是真·原生公式，不是图片也不是纯文本）。
// 导入：docx 里的 <m:oMath> → TeX 源码 → 交给 flutter_math_fork 渲染。
//
// 关键结构约定（与 Word 一致）：大算符 ∫∑ 的**被作用式**要放进 <m:e>——即 LaTeX
// `\int_a^b f dx` 里 `f dx` 整体成为 nary 的 e，而不是与算符并列。
import 'package:xml/xml.dart';

import 'tex.dart';

/// OMML 命名空间（Office Math）。
const String kOmmlNs = 'http://schemas.openxmlformats.org/officeDocument/2006/math';

/// WordprocessingML 命名空间。
const String kWmlNs = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';

/// OMML 前缀声明（写 docx 的根元素时用）。
const String kOmmlNsDecl = 'http://schemas.openxmlformats.org/officeDocument/2006/math';
const String kWmlNsDecl = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';

// ══════════════════════════════════════════════════════════════════
// 导出：TeX / AST → OMML
// ══════════════════════════════════════════════════════════════════

/// TeX 源码 → `<m:oMath>` XML 字符串。
String texToOmmlXml(String tex) {
  final node = parseTex(tex);
  final b = XmlBuilder();
  b.element('m:oMath', nest: () => _writeNode(b, node));
  return b.buildDocument().toXmlString();
}

/// TeX 源码 → `<m:oMath>` 元素（嵌入 docx 时用）。
XmlElement texToOmmlElement(String tex) {
  final node = parseTex(tex);
  final b = XmlBuilder();
  b.element('m:oMath', nest: () => _writeNode(b, node));
  return b.buildDocument().rootElement;
}

/// 单个 AST 节点 → `<m:oMath>` 元素。
XmlElement nodeToOmmlElement(MNode node) {
  final b = XmlBuilder();
  b.element('m:oMath', nest: () => _writeNode(b, node));
  return b.buildDocument().rootElement;
}

/// 显示式公式整段 → `<m:oMathPara>`（docx 里独占一行居中）。
XmlElement texToOmmlPara(String tex) {
  final b = XmlBuilder();
  b.element('m:oMathPara', nest: () {
    b.element('m:oMathParaPr', nest: () {
      b.element('m:jc', attributes: {'m:val': 'center'});
    });
    b.element('m:oMath', nest: () => _writeNode(b, parseTex(tex)));
  });
  return b.buildDocument().rootElement;
}

/// 组合字符（供 m:acc / m:groupChr 使用）：把 AST 里的独立重音字形
/// 映射到 Unicode **组合**字符，Word 才会正确地画在基字符上方。
String _combiningAccent(String a) => switch (a) {
      '^' => '\u0302',
      '¯' => '\u0304',
      '~' => '\u0303',
      '˙' => '\u0307',
      '¨' => '\u0308',
      '→' => '\u20D7',
      '´' => '\u0301',
      '`' => '\u0300',
      '˘' => '\u0306',
      'ˇ' => '\u030C',
      '˚' => '\u030A',
      _ => a,
    };

/// 间距 → Unicode 空格（OMML 没有显式间距元素，Word 用真实空格字符表达）。
String _spaceChar(double em) {
  if (em >= 0.9) return '\u2003'; // em space
  if (em >= 0.4) return '\u2002'; // en space
  if (em <= -0.1) return ''; // 负间距在 OMML 里无从表达，丢弃
  return '\u2009'; // thin space
}

void _writeNode(XmlBuilder b, MNode n) {
  switch (n) {
    case MAtom(:final text, :final kind):
      // 变量斜体（OMML 默认字母斜体）；数字/函数名/算符/符号一律直立。
      _writeRun(b, text, upright: kind != MKind.ident);

    case MTextRun(:final text, :final bold, :final italic):
      _writeRun(b, text, upright: !italic, bold: bold);

    case MSpace(:final em):
      final s = _spaceChar(em);
      if (s.isNotEmpty) {
        b.element('m:r', nest: () {
          b.element('m:t', attributes: {'xml:space': 'preserve'}, nest: () => b.text(s));
        });
      }

    case MRow(:final items):
      _writeRow(b, items);

    case MFrac(:final num, :final den, :final binom):
      if (binom) {
        // 组合数：无横线分式 + 圆括号定界
        b.element('m:d', nest: () {
          b.element('m:dPr', nest: () {
            b.element('m:begChr', attributes: {'m:val': '('});
            b.element('m:endChr', attributes: {'m:val': ')'});
          });
          b.element('m:e', nest: () {
            b.element('m:f', nest: () {
              b.element('m:fPr', nest: () {
                b.element('m:type', attributes: {'m:val': 'noBar'});
              });
              b.element('m:num', nest: () => _writeNode(b, num));
              b.element('m:den', nest: () => _writeNode(b, den));
            });
          });
        });
      } else {
        b.element('m:f', nest: () {
          b.element('m:fPr');
          b.element('m:num', nest: () => _writeNode(b, num));
          b.element('m:den', nest: () => _writeNode(b, den));
        });
      }

    case MScript(:final base, :final sub, :final sup):
      if (sub != null && sup != null) {
        b.element('m:sSubSup', nest: () {
          b.element('m:sSubSupPr');
          b.element('m:e', nest: () => _writeNode(b, base));
          b.element('m:sub', nest: () => _writeNode(b, sub));
          b.element('m:sup', nest: () => _writeNode(b, sup));
        });
      } else if (sup != null) {
        b.element('m:sSup', nest: () {
          b.element('m:sSupPr');
          b.element('m:e', nest: () => _writeNode(b, base));
          b.element('m:sup', nest: () => _writeNode(b, sup));
        });
      } else if (sub != null) {
        b.element('m:sSub', nest: () {
          b.element('m:sSubPr');
          b.element('m:e', nest: () => _writeNode(b, base));
          b.element('m:sub', nest: () => _writeNode(b, sub));
        });
      } else {
        _writeNode(b, base);
      }

    case MSqrt(:final body, :final index):
      b.element('m:rad', nest: () {
        if (index == null) {
          b.element('m:radPr', nest: () {
            b.element('m:degHide', attributes: {'m:val': '1'});
          });
          b.element('m:deg');
        } else {
          b.element('m:radPr');
          b.element('m:deg', nest: () => _writeNode(b, index));
        }
        b.element('m:e', nest: () => _writeNode(b, body));
      });

    case MBigOp():
      // 独立出现（后面没有可吞的式子）时，e 留空
      _writeNary(b, n, const MRow(<MNode>[]));

    case MDelim(:final left, :final right, :final body):
      b.element('m:d', nest: () {
        b.element('m:dPr', nest: () {
          if (left.isNotEmpty) b.element('m:begChr', attributes: {'m:val': left});
          if (right.isNotEmpty) b.element('m:endChr', attributes: {'m:val': right});
        });
        b.element('m:e', nest: () => _writeNode(b, body));
      });

    case MBoxed(:final body):
      // Word 里画可见边框的是 borderBox（box 只是分组，不画框）
      b.element('m:borderBox', nest: () {
        b.element('m:borderBoxPr');
        b.element('m:e', nest: () => _writeNode(b, body));
      });

    case MAccent(:final accent, :final base):
      b.element('m:acc', nest: () {
        b.element('m:accPr', nest: () {
          b.element('m:chr', attributes: {'m:val': _combiningAccent(accent)});
        });
        b.element('m:e', nest: () => _writeNode(b, base));
      });

    case MOverUnder(:final base, :final over, :final under, :final overStyle, :final underStyle):
      _writeOverUnder(b, n, base, over, under, overStyle, underStyle);

    case MMatrix(:final rows, :final env):
      final delims = n.delims;
      void writeMatrix() => _writeMatrix(b, rows, env);
      if (delims != null) {
        final (l, r) = delims;
        b.element('m:d', nest: () {
          b.element('m:dPr', nest: () {
            if (l.isNotEmpty) b.element('m:begChr', attributes: {'m:val': l});
            if (r.isNotEmpty) b.element('m:endChr', attributes: {'m:val': r});
          });
          b.element('m:e', nest: () => writeMatrix());
        });
      } else {
        writeMatrix();
      }

    case MLineBreak():
      // 行内换行在 OMML 里没有对应元素；用 en space 占位以免内容粘连
      b.element('m:r', nest: () {
        b.element('m:t', attributes: {'xml:space': 'preserve'}, nest: () => b.text('\u2002'));
      });
  }
}

/// 行序列：大算符要「吃掉」其后的式子作为 `<m:e>`（与 Word 输出一致）。
void _writeRow(XmlBuilder b, List<MNode> items) {
  var i = 0;
  while (i < items.length) {
    final n = items[i];
    if (n is MBigOp) {
      final rest = items.sublist(i + 1);
      _writeNary(b, n, MRow(rest));
      return; // 其余节点已并入 nary 的 e
    }
    _writeNode(b, n);
    i++;
  }
}

/// n-ary（∫ ∑ ∏ …）：chr + limLoc + 上下限 + 被作用式。
void _writeNary(XmlBuilder b, MBigOp op, MNode body) {
  b.element('m:nary', nest: () {
    b.element('m:naryPr', nest: () {
      b.element('m:chr', attributes: {'m:val': op.op});
      b.element('m:limLoc', attributes: {'m:val': op.limits ? 'undOvr' : 'subSup'});
      if (op.sub == null) b.element('m:subHide', attributes: {'m:val': '1'});
      if (op.sup == null) b.element('m:supHide', attributes: {'m:val': '1'});
    });
    b.element('m:sub', nest: () {
      if (op.sub != null) _writeNode(b, op.sub!);
    });
    b.element('m:sup', nest: () {
      if (op.sup != null) _writeNode(b, op.sup!);
    });
    b.element('m:e', nest: () => _writeNode(b, body));
  });
}

void _writeOverUnder(XmlBuilder b, MNode self, MNode base, MNode? over, MNode? under,
    String overStyle, String underStyle) {
  // 上划线 / 下划线
  if (overStyle == 'line') {
    b.element('m:bar', nest: () {
      b.element('m:barPr', nest: () {
        b.element('m:pos', attributes: {'m:val': 'top'});
      });
      b.element('m:e', nest: () => _writeNode(b, base));
    });
    return;
  }
  if (underStyle == 'line') {
    b.element('m:bar', nest: () {
      b.element('m:barPr', nest: () {
        b.element('m:pos', attributes: {'m:val': 'bot'});
      });
      b.element('m:e', nest: () => _writeNode(b, base));
    });
    return;
  }
  // 上下花括号（\overbrace / \underbrace）
  if (overStyle == 'brace') {
    b.element('m:groupChr', nest: () {
      b.element('m:groupChrPr', nest: () {
        b.element('m:chr', attributes: {'m:val': '\u23DE'}); // ⏞
        b.element('m:pos', attributes: {'m:val': 'top'});
      });
      b.element('m:e', nest: () => _writeNode(b, base));
    });
    if (over != null) {
      // 花括号上的标注
      b.element('m:limUpp', nest: () {
        b.element('m:e');
        b.element('m:lim', nest: () => _writeNode(b, over));
      });
    }
    return;
  }
  if (underStyle == 'brace') {
    b.element('m:groupChr', nest: () {
      b.element('m:groupChrPr', nest: () {
        b.element('m:chr', attributes: {'m:val': '\u23DF'}); // ⏟
        b.element('m:pos', attributes: {'m:val': 'bot'});
      });
      b.element('m:e', nest: () => _writeNode(b, base));
    });
    if (under != null) {
      b.element('m:limLow', nest: () {
        b.element('m:e');
        b.element('m:lim', nest: () => _writeNode(b, under));
      });
    }
    return;
  }
  // \overset / \underset / \stackrel：上下标式标注
  if (under != null) {
    b.element('m:limLow', nest: () {
      b.element('m:e', nest: () => _writeNode(b, base));
      b.element('m:lim', nest: () => _writeNode(b, under));
    });
    return;
  }
  if (over != null) {
    b.element('m:limUpp', nest: () {
      b.element('m:e', nest: () => _writeNode(b, base));
      b.element('m:lim', nest: () => _writeNode(b, over));
    });
    return;
  }
  _writeNode(b, base);
}

void _writeMatrix(XmlBuilder b, List<List<MNode>> rows, String env) {
  b.element('m:m', nest: () {
    // cases 用左对齐两列；普通矩阵居中
    b.element('m:mPr', nest: () {
      b.element('m:mcs', nest: () {
        final cols = rows.isEmpty ? 1 : rows.map((r) => r.length).fold<int>(0, (a, c) => c > a ? c : a);
        for (var c = 0; c < cols; c++) {
          b.element('m:mc', nest: () {
            b.element('m:mcPr', nest: () {
              b.element('m:count', attributes: {'m:val': '1'});
              b.element('m:mcJc', attributes: {'m:val': env == 'cases' && c == 0 ? 'left' : 'center'});
            });
          });
        }
      });
    });
    for (final r in rows) {
      b.element('m:mr', nest: () {
        for (final cell in r) {
          b.element('m:e', nest: () => _writeNode(b, cell));
        }
      });
    }
  });
}

/// 一个数学 run。
void _writeRun(XmlBuilder b, String text, {bool upright = true, bool bold = false}) {
  if (text.isEmpty) return;
  b.element('m:r', nest: () {
    if (upright) {
      b.element('m:rPr', nest: () {
        b.element('m:nor');
      });
    }
    if (bold) {
      b.element('w:rPr', nest: () {
        b.element('w:b');
      });
    }
    b.element('m:t', attributes: {'xml:space': 'preserve'}, nest: () => b.text(text));
  });
}

// ══════════════════════════════════════════════════════════════════
// 导入：docx 里的 OMML → TeX
// ══════════════════════════════════════════════════════════════════

/// 取出 OMML 元素的 `val` 属性（元素缺失时返回 null）。
///
/// 注意：不能按 `getAttribute('val', namespace: kOmmlNs)` 取——package:xml 把
/// `m:val` 存成**前缀名**（prefix=m, local=val），命名空间限定查找会落空。
/// 这里直接按 local 名扫一遍属性，对前缀/命名空间两种写法都成立。
String? _mVal(XmlElement? el) {
  if (el == null) return null;
  for (final a in el.attributes) {
    if (a.name.local == 'val') return a.value;
  }
  return null;
}

/// 子元素按本地名取第一个。
XmlElement? _child(XmlElement el, String local) {
  for (final c in el.childElements) {
    if (c.name.local == local) return c;
  }
  return null;
}

List<XmlElement> _children(XmlElement el, String local) =>
    el.childElements.where((c) => c.name.local == local).toList();

/// OMML 元素 → TeX 源码（供 flutter_math_fork 渲染）。
String ommlToTex(XmlElement el) {
  final sb = StringBuffer();
  _readOmml(el, sb);
  final out = sb.toString().trim();
  return out.isEmpty ? r'\text{ }' : out;
}

/// 读取一段可能包含多个 m:oMath 的容器（如 m:oMathPara 或 w:p）。
String ommlContainerToTex(XmlElement el) {
  final parts = <String>[];
  void walk(XmlElement e) {
    for (final c in e.childElements) {
      if (c.name.local == 'oMath') {
        parts.add(ommlToTex(c));
      } else {
        walk(c);
      }
    }
  }

  walk(el);
  return parts.join(r'\quad ');
}

void _readOmml(XmlElement el, StringBuffer out) {
  switch (el.name.local) {
    case 'oMath':
    case 'oMathPara':
    case 'e':
    case 'num':
    case 'den':
    case 'sub':
    case 'sup':
    case 'lim':
    case 'fName':
    case 'deg':
    case 'box':
    case 'borderBox':
      // 纯容器：递归取内容。
      // 注意：`m` / `mr` **不能**放这里——它们是矩阵与矩阵行，必须落到下面
      // 各自的 case，否则矩阵会被当成容器把单元格内容无分隔地拼成一串（实测踩中）。
      for (final c in el.childElements) {
        _readOmml(c, out);
      }
      return;

    case 'r':
      out.write(_escapeTex(_runText(el)));
      return;

    case 't':
      out.write(_escapeTex(el.innerText));
      return;

    case 'f':
      out.write(r'\frac{');
      _readInto(el, 'num', out);
      out.write('}{');
      _readInto(el, 'den', out);
      out.write('}');
      return;

    case 'sSup':
      out.write('{');
      _readInto(el, 'e', out);
      out.write('}^{');
      _readInto(el, 'sup', out);
      out.write('}');
      return;

    case 'sSub':
      out.write('{');
      _readInto(el, 'e', out);
      out.write('}_{');
      _readInto(el, 'sub', out);
      out.write('}');
      return;

    case 'sSubSup':
      out.write('{');
      _readInto(el, 'e', out);
      out.write('}_{');
      _readInto(el, 'sub', out);
      out.write('}^{');
      _readInto(el, 'sup', out);
      out.write('}');
      return;

    case 'sPre':
      // 前置上下标：\prescript 的近似表达
      out.write(r'{}_{');
      _readInto(el, 'sub', out);
      out.write('}^{');
      _readInto(el, 'sup', out);
      out.write('}');
      _readInto(el, 'e', out);
      return;

    case 'rad':
      final degHide = _mVal(_child(_child(el, 'radPr') ?? el, 'degHide') ?? el);
      final deg = _child(el, 'deg');
      final hasDeg = deg != null && deg.innerText.trim().isNotEmpty && degHide != '1';
      out.write(r'\sqrt');
      if (hasDeg) {
        out.write('[');
        _readOmml(deg, out);
        out.write(']');
      }
      out.write('{');
      _readInto(el, 'e', out);
      out.write('}');
      return;

    case 'nary':
      final pr = _child(el, 'naryPr');
      final chr = pr == null ? null : _mVal(_child(pr, 'chr'));
      final op = (chr == null || chr.isEmpty) ? '∫' : chr;
      out.write(_naryToTex(op));
      final subHide = pr == null ? null : _mVal(_child(pr, 'subHide'));
      final supHide = pr == null ? null : _mVal(_child(pr, 'supHide'));
      final subEl = _child(el, 'sub');
      final supEl = _child(el, 'sup');
      if (subEl != null && subHide != '1' && subEl.innerText.trim().isNotEmpty) {
        out.write('_{');
        _readOmml(subEl, out);
        out.write('}');
      }
      if (supEl != null && supHide != '1' && supEl.innerText.trim().isNotEmpty) {
        out.write('^{');
        _readOmml(supEl, out);
        out.write('}');
      }
      _readInto(el, 'e', out);
      return;

    case 'd':
      final pr = _child(el, 'dPr');
      final beg = pr == null ? null : _mVal(_child(pr, 'begChr'));
      final end = pr == null ? null : _mVal(_child(pr, 'endChr'));
      out.write(r'\left');
      out.write(_delimToTex(beg ?? '('));
      for (final e in _children(el, 'e')) {
        _readOmml(e, out);
      }
      out.write(r'\right');
      out.write(_delimToTex(end ?? ')'));
      return;

    case 'func':
      _readInto(el, 'fName', out);
      out.write(r'\left(');
      _readInto(el, 'e', out);
      out.write(r'\right)');
      return;

    case 'limLow':
      out.write('{');
      _readInto(el, 'e', out);
      out.write('}_{');
      _readInto(el, 'lim', out);
      out.write('}');
      return;

    case 'limUpp':
      out.write('{');
      _readInto(el, 'e', out);
      out.write('}^{');
      _readInto(el, 'lim', out);
      out.write('}');
      return;

    case 'acc':
      final pr = _child(el, 'accPr');
      final chr = pr == null ? null : _mVal(_child(pr, 'chr'));
      out.write(_accentToTex(chr ?? '\u0302'));
      out.write('{');
      _readInto(el, 'e', out);
      out.write('}');
      return;

    case 'bar':
      final pr = _child(el, 'barPr');
      final pos = pr == null ? null : _mVal(_child(pr, 'pos'));
      out.write(pos == 'bot' ? r'\underline{' : r'\overline{');
      _readInto(el, 'e', out);
      out.write('}');
      return;

    case 'groupChr':
      final pr = _child(el, 'groupChrPr');
      final pos = pr == null ? null : _mVal(_child(pr, 'pos'));
      out.write(pos == 'bot' ? r'\underbrace{' : r'\overbrace{');
      _readInto(el, 'e', out);
      out.write('}');
      return;

    case 'm':
      // 矩阵：按环境定界符还原
      final rows = _children(el, 'mr');
      out.write(r'\begin{matrix}');
      for (var i = 0; i < rows.length; i++) {
        if (i > 0) out.write(r'\\');
        final cells = _children(rows[i], 'e');
        for (var c = 0; c < cells.length; c++) {
          if (c > 0) out.write('&');
          _readOmml(cells[c], out);
        }
      }
      out.write(r'\end{matrix}');
      return;

    case 'eqArr':
      final rows = _children(el, 'e');
      out.write(r'\begin{aligned}');
      for (var i = 0; i < rows.length; i++) {
        if (i > 0) out.write(r'\\');
        _readOmml(rows[i], out);
      }
      out.write(r'\end{aligned}');
      return;

    case 'phant':
      out.write(r'\phantom{');
      _readInto(el, 'e', out);
      out.write('}');
      return;

    case 'rPr':
    case 'ctrlPr':
    case 'fPr':
    case 'sSupPr':
    case 'sSubPr':
    case 'sSubSupPr':
    case 'radPr':
    case 'naryPr':
    case 'dPr':
    case 'funcPr':
    case 'limLowPr':
    case 'limUppPr':
    case 'accPr':
    case 'barPr':
    case 'groupChrPr':
    case 'mPr':
    case 'oMathParaPr':
    case 'boxPr':
    case 'borderBoxPr':
    case 'mcPr':
    case 'mcs':
    case 'mc':
    case 'degHide':
    case 'subHide':
    case 'supHide':
    case 'chr':
    case 'pos':
    case 'type':
    case 'begChr':
    case 'endChr':
    case 'limLoc':
    case 'count':
    case 'mcJc':
      return; // 属性/控制元素：无内容

    case 'brk':
      out.write(r'\\');
      return;

    default:
      // 未知元素：递归取内容（绝不丢字）
      for (final c in el.childElements) {
        _readOmml(c, out);
      }
      return;
  }
}

void _readInto(XmlElement parent, String local, StringBuffer out) {
  final c = _child(parent, local);
  if (c != null) _readOmml(c, out);
}

/// 一个 m:r 的可见文本（可能有多个 m:t）。
String _runText(XmlElement r) {
  final b = StringBuffer();
  for (final t in _children(r, 't')) {
    b.write(t.innerText);
  }
  return b.toString();
}

/// OMML 里的大算符字符 → LaTeX 命令。
String _naryToTex(String chr) => switch (chr) {
      '∫' => r'\int',
      '∬' => r'\iint',
      '∭' => r'\iiint',
      '∮' => r'\oint',
      '∑' => r'\sum',
      '∏' => r'\prod',
      '∐' => r'\coprod',
      '⋃' => r'\bigcup',
      '⋂' => r'\bigcap',
      '⋁' => r'\bigvee',
      '⋀' => r'\bigwedge',
      '⨁' => r'\bigoplus',
      '⨂' => r'\bigotimes',
      '⨀' => r'\bigodot',
      '⨆' => r'\bigsqcup',
      _ => chr,
    };

/// 定界符字符 → LaTeX（\left..\right 需要一个命令或单个字符）。
String _delimToTex(String d) => switch (d) {
      '{' => r'\{',
      '}' => r'\}',
      '|' => r'|',
      '‖' => r'\|',
      '⟨' => r'\langle',
      '⟩' => r'\rangle',
      '⌊' => r'\lfloor',
      '⌋' => r'\rfloor',
      '⌈' => r'\lceil',
      '⌉' => r'\rceil',
      '→' => r'\rightarrow',
      '←' => r'\leftarrow',
      _ => d,
    };

/// 组合重音字符 → LaTeX 命令。
String _accentToTex(String c) => switch (c) {
      '\u0302' || '^' => r'\hat',
      '\u0304' || '¯' => r'\bar',
      '\u0303' || '~' => r'\tilde',
      '\u0307' || '˙' => r'\dot',
      '\u0308' || '¨' => r'\ddot',
      '\u20D7' || '→' => r'\vec',
      '\u0301' || '´' => r'\acute',
      '\u0300' || '`' => r'\grave',
      '\u0306' || '˘' => r'\breve',
      '\u030C' || 'ˇ' => r'\check',
      '\u030A' || '˚' => r'\mathring',
      _ => r'\hat',
    };

/// TeX 特殊字符转义（只处理文本 run，命令由上面的映射负责）。
String _escapeTex(String s) {
  final b = StringBuffer();
  for (final r in s.runes) {
    final c = String.fromCharCode(r);
    switch (c) {
      case r'\':
        b.write(r'\backslash ');
      case '{':
        b.write(r'\{');
      case '}':
        b.write(r'\}');
      case r'$':
        b.write(r'\$');
      case '&':
        b.write(r'\&');
      case '#':
        b.write(r'\#');
      case '%':
        b.write(r'\%');
      case '_':
        b.write(r'\_');
      case '~':
        b.write(r'\sim ');
      case '^':
        b.write(r'\hat{}');
      // 全角/中文等直接透传：flutter_math_fork 走 textstyle 能显示
      default:
        if (r < 0x20 && c != '\n' && c != '\t') {
          b.write(' ');
        } else {
          b.write(c);
        }
    }
  }
  return b.toString();
}
