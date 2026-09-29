// TeX 数学解析（v3.2.0）——词法 + 递归下降 → MNode AST。
//
// 覆盖：分数 / 根式 / 上下标 / 大算符（∫∑∏lim）/ 定界符 \left..\right /
// 矩阵与 cases / 重音 / \text 文本块 / 间距 / 希腊字母 / 常用关系与二元算符。
// 未知命令**降级为罗马体文本**而不是丢弃——保证「至少可读」。
//
// 离线工具链（F:\dsh-build-kit）没有 math/latex 类 pub 包，故全部自研，
// 只依赖 dart 核心库；渲染与 OMML 导出都消费本文件的 AST。
import 'dart:math' as math;

// ══════════════════════════════════════════════════════════════════
// AST
// ══════════════════════════════════════════════════════════════════

/// 数学节点基类。
sealed class MNode {
  const MNode();
}

/// 原子类别：决定字形、斜体与间距。
enum MKind {
  /// 数字（罗马体，无间距）
  number,

  /// 标识符 / 变量（斜体）
  ident,

  /// 函数名（罗马体，如 sin、ln）
  func,

  /// 大算符（∫ ∑ ∏，需要放大并带上/下限）
  bigop,

  /// 二元算符（+ − × ±，两侧各 0.22em）
  bin,

  /// 关系符（= < > ≤，两侧各 0.28em）
  rel,

  /// 标点（, ; 后面 0.17em）
  punct,

  /// 定界符（( ) [ ] |，无间距）
  delim,

  /// 其它符号（∞ ∂ ∇ 等，罗马体）
  symbol,
}

/// 行内顺序容器（一个组 / 一个公式体）。
class MRow extends MNode {
  final List<MNode> items;
  const MRow(this.items);
  static const empty = MRow(<MNode>[]);
}

/// 叶子：一段文本 + 类别。
class MAtom extends MNode {
  final String text;
  final MKind kind;
  const MAtom(this.text, this.kind);
}

/// 分式；binom=true 时渲染为 (a b) 组合数形态（无横线）。
class MFrac extends MNode {
  final MNode num;
  final MNode den;
  final bool binom;

  /// 是否为显示式（\dfrac / 行间公式）——影响字号缩放
  final bool display;
  const MFrac(this.num, this.den, {this.binom = false, this.display = false});
}

/// 上标 / 下标（可只有其一）。
class MScript extends MNode {
  final MNode base;
  final MNode? sub;
  final MNode? sup;
  const MScript(this.base, {this.sub, this.sup});
}

/// 根式；index 非空为 n 次根。
class MSqrt extends MNode {
  final MNode body;
  final MNode? index;
  const MSqrt(this.body, {this.index});
}

/// 大算符（∫ ∑ ∏ ⋃ …）带上下限。
class MBigOp extends MNode {
  final String op;

  /// true → 上下限排在正上/正下（∑ ∏ lim）；false → 排在右侧角标（∫）
  final bool limits;
  final MNode? sub;
  final MNode? sup;
  const MBigOp(this.op, {this.limits = true, this.sub, this.sup});
}

/// \left( ... \right) —— 定界符按内容高度自适应。
class MDelim extends MNode {
  final String left;
  final String right;
  final MNode body;
  const MDelim(this.left, this.right, this.body);
}

/// \boxed{...}
class MBoxed extends MNode {
  final MNode body;
  const MBoxed(this.body);
}

/// \text{...} / \mathrm{...} / \mathbf{...} 等文本模式节点。
class MTextRun extends MNode {
  final String text;
  final bool bold;
  final bool italic;
  const MTextRun(this.text, {this.bold = false, this.italic = false});
}

/// 水平间距（em 为单位）。
class MSpace extends MNode {
  final double em;
  const MSpace(this.em);
}

/// 重音（\hat \bar \vec \dot \tilde \widehat …）。
class MAccent extends MNode {
  /// 重音字形
  final String accent;
  final MNode base;
  const MAccent(this.accent, this.base);
}

/// 上/下加横线或括号（\overline \underline \overbrace \underbrace \over/under）。
class MOverUnder extends MNode {
  final MNode base;
  final MNode? over;
  final MNode? under;

  /// 'line' | 'brace' | 'arrow' | 'none' —— 上/下划线样式
  final String overStyle;
  final String underStyle;
  const MOverUnder(this.base, {this.over, this.under, this.overStyle = 'none', this.underStyle = 'none'});
}

/// 矩阵 / cases / aligned 等环境。
class MMatrix extends MNode {
  final List<List<MNode>> rows;
  final String env;
  const MMatrix(this.rows, this.env);

  /// 环境的自带定界符：pmatrix→( )，bmatrix→[ ]，vmatrix→| |，cases→{ ␣
  (String, String)? get delims => switch (env) {
        'pmatrix' => ('(', ')'),
        'bmatrix' => ('[', ']'),
        'Bmatrix' => ('{', '}'),
        'vmatrix' => ('|', '|'),
        'Vmatrix' => ('‖', '‖'),
        'cases' => ('{', ''),
        _ => null,
      };

  bool get isCases => env == 'cases';
}

/// 显式换行（矩阵/cases 内 \\ 也被 MMatrix 吃掉；此节点用于 \newline 之类）。
class MLineBreak extends MNode {
  const MLineBreak();
}

// ══════════════════════════════════════════════════════════════════
// 符号表
// ══════════════════════════════════════════════════════════════════

/// 希腊字母（小写 + 大写 + 变体）。
const Map<String, String> _greek = {
  'alpha': 'α', 'beta': 'β', 'gamma': 'γ', 'delta': 'δ', 'epsilon': 'ϵ',
  'varepsilon': 'ε', 'zeta': 'ζ', 'eta': 'η', 'theta': 'θ', 'vartheta': 'ϑ',
  'iota': 'ι', 'kappa': 'κ', 'lambda': 'λ', 'mu': 'μ', 'nu': 'ν', 'xi': 'ξ',
  'omicron': 'ο', 'pi': 'π', 'varpi': 'ϖ', 'rho': 'ρ', 'varrho': 'ϱ',
  'sigma': 'σ', 'varsigma': 'ς', 'tau': 'τ', 'upsilon': 'υ', 'phi': 'ϕ',
  'varphi': 'φ', 'chi': 'χ', 'psi': 'ψ', 'omega': 'ω',
  'Gamma': 'Γ', 'Delta': 'Δ', 'Theta': 'Θ', 'Lambda': 'Λ', 'Xi': 'Ξ',
  'Pi': 'Π', 'Sigma': 'Σ', 'Upsilon': 'Υ', 'Phi': 'Φ', 'Psi': 'Ψ',
  'Omega': 'Ω',
};

/// 函数名（罗马体，前后按普通间距处理）。
const Set<String> _funcNames = {
  'sin', 'cos', 'tan', 'cot', 'sec', 'csc', 'arcsin', 'arccos', 'arctan',
  'sinh', 'cosh', 'tanh', 'coth', 'ln', 'log', 'lg', 'exp', 'lim', 'limsup',
  'liminf', 'max', 'min', 'sup', 'inf', 'det', 'dim', 'ker', 'deg', 'gcd',
  'hom', 'arg', 'Pr', 'mod',
};

/// 大算符：值为 (字形, 上下限是否排正上正下)。
const Map<String, (String, bool)> _bigOps = {
  'int': ('∫', false), 'iint': ('∬', false), 'iiint': ('∭', false),
  'oint': ('∮', false), 'sum': ('∑', true), 'prod': ('∏', true),
  'coprod': ('∐', true), 'bigcup': ('⋃', true), 'bigcap': ('⋂', true),
  'bigvee': ('⋁', true), 'bigwedge': ('⋀', true), 'bigoplus': ('⨁', true),
  'bigotimes': ('⨂', true), 'bigodot': ('⨀', true), 'bigsqcup': ('⨆', true),
};

/// 关系符 / 二元算符 / 箭头 / 杂项符号 → (字形, 类别)
const Map<String, (String, MKind)> _symbols = {
  // 二元算符
  'pm': ('±', MKind.bin), 'mp': ('∓', MKind.bin), 'times': ('×', MKind.bin),
  'div': ('÷', MKind.bin), 'cdot': ('⋅', MKind.bin), 'ast': ('∗', MKind.bin),
  'star': ('⋆', MKind.bin), 'circ': ('∘', MKind.bin), 'bullet': ('∙', MKind.bin),
  'cap': ('∩', MKind.bin), 'cup': ('∪', MKind.bin), 'setminus': ('∖', MKind.bin),
  'oplus': ('⊕', MKind.bin), 'otimes': ('⊗', MKind.bin), 'odot': ('⊙', MKind.bin),
  'wedge': ('∧', MKind.bin), 'vee': ('∨', MKind.bin), 'land': ('∧', MKind.bin),
  'lor': ('∨', MKind.bin),
  // 关系符
  'le': ('≤', MKind.rel), 'leq': ('≤', MKind.rel), 'ge': ('≥', MKind.rel),
  'geq': ('≥', MKind.rel), 'ne': ('≠', MKind.rel), 'neq': ('≠', MKind.rel),
  'equiv': ('≡', MKind.rel), 'approx': ('≈', MKind.rel), 'sim': ('∼', MKind.rel),
  'simeq': ('≃', MKind.rel), 'cong': ('≅', MKind.rel), 'propto': ('∝', MKind.rel),
  'll': ('≪', MKind.rel), 'gg': ('≫', MKind.rel), 'subset': ('⊂', MKind.rel),
  'supset': ('⊃', MKind.rel), 'subseteq': ('⊆', MKind.rel), 'supseteq': ('⊇', MKind.rel),
  'in': ('∈', MKind.rel), 'ni': ('∋', MKind.rel), 'notin': ('∉', MKind.rel),
  'perp': ('⊥', MKind.rel), 'parallel': ('∥', MKind.rel), 'mid': ('∣', MKind.rel),
  'prec': ('≺', MKind.rel), 'succ': ('≻', MKind.rel),
  // 箭头
  'to': ('→', MKind.rel), 'rightarrow': ('→', MKind.rel), 'leftarrow': ('←', MKind.rel),
  'leftrightarrow': ('↔', MKind.rel), 'Rightarrow': ('⇒', MKind.rel),
  'Leftarrow': ('⇐', MKind.rel), 'Leftrightarrow': ('⇔', MKind.rel),
  'mapsto': ('↦', MKind.rel), 'longrightarrow': ('⟶', MKind.rel),
  'uparrow': ('↑', MKind.rel), 'downarrow': ('↓', MKind.rel),
  // 杂项
  'infty': ('∞', MKind.symbol), 'partial': ('∂', MKind.symbol),
  'nabla': ('∇', MKind.symbol), 'forall': ('∀', MKind.symbol),
  'exists': ('∃', MKind.symbol), 'nexists': ('∄', MKind.symbol),
  'emptyset': ('∅', MKind.symbol), 'varnothing': ('∅', MKind.symbol),
  'neg': ('¬', MKind.symbol), 'lnot': ('¬', MKind.symbol),
  'angle': ('∠', MKind.symbol), 'triangle': ('△', MKind.symbol),
  'square': ('□', MKind.symbol), 'degree': ('°', MKind.symbol),
  'prime': ('′', MKind.symbol), 'ldots': ('…', MKind.symbol),
  'cdots': ('⋯', MKind.symbol), 'vdots': ('⋮', MKind.symbol), 'ddots': ('⋱', MKind.symbol),
  'aleph': ('ℵ', MKind.symbol), 'hbar': ('ℏ', MKind.symbol), 'ell': ('ℓ', MKind.symbol),
  'Re': ('ℜ', MKind.symbol), 'Im': ('ℑ', MKind.symbol), 'wp': ('℘', MKind.symbol),
  'surd': ('√', MKind.symbol), 'checkmark': ('✓', MKind.symbol),
  'clubsuit': ('♣', MKind.symbol), 'diamondsuit': ('♢', MKind.symbol),
  'heartsuit': ('♡', MKind.symbol), 'spadesuit': ('♠', MKind.symbol),
  'top': ('⊤', MKind.symbol), 'bot': ('⊥', MKind.symbol),
  'models': ('⊨', MKind.rel), 'vdash': ('⊢', MKind.rel), 'dashv': ('⊣', MKind.rel),
  'because': ('∵', MKind.symbol), 'therefore': ('∴', MKind.symbol),
  'colon': (':', MKind.punct),
};

/// 定界符命令 → 字形。
const Map<String, String> _delimNames = {
  'lparen': '(', 'rparen': ')', 'lbrack': '[', 'rbrack': ']',
  'lbrace': '{', 'rbrace': '}', 'lvert': '|', 'rvert': '|',
  'lVert': '‖', 'rVert': '‖', 'vert': '|', 'Vert': '‖',
  'langle': '⟨', 'rangle': '⟩', 'lfloor': '⌊', 'rfloor': '⌋',
  'lceil': '⌈', 'rceil': '⌉', 'backslash': '\\', 'uparrow': '↑',
  'downarrow': '↓', 'updownarrow': '↕', 'lgroup': '⟮', 'rgroup': '⟯',
  // 常见别名
  'lt': '<', 'gt': '>', 'mid': '∣', 'parallel': '∥', 'surd': '√',
};

/// 间距命令 → em。
const Map<String, double> _spaces = {
  ',': 3 / 18, ':': 4 / 18, ';': 5 / 18, '!': -3 / 18,
  'quad': 1.0, 'qquad': 2.0, 'enspace': 0.5, 'thinspace': 3 / 18,
  'medspace': 4 / 18, 'thickspace': 5 / 18, 'negthinspace': -3 / 18,
  ' ': 1 / 3,
};

/// 重音命令 → 字形。
const Map<String, String> _accents = {
  'hat': '^', 'widehat': '^', 'check': 'ˇ', 'tilde': '~', 'widetilde': '~',
  'acute': '´', 'grave': '`', 'dot': '˙', 'ddot': '¨', 'breve': '˘',
  'bar': '¯', 'vec': '→', 'mathring': '˚',
};

/// 被识别但直接忽略的排版命令（不产生节点）。
const Set<String> _ignored = {
  'displaystyle', 'textstyle', 'scriptstyle', 'scriptscriptstyle',
  'limits', 'nolimits', 'big', 'Big', 'bigg', 'Bigg', 'bigl', 'bigr',
  'Bigl', 'Bigr', 'biggl', 'biggr', 'Biggl', 'Biggr', 'left.', 'right.',
  'mathstrut', 'strut', 'phantom', 'hphantom', 'vphantom', 'allowbreak',
  'nobreak', 'relax', 'nonumber', 'notag', 'label', 'tag', 'qquad',
};

/// 矩阵类环境名（识别用）。
const Set<String> _matrixEnvs = {
  'matrix', 'pmatrix', 'bmatrix', 'Bmatrix', 'vmatrix', 'Vmatrix',
  'cases', 'array', 'aligned', 'align', 'gathered', 'gather', 'split', 'smallmatrix',
};

// ══════════════════════════════════════════════════════════════════
// 词法
// ══════════════════════════════════════════════════════════════════

enum _T { cmd, chr, lbrace, rbrace, sup, sub, amp, rowBreak, lbrack, rbrack, eof }

class _Tok {
  final _T t;

  /// cmd → 命令名（不含反斜杠）；chr → 单个字符
  final String v;
  final int pos;
  const _Tok(this.t, this.v, this.pos);
}

/// TeX 词法器。TeX 规则：命令为 `\` + 连续字母，或 `\` + 单个非字母字符。
List<_Tok> _lex(String s) {
  final out = <_Tok>[];
  var i = 0;
  while (i < s.length) {
    final c = s[i];
    if (c == '\\') {
      final start = i;
      i++;
      if (i >= s.length) {
        out.add(_Tok(_T.cmd, '', start));
        break;
      }
      final n = s[i];
      if (_isLetter(n)) {
        final b = StringBuffer();
        while (i < s.length && _isLetter(s[i])) {
          b.write(s[i]);
          i++;
        }
        out.add(_Tok(_T.cmd, b.toString(), start));
      } else {
        // \, \; \{ \} \\ 等单字符命令
        out.add(_Tok(_T.cmd, n, start));
        i++;
      }
      continue;
    }
    switch (c) {
      case '{':
        out.add(_Tok(_T.lbrace, c, i));
        i++;
        continue;
      case '}':
        out.add(_Tok(_T.rbrace, c, i));
        i++;
        continue;
      case '^':
        out.add(_Tok(_T.sup, c, i));
        i++;
        continue;
      case '_':
        out.add(_Tok(_T.sub, c, i));
        i++;
        continue;
      case '&':
        out.add(_Tok(_T.amp, c, i));
        i++;
        continue;
      case '[':
        out.add(_Tok(_T.lbrack, c, i));
        i++;
        continue;
      case ']':
        out.add(_Tok(_T.rbrack, c, i));
        i++;
        continue;
      case '~':
        // 不断行空格
        out.add(_Tok(_T.cmd, ' ', i));
        i++;
        continue;
      default:
        out.add(_Tok(_T.chr, c, i));
        i++;
        continue;
    }
  }
  out.add(_Tok(_T.eof, '', s.length));
  return out;
}

bool _isLetter(String c) {
  final u = c.codeUnitAt(0);
  return (u >= 0x41 && u <= 0x5A) || (u >= 0x61 && u <= 0x7A);
}

bool _isDigit(String c) {
  final u = c.codeUnitAt(0);
  return u >= 0x30 && u <= 0x39;
}

// ══════════════════════════════════════════════════════════════════
// 语法分析
// ══════════════════════════════════════════════════════════════════

class _Parser {
  final List<_Tok> toks;
  int i = 0;
  _Parser(this.toks);

  _Tok get cur => toks[i];
  _Tok peek([int n = 1]) => toks[math.min(i + n, toks.length - 1)];
  void advance() {
    if (i < toks.length - 1) i++;
  }

  /// 解析到 [stop] 为止的节点序列。
  /// stop 判定：rbrace（组结束）/ eof / amp / rowBreak / 指定命令名（如 right、end）
  MRow parseList({Set<String> stopCmds = const {}}) {
    final items = <MNode>[];
    while (true) {
      final t = cur;
      if (t.t == _T.eof || t.t == _T.rbrace || t.t == _T.amp || t.t == _T.rowBreak) break;
      if (t.t == _T.cmd && stopCmds.contains(t.v)) break;
      if (t.t == _T.rbrack) break;
      final node = parseAtom();
      if (node != null) {
        // 上下标：一次原子后最多一组 ^ 与 _（顺序任意）
        if (cur.t == _T.sup || cur.t == _T.sub) {
          items.add(_attachScripts(node));
        } else {
          items.add(node);
        }
      } else {
        // parseAtom 已推进（忽略类命令）
        continue;
      }
    }
    return MRow(items);
  }

  /// 把紧随其后的 ^ / _ 挂到 [base] 上（支持 ^{\prime} 之类）。
  MNode _attachScripts(MNode base) {
    MNode? sup;
    MNode? sub;
    var guard = 0;
    while ((cur.t == _T.sup || cur.t == _T.sub) && guard < 4) {
      guard++;
      final isSup = cur.t == _T.sup;
      advance();
      final arg = parseScriptArg();
      if (isSup) {
        sup = sup == null ? arg : MRow([sup, arg]);
      } else {
        sub = sub == null ? arg : MRow([sub, arg]);
      }
    }
    return MScript(base, sup: sup, sub: sub);
  }

  /// 上下标的实参：可以是 {组} 或单个原子。
  MNode parseScriptArg() {
    if (cur.t == _T.lbrace) {
      advance();
      final r = parseList();
      if (cur.t == _T.rbrace) advance();
      return _flatten(r);
    }
    return parseAtom() ?? MRow.empty;
  }

  /// 必填组参数（\frac 的分母等）：{...}；缺失时返回空行。
  MNode parseGroup() {
    if (cur.t == _T.lbrace) {
      advance();
      final r = parseList();
      if (cur.t == _T.rbrace) advance();
      return _flatten(r);
    }
    // 容错：\frac12 这类简写按单原子处理
    return parseAtom() ?? MRow.empty;
  }

  /// 可选 [ ... ] 参数；不存在返回 null。
  MNode? parseOptionalGroup() {
    if (cur.t != _T.lbrack) return null;
    advance();
    final r = parseList();
    if (cur.t == _T.rbrack) advance();
    return _flatten(r);
  }

  /// 读取花括号内**原文**（\text{} 需要保留空格与汉字）。
  String? parseRawGroup() {
    if (cur.t != _T.lbrace) return null;
    advance();
    final b = StringBuffer();
    var depth = 1;
    while (cur.t != _T.eof) {
      if (cur.t == _T.lbrace) depth++;
      if (cur.t == _T.rbrace) {
        depth--;
        if (depth == 0) {
          advance();
          break;
        }
      }
      b.write(_tokSource(cur));
      advance();
    }
    return b.toString();
  }

  static String _tokSource(_Tok t) => switch (t.t) {
        _T.cmd => t.v.length == 1 && !_isLetter(t.v) ? t.v : '\\${t.v}',
        _T.chr => t.v,
        _T.lbrace => '{',
        _T.rbrace => '}',
        _T.sup => '^',
        _T.sub => '_',
        _T.amp => '&',
        _T.rowBreak => '\\\\',
        _T.lbrack => '[',
        _T.rbrack => ']',
        _T.eof => '',
      };

  /// 解析一个原子；返回 null 表示「已消费但无产物」（忽略类命令）。
  MNode? parseAtom() {
    final t = cur;
    switch (t.t) {
      case _T.lbrace:
        advance();
        final r = parseList();
        if (cur.t == _T.rbrace) advance();
        return _flatten(r);

      case _T.chr:
        advance();
        return _charAtom(t.v);

      case _T.cmd:
        return _cmdAtom(t.v);

      case _T.lbrack:
      case _T.rbrack:
        advance();
        return MAtom(t.v, MKind.delim);

      case _T.sup:
      case _T.sub:
        // 裸上下标（无基底）：按空基底处理，仍显示角标
        advance();
        return parseScriptArg();

      case _T.amp:
        advance();
        return null;

      case _T.rowBreak:
        advance();
        return const MLineBreak();

      case _T.rbrace:
      case _T.eof:
        if (t.t == _T.eof) return null;
        advance();
        return null;
    }
  }

  MNode _charAtom(String c) {
    if (_isDigit(c)) return MAtom(c, MKind.number);
    if (_isLetter(c)) return MAtom(c, MKind.ident);
    // 拉丁字母以外的字符（汉字等）在数学模式下按罗马体显示
    switch (c) {
      case '+':
        return const MAtom('+', MKind.bin);
      case '-':
      case '−':
        return const MAtom('−', MKind.bin);
      case '*':
        return const MAtom('∗', MKind.bin);
      case '/':
        return const MAtom('/', MKind.bin);
      case '=':
        return const MAtom('=', MKind.rel);
      case '<':
        return const MAtom('<', MKind.rel);
      case '>':
        return const MAtom('>', MKind.rel);
      case ',':
      case ';':
        return MAtom(c, MKind.punct);
      case ':':
        return const MAtom(':', MKind.rel);
      case '(':
      case ')':
      case '[':
      case ']':
      case '|':
        return MAtom(c, MKind.delim);
      case '.':
        return const MAtom('.', MKind.punct);
      case '!':
        return const MAtom('!', MKind.punct);
      case '?':
        return const MAtom('?', MKind.punct);
      case "'":
        return const MAtom('′', MKind.symbol);
      case ' ':
        return const MSpace(1 / 3);
      default:
        return MAtom(c, MKind.symbol);
    }
  }

  MNode? _cmdAtom(String name) {
    // 间距命令
    final sp = _spaces[name];
    if (sp != null) {
      advance();
      return MSpace(sp);
    }
    // 忽略类
    if (_ignored.contains(name)) {
      advance();
      return null;
    }
    // 定界符命令
    final dm = _delimNames[name];
    if (dm != null) {
      advance();
      return MAtom(dm, MKind.delim);
    }
    // 大算符
    final big = _bigOps[name];
    if (big != null) {
      advance();
      final (glyph, limits) = big;
      // 上下限：紧跟的 _ / ^
      MNode? sub;
      MNode? sup;
      var guard = 0;
      while ((cur.t == _T.sub || cur.t == _T.sup) && guard < 4) {
        guard++;
        final isSub = cur.t == _T.sub;
        advance();
        final arg = parseScriptArg();
        if (isSub) {
          sub = sub == null ? arg : MRow([sub, arg]);
        } else {
          sup = sup == null ? arg : MRow([sup, arg]);
        }
      }
      // \limits / \nolimits 显式覆盖
      var useLimits = limits;
      if (cur.t == _T.cmd && cur.v == 'limits') {
        useLimits = true;
        advance();
      } else if (cur.t == _T.cmd && cur.v == 'nolimits') {
        useLimits = false;
        advance();
      }
      return MBigOp(glyph, limits: useLimits, sub: sub, sup: sup);
    }
    // 函数名 / lim
    if (_funcNames.contains(name)) {
      advance();
      if (name == 'lim') {
        // lim 的上下限排正下
        MNode? sub;
        MNode? sup;
        var guard = 0;
        while ((cur.t == _T.sub || cur.t == _T.sup) && guard < 4) {
          guard++;
          final isSub = cur.t == _T.sub;
          advance();
          final arg = parseScriptArg();
          if (isSub) {
            sub = arg;
          } else {
            sup = arg;
          }
        }
        if (sub != null || sup != null) {
          return MBigOp('lim', limits: true, sub: sub, sup: sup);
        }
      }
      return MAtom(name, MKind.func);
    }
    // 希腊字母
    final g = _greek[name];
    if (g != null) {
      advance();
      return MAtom(g, MKind.ident);
    }
    // 符号表
    final sym = _symbols[name];
    if (sym != null) {
      advance();
      final (glyph, kind) = sym;
      return MAtom(glyph, kind);
    }
    // 重音
    final acc = _accents[name];
    if (acc != null) {
      advance();
      // \vec 等需要实参
      final arg = (cur.t == _T.lbrace) ? parseGroup() : (parseAtom() ?? MRow.empty);
      return MAccent(acc, arg);
    }
    // 结构化命令
    switch (name) {
      case 'frac':
      case 'dfrac':
      case 'tfrac':
      case 'cfrac':
        advance();
        final a = parseGroup();
        final b = parseGroup();
        return MFrac(a, b, display: name == 'dfrac');

      case 'binom':
      case 'dbinom':
      case 'tbinom':
        advance();
        final a = parseGroup();
        final b = parseGroup();
        return MFrac(a, b, binom: true);

      case 'sqrt':
        advance();
        final idx = parseOptionalGroup();
        final body = parseGroup();
        return MSqrt(body, index: idx);

      case 'boxed':
      case 'fbox':
        advance();
        return MBoxed(parseGroup());

      case 'text':
      case 'textrm':
      case 'textnormal':
      case 'mbox':
        advance();
        final raw = parseRawGroup();
        return MTextRun(raw ?? '');

      case 'mathrm':
      case 'mathup':
      case 'mathsf':
      case 'mathtt':
      case 'operatorname':
        advance();
        final raw = parseRawGroup();
        return MTextRun(raw ?? '');

      case 'mathbf':
      case 'bm':
      case 'boldsymbol':
      case 'symbf':
        advance();
        final raw = parseRawGroup();
        return MTextRun(raw ?? '', bold: true);

      case 'mathit':
      case 'mathnormal':
        advance();
        final raw = parseRawGroup();
        return MTextRun(raw ?? '', italic: true);

      case 'mathbb':
      case 'mathcal':
      case 'mathfrak':
      case 'mathscr':
        advance();
        // 黑板体/花体字形不全，按普通罗马体显示，内容不丢
        final raw = parseRawGroup();
        return MTextRun(raw ?? '');

      case 'left':
        advance();
        return _parseLeftRight();

      case 'right':
        // 落单的 \right：忽略
        advance();
        return null;

      case 'begin':
        advance();
        return _parseEnvironment();

      case 'end':
        advance();
        // 未配对的 \end{...}：吃掉环境名
        if (cur.t == _T.lbrace) parseRawGroup();
        return null;

      case 'overline':
        advance();
        return MOverUnder(parseGroup(), overStyle: 'line');

      case 'underline':
        advance();
        return MOverUnder(parseGroup(), underStyle: 'line');

      case 'overbrace':
        advance();
        final b = parseGroup();
        MNode? sup;
        if (cur.t == _T.sup) {
          advance();
          sup = parseScriptArg();
        }
        return MOverUnder(b, over: sup, overStyle: 'brace');

      case 'underbrace':
        advance();
        final b = parseGroup();
        MNode? sub;
        if (cur.t == _T.sub) {
          advance();
          sub = parseScriptArg();
        }
        return MOverUnder(b, under: sub, underStyle: 'brace');

      case 'overset':
        advance();
        final over = parseGroup();
        final base = parseGroup();
        return MOverUnder(base, over: over);

      case 'underset':
        advance();
        final under = parseGroup();
        final base = parseGroup();
        return MOverUnder(base, under: under);

      case 'stackrel':
        advance();
        final over = parseGroup();
        final base = parseGroup();
        return MOverUnder(base, over: over);

      case 'pmod':
        advance();
        return MRow([const MSpace(0.5), const MAtom('(', MKind.delim), const MTextRun('mod'), const MSpace(0.3), parseGroup(), const MAtom(')', MKind.delim)]);

      case 'quad':
        advance();
        return const MSpace(1.0);

      case 'qquad':
        advance();
        return const MSpace(2.0);

      case '\\':
        advance();
        return const MLineBreak();

      case '{':
        advance();
        return const MAtom('{', MKind.delim);

      case '}':
        advance();
        return const MAtom('}', MKind.delim);

      case '%':
      case '#':
      case '&':
      case '_':
      case r'$':
        advance();
        return MAtom(name, MKind.symbol);
    }

    // 未知命令：降级为罗马体文本（保留内容，绝不丢）
    advance();
    return MTextRun(name);
  }

  /// \left X ... \right Y
  MNode _parseLeftRight() {
    // 左定界符
    final left = _readDelim();
    final body = parseList(stopCmds: const {'right'});
    var right = '';
    if (cur.t == _T.cmd && cur.v == 'right') {
      advance();
      right = _readDelim();
    }
    return MDelim(left, right, _flatten(body));
  }

  /// 读一个定界符（命令名 / 单字符）。
  String _readDelim() {
    final t = cur;
    if (t.t == _T.cmd) {
      advance();
      if (t.v == '.' || t.v.isEmpty) return ''; // \left. 无定界符
      return _delimNames[t.v] ?? _symbols[t.v]?.$1 ?? t.v;
    }
    if (t.t == _T.lbrace) {
      advance();
      final r = parseList();
      if (cur.t == _T.rbrace) advance();
      return _plainOf(r);
    }
    if (t.t == _T.chr) {
      advance();
      return t.v;
    }
    if (t.t == _T.lbrack) {
      advance();
      return '[';
    }
    if (t.t == _T.rbrack) {
      advance();
      return ']';
    }
    if (t.t == _T.eof) return '';
    advance();
    return '';
  }

  /// \begin{env} ... \end{env}
  MNode _parseEnvironment() {
    final env = (parseRawGroup() ?? '').trim();
    // array 的列格式参数：{c|c} 之类，读掉
    if (env == 'array' && cur.t == _T.lbrace) parseRawGroup();

    if (_matrixEnvs.contains(env)) {
      final rows = <List<MNode>>[];
      var row = <MNode>[];
      while (true) {
        if (cur.t == _T.eof) break;
        if (cur.t == _T.cmd && cur.v == 'end') {
          advance();
          // 吃掉 \end{env}
          if (cur.t == _T.lbrace) parseRawGroup();
          break;
        }
        if (cur.t == _T.amp) {
          advance();
          row.add(MRow.empty);
          continue;
        }
        if (cur.t == _T.rowBreak) {
          advance();
          rows.add(row);
          row = <MNode>[];
          continue;
        }
        final n = parseAtom();
        if (n == null) continue;
        if (cur.t == _T.sup || cur.t == _T.sub) {
          row.add(_attachScripts(n));
        } else {
          row.add(n);
        }
      }
      if (row.isNotEmpty) rows.add(row);
      // cases 每行左侧自带 "{"，用 MMatrix 的 delims 处理
      return MMatrix(rows, env);
    }

    // 非矩阵环境：按普通内容读到 \end
    final body = parseList(stopCmds: const {'end'});
    if (cur.t == _T.cmd && cur.v == 'end') {
      advance();
      if (cur.t == _T.lbrace) parseRawGroup();
    }
    return body;
  }

  static String _plainOf(MNode n) {
    final b = StringBuffer();
    void walk(MNode x) {
      switch (x) {
        case MAtom(:final text):
          b.write(text);
        case MTextRun(:final text):
          b.write(text);
        case MRow(:final items):
          for (final c in items) {
            walk(c);
          }
        case MScript(:final base):
          walk(base);
        default:
          break;
      }
    }

    walk(n);
    return b.toString();
  }
}

/// 单节点行展开为节点本身；多节点保持 MRow。
MNode _flatten(MRow r) => r.items.length == 1 ? r.items.first : r;

// ══════════════════════════════════════════════════════════════════
// 公开入口
// ══════════════════════════════════════════════════════════════════

/// TeX 源码 → AST。永不抛异常（任何异常都降级为纯文本行）。
MNode parseTex(String src) {
  try {
    final body = _stripDelimiters(src);
    final toks = _lex(body);
    final p = _Parser(toks);
    final row = p.parseList();
    return _flatten(row);
  } catch (_) {
    return MTextRun(src);
  }
}

/// 去掉最外层的 $ / $$ / \[ \] / \( \) / 显式标记 /"…"/
String _stripDelimiters(String s) {
  var t = s.trim();
  while (true) {
    // 显式公式标记：/"…"/ 或 ／“…”／
    if (t.length >= 4 &&
        _isSlash(t[0]) &&
        _isOpenQuote(t[1]) &&
        _isCloseQuote(t[t.length - 2]) &&
        _isSlash(t[t.length - 1])) {
      t = t.substring(2, t.length - 2).trim();
      continue;
    }
    if (t.length >= 4 && t.startsWith(r'$$') && t.endsWith(r'$$')) {
      t = t.substring(2, t.length - 2).trim();
      continue;
    }
    if (t.length >= 4 && t.startsWith(r'\[') && t.endsWith(r'\]')) {
      t = t.substring(2, t.length - 2).trim();
      continue;
    }
    if (t.length >= 4 && t.startsWith(r'\(') && t.endsWith(r'\)')) {
      t = t.substring(2, t.length - 2).trim();
      continue;
    }
    if (t.length >= 2 && t.startsWith(r'$') && t.endsWith(r'$') && !t.substring(1, t.length - 1).contains(r'$')) {
      t = t.substring(1, t.length - 1).trim();
      continue;
    }
    break;
  }
  return t;
}

/// AST → 纯文本（复制/搜索/无障碍用；不含排版信息）。
String mathToPlain(MNode n) {
  final b = StringBuffer();
  void walk(MNode x) {
    switch (x) {
      case MAtom(:final text):
        b.write(text);
      case MTextRun(:final text):
        b.write(text);
      case MRow(:final items):
        for (final c in items) {
          walk(c);
        }
      case MFrac(:final num, :final den):
        if (x.binom) {
          b.write('(');
          walk(num);
          b.write(' ');
          walk(den);
          b.write(')');
        } else {
          walk(num);
          b.write('/');
          walk(den);
        }
      case MScript(:final base, :final sub, :final sup):
        walk(base);
        if (sub != null) {
          b.write('_');
          walk(sub);
        }
        if (sup != null) {
          b.write('^');
          walk(sup);
        }
      case MSqrt(:final body, :final index):
        b.write('√');
        if (index != null) {
          b.write('[');
          walk(index);
          b.write(']');
        }
        b.write('(');
        walk(body);
        b.write(')');
      case MBigOp(:final op, :final sub, :final sup):
        b.write(op);
        if (sub != null) {
          b.write('_');
          walk(sub);
        }
        if (sup != null) {
          b.write('^');
          walk(sup);
        }
      case MDelim(:final left, :final right, :final body):
        b.write(left);
        walk(body);
        b.write(right);
      case MBoxed(:final body):
        b.write('[');
        walk(body);
        b.write(']');
      case MSpace():
        b.write(' ');
      case MAccent(:final accent, :final base):
        walk(base);
        b.write(accent);
      case MOverUnder(:final base, :final over, :final under):
        if (over != null) {
          walk(over);
          b.write(' ');
        }
        walk(base);
        if (under != null) {
          b.write(' ');
          walk(under);
        }
      case MMatrix(:final rows):
        for (var r = 0; r < rows.length; r++) {
          if (r > 0) b.write('; ');
          for (var c = 0; c < rows[r].length; c++) {
            if (c > 0) b.write(', ');
            walk(rows[r][c]);
          }
        }
      case MLineBreak():
        b.write('\n');
    }
  }

  walk(n);
  return b.toString();
}

// ══════════════════════════════════════════════════════════════════
// 正文中的公式探测
// ══════════════════════════════════════════════════════════════════

/// 正文里发现的一段数学。
class MathSegment {
  /// 在原文中的起止下标（含定界符）
  final int start;
  final int end;

  /// 去掉定界符的 TeX 源码
  final String tex;

  /// 是否为独立成行的显示式
  final bool display;
  const MathSegment(this.start, this.end, this.tex, this.display);
}

/// 在正文中扫描数学片段。
///
/// 识别顺序（**优先级从高到低**，先命中的先切走）：
///  1. `/"…"/`  —— 显式公式标记（本项目的推荐写法，见 docs/formula-markup.md）
///  2. `$$…$$`  —— 显示式
///  3. `\[…\]`  —— 显示式
///  4. `\(…\)`  —— 行内
///  5. `$…$`    —— 行内（带误报防护）
///
/// 显式标记排最前：它是作者主动写的意图，任何情况下都优先于启发式判断。
/// 反引号代码与围栏代码块内的标记由**调用方**先切走（order：代码 > 公式），
/// 本函数只看收到的文本。
List<MathSegment> findMathSegments(String text) {
  final out = <MathSegment>[];
  var i = 0;
  final n = text.length;
  while (i < n) {
    final c = text[i];

    // ① 显式公式标记 /"…"/（含全角与弯引号容错）
    final marked = _findFormulaMarkup(text, i);
    if (marked != null) {
      out.add(marked);
      i = marked.end;
      continue;
    }

    // ② $$...$$ 显示式
    if (c == r'$' && i + 1 < n && text[i + 1] == r'$') {
      final close = text.indexOf(r'$$', i + 2);
      if (close > i) {
        final tex = text.substring(i + 2, close);
        if (tex.trim().isNotEmpty) {
          out.add(MathSegment(i, close + 2, tex.trim(), true));
          i = close + 2;
          continue;
        }
      }
      i += 2;
      continue;
    }

    // \[...\] 显示式
    if (c == '\\' && i + 1 < n && text[i + 1] == '[') {
      final close = text.indexOf(r'\]', i + 2);
      if (close > i) {
        final tex = text.substring(i + 2, close);
        if (tex.trim().isNotEmpty) {
          out.add(MathSegment(i, close + 2, tex.trim(), true));
          i = close + 2;
          continue;
        }
      }
      i += 2;
      continue;
    }

    // \(...\) 行内
    if (c == '\\' && i + 1 < n && text[i + 1] == '(') {
      final close = text.indexOf(r'\)', i + 2);
      if (close > i) {
        final tex = text.substring(i + 2, close);
        if (tex.trim().isNotEmpty) {
          out.add(MathSegment(i, close + 2, tex.trim(), false));
          i = close + 2;
          continue;
        }
      }
      i += 2;
      continue;
    }

    // $...$ 行内（带误报防护）
    if (c == r'$') {
      final close = _findInlineDollarClose(text, i);
      if (close > 0) {
        final tex = text.substring(i + 1, close);
        if (_looksLikeMath(tex)) {
          out.add(MathSegment(i, close + 1, tex.trim(), false));
          i = close + 1;
          continue;
        }
      }
      i++;
      continue;
    }

    i++;
  }
  return out;
}

// ══════════════════════════════════════════════════════════════════
// 显式公式标记 /"…"/
// ══════════════════════════════════════════════════════════════════
//
// 规范见 docs/formula-markup.md：一对一对方便中文输入法打出的定界符，
// 把中间内容「尝试转换为公式」（渲染 + 导出 Word 原生 OMML）。
//
//  开：`/` 或 `／`(U+FF0F)  紧跟  `"` 或 `“`(U+201C)
//  闭：`"` 或 `”`(U+201D)  紧跟  `/` 或 `／`
//
// 之所以同时容忍全角斜杠与弯引号：中文输入法下直接敲 `/` 与 `"` 常常得到
// 全角/弯引号，若不容错，用户「明明写对了」却渲染不出来——这是最容易劝退的坑。
//
// 形态判定：标记**独占一行**（前后只剩空白）→ 显示式；夹在正文中 → 行内式。
// 用同一个标记表达两种形态，作者不必记两套语法。

/// 斜杠（半角或全角）。
bool _isSlash(String c) => c == '/' || c == '\uFF0F';

/// 开引号（半角双引号或中文左双引号）。
bool _isOpenQuote(String c) => c == '"' || c == '\u201C' || c == '\u201D';

/// 闭引号（半角双引号或中文右双引号）。
bool _isCloseQuote(String c) => c == '"' || c == '\u201D' || c == '\u201C';

/// 标记内容允许跨行，但设上限：避免「漏写闭标记」时吞掉后面大半篇文章。
const int _kFormulaMarkupMaxSpan = 4000;

/// 从 [open] 处尝试解析一个显式公式标记；不是标记则返回 null。
MathSegment? _findFormulaMarkup(String text, int open) {
  final n = text.length;
  if (open + 1 >= n) return null;
  if (!_isSlash(text[open])) return null;
  if (!_isOpenQuote(text[open + 1])) return null;

  final limit = math.min(n, open + _kFormulaMarkupMaxSpan);
  var j = open + 2;
  while (j + 1 < limit) {
    final c = text[j];
    if (_isCloseQuote(c) && _isSlash(text[j + 1])) {
      final tex = text.substring(open + 2, j).trim();
      if (tex.isEmpty) return null;
      final end = j + 2;
      return MathSegment(open, end, tex, _isWholeLineAt(text, open, end));
    }
    j++;
  }
  return null;
}

/// [start, end) 这一段是否独占一行（前后只剩空白）→ 决定显示式 / 行内式。
bool _isWholeLineAt(String text, int start, int end) {
  var a = start - 1;
  while (a >= 0 && text[a] != '\n') {
    if (text[a].trim().isNotEmpty) return false;
    a--;
  }
  var b = end;
  while (b < text.length && text[b] != '\n') {
    if (text[b].trim().isNotEmpty) return false;
    b++;
  }
  return true;
}

/// 找行内 $ 的闭合位置；-1 表示没有合法闭合。
int _findInlineDollarClose(String text, int open) {
  final n = text.length;
  if (open + 1 >= n) return -1;
  if (text[open + 1].trim().isEmpty) return -1; // $ 后紧跟空白 → 不是公式
  var j = open + 1;
  while (j < n) {
    final c = text[j];
    if (c == '\n') return -1; // 不跨行
    if (c == '\\') {
      j += 2;
      continue;
    }
    if (c == r'$') {
      if (j == open + 1) return -1;
      if (text[j - 1].trim().isEmpty) return -1; // 闭合前有空白 → 不是公式
      return j;
    }
    j++;
  }
  return -1;
}

final _mathSignalRe = RegExp(r'[\\^_{}]|[=+\-*/<>≤≥≠±×÷∑∫√∞∂∇→←]');

/// 行内 $...$ 内容是否「像公式」。
bool _looksLikeMath(String tex) {
  final t = tex.trim();
  if (t.isEmpty) return false;
  if (_mathSignalRe.hasMatch(t)) return true;
  // 纯字母数字且很短：允许单变量 a、x1 这种；过长的自然语言排除
  if (t.length <= 4 && RegExp(r'^[A-Za-z][A-Za-z0-9]*$').hasMatch(t)) return true;
  return false;
}

/// 某一**整行**恰好就是一对公式标记 → 返回其中的 TeX 源码；否则 null。
///
/// 供块级解析器使用：整行标记按规范是**显示式**（独占一块、居中），
/// 不能退化成行内公式塞进段落里。
String? formulaMarkupWholeLine(String line) {
  final t = line.trim();
  if (t.length < 4) return null;
  final seg = _findFormulaMarkup(t, 0);
  if (seg == null) return null;
  if (seg.start != 0 || seg.end != t.length) return null;
  return seg.tex;
}

/// 正文里是否含数学片段（快速判断，入口处用于点亮「公式」标记）。
bool containsMath(String text) {
  if (!text.contains(r'$') && !text.contains(r'\(') && !text.contains(r'\[')) return false;
  return findMathSegments(text).isNotEmpty;
}
