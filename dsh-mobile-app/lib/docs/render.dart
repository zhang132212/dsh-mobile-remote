// 文档渲染层（v3.2.0）——把 docs/model.dart 的块模型渲染成 Widget。
// md / txt / docx / xlsx 四种来源归一到这里，所以「各格式特色」由模型承载、
// 呈现保持一致；公式一律走 math/view.dart（flutter_math_fork）。
//
// 设计：整篇文档是一个 `DocBlocks` widget，context 自上而下显式传递
// （不用全局槽位——那样 rebuild 顺序一变就取错主题色）。
//
// v3.3.0（官方风格）：视觉与 lib/md.dart 同一套令牌——标题 mdH1..mdH4、正文 mdBase、
// 表格 mdTable/mdTableHead、代码 mdCodeBlock + codeBanner 标题条、引用 2px line3 竖线；
// 阅读页的「字号 +/−」只缩放令牌字号（不改令牌本身）。
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api.dart';
import '../dsh_kit.dart';
import '../l10n.dart';
import '../math/view.dart';
import '../theme.dart';
import '../toast.dart';
import 'link.dart';
import 'model.dart';
import 'sheet.dart';

/// 渲染参数：字号缩放（阅读页「字号 +/−」控制），1.0 为基准。
class DocRenderCtx {
  final double scale;
  const DocRenderCtx({this.scale = 1.0});

  /// 正文实际字号：官方 Markdown 正文令牌 × 阅读缩放。
  double get body => _mdBaseSize * scale;

  TextStyle bodyStyle(BuildContext c) => DshType.mdBase.copyWith(
        fontSize: body,
        color: DshPalette.of(c).ink,
      );
}

/// 正文基准字号（令牌，不写死）。
double get _mdBaseSize => DshType.mdBase.fontSize!;

/// 令牌文本样式 × 阅读缩放——文档里所有字号都由令牌推出，页面不写死 fontSize。
TextStyle _scaled(TextStyle token, DocRenderCtx ctx, {Color? color}) {
  final fs = (token.fontSize ?? _mdBaseSize) * ctx.scale;
  return color == null
      ? token.copyWith(fontSize: fs)
      : token.copyWith(fontSize: fs, color: color);
}

/// 打开链接。
///
/// 优先级（v3.2.1）：
///  1. **文档链接**（`dsh-doc:` 或扩展名可读的 http(s)）→ 在**底部抽屉**里就地阅读，
///     对话不被关闭、也不跳浏览器。这是用户明确要的手感。
///  2. 普通 http/https → 交给系统浏览器（外部应用）。
///  3. 其它 scheme（file:/intent:/tel: …）一律不拉起外部应用，避免被文档内容劫持。
Future<void> openDocLink(BuildContext context, String url) async {
  // ① 文档链接：就地打开
  final docTarget = parseDocLink(url);
  if (docTarget != null) {
    await showDocSheet(
      context,
      name: docTarget.name,
      localPath: docTarget.localPath,
      httpUrl: docTarget.httpUrl,
      api: api,
    );
    return;
  }

  Uri uri;
  try {
    uri = Uri.parse(url.trim());
  } catch (_) {
    showToast(context, L10n.t('链接无法解析', 'Unresolvable link'));
    return;
  }
  if (uri.scheme != 'http' && uri.scheme != 'https') {
    showToast(context, L10n.t('非网页链接：$url', 'Not a web link: $url'));
    return;
  }
  final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!ok && context.mounted) {
    showToast(context, L10n.t('无法打开链接', 'Cannot open link'));
  }
}

// ══════════════════════════════════════════════════════════════════
// 文档块视图
// ══════════════════════════════════════════════════════════════════

/// 整篇文档的块视图。
///
/// [headingKeys] 用于「目录跳转」：按块下标给出 GlobalKey，标题块挂上去，
/// 目录点击时 `Scrollable.ensureVisible` 滚到对应位置。
class DocBlocks extends StatelessWidget {
  final List<DocBlock> blocks;
  final DocRenderCtx ctx;
  final Map<int, GlobalKey>? headingKeys;
  const DocBlocks(this.blocks, {super.key, required this.ctx, this.headingKeys});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < blocks.length; i++)
          KeyedSubtree(
            key: headingKeys?[i],
            child: _block(context, blocks[i], ctx),
          ),
      ],
    );
  }
}

Widget _block(BuildContext context, DocBlock b, DocRenderCtx ctx) {
  final c = DshPalette.of(context);
  switch (b) {
    case DocHeading(:final level, :final spans):
      // 官方 Markdown 标题阶梯：mdH1 21 / mdH2 19 / mdH3 18 / mdH4 14
      final token = switch (level) {
        1 => DshType.mdH1,
        2 => DshType.mdH2,
        3 => DshType.mdH3,
        _ => DshType.mdH4,
      };
      return Padding(
        padding: EdgeInsets.only(
          top: level <= 2 ? DshSpace.xl : DshSpace.lg,
          bottom: DshSpace.sm,
        ),
        child: _RichBlock(
          spans: spans,
          ctx: ctx,
          style: _scaled(token, ctx, color: c.ink),
        ),
      );

    case DocPara(:final spans, :final align):
      return Padding(
        padding: const EdgeInsets.only(bottom: DshSpace.md),
        child: _RichBlock(spans: spans, ctx: ctx, style: ctx.bodyStyle(context), align: align),
      );

    case DocList(:final items, :final ordered, :final start):
      return Padding(
        padding: const EdgeInsets.only(bottom: DshSpace.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < items.length; i++)
              Padding(
                padding: const EdgeInsets.only(top: DshSpace.xxs),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 序号/圆点用三级文字色，宽度随缩放一起走
                    SizedBox(
                      width: DshSpace.xl * ctx.scale,
                      child: Text(
                        ordered ? '${start + i}.' : '•',
                        style: ctx.bodyStyle(context).copyWith(color: c.ink3),
                      ),
                    ),
                    Expanded(
                      child: _RichBlock(
                        spans: items[i],
                        ctx: ctx,
                        style: ctx.bodyStyle(context),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      );

    case DocCode(:final text, :final lang):
      return _DocCodeBlock(text: text, lang: lang, ctx: ctx);

    case DocQuote(:final spans):
      // 官方引用：左侧 2px line3 竖线 + 12 内边距，文字 ink2
      return Container(
        margin: const EdgeInsets.only(bottom: DshSpace.md),
        padding: const EdgeInsets.all(DshSpace.md),
        decoration: BoxDecoration(
          border: Border(left: BorderSide(color: c.line3, width: 2)),
        ),
        child: _RichBlock(
          spans: spans,
          ctx: ctx,
          style: ctx.bodyStyle(context).copyWith(color: c.ink2),
        ),
      );

    case DocRule():
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: DshSpace.md),
        child: DshDivider(),
      );

    case DocTable(:final rows):
      return _DocTable(rows: rows, ctx: ctx);

    case DocMathBlock(:final tex, :final tag):
      // 显示式公式：module 轻底静区分隔，尺寸跟随正文字号
      return Padding(
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
          child: DisplayMath(tex, style: ctx.bodyStyle(context), tag: tag),
        ),
      );

    case DocRaw(:final text):
      return Padding(
        padding: const EdgeInsets.only(bottom: DshSpace.md),
        child: Text(text, style: ctx.bodyStyle(context)),
      );
  }
}

// ══════════════════════════════════════════════════════════════════
// 行内
// ══════════════════════════════════════════════════════════════════

class _RichBlock extends StatelessWidget {
  final List<DocInline> spans;
  final DocRenderCtx ctx;
  final TextStyle style;
  final String? align;
  const _RichBlock({required this.spans, required this.ctx, required this.style, this.align});

  @override
  Widget build(BuildContext context) {
    final textAlign = switch (align) {
      'center' => TextAlign.center,
      'right' => TextAlign.right,
      'justify' || 'both' => TextAlign.justify,
      _ => TextAlign.start,
    };
    return Text.rich(
      TextSpan(children: inlineSpans(context, spans, style, ctx.scale), style: style),
      style: style,
      textAlign: textAlign,
    );
  }
}

/// 行内代码：mdCode + inlineCode 底 + R4 + 左右 4px（与 md.dart 同一视觉语言）。
class _InlineCodeChip extends StatelessWidget {
  const _InlineCodeChip(this.text);

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

/// 行内 → InlineSpan 列表。
///
/// 公式与链接用 WidgetSpan（公式需要真正的排版盒子；链接需要点击热区），
/// 其余为 TextSpan。WidgetSpan 一律按基线对齐，避免行高被撑破。
List<InlineSpan> inlineSpans(BuildContext c, List<DocInline> spans, TextStyle base, double scale) {
  final palette = DshPalette.of(c);
  final baseSize = base.fontSize ?? _mdBaseSize;
  final out = <InlineSpan>[];
  for (final s in spans) {
    switch (s) {
      case DocText():
        if (s.text.isEmpty) break;
        if (s.code) {
          // 行内代码整段走圆角底片（TextSpan 画不出内边距与圆角）
          out.add(WidgetSpan(
            alignment: PlaceholderAlignment.baseline,
            baseline: TextBaseline.alphabetic,
            child: _InlineCodeChip(s.text),
          ));
          break;
        }
        var st = base;
        if (s.bold) st = st.copyWith(fontWeight: FontWeight.w600);
        if (s.italic) st = st.copyWith(fontStyle: FontStyle.italic);
        if (s.underline) st = st.copyWith(decoration: TextDecoration.underline);
        if (s.strike) st = st.copyWith(decoration: TextDecoration.lineThrough);
        if (s.sizeScale != null) {
          st = st.copyWith(fontSize: baseSize * s.sizeScale!.clamp(0.6, 2.0));
        }
        if (s.colorHex != null) {
          final col = _parseColor(s.colorHex!);
          if (col != null) st = st.copyWith(color: col);
        }
        if (s.superscript || s.subscript) {
          // Flutter 没有原生上下标：缩小字号 + 平移近似（比例跟随当前正文字号）
          final fs = baseSize * _scriptScale;
          out.add(WidgetSpan(
            alignment: PlaceholderAlignment.baseline,
            baseline: TextBaseline.alphabetic,
            child: Transform.translate(
              offset: Offset(0, s.superscript ? -fs * 0.45 : fs * 0.28),
              child: Text(s.text, style: st.copyWith(fontSize: fs)),
            ),
          ));
          break;
        }
        out.add(TextSpan(text: s.text, style: st));

      case DocBreak():
        out.add(const TextSpan(text: '\n'));

      case DocLink(:final spans, :final url):
        final label = spans.map((e) => e is DocText ? e.text : '').join();
        if (url == null) {
          out.add(TextSpan(text: label, style: base));
        } else {
          out.add(WidgetSpan(
            alignment: PlaceholderAlignment.baseline,
            baseline: TextBaseline.alphabetic,
            child: GestureDetector(
              onTap: () => openDocLink(c, url),
              child: Text(
                label.isEmpty ? url : label,
                // 链接：link 色 + w500，静止态无下划线（官方规则）
                style: base.copyWith(
                  color: palette.link,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ));
        }

      case DocMathInline(:final tex):
        out.add(WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: InlineMath(tex, style: base.copyWith(color: palette.ink)),
        ));

      case DocImage(:final alt):
        final label = (alt == null || alt.isEmpty) ? L10n.t('图片', 'Image') : alt;
        out.add(WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: DshSpace.sm,
              vertical: DshSpace.xxs,
            ),
            decoration: BoxDecoration(
              color: palette.tag,
              borderRadius: DshRadius.rSm,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.image_outlined, size: DshSpace.md * scale, color: palette.ink2),
                const SizedBox(width: DshSpace.xs),
                Text(
                  label,
                  style: base.copyWith(
                    fontSize: baseSize * _imageLabelScale,
                    color: palette.ink2,
                  ),
                ),
              ],
            ),
          ),
        ));
    }
  }
  return out;
}

/// 上下标相对正文字号的缩放比。
const double _scriptScale = 0.72;

/// 图片占位标签相对正文字号的缩放比。
const double _imageLabelScale = 0.85;

Color? _parseColor(String hex) {
  final h = hex.replaceAll('#', '').trim();
  if (h.length != 6) return null;
  final v = int.tryParse(h, radix: 16);
  if (v == null) return null;
  // 文档自带的 w:color（内容而非样式令牌）——按 ARGB 还原，不用十六进制字面量
  return Color.fromARGB(255, (v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF);
}

// ══════════════════════════════════════════════════════════════════
// 代码块 / 表格
// ══════════════════════════════════════════════════════════════════

/// 横向滚动容器：滚动条外观一律取主题 scrollbarTheme，不在本地覆写。
class _HScroll extends StatefulWidget {
  const _HScroll({required this.child});

  final Widget child;

  @override
  State<_HScroll> createState() => _HScrollState();
}

class _HScrollState extends State<_HScroll> {
  final _ctrl = ScrollController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scrollbar(
        controller: _ctrl,
        child: SingleChildScrollView(
          controller: _ctrl,
          scrollDirection: Axis.horizontal,
          child: widget.child,
        ),
      );
}

/// 代码块：官方 markdown-code-block——R16 + codeBlock 底 + codeBanner 标题条 + 复制。
class _DocCodeBlock extends StatefulWidget {
  const _DocCodeBlock({required this.text, required this.lang, required this.ctx});

  final String text;
  final String? lang;
  final DocRenderCtx ctx;

  @override
  State<_DocCodeBlock> createState() => _DocCodeBlockState();
}

class _DocCodeBlockState extends State<_DocCodeBlock> {
  @override
  Widget build(BuildContext context) {
    final c = DshPalette.of(context);
    final lines = widget.text.split('\n').length;
    final lang = widget.lang;
    final label = (lang != null && lang.isNotEmpty)
        ? lang
        : L10n.t('代码 · $lines 行', 'Code · $lines lines');

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: DshSpace.sm),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: c.codeBlock,
        borderRadius: DshRadius.rLg,
        border: Border.fromBorderSide(DshStroke.side(c.line2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
                Expanded(
                  child: Text(
                    label,
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
                    Clipboard.setData(ClipboardData(text: widget.text));
                    showToast(context, L10n.t('已复制代码', 'Copied code'));
                  },
                ),
              ],
            ),
          ),
          // 亮色下 codeBanner 与 codeBlock 同色，补一条发丝线分层
          const DshDivider(),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 420),
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(DshSpace.md),
                // 代码块横向滚动，不挤压换行；字号随阅读缩放走
                child: _HScroll(
                  child: Text(
                    widget.text,
                    style: _scaled(DshType.mdCodeBlock, widget.ctx, color: c.ink),
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

/// 文档表格：mdTable 正文 / mdTableHead 表头 + line2 发丝分隔，超宽横向滚动。
class _DocTable extends StatelessWidget {
  const _DocTable({required this.rows, required this.ctx});

  final List<List<DocCell>> rows;
  final DocRenderCtx ctx;

  @override
  Widget build(BuildContext context) {
    final c = DshPalette.of(context);
    if (rows.isEmpty) return const SizedBox.shrink();
    final cols = rows.map((r) => r.length).fold<int>(1, (a, b) => b > a ? b : a);

    return Padding(
      padding: const EdgeInsets.only(bottom: DshSpace.md),
      child: _HScroll(
        child: Container(
          decoration: BoxDecoration(
            border: Border.fromBorderSide(DshStroke.side(c.line2)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var r = 0; r < rows.length; r++)
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var k = 0; k < cols; k++)
                        _cell(
                          context,
                          c,
                          k < rows[r].length ? rows[r][k] : DocCell.empty,
                          isHeader: k < rows[r].length && rows[r][k].header,
                          lastRow: r == rows.length - 1,
                          lastCol: k == cols - 1,
                          ctx: ctx,
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

Widget _cell(
  BuildContext context,
  DshPalette c,
  DocCell cell, {
  required bool isHeader,
  required bool lastRow,
  required bool lastCol,
  required DocRenderCtx ctx,
}) {
  final style = _scaled(
    isHeader ? DshType.mdTableHead : DshType.mdTable,
    ctx,
    color: c.ink,
  );
  final align = switch (cell.align) {
    'center' => TextAlign.center,
    'right' => TextAlign.right,
    _ => TextAlign.start,
  };
  return Container(
    constraints: BoxConstraints(
      minWidth: 56 * ctx.scale,
      maxWidth: 300 * ctx.scale,
    ),
    padding: const EdgeInsets.symmetric(
      horizontal: DshSpace.sm,
      vertical: DshSpace.xs,
    ),
    decoration: BoxDecoration(
      color: isHeader ? c.module : null,
      border: Border(
        right: lastCol
            ? BorderSide.none
            : BorderSide(color: c.line2, width: DshStroke.hairline),
        bottom: lastRow
            ? BorderSide.none
            : BorderSide(color: c.line2, width: DshStroke.hairline),
      ),
    ),
    child: Text.rich(
      TextSpan(children: inlineSpans(context, cell.spans, style, ctx.scale), style: style),
      style: style,
      textAlign: align,
    ),
  );
}

// ══════════════════════════════════════════════════════════════════
// 电子表格
// ══════════════════════════════════════════════════════════════════

/// 渲染一张工作表：行列头 + 双向滚动 + 可点超链接。
class SheetView extends StatelessWidget {
  final Sheet sheet;
  final DocRenderCtx ctx;
  const SheetView(this.sheet, {super.key, required this.ctx});

  @override
  Widget build(BuildContext context) {
    final c = DshPalette.of(context);
    final rows = sheet.rows;
    final cols = sheet.maxCol;
    final fs = (DshType.mdTable.fontSize ?? _mdBaseSize) * ctx.scale;

    if (rows.isEmpty) {
      return DshEmpty(
        icon: Icons.grid_off_outlined,
        title: L10n.t('（空工作表）', '(empty sheet)'),
        compact: true,
      );
    }

    BorderSide gridSide() => BorderSide(color: c.line2, width: DshStroke.hairline);
    BoxDecoration headerCell() => BoxDecoration(
          color: c.module,
          border: Border(right: gridSide(), bottom: gridSide()),
        );

    return SingleChildScrollView(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  width: _rowHeaderW,
                  height: DshSpace.xxl,
                  decoration: headerCell(),
                ),
                for (var k = 0; k < cols; k++)
                  Container(
                    width: _colWidth(k, fs),
                    height: DshSpace.xxl,
                    alignment: Alignment.center,
                    decoration: headerCell(),
                    child: Text(
                      _colName(k),
                      style: _scaled(DshType.xxsStrong12, ctx, color: c.ink3),
                    ),
                  ),
              ],
            ),
            for (var r = 0; r < rows.length; r++)
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      width: _rowHeaderW,
                      alignment: Alignment.center,
                      decoration: headerCell(),
                      child: Text(
                        '${r + 1}',
                        style: _scaled(DshType.xxs12, ctx, color: c.ink3),
                      ),
                    ),
                    for (var k = 0; k < cols; k++) _sheetCell(context, c, rows[r], k, fs),
                  ],
                ),
              ),
            const SizedBox(height: DshSpace.xxl),
          ],
        ),
      ),
    );
  }
}

/// 行号列宽（4 的倍数）。
const double _rowHeaderW = 40;

Widget _sheetCell(BuildContext context, DshPalette c, List<SheetCell> row, int k, double fs) {
  final cell = k < row.length ? row[k] : null;
  final text = cell?.text ?? '';
  final url = cell?.url;
  final style = DshType.mdTable.copyWith(fontSize: fs, color: c.ink);
  return Container(
    width: _colWidth(k, fs),
    padding: const EdgeInsets.symmetric(
      horizontal: DshSpace.sm,
      vertical: DshSpace.xs,
    ),
    decoration: BoxDecoration(
      border: Border(
        right: BorderSide(color: c.line2, width: DshStroke.hairline),
        bottom: BorderSide(color: c.line2, width: DshStroke.hairline),
      ),
    ),
    child: url != null
        ? GestureDetector(
            onTap: () => openDocLink(context, url),
            child: Text(
              text.isEmpty ? url : text,
              style: style.copyWith(
                color: c.link,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          )
        : Text(text, style: style, maxLines: 6, overflow: TextOverflow.ellipsis),
  );
}

double _colWidth(int k, double fs) {
  // 简单自适应：前两列宽一些（表格常见形态），其余固定；随阅读缩放线性放大
  final base = k < 2 ? 112.0 : 88.0;
  return base * (fs / (DshType.mdTable.fontSize ?? _mdBaseSize));
}

String _colName(int k) {
  var c = k;
  final b = StringBuffer();
  while (true) {
    b.write(String.fromCharCode(65 + (c % 26)));
    c = c ~/ 26 - 1;
    if (c < 0) break;
  }
  return b.toString().split('').reversed.join();
}
