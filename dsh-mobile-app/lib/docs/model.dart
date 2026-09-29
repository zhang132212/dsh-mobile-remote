// 文档阅读器统一模型（v3.2.0）——md / txt / docx / xlsx 都归一到这一套结构，
// 由 docs/viewer widgets 统一渲染，保证各格式「特色」在只读前提下尽量保留：
//   · md    → 标题/列表/引用/代码块/表格/链接/行内样式/公式
//   · txt   → 段落 + URL 自动识别
//   · docx  → 段落样式/对齐、标题、列表、表格、超链接、行内公式（OMML）
//   · xlsx  → 多工作表、行列、共享字符串、合并单元格、超链接、数字格式
//
// 设计约束（离线工具链）：不引入 markdown/docx 第三方包，docx/xlsx 走
// archive + xml 自行解包解析；xlsx 用已审计过的 `excel` 包。

// ══════════════════════════════════════════════════════════════════
// 块级
// ══════════════════════════════════════════════════════════════════

/// 文档块基类。
sealed class DocBlock {
  const DocBlock();
}

/// 标题（level 1-6；md 的 #，docx 的 Heading N）。
class DocHeading extends DocBlock {
  final int level;
  final List<DocInline> spans;
  const DocHeading(this.level, this.spans);
}

/// 普通段落。
class DocPara extends DocBlock {
  final List<DocInline> spans;

  /// 'left' | 'center' | 'right' | 'justify' | null（docx 段落对齐）
  final String? align;
  const DocPara(this.spans, {this.align});
}

/// 列表（有序/无序，支持一层嵌套项内的行内格式）。
class DocList extends DocBlock {
  final bool ordered;

  /// 每项的起始序号（md 有序列表可指定 "3." 起）；无序时忽略。
  final int start;
  final List<List<DocInline>> items;
  const DocList(this.items, {this.ordered = false, this.start = 1});
}

/// 代码块（md 围栏 / txt 不产出）。
class DocCode extends DocBlock {
  final String text;
  final String? lang;
  const DocCode(this.text, {this.lang});
}

/// 引用块。
class DocQuote extends DocBlock {
  final List<DocInline> spans;
  const DocQuote(this.spans);
}

/// 分隔线。
class DocRule extends DocBlock {
  const DocRule();
}

/// 表格。
class DocTable extends DocBlock {
  final List<List<DocCell>> rows;

  /// 首行是否为表头（md 语法决定；docx 保留原样为 false）。
  final bool headerRow;
  const DocTable(this.rows, {this.headerRow = false});
}

/// 块级公式（单独成行的 $$...$$ / \[...\]；docx 的 oMathPara）。
///
/// 统一以 **TeX 源码**为载体：md/docx 两条来源都归一成 TeX，
/// 渲染交给 flutter_math_fork（`math/view.dart`），导出 OMML 交给
/// `math/omml.dart` 的 AST 解析器——单一表示，两条路径不打架。
class DocMathBlock extends DocBlock {
  final String tex;

  /// 编号（若文档里有，如 "(1)"）。
  final String? tag;
  const DocMathBlock(this.tex, {this.tag});
}

/// 未知/兜底块：按纯文本段落渲染，保证「至少可读」。
class DocRaw extends DocBlock {
  final String text;
  const DocRaw(this.text);
}

// ══════════════════════════════════════════════════════════════════
// 行内
// ══════════════════════════════════════════════════════════════════

sealed class DocInline {
  const DocInline();
}

/// 文本片段 + 行内样式。
class DocText extends DocInline {
  final String text;
  final bool bold;
  final bool italic;
  final bool underline;
  final bool strike;

  /// 行内代码（等宽 + 底色）。
  final bool code;

  /// 上标/下标（docx 的 vertAlign）。
  final bool superscript;
  final bool subscript;

  /// 字号倍数（docx 的 sz 相对正文），null 表示默认。
  final double? sizeScale;

  /// 文本颜色（docx 的 w:color，如 'FF0000'）；null 表示跟随主题。
  final String? colorHex;

  const DocText(
    this.text, {
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.strike = false,
    this.code = false,
    this.superscript = false,
    this.subscript = false,
    this.sizeScale,
    this.colorHex,
  });

  /// 合并样式（docx run 继承：段落默认样式 ⊕ 自身）
  DocText merge({
    bool? bold,
    bool? italic,
    bool? underline,
    bool? strike,
    bool? code,
    bool? superscript,
    bool? subscript,
    double? sizeScale,
    String? colorHex,
  }) =>
      DocText(
        text,
        bold: bold ?? this.bold,
        italic: italic ?? this.italic,
        underline: underline ?? this.underline,
        strike: strike ?? this.strike,
        code: code ?? this.code,
        superscript: superscript ?? this.superscript,
        subscript: subscript ?? this.subscript,
        sizeScale: sizeScale ?? this.sizeScale,
        colorHex: colorHex ?? this.colorHex,
      );
}

/// 超链接。url 为 null 时（如内部锚点无法解析）按普通文本渲染。
class DocLink extends DocInline {
  final List<DocInline> spans;
  final String? url;
  const DocLink(this.spans, this.url);
}

/// 行内公式（TeX 源码）。
class DocMathInline extends DocInline {
  final String tex;
  const DocMathInline(this.tex);
}

/// 图片（docx 内嵌图 / md 图片语法）。url 可为 http(s) 或 data:。
class DocImage extends DocInline {
  final String? url;
  final String? alt;
  const DocImage(this.url, {this.alt});
}

/// 硬换行（docx 的 w:br，或 md 行尾两空格）。
class DocBreak extends DocInline {
  const DocBreak();
}

// ══════════════════════════════════════════════════════════════════
// 表格单元格
// ══════════════════════════════════════════════════════════════════

class DocCell {
  final List<DocInline> spans;

  /// 水平对齐：'left' | 'center' | 'right' | null
  final String? align;

  /// 是否为表头单元格（md 首行 / xlsx 无）
  final bool header;
  const DocCell(this.spans, {this.align, this.header = false});

  static const empty = DocCell([]);
}

// ══════════════════════════════════════════════════════════════════
// 电子表格（xlsx）
// ══════════════════════════════════════════════════════════════════

/// 一个工作表。
class Sheet {
  final String name;

  /// 行 → 单元格（稀疏：null 表示空单元格/被合并覆盖）。
  final List<List<SheetCell>> rows;

  /// 最大列数（用于补齐列头）
  final int maxCol;
  const Sheet(this.name, this.rows, this.maxCol);
}

/// 表内单元格。
class SheetCell {
  final String text;

  /// 超链接目标（xlsx 的 hyperlink 关系）
  final String? url;

  /// 是否为公式结果（渲染时给一个轻标记）
  final bool formula;
  const SheetCell(this.text, {this.url, this.formula = false});
}

/// 整个工作簿。
class Spreadsheet {
  final List<Sheet> sheets;
  final String? title;
  const Spreadsheet(this.sheets, {this.title});
}

// ══════════════════════════════════════════════════════════════════
// 阅读器统一产物
// ══════════════════════════════════════════════════════════════════

/// 文档格式。
enum DocFormat { markdown, text, docx, xlsx, unknown }

/// 从文件名/路径推断格式。
DocFormat detectFormat(String nameOrPath) {
  final lower = nameOrPath.toLowerCase();
  final dot = lower.lastIndexOf('.');
  final ext = dot >= 0 ? lower.substring(dot + 1) : '';
  switch (ext) {
    case 'md':
    case 'markdown':
    case 'mdown':
    case 'mkd':
      return DocFormat.markdown;
    case 'txt':
    case 'log':
    case 'text':
    case 'csv':
    case 'json':
    case 'yaml':
    case 'yml':
    case 'ini':
    case 'conf':
      return DocFormat.text;
    case 'docx':
    case 'docm':
      return DocFormat.docx;
    case 'xlsx':
    case 'xlsm':
      return DocFormat.xlsx;
    default:
      return DocFormat.unknown;
  }
}

/// 一个已解析、可渲染的文档。
class Document {
  final String title;
  final DocFormat format;
  final List<DocBlock> blocks;

  /// 电子表格专用（format == xlsx 时非空）
  final Spreadsheet? sheet;

  /// 解析过程中的告警（页面底部可提示「部分内容未完整渲染」）
  final List<String> warnings;
  const Document(this.title, this.format, this.blocks, {this.sheet, this.warnings = const []});
}

/// 该格式是否受支持（用于入口处判断「能否用本 App 打开」）。
bool isReadableFormat(String nameOrPath) => detectFormat(nameOrPath) != DocFormat.unknown;

/// 支持打开的扩展名（Android intent-filter 与文件过滤共用，保持单一事实来源）。
const List<String> kReadableExtensions = [
  'md', 'markdown', 'txt', 'text', 'log', 'csv', 'json', 'yaml', 'yml',
  'docx', 'xlsx',
];
