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
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';

import '../api.dart';
import '../dsh_kit.dart';
import '../l10n.dart';
import '../logger.dart';
import '../math/view.dart';
import '../theme.dart';
import '../toast.dart';
import 'link.dart';
import 'model.dart';
import 'sheet.dart';

/// 渲染参数：字号缩放（阅读页「字号 +/−」控制），1.0 为基准。
///
/// v3.2.4：图片链路要落地，光有 scale 不够 —— 渲染器还需要「去哪儿取图」：
///   · [api]     ：按绝对路径把字节从电脑上拉下来（走 /api/files）
///   · [baseDir] ：本地文档所在目录，用于解析 `![](图/x.png)` 这类相对路径
///   · [baseUrl] ：网络文档的基址，用于解析相对图片 URL
class DocRenderCtx {
  final double scale;
  final Api? api;
  final String? baseDir;
  final String? baseUrl;

  /// 树形结构（XML / JSON）的展开状态控制器。
  ///
  /// 放在渲染上下文里而不是树 widget 内部：阅读页「更多」菜单的
  /// 「全部展开 / 全部折叠」和正文里的单节点点击要共享同一份状态，
  /// 下拉重建（滚动 / 改字号）时也不该把用户展开的层级丢掉。
  final DocTreeController? tree;
  const DocRenderCtx({
    this.scale = 1.0,
    this.api,
    this.baseDir,
    this.baseUrl,
    this.tree,
  });

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

    // v3.2.11：数据结构类文档——XML / JSON 树、SVG 矢量图
    case DocTree(:final roots):
      return DocTreeView(roots: roots, ctx: ctx);

    case DocSvg(:final doc, :final source):
      return SvgView(doc: doc, source: source, ctx: ctx);
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
      TextSpan(children: inlineSpans(context, spans, style, ctx), style: style),
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
List<InlineSpan> inlineSpans(BuildContext c, List<DocInline> spans, TextStyle base, DocRenderCtx ctx) {
  // 合并后：签名用发行线的 ctx（DocImageView 取图需要 baseDir/scale），
  // 函数体仍是我方重写过的版本，这里补回它依赖的两个局部量。
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

      case DocImage(:final url, :final alt):
        // v3.2.4：真渲染图片（此前只画一个占位 chip）
        out.add(WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: DocImageView(src: url, alt: alt, ctx: ctx, base: base),
        ));
    }
  }
  return out;
}

/// 把文档里的图片 src 解析成**电脑上的绝对路径**（解析不出来返回 null）。
///
/// 必须用 `p.windows` 上下文：文档都在电脑上，是 Windows 路径；
/// 而 App 跑在 Android（POSIX）。默认上下文下 `p.dirname(r'D:\a\b.md')`
/// 会因为找不到 `/` 而返回 `.`，拼出来就是 `./图.png` —— 取图必然 ENOENT。
/// （真机实测踩中：日志里出现 `DocImage: 按路径取图失败 ./图5-受控源电路.png`。）
String? resolveDocImagePath({required String src, String? baseDir}) {
  final s = src.trim();
  if (s.isEmpty) return null;
  final win = p.windows;
  final norm = s.replaceAll('\\', '/');
  if (win.isAbsolute(norm)) return norm;
  final base = baseDir ?? '';
  if (base.isEmpty) return null;
  return win.join(base, norm);
}

/// 文档里的图片（v3.2.4）。
///
/// 此前文档里的图片只会渲染成一个「🖼 文件名」占位 chip，原因是三处叠加：
///   ① markdown 解析器**根本不认 `![](…)`**（图片语法被当普通文字）；
///   ② docx 读取器把图片二进制丢了（`DocImage(null, …)`）；
///   ③ 这里的 DocImage 分支只用了 alt，且 DocRenderCtx 手里没有取图能力。
/// 现在 ①③ 已补齐（docx 内嵌图见后续），本 widget 负责**按 src 取字节真渲染**。
///
/// 取不到图时**退回占位 chip** —— 对齐「绝不吞内容」：宁可显示文件名，也不留空白。
class DocImageView extends StatefulWidget {
  final String? src;
  final String? alt;
  final DocRenderCtx ctx;
  final TextStyle base;
  const DocImageView({
    super.key,
    required this.src,
    required this.alt,
    required this.ctx,
    required this.base,
  });

  @override
  State<DocImageView> createState() => _DocImageViewState();
}

class _DocImageViewState extends State<DocImageView> {
  /// 进程内缓存：同一张图在正文/目录里重复出现时不重复下载。
  static final Map<String, Uint8List> _cache = <String, Uint8List>{};
  static const int _cacheCap = 24;

  Uint8List? _bytes;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(DocImageView old) {
    super.didUpdateWidget(old);
    if (old.src != widget.src) {
      _done = false;
      _bytes = null;
      _load();
    }
  }

  static void _remember(String key, Uint8List bytes) {
    if (_cache.length >= _cacheCap) _cache.remove(_cache.keys.first);
    _cache[key] = bytes;
  }

  void _hit(String key, Uint8List bytes) {
    _remember(key, bytes);
    if (mounted) {
      setState(() {
        _bytes = bytes;
        _done = true;
      });
    }
  }

  Future<void> _load() async {
    final src = (widget.src ?? '').trim();
    if (src.isEmpty) {
      if (mounted) setState(() => _done = true);
      return;
    }

    final uri = Uri.tryParse(src);
    final isHttp = uri != null && (uri.scheme == 'http' || uri.scheme == 'https');

    // ① 网络图：绝对 URL，或相对 URL 按文档基址解析
    if (isHttp) {
      await _fromNetwork(uri);
      return;
    }
    final baseUrl = widget.ctx.baseUrl;
    if (uri != null && !uri.hasScheme && baseUrl != null && baseUrl.isNotEmpty) {
      final base = Uri.tryParse(baseUrl);
      if (base != null) {
        await _fromNetwork(base.resolveUri(uri));
        return;
      }
    }

    // ② 本地文件：绝对路径直接用；相对路径按「文档所在目录」拼
    final abs = resolveDocImagePath(src: src, baseDir: widget.ctx.baseDir);
    final api = widget.ctx.api;
    if (abs != null && api != null) {
      final hit = _cache[abs];
      if (hit != null) {
        _hit(abs, hit);
        return;
      }
      try {
        final bytes = await api.downloadFile(abs);
        if (bytes.isNotEmpty) {
          _hit(abs, bytes);
          return;
        }
      } catch (e) {
        AppLog.instance.log('DocImage: 按路径取图失败 $abs → $e');
      }
    }
    if (mounted) setState(() => _done = true);
  }

  Future<void> _fromNetwork(Uri uri) async {
    final key = uri.toString();
    final hit = _cache[key];
    if (hit != null) {
      _hit(key, hit);
      return;
    }
    try {
      final r = await http.get(uri).timeout(const Duration(seconds: 20));
      if (r.statusCode == 200 && r.bodyBytes.isNotEmpty) {
        _hit(key, r.bodyBytes);
        return;
      }
    } catch (e) {
      AppLog.instance.log('DocImage: 下载图片失败 $key → $e');
    }
    if (mounted) setState(() => _done = true);
  }

  /// 取不到图时的占位（保留原有的「🖼 文件名」观感）。
  Widget _placeholder({required bool loading}) {
    final c = context;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: DshColors.line(c),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.image_outlined, size: 13 * widget.ctx.scale, color: DshColors.ink2(c)),
          const SizedBox(width: 3),
          Text(
            loading ? '加载图片…' : (widget.alt ?? widget.src ?? '图片'),
            style: widget.base.copyWith(
              fontSize: (widget.base.fontSize ?? 15) * 0.85,
              color: DshColors.ink2(c),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _bytes;
    if (bytes == null) return _placeholder(loading: !_done);

    // 单独成段的图片给足宽度；行内图片也不会撑破屏幕。
    final screen = MediaQuery.of(context).size.width;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: (screen - 48).clamp(120.0, 1200.0),
          maxHeight: 520,
        ),
        child: Image.memory(
          bytes,
          fit: BoxFit.contain,
          alignment: Alignment.centerLeft,
          gaplessPlayback: true,
        ),
      ),
    );
  }
}

/// 上下标相对正文字号的缩放比。
const double _scriptScale = 0.72;

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
      TextSpan(children: inlineSpans(context, cell.spans, style, ctx), style: style),
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

// ══════════════════════════════════════════════════════════════════
// 树形结构（XML / JSON）
// ══════════════════════════════════════════════════════════════════

/// 树形视图的展开状态控制器（由阅读页持有，见 DocRenderCtx.tree）。
class DocTreeController extends ChangeNotifier {
  /// true = 全部展开，false = 全部折叠，null = 用视图默认（展开前两层）。
  bool? expand;

  void expandAll() {
    expand = true;
    notifyListeners();
  }

  void collapseAll() {
    expand = false;
    notifyListeners();
  }
}

/// 可折叠树视图：XML / JSON 共用的「数据结构」呈现。
///
/// 默认展开前两层——顶层键 / 根元素一眼可见，深层内容点开再看，
/// 既不糊一屏源码，也不让人为了看一个字段点十次。
class DocTreeView extends StatefulWidget {
  const DocTreeView({super.key, required this.roots, required this.ctx});

  final List<TreeNode> roots;
  final DocRenderCtx ctx;

  @override
  State<DocTreeView> createState() => _DocTreeViewState();
}

class _DocTreeViewState extends State<DocTreeView> {
  /// 已展开节点的路径集合（路径 = 子节点下标链，如 /0/2/1）。
  final Set<String> _expanded = {};
  bool _seeded = false;

  @override
  void initState() {
    super.initState();
    widget.ctx.tree?.addListener(_applyController);
  }

  @override
  void dispose() {
    widget.ctx.tree?.removeListener(_applyController);
    super.dispose();
  }

  void _applyController() {
    final ctrl = widget.ctx.tree;
    if (ctrl == null || ctrl.expand == null) return;
    setState(() {
      _expanded.clear();
      if (ctrl.expand == true) _addAll(widget.roots, '');
      _seeded = true;
    });
  }

  void _addAll(List<TreeNode> nodes, String prefix) {
    for (var i = 0; i < nodes.length; i++) {
      final path = '$prefix/$i';
      if (nodes[i].children.isNotEmpty) _expanded.add(path);
      _addAll(nodes[i].children, path);
    }
  }

  void _seed() {
    if (_seeded) return;
    _seeded = true;
    void walk(List<TreeNode> nodes, String prefix, int depth) {
      for (var i = 0; i < nodes.length; i++) {
        final path = '$prefix/$i';
        if (nodes[i].children.isNotEmpty && depth < 2) _expanded.add(path);
        if (depth < 2) walk(nodes[i].children, path, depth + 1);
      }
    }

    walk(widget.roots, '', 0);
  }

  @override
  Widget build(BuildContext context) {
    _seed();
    final c = DshPalette.of(context);
    final rows = <Widget>[];
    void walk(List<TreeNode> nodes, String prefix, int depth) {
      for (var i = 0; i < nodes.length; i++) {
        final node = nodes[i];
        final path = '$prefix/$i';
        final expanded = _expanded.contains(path);
        rows.add(_TreeRow(
          node: node,
          depth: depth,
          expanded: expanded,
          onToggle: node.isLeaf
              ? null
              : () => setState(() {
                    if (!_expanded.remove(path)) _expanded.add(path);
                  }),
        ));
        if (expanded && node.children.isNotEmpty) walk(node.children, path, depth + 1);
      }
    }

    walk(widget.roots, '', 0);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: DshSpace.md),
      padding: const EdgeInsets.symmetric(vertical: DshSpace.xs),
      decoration: BoxDecoration(
        color: c.module,
        borderRadius: DshRadius.rMd,
        border: Border.fromBorderSide(DshStroke.side(c.line2)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: rows),
    );
  }
}

/// 一行树节点：缩进 + 折叠箭头 + 名称 + 类型徽标 + 属性 + 文本。
class _TreeRow extends StatelessWidget {
  const _TreeRow({
    required this.node,
    required this.depth,
    required this.expanded,
    this.onToggle,
  });

  final TreeNode node;
  final int depth;
  final bool expanded;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    final c = DshPalette.of(context);
    return InkWell(
      onTap: onToggle,
      child: Padding(
        padding: EdgeInsets.only(
          left: DshSpace.xs + depth * 14.0,
          right: DshSpace.sm,
          top: 2,
          bottom: 2,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 18,
              height: 20,
              child: onToggle == null
                  ? null
                  : Icon(
                      expanded ? Icons.expand_more : Icons.chevron_right,
                      size: 16,
                      color: c.ink3,
                    ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: DshSpace.xs,
                    runSpacing: 2,
                    children: [
                      Text(
                        node.name,
                        style: DshType.mdCode.copyWith(
                          color: c.ink,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (node.kind != null) _kindBadge(context, node.kind!),
                      for (final attr in node.attrs.take(6))
                        Text(
                          '${attr.name}="${attr.value}"',
                          style: DshType.xxs12.copyWith(color: c.ink3),
                        ),
                      if (node.attrs.length > 6)
                        Text(
                          '+${node.attrs.length - 6}',
                          style: DshType.xxs12.copyWith(color: c.ink3),
                        ),
                    ],
                  ),
                  if (node.text != null && node.text!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 1),
                      child: Text(
                        node.text!,
                        style: DshType.xs13.copyWith(color: c.ink2),
                        maxLines: 6,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _kindBadge(BuildContext context, String kind) {
    final c = DshPalette.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: c.brandSoft,
        borderRadius: DshRadius.rXs,
      ),
      child: Text(
        kind,
        style: DshType.xxs12.copyWith(color: c.ink3, fontSize: 10),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
// SVG 矢量图（纯 Dart CustomPainter）
// ══════════════════════════════════════════════════════════════════

/// SVG 图形视图：白底卡片 + 等比缩放 + 可展开的源码。
///
/// 白底是刻意的：绝大多数 SVG 是按浅色页面画的（白底黑线），
/// 直接铺在深色阅读页上会「看不见」；卡片也让图形与正文有明确边界。
class SvgView extends StatelessWidget {
  const SvgView({super.key, required this.doc, required this.source, required this.ctx});

  final SvgDoc doc;
  final String source;
  final DocRenderCtx ctx;

  @override
  Widget build(BuildContext context) {
    final c = DshPalette.of(context);
    final aspect = (doc.width > 0 && doc.height > 0) ? doc.width / doc.height : 2.0;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: DshSpace.md),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: const Color(0xFFFFFFFF),
        borderRadius: DshRadius.rLg,
        border: Border.fromBorderSide(DshStroke.side(c.line2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(DshSpace.md),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final maxW = constraints.maxWidth;
                var w = maxW;
                var h = aspect > 0 ? w / aspect : w / 2;
                final maxH = 460 * ctx.scale;
                if (h > maxH) {
                  h = maxH;
                  w = h * aspect;
                }
                return Center(
                  child: SizedBox(
                    width: w,
                    height: h,
                    child: CustomPaint(painter: SvgPainter(doc)),
                  ),
                );
              },
            ),
          ),
          const DshDivider(),
          ExpansionTile(
            tilePadding: const EdgeInsets.symmetric(horizontal: DshSpace.md),
            childrenPadding:
                const EdgeInsets.fromLTRB(DshSpace.sm, 0, DshSpace.sm, DshSpace.sm),
            shape: const Border(),
            collapsedShape: const Border(),
            iconColor: c.ink3,
            collapsedIconColor: c.ink3,
            title: Text(
              L10n.t('查看 SVG 源码', 'View SVG source'),
              style: DshType.mdSmall.copyWith(color: c.ink2),
            ),
            children: [
              _DocCodeBlock(text: source, lang: 'svg', ctx: ctx),
            ],
          ),
        ],
      ),
    );
  }
}

/// SVG 画布：把图形模型画到 Canvas 上（viewBox 缩放 + transform + 填充/描边/文本）。
class SvgPainter extends CustomPainter {
  const SvgPainter(this.doc);

  final SvgDoc doc;

  @override
  void paint(Canvas canvas, Size size) {
    final vbW = doc.viewBoxW > 0 ? doc.viewBoxW : doc.width;
    final vbH = doc.viewBoxH > 0 ? doc.viewBoxH : doc.height;
    if (size.width <= 0 || size.height <= 0 || vbW <= 0 || vbH <= 0) return;
    canvas.save();
    canvas.scale(size.width / vbW, size.height / vbH);
    canvas.translate(-doc.viewBoxX, -doc.viewBoxY);
    for (final node in doc.nodes) {
      _drawNode(canvas, node, 1.0);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant SvgPainter oldDelegate) => oldDelegate.doc != doc;

  void _drawNode(Canvas canvas, SvgNode node, double parentOpacity) {
    switch (node) {
      case SvgGroup(:final children, :final transform):
        canvas.save();
        _applyTransform(canvas, transform);
        for (final child in children) {
          _drawNode(canvas, child, parentOpacity);
        }
        canvas.restore();
      case SvgShape(:final geometry, :final style, :final transform):
        canvas.save();
        _applyTransform(canvas, transform);
        final opacity = (parentOpacity * style.opacity).clamp(0.0, 1.0);
        final path = _pathOf(geometry);
        if (path != null) {
          final fill = _paintFor(style, style.fill, opacity, PaintingStyle.fill, 1.0);
          if (fill != null) canvas.drawPath(path, fill);
          final stroke = _paintFor(style, style.stroke, opacity, PaintingStyle.stroke, style.strokeWidth);
          if (stroke != null) canvas.drawPath(path, stroke);
        }
        canvas.restore();
      case SvgTextNode():
        canvas.save();
        _applyTransform(canvas, node.transform);
        _drawText(canvas, node, (parentOpacity * node.style.opacity).clamp(0.0, 1.0));
        canvas.restore();
    }
  }

  void _applyTransform(Canvas canvas, SvgTransform? t) {
    if (t == null || t.isIdentity) return;
    // SVG matrix(a b c d e f) 与 Flutter 列主序 4x4 的对应
    final storage = Float64List.fromList(<double>[
      t.a, t.b, 0, 0,
      t.c, t.d, 0, 0,
      0, 0, 1, 0,
      t.e, t.f, 0, 1,
    ]);
    canvas.transform(storage);
  }

  Paint? _paintFor(
    SvgStyle style,
    int? argb,
    double opacity,
    PaintingStyle paintingStyle,
    double strokeWidth,
  ) {
    if (argb == null) return null;
    final alpha = (((argb >> 24) & 0xFF) * opacity).round().clamp(0, 255);
    final paint = Paint()
      ..isAntiAlias = true
      ..style = paintingStyle
      ..color = Color((alpha << 24) | (argb & 0x00FFFFFF));
    if (paintingStyle == PaintingStyle.stroke) {
      paint.strokeWidth = strokeWidth <= 0 ? 1.0 : strokeWidth;
      paint.strokeCap = switch (style.lineCap) {
        'round' => StrokeCap.round,
        'square' => StrokeCap.square,
        _ => StrokeCap.butt,
      };
      paint.strokeJoin = switch (style.lineJoin) {
        'round' => StrokeJoin.round,
        'bevel' => StrokeJoin.bevel,
        _ => StrokeJoin.miter,
      };
    }
    return paint;
  }

  void _drawText(Canvas canvas, SvgTextNode node, double opacity) {
    final argb = node.style.fill;
    if (argb == null) return;
    final alpha = (((argb >> 24) & 0xFF) * opacity).round().clamp(0, 255);
    final tp = TextPainter(
      text: TextSpan(
        text: node.text,
        style: TextStyle(
          color: Color((alpha << 24) | (argb & 0x00FFFFFF)),
          fontSize: node.fontSize <= 0 ? 16 : node.fontSize,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    var dx = node.x;
    if (node.anchor == 'middle') {
      dx -= tp.width / 2;
    } else if (node.anchor == 'end') {
      dx -= tp.width;
    }
    // SVG 的 y 是基线：TextPainter 从行顶开始画，按 0.8em 近似基线偏移
    tp.paint(canvas, Offset(dx, node.y - tp.height * 0.8));
  }

  Path? _pathOf(SvgGeometry g) {
    switch (g) {
      case SvgRect(:final x, :final y, :final w, :final h, :final rx, :final ry):
        if (w <= 0 || h <= 0) return null;
        final rect = Rect.fromLTWH(x, y, w, h);
        if (rx > 0 || ry > 0) {
          final rX = rx > 0 ? rx : ry;
          final rY = ry > 0 ? ry : rx;
          return Path()
            ..addRRect(RRect.fromRectAndRadius(rect, Radius.elliptical(rX, rY)));
        }
        return Path()..addRect(rect);
      case SvgCircle(:final cx, :final cy, :final r):
        if (r <= 0) return null;
        return Path()..addOval(Rect.fromCircle(center: Offset(cx, cy), radius: r));
      case SvgEllipse(:final cx, :final cy, :final rx, :final ry):
        if (rx <= 0 || ry <= 0) return null;
        return Path()
          ..addOval(Rect.fromCenter(
            center: Offset(cx, cy),
            width: rx * 2,
            height: ry * 2,
          ));
      case SvgLineGeom(:final x1, :final y1, :final x2, :final y2):
        return Path()
          ..moveTo(x1, y1)
          ..lineTo(x2, y2);
      case SvgPoly(:final points, :final close):
        if (points.isEmpty) return null;
        final path = Path()..moveTo(points.first.$1, points.first.$2);
        for (var i = 1; i < points.length; i++) {
          path.lineTo(points[i].$1, points[i].$2);
        }
        if (close) path.close();
        return path;
      case SvgPathGeom(:final cmds):
        return _pathOfCommands(cmds);
    }
  }

  Path _pathOfCommands(List<SvgPathCmd> cmds) {
    final path = Path();
    var cx = 0.0, cy = 0.0, startX = 0.0, startY = 0.0;
    for (final cmd in cmds) {
      switch (cmd) {
        case SvgCmdMove(:final x, :final y):
          path.moveTo(x, y);
          cx = x;
          cy = y;
          startX = x;
          startY = y;
        case SvgCmdLine(:final x, :final y):
          path.lineTo(x, y);
          cx = x;
          cy = y;
        case SvgCmdCubic(:final x1, :final y1, :final x2, :final y2, :final x, :final y):
          path.cubicTo(x1, y1, x2, y2, x, y);
          cx = x;
          cy = y;
        case SvgCmdQuad(:final x1, :final y1, :final x, :final y):
          path.quadraticBezierTo(x1, y1, x, y);
          cx = x;
          cy = y;
        case SvgCmdArc(:final rx, :final ry, :final rot, :final largeArc, :final sweep, :final x, :final y):
          _arcTo(path, cx, cy, rx, ry, rot, largeArc, sweep, x, y);
          cx = x;
          cy = y;
        case SvgCmdClose():
          path.close();
          cx = startX;
          cy = startY;
      }
    }
    return path;
  }

  /// SVG 椭圆弧（端点参数化 → 中心参数化，再按 ≤10° 折线近似）。
  ///
  /// 不用 Path.arcTo 是因为它只支持轴对齐椭圆；SVG 的 A 命令带 x-axis-rotation，
  /// 折线近似在手机屏幕尺寸下视觉无损，且代码量小、可单测。
  void _arcTo(
    Path path,
    double x1,
    double y1,
    double rx,
    double ry,
    double rotDeg,
    bool largeArc,
    bool sweep,
    double x2,
    double y2,
  ) {
    if (rx == 0 || ry == 0) {
      path.lineTo(x2, y2);
      return;
    }
    rx = rx.abs();
    ry = ry.abs();
    final phi = rotDeg * math.pi / 180.0;
    final cosPhi = math.cos(phi);
    final sinPhi = math.sin(phi);
    final dx = (x1 - x2) / 2.0;
    final dy = (y1 - y2) / 2.0;
    final x1p = cosPhi * dx + sinPhi * dy;
    final y1p = -sinPhi * dx + cosPhi * dy;
    var rx2 = rx * rx;
    var ry2 = ry * ry;
    final x1p2 = x1p * x1p;
    final y1p2 = y1p * y1p;
    final lambda = x1p2 / rx2 + y1p2 / ry2;
    if (lambda > 1) {
      final s = math.sqrt(lambda);
      rx *= s;
      ry *= s;
      rx2 = rx * rx;
      ry2 = ry * ry;
    }
    final numerator = rx2 * ry2 - rx2 * y1p2 - ry2 * x1p2;
    final denominator = rx2 * y1p2 + ry2 * x1p2;
    final sign = largeArc != sweep ? 1.0 : -1.0;
    final coef = denominator == 0
        ? 0.0
        : sign * math.sqrt(math.max(0.0, numerator / denominator));
    final cxp = coef * rx * y1p / ry;
    final cyp = -coef * ry * x1p / rx;
    final cx = cosPhi * cxp - sinPhi * cyp + (x1 + x2) / 2.0;
    final cy = sinPhi * cxp + cosPhi * cyp + (y1 + y2) / 2.0;

    double angleOf(double ux, double uy, double vx, double vy) {
      final dot = ux * vx + uy * vy;
      final len = math.sqrt((ux * ux + uy * uy) * (vx * vx + vy * vy));
      var a = len == 0 ? 0.0 : math.acos((dot / len).clamp(-1.0, 1.0));
      if (ux * vy - uy * vx < 0) a = -a;
      return a;
    }

    final ux = (x1p - cxp) / rx;
    final uy = (y1p - cyp) / ry;
    final vx = (-x1p - cxp) / rx;
    final vy = (-y1p - cyp) / ry;
    final theta1 = angleOf(1, 0, ux, uy);
    var dTheta = angleOf(ux, uy, vx, vy);
    if (!sweep && dTheta > 0) dTheta -= 2 * math.pi;
    if (sweep && dTheta < 0) dTheta += 2 * math.pi;
    final steps = math.max(2, (dTheta.abs() / (math.pi / 18)).ceil());
    for (var i = 1; i <= steps; i++) {
      final t = theta1 + dTheta * i / steps;
      final ct = math.cos(t);
      final st = math.sin(t);
      final px = cx + cosPhi * rx * ct - sinPhi * ry * st;
      final py = cy + sinPhi * rx * ct + cosPhi * ry * st;
      path.lineTo(px, py);
    }
  }
}


