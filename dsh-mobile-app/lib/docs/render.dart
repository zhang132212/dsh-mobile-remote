// 文档渲染层（v3.2.0）——把 docs/model.dart 的块模型渲染成 Widget。
// md / txt / docx / xlsx 四种来源归一到这里，所以「各格式特色」由模型承载、
// 呈现保持一致；公式一律走 math/view.dart（flutter_math_fork）。
//
// 设计：整篇文档是一个 `DocBlocks` widget，context 自上而下显式传递
// （不用全局槽位——那样 rebuild 顺序一变就取错主题色）。
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api.dart';
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

  double get body => 15.0 * scale;

  TextStyle bodyStyle(BuildContext c) =>
      TextStyle(fontSize: body, height: 1.7, color: DshColors.ink(c));
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
    showToast(context, '链接无法解析');
    return;
  }
  if (uri.scheme != 'http' && uri.scheme != 'https') {
    showToast(context, '非网页链接：$url');
    return;
  }
  final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!ok && context.mounted) showToast(context, '无法打开链接');
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

Widget _block(BuildContext c, DocBlock b, DocRenderCtx ctx) {
  switch (b) {
    case DocHeading(:final level, :final spans):
      return Padding(
        padding: EdgeInsets.only(top: level == 1 ? 20 : 16, bottom: 6),
        child: _RichBlock(
          spans: spans,
          ctx: ctx,
          style: TextStyle(
            fontSize: (switch (level) {
                  1 => 21.0,
                  2 => 18.5,
                  3 => 16.5,
                  _ => 15.5,
                }) *
                ctx.scale,
            fontWeight: FontWeight.w700,
            height: 1.35,
            color: DshColors.ink(c),
          ),
        ),
      );

    case DocPara(:final spans, :final align):
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: _RichBlock(spans: spans, ctx: ctx, style: ctx.bodyStyle(c), align: align),
      );

    case DocList(:final items, :final ordered, :final start):
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < items.length; i++)
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 26 * ctx.scale,
                      child: Text(
                        ordered ? '${start + i}.' : '•',
                        style: TextStyle(fontSize: ctx.body, color: DshColors.ink2(c), height: 1.7),
                      ),
                    ),
                    Expanded(child: _RichBlock(spans: items[i], ctx: ctx, style: ctx.bodyStyle(c))),
                  ],
                ),
              ),
          ],
        ),
      );

    case DocCode(:final text, :final lang):
      return _codeBlock(c, text, lang, ctx);

    case DocQuote(:final spans):
      return Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
        decoration: BoxDecoration(
          color: DshColors.brandSoft(c),
          borderRadius: const BorderRadius.horizontal(right: Radius.circular(8)),
        ),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 3, margin: const EdgeInsets.only(right: 10), color: DshColors.brand(c)),
              Expanded(
                child: _RichBlock(
                  spans: spans,
                  ctx: ctx,
                  style: ctx.bodyStyle(c).copyWith(color: DshColors.ink2(c), fontSize: ctx.body * 0.95),
                ),
              ),
            ],
          ),
        ),
      );

    case DocRule():
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Divider(color: DshColors.line(c), height: 1),
      );

    case DocTable(:final rows):
      return _table(c, rows, ctx);

    case DocMathBlock(:final tex, :final tag):
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 10),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        decoration: BoxDecoration(
          color: DshColors.brandSoft(c),
          borderRadius: BorderRadius.circular(8),
        ),
        child: DisplayMath(tex, style: ctx.bodyStyle(c).copyWith(height: 1.3), tag: tag),
      );

    case DocRaw(:final text):
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(text, style: ctx.bodyStyle(c)),
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

/// 行内 → InlineSpan 列表。
///
/// 公式与链接用 WidgetSpan（公式需要真正的排版盒子；链接需要点击热区），
/// 其余为 TextSpan。WidgetSpan 一律按基线对齐，避免行高被撑破。
List<InlineSpan> inlineSpans(BuildContext c, List<DocInline> spans, TextStyle base, double scale) {
  final out = <InlineSpan>[];
  for (final s in spans) {
    switch (s) {
      case DocText():
        if (s.text.isEmpty) break;
        var st = base;
        if (s.bold) st = st.copyWith(fontWeight: FontWeight.w700);
        if (s.italic) st = st.copyWith(fontStyle: FontStyle.italic);
        if (s.underline) st = st.copyWith(decoration: TextDecoration.underline);
        if (s.strike) st = st.copyWith(decoration: TextDecoration.lineThrough);
        if (s.code) {
          st = st.copyWith(
            fontFamily: 'monospace',
            fontSize: (base.fontSize ?? 15) * 0.93,
            backgroundColor: DshColors.line(c).withValues(alpha: 0.55),
          );
        }
        if (s.sizeScale != null) {
          st = st.copyWith(fontSize: (base.fontSize ?? 15) * s.sizeScale!.clamp(0.6, 2.0));
        }
        if (s.colorHex != null) {
          final col = _parseColor(s.colorHex!);
          if (col != null) st = st.copyWith(color: col);
        }
        if (s.superscript || s.subscript) {
          // Flutter 没有原生上下标：缩小字号 + 平移近似
          final fs = (base.fontSize ?? 15) * 0.72;
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
                style: base.copyWith(
                  color: DshColors.brand(c),
                  decoration: TextDecoration.underline,
                  decorationColor: DshColors.brand(c),
                ),
              ),
            ),
          ));
        }

      case DocMathInline(:final tex):
        out.add(WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: InlineMath(tex, style: base.copyWith(fontSize: (base.fontSize ?? 15) * 1.02)),
        ));

      case DocImage(:final alt):
        out.add(WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: DshColors.line(c),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.image_outlined, size: 13 * scale, color: DshColors.ink2(c)),
                const SizedBox(width: 3),
                Text(
                  alt ?? '图片',
                  style: base.copyWith(fontSize: (base.fontSize ?? 15) * 0.85, color: DshColors.ink2(c)),
                ),
              ],
            ),
          ),
        ));
    }
  }
  return out;
}

Color? _parseColor(String hex) {
  final h = hex.replaceAll('#', '').trim();
  if (h.length != 6) return null;
  final v = int.tryParse(h, radix: 16);
  if (v == null) return null;
  return Color(0xFF000000 | v);
}

// ══════════════════════════════════════════════════════════════════
// 代码块 / 表格
// ══════════════════════════════════════════════════════════════════

Widget _codeBlock(BuildContext c, String text, String? lang, DocRenderCtx ctx) {
  final lines = text.split('\n').length;
  return Container(
    width: double.infinity,
    margin: const EdgeInsets.symmetric(vertical: 8),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: DshColors.surface(c),
      border: Border.all(color: DshColors.line(c)),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              (lang != null && lang.isNotEmpty) ? lang : '代码 · $lines 行',
              style: TextStyle(fontSize: 10.5, color: DshColors.ink2(c)),
            ),
            const Spacer(),
            InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: () {
                Clipboard.setData(ClipboardData(text: text));
                showToast(c, '已复制代码');
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.copy_all, size: 13, color: DshColors.ink2(c)),
                    const SizedBox(width: 3),
                    Text('复制', style: TextStyle(fontSize: 10.5, color: DshColors.ink2(c))),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 420),
          child: SingleChildScrollView(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Text(
                text,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12.5 * ctx.scale,
                  height: 1.5,
                  color: DshColors.ink(c),
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

Widget _table(BuildContext c, List<List<DocCell>> rows, DocRenderCtx ctx) {
  if (rows.isEmpty) return const SizedBox.shrink();
  final cols = rows.map((r) => r.length).fold<int>(1, (a, b) => b > a ? b : a);
  final fs = 13.0 * ctx.scale;

  return SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(border: Border.all(color: DshColors.line(c))),
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
                      c,
                      k < rows[r].length ? rows[r][k] : DocCell.empty,
                      isHeader: k < rows[r].length && rows[r][k].header,
                      lastRow: r == rows.length - 1,
                      lastCol: k == cols - 1,
                      fs: fs,
                      ctx: ctx,
                    ),
                ],
              ),
            ),
        ],
      ),
    ),
  );
}

Widget _cell(
  BuildContext c,
  DocCell cell, {
  required bool isHeader,
  required bool lastRow,
  required bool lastCol,
  required double fs,
  required DocRenderCtx ctx,
}) {
  final style = TextStyle(
    fontSize: fs,
    fontWeight: isHeader ? FontWeight.w600 : FontWeight.w400,
    color: DshColors.ink(c),
    height: 1.4,
  );
  final align = switch (cell.align) {
    'center' => TextAlign.center,
    'right' => TextAlign.right,
    _ => TextAlign.start,
  };
  return Container(
    constraints: BoxConstraints(minWidth: 56 * ctx.scale, maxWidth: 300 * ctx.scale),
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
    decoration: BoxDecoration(
      color: isHeader ? DshColors.line(c) : null,
      border: Border(
        right: lastCol ? BorderSide.none : BorderSide(color: DshColors.line(c)),
        bottom: lastRow ? BorderSide.none : BorderSide(color: DshColors.line(c)),
      ),
    ),
    child: Text.rich(
      TextSpan(children: inlineSpans(c, cell.spans, style, ctx.scale), style: style),
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
    final rows = sheet.rows;
    final cols = sheet.maxCol;
    final fs = 12.5 * ctx.scale;
    const rowHeaderW = 42.0;

    if (rows.isEmpty) {
      return Center(
        child: Text('（空工作表）', style: TextStyle(color: DshColors.ink2(context))),
      );
    }

    BoxDecoration gridCellBorder() => BoxDecoration(border: Border.all(color: DshColors.line(context)));

    return SingleChildScrollView(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(width: rowHeaderW, height: 26, decoration: gridCellBorder()),
                for (var k = 0; k < cols; k++)
                  Container(
                    width: _colWidth(k, fs),
                    height: 26,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: DshColors.line(context),
                      border: Border.all(color: DshColors.line(context)),
                    ),
                    child: Text(
                      _colName(k),
                      style: TextStyle(
                        fontSize: 11 * ctx.scale,
                        fontWeight: FontWeight.w600,
                        color: DshColors.ink2(context),
                      ),
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
                      width: rowHeaderW,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: DshColors.line(context),
                        border: Border.all(color: DshColors.line(context)),
                      ),
                      child: Text(
                        '${r + 1}',
                        style: TextStyle(fontSize: 11 * ctx.scale, color: DshColors.ink2(context)),
                      ),
                    ),
                    for (var k = 0; k < cols; k++) _sheetCell(context, rows[r], k, fs),
                  ],
                ),
              ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

Widget _sheetCell(BuildContext c, List<SheetCell> row, int k, double fs) {
  final cell = k < row.length ? row[k] : null;
  final text = cell?.text ?? '';
  final url = cell?.url;
  final style = TextStyle(fontSize: fs, color: DshColors.ink(c), height: 1.4);
  return Container(
    width: _colWidth(k, fs),
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
    decoration: BoxDecoration(
      border: Border(
        right: BorderSide(color: DshColors.line(c)),
        bottom: BorderSide(color: DshColors.line(c)),
      ),
    ),
    child: url != null
        ? GestureDetector(
            onTap: () => openDocLink(c, url),
            child: Text(
              text.isEmpty ? url : text,
              style: style.copyWith(
                color: DshColors.brand(c),
                decoration: TextDecoration.underline,
                decorationColor: DshColors.brand(c),
              ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          )
        : Text(text, style: style, maxLines: 6, overflow: TextOverflow.ellipsis),
  );
}

double _colWidth(int k, double fs) {
  // 简单自适应：前两列宽一些（表格常见形态），其余固定
  final base = k < 2 ? 110.0 : 88.0;
  return base * (fs / 12.5);
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
