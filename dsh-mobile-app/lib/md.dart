// Markdown 渲染 —— 完全对齐网页端 page.html 的 renderMarkdown：
// 段落/标题1-4/列表/引用/代码块/行内代码/表格/链接/分隔线，样式同 CSS。
//
// v3.2.0：接入 LaTeX 公式——行内 $...$ / \(...\) 与显示式 $$...$$ / \[...\] 交给
// math/view.dart（flutter_math_fork）真排版；代码块内的 $ 一律不解析（代码要保持原样）。
//
// v3.3.0（官方风格）：视觉全部改走 lib/theme.dart 令牌——标题 mdH1..mdH4、正文 mdBase
// （加粗 600 而不是 700）、表格 mdTable/mdTableHead、代码 mdCode/mdCodeBlock；
// 行内代码用 inlineCode 底 + R4，代码块用 codeBlock 底 + R16 + codeBanner 标题条，
// 引用块用 2px line3 竖线，链接用 link 色（静止态不下划线）。解析逻辑一行未动。
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'api.dart';
import 'docs/link.dart';
import 'docs/sheet.dart';
import 'dsh_kit.dart';
import 'l10n.dart';
import 'math/tex.dart';
import 'math/view.dart';
import 'theme.dart';
import 'toast.dart';

/// 只放行 http/https 链接（v2.6.0 安全加固）：
/// 防止消息内容（或中间人篡改的回复）用 file:/intent:/tel: 等 scheme 拉起任意应用/Intent。
/// 解析失败或 scheme 不允许时返回 null（渲染为纯文本，不可点击）。
Uri? safeLinkUrl(String raw) {
  try {
    final uri = Uri.parse(raw.trim());
    if (uri.scheme == 'http' || uri.scheme == 'https') return uri;
  } catch (_) {}
  return null;
}

/// 行内 token：**加粗** *斜体* `代码` [链接](url)
final _inlineRe = RegExp(r'(\*\*[^*]+\*\*|\*[^*\s][^*]*\*|`[^`]+`|\[[^\]]*\]\([^)\s]+\))');

// v3.0.0 review：块级判定正则提为顶层常量——渲染长消息时逐行构造会重复编译
final _mdTableSepRe = RegExp(r'^\s*\|?[\s:|-]+\|?\s*$');
final _mdHeadingRe = RegExp(r'^(#{1,4})\s+(.*)$');
final _mdHrRe = RegExp(r'^\s*(---|\*\*\*|___)\s*$');
final _mdBulletRe = RegExp(r'^\s*[-*+]\s+(.*)$');
final _mdNumberedRe = RegExp(r'^\s*(\d+)\.\s+(.*)$');
final _mdQuoteRe = RegExp(r'^\s*>\s?');

/// 超过该行数的代码块在标题条上提示「可滚动查看」。
const int _longCodeLines = 15;

/// 合法代码围栏开启行 → 返回反引号数量 N；否则返回 null。
///
/// 规则：trim 后以 ≥3 个反引号开头，且其后的信息串（语言标注）不含反引号。
/// 缩进有意不做限制：CommonMark 只允许 ≤3 空格，但放宽可保住列表内缩进的代码块。
int? fenceOpenCount(String line) {
  final t = line.trim();
  if (!t.startsWith('```')) return null;
  var n = 0;
  while (n < t.length && t.codeUnitAt(n) == 0x60) {
    n++;
  }
  if (n < 3) return null;
  if (t.substring(n).contains('`')) return null; // 信息串含反引号 → 不是围栏
  return n;
}

/// 是否为长度为 [openCount] 的开启围栏的合法闭合行。
///
/// 规则：trim 后仅由 ≥openCount 个反引号组成（允许尾随空白）。因此围栏内部带其它
/// 字符的反引号行（例如 4 反引号文档围栏里的内层 ```js）不会被误判为闭合。
bool isFenceClose(String line, int openCount) {
  final t = line.trim();
  if (t.isEmpty || !t.startsWith('`')) return false;
  var n = 0;
  while (n < t.length && t.codeUnitAt(n) == 0x60) {
    n++;
  }
  if (n < openCount) return false;
  return t.substring(n).trim().isEmpty;
}

/// 围栏开启行上的语言标注（```dart → dart）；没有则返回空串。
String _fenceInfo(String line) {
  final t = line.trim();
  var n = 0;
  while (n < t.length && t.codeUnitAt(n) == 0x60) {
    n++;
  }
  return t.substring(n).trim();
}

/// 渲染完整 Markdown 文本 → 块级 Widget 列表（放置于 Column 中）。
List<Widget> renderMarkdownBlocks(String text, BuildContext context) {
  final c = DshPalette.of(context);
  final blocks = <Widget>[];
  final lines = text.split('\n');
  var i = 0;
  var inCode = false;
  var fenceLen = 0; // 当前开启围栏的反引号数量（闭合需 ≥ 该值）
  var fenceLang = ''; // 当前围栏的语言标注（代码块标题条用）
  final codeBuf = <String>[];
  var listEl = <String>[]; // 当前列表项内容
  var listOrdered = false;
  var para = <String>[];
  var tableBuf = <String>[];

  // 正文样式：官方 Markdown 阶梯（14/24）。
  TextStyle bodyStyle() => DshType.mdBase.copyWith(color: c.ink);

  void flushPara() {
    if (para.isEmpty) return;
    blocks.add(Padding(
      padding: const EdgeInsets.only(bottom: DshSpace.md),
      child: _InlineText(para.join('\n'), style: bodyStyle()),
    ));
    para = [];
  }

  void flushList() {
    if (listEl.isEmpty) return;
    blocks.add(Padding(
      padding: const EdgeInsets.only(bottom: DshSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var idx = 0; idx < listEl.length; idx++)
            Padding(
              padding: const EdgeInsets.only(top: DshSpace.xxs),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 标记（• / 1.）用三级文字色，正文沿用 14/24
                  SizedBox(
                    width: DshSpace.xl,
                    child: Text(
                      listOrdered ? '${idx + 1}.' : '•',
                      style: DshType.mdBase.copyWith(color: c.ink3),
                    ),
                  ),
                  Expanded(child: _InlineText(listEl[idx], style: bodyStyle())),
                ],
              ),
            ),
        ],
      ),
    ));
    listEl = [];
  }

  void flushTable() {
    if (tableBuf.isEmpty) return;
    blocks.add(_MarkdownTable(tableBuf));
    tableBuf = [];
  }

  // 显示式公式块：官方版式是「独立成行居中」，用 module 轻底做静区分隔。
  void flushDisplayMath(String tex) {
    blocks.add(Padding(
      padding: const EdgeInsets.symmetric(vertical: DshSpace.md),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(
          horizontal: DshSpace.sm,
          vertical: DshSpace.md,
        ),
        decoration: BoxDecoration(
          color: c.module,
          borderRadius: DshRadius.rMd,
        ),
        child: DisplayMath(tex, style: bodyStyle()),
      ),
    ));
  }

  void pushCodeBlock() {
    if (codeBuf.isEmpty) return;
    final lineCount = codeBuf.length;
    final code = codeBuf.join('\n');
    final lang = fenceLang;
    fenceLang = '';
    codeBuf.clear();
    blocks.add(Padding(
      padding: const EdgeInsets.symmetric(vertical: DshSpace.sm),
      child: _CodeBlock(code: code, lineCount: lineCount, lang: lang),
    ));
  }

  while (i < lines.length) {
    final raw = lines[i];
    // issue #22：围栏按「开启反引号数量」配对——开启行记录 N，闭合行必须
    // 仅由 ≥N 个反引号组成。修复此前 startsWith('```') 二元翻转导致 4 反引号文档围栏
    // 包裹 3 反引号代码块时「正文被吞成代码、代码被当作正文」的错位。
    if (!inCode) {
      final open = fenceOpenCount(raw);
      if (open != null) {
        flushPara();
        flushList();
        flushTable();
        inCode = true;
        fenceLen = open;
        fenceLang = _fenceInfo(raw);
        codeBuf.clear();
        i++;
        continue;
      }
    } else if (isFenceClose(raw, fenceLen)) {
      pushCodeBlock();
      inCode = false;
      i++;
      continue;
    }
    if (inCode) {
      codeBuf.add(raw);
      i++;
      continue;
    }
    // v3.2.0：显式公式标记整行（/"…"/）→ 显示式公式块
    final markedTex = formulaMarkupWholeLine(raw);
    if (markedTex != null) {
      flushPara();
      flushList();
      flushTable();
      flushDisplayMath(markedTex);
      continue;
    }
    // v3.2.0：显示式公式 $$...$$（可跨行）独占一块——与网页端 MathJax 的
    // display 语义一致。只认「整行以 $$ 开头」，避免把正文里的「$$5」当公式。
    final mathLine = raw.trim();
    if (mathLine.startsWith(r'$$')) {
      flushPara();
      flushList();
      flushTable();
      final after = mathLine.substring(2);
      var tex = '';
      final sameLine = after.indexOf(r'$$');
      if (sameLine >= 0) {
        tex = after.substring(0, sameLine).trim();
        i++;
      } else {
        final buf = <String>[after];
        i++;
        while (i < lines.length && !lines[i].contains(r'$$')) {
          buf.add(lines[i]);
          i++;
        }
        if (i < lines.length) {
          buf.add(lines[i].split(r'$$').first);
          i++;
        }
        tex = buf.join(' ').trim();
      }
      if (tex.isNotEmpty) flushDisplayMath(tex);
      continue;
    }
    // 表格：| a | b | 下一行是分隔行 |---|---|
    final tableStart = raw.startsWith('|') &&
        i + 1 < lines.length &&
        _mdTableSepRe.hasMatch(lines[i + 1]) &&
        lines[i + 1].contains('-');
    if (tableStart) {
      flushPara();
      flushList();
      tableBuf.add(raw);
      i++;
      while (i < lines.length && lines[i].startsWith('|')) {
        tableBuf.add(lines[i]);
        i++;
      }
      flushTable();
      continue;
    }
    // 标题：# 1-4 → mdH1..mdH4（21/19/18/14，与官方 Markdown 阶梯一致）
    final heading = _mdHeadingRe.firstMatch(raw);
    if (heading != null) {
      flushPara();
      flushList();
      flushTable();
      final level = heading.group(1)!.length;
      final style = switch (level) {
        1 => DshType.mdH1,
        2 => DshType.mdH2,
        3 => DshType.mdH3,
        _ => DshType.mdH4,
      };
      blocks.add(Padding(
        padding: EdgeInsets.only(
          top: level <= 2 ? DshSpace.lg : DshSpace.md,
          bottom: DshSpace.sm,
        ),
        child: _InlineText(
          heading.group(2)!,
          style: style.copyWith(color: c.ink),
        ),
      ));
      i++;
      continue;
    }
    // 分隔线：0.5px line2（DshDivider）
    if (_mdHrRe.hasMatch(raw)) {
      flushPara();
      flushList();
      flushTable();
      blocks.add(const Padding(
        padding: EdgeInsets.symmetric(vertical: DshSpace.md),
        child: DshDivider(),
      ));
      i++;
      continue;
    }
    // 列表
    final bullet = _mdBulletRe.firstMatch(raw);
    final numbered = _mdNumberedRe.firstMatch(raw);
    if (bullet != null || numbered != null) {
      flushPara();
      flushTable();
      if (listEl.isEmpty) listOrdered = numbered != null;
      listEl.add(bullet != null ? bullet.group(1)! : numbered!.group(2)!);
      i++;
      continue;
    }
    // 引用：左侧 2px line3 竖线 + 12 内边距，文字 ink2
    if (_mdQuoteRe.hasMatch(raw)) {
      flushPara();
      flushList();
      flushTable();
      blocks.add(Container(
        margin: const EdgeInsets.only(bottom: DshSpace.md),
        padding: const EdgeInsets.all(DshSpace.md),
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(color: c.line3, width: 2),
          ),
        ),
        child: _InlineText(
          raw.replaceFirst(_mdQuoteRe, ''),
          style: DshType.mdBase.copyWith(color: c.ink2),
        ),
      ));
      i++;
      continue;
    }
    // v3.0.0：列表/表格后的普通段落必须先落盘前一区块——此前 flushPara 在循环结束时恒在
    // flushList/flushTable 之前执行，“- a\n- b\nprose” 会把 prose 渲染到列表上方
    // （表格后跟段落同病）。同时空行/段落行也顺带结束当前列表，符合 Markdown 直觉。
    if (listEl.isNotEmpty) flushList();
    if (tableBuf.isNotEmpty) flushTable();
    para.add(raw);
    i++;
  }
  flushPara();
  flushList();
  flushTable();
  if (inCode && codeBuf.isNotEmpty) pushCodeBlock();
  return blocks;
}

// ══════════════════════════════════════════════════════════════════
// 代码块
// ══════════════════════════════════════════════════════════════════

/// 代码块：官方 markdown-code-block 版式——R16 + codeBlock 底 + codeBanner 标题条。
///
/// 标题条左侧是语言标签（xxs12 · ink3），右侧是复制；正文横向滚动不换行，
/// 超过 [_longCodeLines] 行时纵向限高并在标签上提示可滚动。
class _CodeBlock extends StatefulWidget {
  const _CodeBlock({
    required this.code,
    required this.lineCount,
    required this.lang,
  });

  final String code;
  final int lineCount;
  final String lang;

  @override
  State<_CodeBlock> createState() => _CodeBlockState();
}

class _CodeBlockState extends State<_CodeBlock> {
  final _hScroll = ScrollController();

  @override
  void dispose() {
    _hScroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = DshPalette.of(context);
    // 标题条：左侧语言标签（有语言时），右侧滚动提示（长块带行数）+ 复制。
    // 长块提示固定以「代码 · N 行 · 可滚动查看」表述——行数提示是既有行为，不因有语言而丢失。
    final hint = widget.lineCount > _longCodeLines
        ? L10n.t(
            '代码 · ${widget.lineCount} 行 · 可滚动查看',
            'Code · ${widget.lineCount} lines · scrollable',
          )
        : L10n.t('代码', 'Code');

    return Container(
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: c.codeBlock,
        borderRadius: DshRadius.rLg,
        border: Border.fromBorderSide(DshStroke.side(c.line2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题条
          Container(
            color: c.codeBanner,
            padding: const EdgeInsets.only(
              left: DshSpace.md,
              right: DshSpace.xs,
              top: DshSpace.xxs,
              bottom: DshSpace.xxs,
            ),
            child: Row(
              children: [
                if (widget.lang.isNotEmpty) ...[
                  DshTag(label: widget.lang, dense: true),
                  const SizedBox(width: DshSpace.sm),
                ],
                Expanded(
                  child: Text(
                    hint,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: DshType.xxs12.copyWith(color: c.ink3),
                  ),
                ),
                DshIconButton(
                  icon: Icons.copy_all,
                  size: DshSpace.controlSm,
                  iconSize: 16,
                  tooltip: L10n.t('复制', 'Copy'),
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: widget.code));
                    showToast(
                      context,
                      L10n.t(
                        '已复制代码（${widget.lineCount} 行）',
                        'Copied ${widget.lineCount} lines of code',
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          // 标题条与代码之间补一条发丝线：亮色下 codeBanner 与 codeBlock 同色，靠线分层
          const DshDivider(),
          // 正文：横向滚动（滚动条外观走主题 scrollbarTheme），长块纵向限高兜底
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 320),
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(DshSpace.md),
                child: _HScroll(
                  controller: _hScroll,
                  child: Text(
                    widget.code,
                    style: DshType.mdCodeBlock.copyWith(color: c.ink),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 横向滚动容器：滚动条外观一律取主题 scrollbarTheme，不在本地覆写。
class _HScroll extends StatelessWidget {
  const _HScroll({required this.controller, required this.child});

  final ScrollController controller;
  final Widget child;

  @override
  Widget build(BuildContext context) => Scrollbar(
        controller: controller,
        child: SingleChildScrollView(
          controller: controller,
          scrollDirection: Axis.horizontal,
          child: child,
        ),
      );
}

// ══════════════════════════════════════════════════════════════════
// 表格
// ══════════════════════════════════════════════════════════════════

/// 表格（对齐官方 .md-table：mdTable 正文 / mdTableHead 表头 + line2 发丝分隔）。
///
/// 缺陷修复（GitLab !3）保留：此前每行是独立 `Row`、单元格各取自然宽，导致同一列在不同行的
/// x 起点相差数百像素、边框呈阶梯状错位（观感像内容跑到表格外）；且单元格用裸 `Text`，
/// 行内 Markdown（`**加粗**`、`` `code` ``、链接）会把标记原样显示。现为：
/// 1. **共享列宽**——先测量每列的最大自然宽（含表头），所有行共用同一组宽度；
/// 2. 单元格复用 [_InlineText]，与段落同一套行内解析；
/// 3. 边框改为「单一外框 + 行/列单线分隔」，同行单元格等高，不再出现双线与断框。
///
/// 列宽 = 内容自然宽、不换行、不设上限；整表超宽时横向滚动（滚动条走主题 scrollbarTheme）。
class _MarkdownTable extends StatefulWidget {
  const _MarkdownTable(this.rows);

  final List<String> rows;

  @override
  State<_MarkdownTable> createState() => _MarkdownTableState();
}

class _MarkdownTableState extends State<_MarkdownTable> {
  final _hScroll = ScrollController();

  @override
  void dispose() {
    _hScroll.dispose();
    super.dispose();
  }

  List<String> _parseRow(String l) => l
      .trim()
      .replaceAll(RegExp(r'^\||\|$'), '')
      .split('|')
      .map((s) => s.trim())
      .toList();

  @override
  Widget build(BuildContext context) {
    final c = DshPalette.of(context);
    final rows = widget.rows;
    final head = _parseRow(rows[0]);
    final body = <List<String>>[];
    for (var i = 2; i < rows.length; i++) {
      body.add(_parseRow(rows[i]));
    }

    const hPad = DshSpace.sm; // 单元格左右内边距
    const vPad = DshSpace.xs; // 单元格上下内边距

    TextStyle cellStyle({bool header = false}) =>
        (header ? DshType.mdTableHead : DshType.mdTable).copyWith(color: c.ink);

    var colCount = head.length;
    for (final r in body) {
      if (r.length > colCount) colCount = r.length;
    }
    if (colCount == 0) return const SizedBox.shrink();

    // 用与渲染完全相同的 spans（含粗体/代码样式）测量，并按系统字号缩放；
    // 否则粗体或放大字号下测量偏小，单元格会意外换行。
    final textScaler = MediaQuery.textScalerOf(context);
    // 必须与渲染路径同源：`_InlineText` 的 Text.rich 会把样式并入 ambient DefaultTextStyle
    // （字体族/度量都参与），只按裸 style 测量会偏小 → 单元格意外换行。
    final ambient = DefaultTextStyle.of(context).style;
    double measure(String text, {required bool header}) {
      final style = ambient.merge(cellStyle(header: header));
      final spans = _inlineSpans(text, context, style);
      // 行内代码/链接在 _inlineSpans 中是 WidgetSpan，无法直接在裸 TextPainter 里布局
      // （需要 placeholder dimensions，否则断言 'dimensions != null' → 整条消息渲染失败）。
      // 故还原成「等价的文本 span + 固定额外宽度」来测量，宽度与真实渲染一致。
      final m = _measureSpan(spans, style);
      final tp = TextPainter(
        text: m.span,
        textDirection: TextDirection.ltr,
        textScaler: textScaler,
        maxLines: 1,
      )..layout();
      return tp.width + m.extra;
    }

    final widths = List<double>.filled(colCount, 0);
    for (var col = 0; col < colCount; col++) {
      var w = col < head.length ? measure(head[col], header: true) : 0.0;
      for (final r in body) {
        if (col < r.length) {
          final m = measure(r[col], header: false);
          if (m > w) w = m;
        }
      }
      // +1 抵消亚像素取整，保证不换行
      widths[col] = w + hPad * 2 + 1;
    }

    Widget cell(
      String text,
      int col, {
      required bool header,
      required bool lastRow,
      required bool lastCol,
    }) =>
        Container(
          width: widths[col],
          padding: const EdgeInsets.symmetric(horizontal: hPad, vertical: vPad),
          decoration: BoxDecoration(
            color: header ? c.module : null,
            // 内部只画右/下分隔线，最后一行/列不画；外框由外层容器统一提供 → 单线不重叠
            border: Border(
              right: lastCol
                  ? BorderSide.none
                  : BorderSide(color: c.line2, width: DshStroke.hairline),
              bottom: lastRow
                  ? BorderSide.none
                  : BorderSide(color: c.line2, width: DshStroke.hairline),
            ),
          ),
          child: Align(
            alignment: Alignment.centerLeft,
            child: _InlineText(text, style: cellStyle(header: header)),
          ),
        );

    // IntrinsicHeight + stretch：同行单元格强制等高。行内代码（等宽字体）与链接
    //（WidgetSpan 的 Text child）的自然行高比普通文本高，若各按自然高度渲染，该行的下
    // 边框会出现断口（阶梯状分隔线）。等高后行/列分隔线连续。
    Widget row(List<String> cells, {required bool header, required bool lastRow}) =>
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var col = 0; col < colCount; col++)
                cell(
                  col < cells.length ? cells[col] : '',
                  col,
                  header: header,
                  lastRow: lastRow,
                  lastCol: col == colCount - 1,
                ),
            ],
          ),
        );

    return Padding(
      padding: const EdgeInsets.only(bottom: DshSpace.md),
      child: _HScroll(
        controller: _hScroll,
        child: Container(
          decoration: BoxDecoration(
            border: Border.fromBorderSide(DshStroke.side(c.line2)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              row(head, header: true, lastRow: body.isEmpty),
              for (var r = 0; r < body.length; r++)
                row(body[r], header: false, lastRow: r == body.length - 1),
            ],
          ),
        ),
      ),
    );
  }
}

/// 段落文本（可选中复制），内部解析行内样式。
class _InlineText extends StatelessWidget {
  final String text;
  final TextStyle style;
  const _InlineText(this.text, {required this.style});

  @override
  Widget build(BuildContext context) {
    // v2.9.0 review(M3)：行内解析带 context——深色模式下链接用品牌深色（原静态浅色对比度差）
    final spans = _inlineSpans(text, context, style);
    // 用普通 Text 渲染（SelectableText 在部分 Android 设备上长文本换行/重叠渲染异常）
    return Text.rich(
      TextSpan(children: spans, style: style),
      style: style,
    );
  }
}

/// 行内代码（官方 markdown inline-code）：mdCode 字号 + inlineCode 底 + R4 + 左右 4px 内边距。
///
/// 用 WidgetSpan 承载是因为 TextSpan 画不出圆角与内边距；基线对齐保证与正文同行不跳动。
class _InlineCodeBox extends StatelessWidget {
  const _InlineCodeBox(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final c = DshPalette.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: DshSpace.xs),
      decoration: BoxDecoration(
        color: c.inlineCode,
        borderRadius: DshRadius.rXs,
      ),
      child: Text(text, style: DshType.mdCode.copyWith(color: c.ink)),
    );
  }
}

/// 把渲染用的行内 spans 还原成「可测量的文本 span + 固定额外宽度」。
///
/// [TextPainter] 无法布局 [WidgetSpan]（需要 placeholder dimensions），
/// 因此行内代码（[_InlineCodeBox]）取其文字 + mdCode 样式，并把它左右各 4px 的内边距
/// 记进 extra；链接取其 `Text` child 的文字与样式。
({TextSpan span, double extra}) _measureSpan(
  List<InlineSpan> spans,
  TextStyle base,
) {
  final out = <InlineSpan>[];
  var extra = 0.0;
  for (final s in spans) {
    if (s is WidgetSpan) {
      final child = s.child;
      if (child is _InlineCodeBox) {
        out.add(TextSpan(text: child.text, style: DshType.mdCode));
        extra += DshSpace.xs * 2;
      } else {
        final t = _textOf(child);
        if (t != null) out.add(TextSpan(text: t.data ?? '', style: t.style));
      }
    } else if (s is TextSpan) {
      out.add(s);
    }
  }
  return (span: TextSpan(children: out, style: base), extra: extra);
}

/// 取出 WidgetSpan 里承载文字的 [Text]（链接外面还套了一层 GestureDetector）。
Text? _textOf(Widget child) {
  if (child is Text) return child;
  if (child is GestureDetector) {
    final inner = child.child;
    if (inner is Text) return inner;
  }
  return null;
}

/// 行内解析总入口（v3.2.0）：**行内代码 → 公式 → Markdown 行内规则**，三层优先级。
///
/// 顺序很关键，两头都踩过坑：
///  · 代码必须最先切：正文写 `` `$$...$$` ``（说明公式语法）时，若先做公式探测，
///    `$$` 会被当成显示式公式、反引号变成字面量（模拟器实测）；
///  · 公式要早于 Markdown：公式里可能含 `*` `_` `[]`（如 `$a_i^*$`），
///    先走 Markdown 正则会把它切碎成乱码。
List<InlineSpan> _inlineSpans(String text, BuildContext context, TextStyle base) {
  final out = <InlineSpan>[];
  var last = 0;
  for (final m in _codeSpanRe.allMatches(text)) {
    if (m.start > last) {
      out.addAll(_mathThenMd(text.substring(last, m.start), context, base));
    }
    // 连反引号一起交回原有解析器 → 复用既有的行内代码样式
    out.addAll(_mdInlineSpans(m.group(0)!, context, base));
    last = m.end;
  }
  if (last < text.length) {
    out.addAll(_mathThenMd(text.substring(last), context, base));
  }
  return out;
}

final _codeSpanRe = RegExp(r'`[^`]+`');

/// 在非代码文本里切公式，其余走 Markdown 行内规则。
List<InlineSpan> _mathThenMd(String text, BuildContext context, TextStyle base) {
  if (text.isEmpty) return const [];
  final segs = findMathSegments(text);
  if (segs.isEmpty) return _mdInlineSpans(text, context, base);
  final out = <InlineSpan>[];
  var last = 0;
  for (final s in segs) {
    if (s.start > last) {
      out.addAll(_mdInlineSpans(text.substring(last, s.start), context, base));
    }
    out.add(_mathSpan(s.tex, context, base));
    last = s.end;
  }
  if (last < text.length) {
    out.addAll(_mdInlineSpans(text.substring(last), context, base));
  }
  return out;
}

/// 公式 → 基线对齐的 WidgetSpan（与正文同高，不会把行高撑破）。
///
/// 字号跟随所在文本 [base]（标题里的公式与标题同大），颜色取主题 ink。
InlineSpan _mathSpan(String tex, BuildContext context, TextStyle base) => WidgetSpan(
      alignment: PlaceholderAlignment.middle,
      child: InlineMath(
        tex,
        style: base.copyWith(color: DshPalette.of(context).ink),
      ),
    );

/// 行内解析：**加粗** / *斜体* / `代码` / [文字](链接)
List<InlineSpan> _mdInlineSpans(String text, BuildContext context, TextStyle base) {
  final c = DshPalette.of(context);
  // 链接：link 色 + w500，静止态不带下划线（官方规则）
  final linkStyle = base.copyWith(color: c.link, fontWeight: FontWeight.w500);
  final spans = <InlineSpan>[];
  var last = 0;
  for (final m in _inlineRe.allMatches(text)) {
    if (m.start > last) spans.add(TextSpan(text: text.substring(last, m.start)));
    final tok = m.group(0)!;
    if (tok.startsWith('**')) {
      // 加粗 600（mdBaseStrong），不是 700——相对字重以便在表格 13px 单元格里同样成立
      spans.add(TextSpan(
        text: tok.substring(2, tok.length - 2),
        style: const TextStyle(fontWeight: FontWeight.w600),
      ));
    } else if (tok.startsWith('`')) {
      spans.add(WidgetSpan(
        alignment: PlaceholderAlignment.baseline,
        baseline: TextBaseline.alphabetic,
        child: _InlineCodeBox(tok.substring(1, tok.length - 1)),
      ));
    } else if (tok.startsWith('[')) {
      final mm = RegExp(r'^\[([^\]]*)\]\(([^)]*)\)$').firstMatch(tok);
      if (mm != null) {
        final label = mm.group(1)!;
        final rawUrl = mm.group(2)!;
        // v3.2.1：**文档链接就地打开**——在底部抽屉里读，不跳出对话、也不惊动浏览器。
        // 这是用户明确要的手感：「点我发的链接 → 直接开始读，对话不关」。
        final docTarget = parseDocLink(rawUrl);
        if (docTarget != null) {
          spans.add(WidgetSpan(
            alignment: PlaceholderAlignment.baseline,
            baseline: TextBaseline.alphabetic,
            child: GestureDetector(
              onTap: () => showDocSheet(
                context,
                name: docTarget.name,
                localPath: docTarget.localPath,
                httpUrl: docTarget.httpUrl,
                api: api,
              ),
              child: Text(
                // 📄 前缀让「文档」一眼区别于普通网页链接
                '📄 ${label.isEmpty ? docTarget.name : label}',
                style: linkStyle,
              ),
            ),
          ));
          last = m.end;
          continue;
        }
        final target = safeLinkUrl(rawUrl);
        if (target == null) {
          // 非 http/https 链接（或解析失败）：渲染为纯文本，不可点击（v2.6.0）
          spans.add(TextSpan(text: label));
        } else {
          spans.add(WidgetSpan(
            alignment: PlaceholderAlignment.baseline,
            baseline: TextBaseline.alphabetic,
            child: GestureDetector(
              onTap: () => launchUrl(target, mode: LaunchMode.externalApplication),
              child: Text(label, style: linkStyle),
            ),
          ));
        }
      } else {
        spans.add(TextSpan(text: tok));
      }
    } else {
      spans.add(TextSpan(
        text: tok.substring(1, tok.length - 1),
        style: const TextStyle(fontStyle: FontStyle.italic),
      ));
    }
    last = m.end;
  }
  if (last < text.length) spans.add(TextSpan(text: text.substring(last)));
  return spans;
}
