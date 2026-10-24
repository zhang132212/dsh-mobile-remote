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

  /// 文档内锚点 id（HTML 的 id / name 属性）；无则为 null。
  /// 阅读页用它响应当前文件内的 #hash 链接跳转。
  final String? anchor;
  const DocHeading(this.level, this.spans, {this.anchor});
}

/// 普通段落。
class DocPara extends DocBlock {
  final List<DocInline> spans;

  /// 'left' | 'center' | 'right' | 'justify' | null（docx 段落对齐）
  final String? align;

  /// 文档内锚点 id（HTML 的 id / name 属性）；无则为 null。
  final String? anchor;
  const DocPara(this.spans, {this.align, this.anchor});
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

/// 树形结构块（v3.2.8）。
///
/// 树是「数据结构」类文档的天然形态：源码摊平了要人肉数缩进，树能折叠、
/// 能一眼看清层级与属性。当前由 XML 家族产出（见 docs/xml.dart），
/// JSON / YAML 后续可复用同一块类型与渲染。
class DocTree extends DocBlock {
  /// 顶层节点（XML 的根元素、声明、注释可以并列，故是列表而非单根）。
  final List<TreeNode> roots;
  const DocTree(this.roots);
}

/// 树节点：名称 + 属性 + 文本 + 子节点。
class TreeNode {
  /// 元素名（含命名空间前缀，如 `w:p`）；`#comment` / `#declaration` 等为伪节点。
  final String name;

  /// 直接文本内容（已折空白）；无文本为 null。
  final String? text;

  /// 数据类型标签（v3.2.11）。
  ///
  /// XML 元素为 null；JSON 用 object / array / string / number / boolean / null
  /// 标注值类型，渲染时以浅色徽标显示——树里一眼能分清「键」和「值」。
  final String? kind;

  /// 属性（按文档出现顺序）。
  final List<TreeAttr> attrs;

  /// 子元素。
  final List<TreeNode> children;

  const TreeNode(
    this.name, {
    this.text,
    this.kind,
    this.attrs = const [],
    this.children = const [],
  });

  /// 叶子节点（渲染时不给折叠箭头）。
  bool get isLeaf => children.isEmpty;

  /// 属性个数（渲染摘要行用）。
  int get attrCount => attrs.length;
}

/// 树节点的一个属性。
class TreeAttr {
  final String name;
  final String value;
  const TreeAttr(this.name, this.value);
}

/// SVG 图形块（v3.2.11）。
///
/// 图形模型见文件末尾「SVG 矢量图形」一节；解析在 docs/svg.dart，
/// 渲染在 docs/render.dart 的 SvgView（CustomPainter，不引第三方 SVG 库）。
class DocSvg extends DocBlock {
  final SvgDoc doc;

  /// 原始源码（供「查看源码」/复制）。
  final String source;
  const DocSvg(this.doc, this.source);
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
///
/// v3.2.11 新增 xml / html / svg / json 四种「数据结构类」：
///   · xml  —— 树形阅读（xsd / xsl / plist / rss / csproj / resx … 同族）
///   · json —— 树形阅读（对象/数组/标量按类型标注，JSONC 容错）
///   · html —— 就地按文档阅读，不再跳浏览器
///   · svg  —— 本机矢量渲染（纯 Dart 解析 + CustomPainter，不引第三方 SVG 库）
enum DocFormat { markdown, text, docx, xlsx, xml, json, html, svg, unknown }

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
    case 'yaml':
    case 'yml':
    case 'ini':
    case 'conf':
      return DocFormat.text;
    // v3.2.11：JSON 家族——树形阅读（原来按纯文本处理）
    case 'json':
    case 'jsonc':
    case 'geojson':
    case 'webmanifest':
      return DocFormat.json;
    case 'docx':
    case 'docm':
      return DocFormat.docx;
    case 'xlsx':
    case 'xlsm':
      return DocFormat.xlsx;
    // v3.2.8：XML 家族（数据结构）——走树形阅读
    case 'xml':
    case 'xsd':
    case 'xsl':
    case 'xslt':
    case 'plist':
    case 'rss':
    case 'atom':
    case 'kml':
    case 'csproj':
    case 'props':
    case 'resx':
    case 'pom':
    case 'xaml':
      return DocFormat.xml;
    // v3.2.8：网页——就地按文档阅读，不跳浏览器
    case 'html':
    case 'htm':
    case 'xhtml':
    case 'shtml':
      return DocFormat.html;
    // v3.2.8：矢量图——本机渲染
    case 'svg':
      return DocFormat.svg;
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
  'md', 'markdown', 'txt', 'text', 'log', 'csv', 'yaml', 'yml',
  'docx', 'xlsx',
  // v3.2.11：数据结构（JSON / XML 家族）/ 网页 / 矢量图
  'json', 'jsonc', 'geojson', 'webmanifest',
  'xml', 'xsd', 'xsl', 'xslt', 'plist', 'rss', 'atom', 'kml',
  'csproj', 'props', 'resx', 'pom', 'xaml',
  'html', 'htm', 'xhtml', 'shtml',
  'svg',
];

// ══════════════════════════════════════════════════════════════════
// SVG 矢量图形（v3.2.11）
//
// 纯数据模型：解析在 docs/svg.dart，渲染在 docs/render.dart 的 SvgView。
// 放在统一模型里的原因与 Spreadsheet 一致——DocBlock 是 sealed 的，块类型必须和
// 基类同库；渲染端才能靠「穷尽 switch」保证新格式不会被静默漏掉。
// ══════════════════════════════════════════════════════════════════

/// 解析后的 SVG：画布 + 视口 + 图元树。
class SvgDoc {
  /// 画布宽高（width/height 属性；缺省时退回 viewBox 尺寸）。
  final double width;
  final double height;

  /// viewBox（minX minY w h）——渲染时按它缩放到画布。
  final double viewBoxX;
  final double viewBoxY;
  final double viewBoxW;
  final double viewBoxH;

  final List<SvgNode> nodes;
  const SvgDoc({
    required this.width,
    required this.height,
    required this.nodes,
    this.viewBoxX = 0,
    this.viewBoxY = 0,
    double? viewBoxW,
    double? viewBoxH,
  })  : viewBoxW = viewBoxW ?? width,
        viewBoxH = viewBoxH ?? height;
}

/// 图元基类。
sealed class SvgNode {
  const SvgNode();
}

/// 分组（g 元素，以及被当作容器的 svg 元素）。
class SvgGroup extends SvgNode {
  final List<SvgNode> children;
  final SvgTransform? transform;
  const SvgGroup(this.children, {this.transform});
}

/// 一个可填充/描边的图元。
class SvgShape extends SvgNode {
  final SvgGeometry geometry;
  final SvgStyle style;
  final SvgTransform? transform;
  const SvgShape(this.geometry, {this.style = const SvgStyle(), this.transform});
}

/// 文本。
class SvgTextNode extends SvgNode {
  final double x;
  final double y;
  final String text;
  final double fontSize;

  /// start | middle | end
  final String anchor;
  final SvgStyle style;
  final SvgTransform? transform;
  const SvgTextNode(
    this.x,
    this.y,
    this.text, {
    this.fontSize = 16,
    this.anchor = 'start',
    this.style = const SvgStyle(),
    this.transform,
  });
}

// ── 几何 ──────────────────────────────────────────────────────────

sealed class SvgGeometry {
  const SvgGeometry();
}

class SvgRect extends SvgGeometry {
  final double x, y, w, h, rx, ry;
  const SvgRect(this.x, this.y, this.w, this.h, {this.rx = 0, this.ry = 0});
}

class SvgCircle extends SvgGeometry {
  final double cx, cy, r;
  const SvgCircle(this.cx, this.cy, this.r);
}

class SvgEllipse extends SvgGeometry {
  final double cx, cy, rx, ry;
  const SvgEllipse(this.cx, this.cy, this.rx, this.ry);
}

class SvgLineGeom extends SvgGeometry {
  final double x1, y1, x2, y2;
  const SvgLineGeom(this.x1, this.y1, this.x2, this.y2);
}

/// 折线 / 多边形（close = true 时闭合）。
class SvgPoly extends SvgGeometry {
  final List<(double, double)> points;
  final bool close;
  const SvgPoly(this.points, {this.close = false});
}

/// 路径（命令已折算成绝对坐标）。
class SvgPathGeom extends SvgGeometry {
  final List<SvgPathCmd> cmds;
  const SvgPathGeom(this.cmds);
}

// ── 路径命令（相对坐标已在解析期折算） ──────────────────────────────

sealed class SvgPathCmd {
  const SvgPathCmd();
}

class SvgCmdMove extends SvgPathCmd {
  final double x, y;
  const SvgCmdMove(this.x, this.y);
}

class SvgCmdLine extends SvgPathCmd {
  final double x, y;
  const SvgCmdLine(this.x, this.y);
}

class SvgCmdCubic extends SvgPathCmd {
  final double x1, y1, x2, y2, x, y;
  const SvgCmdCubic(this.x1, this.y1, this.x2, this.y2, this.x, this.y);
}

class SvgCmdQuad extends SvgPathCmd {
  final double x1, y1, x, y;
  const SvgCmdQuad(this.x1, this.y1, this.x, this.y);
}

class SvgCmdArc extends SvgPathCmd {
  final double rx, ry, rot;
  final bool largeArc, sweep;
  final double x, y;
  const SvgCmdArc(this.rx, this.ry, this.rot, this.largeArc, this.sweep, this.x, this.y);
}

class SvgCmdClose extends SvgPathCmd {
  const SvgCmdClose();
}

// ── 样式 / 变换 ───────────────────────────────────────────────────

/// 绘制样式。fill / stroke 为 null 表示「不画」（SVG 的 none）。
/// 继承已在解析期算完，所以这里的取值就是最终值。
class SvgStyle {
  final int? fill;
  final int? stroke;
  final double strokeWidth;
  final double opacity;

  /// butt | round | square
  final String lineCap;

  /// miter | round | bevel
  final String lineJoin;
  const SvgStyle({
    this.fill = 0xFF000000,
    this.stroke,
    this.strokeWidth = 1.0,
    this.opacity = 1.0,
    this.lineCap = 'butt',
    this.lineJoin = 'miter',
  });
}

/// 2D 仿射变换，存成 SVG matrix(a b c d e f) 同序的六个分量。
class SvgTransform {
  final double a, b, c, d, e, f;
  const SvgTransform(this.a, this.b, this.c, this.d, this.e, this.f);
  static const SvgTransform identity = SvgTransform(1, 0, 0, 1, 0, 0);

  /// this × o（先应用 o 再应用 this，与 SVG transform 列表语义一致）。
  SvgTransform multiply(SvgTransform o) => SvgTransform(
        a * o.a + c * o.b,
        b * o.a + d * o.b,
        a * o.c + c * o.d,
        b * o.c + d * o.d,
        a * o.e + c * o.f + e,
        b * o.e + d * o.f + f,
      );

  bool get isIdentity => a == 1 && b == 0 && c == 0 && d == 1 && e == 0 && f == 0;
}

