// 文档阅读页（v3.2.0）——md / txt / docx / xlsx 的统一只读阅读器。
//
// 只读定位（用户明确说「不要求有顺畅的编辑能力，至少可读」），但把「可读」做扎实：
//   · 目录跳转（长文档不再靠手滑）
//   · 字号缩放（手机上小字公式也能看清）
//   · 超链接可点（md/docx/xlsx 全支持）
//   · 公式真排版（flutter_math_fork，KaTeX 级）
//   · 导出 .docx，公式落成 Word 原生 OMML（Alt+= 可继续编辑）
//
// v3.3.0（官方风格）：页面底 c.docPreview，正文套一张 DshCard「纸张」（layer1 + 发丝边 +
// R20）；标题栏换 DshAppBar，动作按钮换 DshIconButton，加载/错误/告警分别用
// DshLoading / DshError / DshBanner，目录弹层用 DshSheet + DshTile。
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../api.dart';
import '../docs/docx_writer.dart';
import '../docs/loader.dart';
import '../docs/model.dart';
import '../docs/render.dart';
import '../dsh_kit.dart';
import '../l10n.dart';
import '../theme.dart';
import '../toast.dart';

/// 原生文件通道（saveToDownloads / getIncomingFile / clearIncomingFile）。
const MethodChannel _filesChannel = MethodChannel('dsh/files');

class DocViewerScreen extends StatefulWidget {
  /// 文件名（含扩展名），用于判定格式
  final String name;

  /// 已拿到的字节（本地文件 / 分享进入 / 聊天产物）；与 [remotePath]/[httpUrl] 三选一
  final Uint8List? bytes;

  /// 需要从 harness 工作区拉取的文件路径
  final String? remotePath;

  /// http(s) 直链（点开外部文档链接时用）
  final String? httpUrl;

  /// 拉取用 API（remotePath 非空时必需）
  final Api? api;

  /// 嵌入式：不套 Scaffold/AppBar，改用紧凑头部——供底部抽屉复用，
  /// 这样在聊天里点链接就地阅读时，**对话不会被关掉**。
  final bool embedded;
  const DocViewerScreen({
    super.key,
    required this.name,
    this.bytes,
    this.remotePath,
    this.httpUrl,
    this.api,
    this.embedded = false,
  });

  @override
  State<DocViewerScreen> createState() => _DocViewerScreenState();
}

class _DocViewerScreenState extends State<DocViewerScreen> {
  Document? _doc;
  Uint8List? _raw;
  String? _error;
  bool _loading = true;
  double _scale = 1.0;
  int _sheetIndex = 0;
  final _scroll = ScrollController();
  final _headingKeys = <int, GlobalKey>{};
  final _outline = <(int, String)>[];
  final _outlineBlockIndex = <int>[];

  /// 树形结构（XML / JSON）的展开状态——放在页面 state 里，
  /// 「更多」菜单和正文树共享同一份；滚动 / 改字号重建不丢。
  final _treeCtrl = DocTreeController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _scroll.dispose();
    _treeCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      var bytes = widget.bytes;
      if (bytes == null) {
        final url = widget.httpUrl;
        if (url != null) {
          // 外部直链：直接下载后在本 App 内渲染（不跳浏览器）
          bytes = await _fetchHttp(url);
        } else {
          final api = widget.api;
          final path = widget.remotePath;
          if (api == null || path == null) {
            throw Exception(L10n.t('缺少文件来源', 'Missing file source'));
          }
          bytes = await api.downloadFile(path);
        }
      }
      final doc = loadDocument(bytes, widget.name);
      if (!mounted) return;
      setState(() {
        _raw = bytes;
        _doc = doc;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  /// 拉取 http(s) 文档直链。超时与体积都在 loader 那层再兜一道。
  Future<Uint8List> _fetchHttp(String url) async {
    final res = await http
        .get(Uri.parse(url), headers: const {'User-Agent': 'DSH-Remote'})
        .timeout(const Duration(seconds: 90));
    if (res.statusCode != 200) {
      throw Exception(L10n.t('下载失败 HTTP ${res.statusCode}', 'Download failed: HTTP ${res.statusCode}'));
    }
    if (res.bodyBytes.isEmpty) {
      throw Exception(L10n.t('下载内容为空', 'Downloaded content is empty'));
    }
    return res.bodyBytes;
  }

  /// 收集标题块下标 + 建 GlobalKey，供目录跳转。
  void _ensureOutline(Document doc) {
    if (_outline.isNotEmpty) return;
    for (var i = 0; i < doc.blocks.length; i++) {
      final b = doc.blocks[i];
      if (b is DocHeading && b.level <= 3) {
        final text = _plainOfInline(b.spans);
        if (text.isEmpty) continue;
        _headingKeys[i] = GlobalKey();
        _outline.add((b.level, text));
        _outlineBlockIndex.add(i);
      }
    }
  }

  static String _plainOfInline(List<DocInline> spans) {
    final b = StringBuffer();
    for (final s in spans) {
      switch (s) {
        case DocText(:final text):
          b.write(text);
        case DocMathInline(:final tex):
          b.write(tex);
        case DocLink(:final spans):
          b.write(_plainOfInline(spans));
        default:
          break;
      }
    }
    return b.toString().trim();
  }

  void _jumpTo(int outlineIndex) {
    final blockIdx = _outlineBlockIndex[outlineIndex];
    final key = _headingKeys[blockIdx];
    final ctx = key?.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(ctx,
          duration: DshMotion.normal, alignment: 0.02);
    }
  }

  /// 目录：官方底部弹层（DshSheet + DshTile），层级用左内衬表达。
  Future<void> _showOutline() async {
    if (_outline.isEmpty) {
      showToast(context, L10n.t('本文档没有标题结构', 'This document has no headings'));
      return;
    }
    final picked = await showDshSheet<int>(
      context: context,
      builder: (sheetCtx) => DshSheet(
        title: L10n.t('目录', 'Contents'),
        padding: const EdgeInsets.only(bottom: DshSpace.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < _outline.length; i++)
              DshTile(
                titleWidget: Text(
                  _outline[i].$2,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: (_outline[i].$1 == 1 ? DshType.sStrong14 : DshType.s14)
                      .copyWith(color: DshPalette.of(sheetCtx).ink),
                ),
                padding: EdgeInsets.only(
                  left: DshSpace.pageH + (_outline[i].$1 - 1) * DshSpace.lg,
                  right: DshSpace.pageH,
                ),
                onTap: () => Navigator.of(sheetCtx).pop(i),
              ),
          ],
        ),
      ),
    );
    if (picked != null) _jumpTo(picked);
  }

  /// 导出 .docx：公式写成 Word 原生 OMML（在 Word 里可 Alt+= 继续编辑）。
  Future<void> _exportDocx() async {
    final doc = _doc;
    if (doc == null) return;
    try {
      final bytes = buildDocx(doc, title: doc.title);
      if (bytes.isEmpty) {
        showToast(context, L10n.t('导出失败：生成内容为空', 'Export failed: empty output'));
        return;
      }
      final outName = '${doc.title.isEmpty ? 'document' : doc.title}.docx';
      final where = await _filesChannel.invokeMethod<String>('saveToDownloads', {
        'name': outName,
        'bytes': bytes,
      });
      if (!mounted) return;
      final hasMath = documentHasMath(doc);
      showToast(
        context,
        hasMath
            ? L10n.t('已导出到「$where」\n公式是 Word 原生公式，可在 Word 里 Alt+= 编辑',
                'Saved to "$where"\nEquations are native Word equations (editable with Alt+=)')
            : L10n.t('已导出到「$where」', 'Saved to "$where"'),
      );
    } catch (e) {
      if (!mounted) return;
      showToast(context, L10n.t('导出失败：$e', 'Export failed: $e'));
    }
  }

  /// 把原始文件另存到系统下载目录。
  Future<void> _saveOriginal() async {
    final raw = _raw;
    if (raw == null) return;
    try {
      final where = await _filesChannel.invokeMethod<String>('saveToDownloads', {
        'name': widget.name.split(RegExp(r'[\\/]')).last,
        'bytes': raw,
      });
      if (!mounted) return;
      showToast(context, L10n.t('已保存到「$where」', 'Saved to "$where"'));
    } catch (e) {
      if (!mounted) return;
      showToast(context, L10n.t('保存失败：$e', 'Save failed: $e'));
    }
  }

  void _copyAll() {
    final doc = _doc;
    if (doc == null) return;
    final text = doc.blocks.map(_plainOfBlock).where((s) => s.isNotEmpty).join('\n\n');
    Clipboard.setData(ClipboardData(text: text));
    showToast(context, L10n.t('已复制全文', 'Copied full text'));
  }

  static String _plainOfBlock(DocBlock b) => switch (b) {
        DocHeading(:final spans) => _plainOfInline(spans),
        DocPara(:final spans) => _plainOfInline(spans),
        DocQuote(:final spans) => _plainOfInline(spans),
        DocList(:final items) => items.map(_plainOfInline).join('\n'),
        DocCode(:final text) => text,
        DocMathBlock(:final tex) => tex,
        DocTable(:final rows) =>
          rows.map((r) => r.map((c) => _plainOfInline(c.spans)).join(' | ')).join('\n'),
        DocRaw(:final text) => text,
        DocTree(:final roots) => _plainOfTree(roots),
        DocSvg(:final source) => source,
        DocRule() => '',
      };

  /// 树形结构拍平成缩进文本（复制全文用；缩进保留层级，粘到聊天里也可读）。
  static String _plainOfTree(List<TreeNode> roots) {
    final b = StringBuffer();
    void walk(List<TreeNode> nodes, int depth) {
      for (final n in nodes) {
        final attrs = n.attrs.isEmpty
            ? ''
            : ' ${n.attrs.map((a) => '${a.name}="${a.value}"').join(' ')}';
        final text = n.text == null || n.text!.isEmpty ? '' : ': ${n.text}';
        b.writeln('${'  ' * depth}${n.name}$attrs$text');
        walk(n.children, depth + 1);
      }
    }

    walk(roots, 0);
    return b.toString().trimRight();
  }

  @override
  Widget build(BuildContext context) {
    final c = DshPalette.of(context);
    final doc = _doc;
    if (doc != null) _ensureOutline(doc);

    if (widget.embedded) {
      // 抽屉模式：紧凑头部 + 正文。对话在抽屉下面保持存活，划下去就回到聊天。
      // 底色与全屏页一致（docPreview），「纸张」卡片才有层次。
      return ColoredBox(
        color: c.docPreview,
        child: Column(
          children: [
            _embeddedHeader(context, doc),
            Expanded(child: _body()),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: c.docPreview,
      appBar: DshAppBar(
        title: widget.name.split(RegExp(r'[\\/]')).last,
        actions: _actions(doc),
      ),
      body: _body(),
    );
  }

  /// 抽屉内的紧凑头部：左侧拖拽提示 + 文件名 + 与全屏页一致的操作 + 关闭。
  Widget _embeddedHeader(BuildContext context, Document? doc) {
    final c = DshPalette.of(context);
    return DshAppBar(
      title: widget.name.split(RegExp(r'[\\/]')).last,
      automaticallyImplyLeading: false,
      // 嵌在抽屉/弹层里，安全区由外层负责；这里不能再吃一次状态栏高度。
      primary: false,
      leading: Icon(Icons.drag_handle, size: 18, color: c.ink3),
      actions: [
        ..._actions(doc),
        Center(
          child: DshIconButton(
            icon: Icons.keyboard_arrow_down,
            tooltip: L10n.t('收起', 'Close'),
            onTap: () => Navigator.of(context).maybePop(),
          ),
        ),
      ],
    );
  }

  /// 只有真有标题结构才显示「目录」：xlsx / 树形结构与目录无关。
  bool _hasOutlineEntry(Document? doc) =>
      doc != null && doc.format != DocFormat.xlsx && !documentHasTree(doc);

  /// 「导出 Word」对数据结构 / 矢量图没有意义（原样阅读才是需求），
  /// 对正文类格式保留（md / txt / docx / html）。
  bool _canExportWord(Document? doc) =>
      doc == null ||
      (doc.format != DocFormat.svg &&
          doc.format != DocFormat.xml &&
          doc.format != DocFormat.json);

  /// 全屏页与抽屉共用的操作按钮。
  List<Widget> _actions(Document? doc) => [
        if (_hasOutlineEntry(doc))
          Center(
            child: DshIconButton(
              icon: Icons.list_alt_outlined,
              tooltip: L10n.t('目录', 'Contents'),
              onTap: _showOutline,
            ),
          ),
        Center(
          child: PopupMenuButton<String>(
            tooltip: L10n.t('更多', 'More'),
            iconSize: 20,
            onSelected: (v) {
              switch (v) {
                case 'font-':
                  setState(() => _scale = (_scale - 0.1).clamp(0.7, 2.0));
                case 'font+':
                  setState(() => _scale = (_scale + 0.1).clamp(0.7, 2.0));
                case 'font0':
                  setState(() => _scale = 1.0);
                case 'word':
                  _exportDocx();
                case 'save':
                  _saveOriginal();
                case 'copy':
                  _copyAll();
                case 'tree-expand':
                  _treeCtrl.expandAll();
                case 'tree-collapse':
                  _treeCtrl.collapseAll();
              }
            },
            itemBuilder: (c) => [
              PopupMenuItem(
                value: 'font+',
                child: Text(L10n.t('放大字号（${(_scale * 100).round()}%）', 'Larger text (${(_scale * 100).round()}%)')),
              ),
              PopupMenuItem(
                value: 'font-',
                child: Text(L10n.t('缩小字号（${(_scale * 100).round()}%）', 'Smaller text (${(_scale * 100).round()}%)')),
              ),
              PopupMenuItem(value: 'font0', child: Text(L10n.t('恢复默认字号', 'Reset text size'))),
              const PopupMenuDivider(),
              if (doc != null && documentHasTree(doc)) ...[
                PopupMenuItem(
                  value: 'tree-expand',
                  child: Text(L10n.t('全部展开', 'Expand all')),
                ),
                PopupMenuItem(
                  value: 'tree-collapse',
                  child: Text(L10n.t('全部折叠', 'Collapse all')),
                ),
                const PopupMenuDivider(),
              ],
              if (_canExportWord(doc))
                PopupMenuItem(
                  value: 'word',
                  child: Text(L10n.t('导出 Word（公式原生）', 'Export Word (native equations)')),
                ),
              PopupMenuItem(value: 'save', child: Text(L10n.t('另存原文件', 'Save original file'))),
              if (doc != null && doc.format != DocFormat.xlsx)
                PopupMenuItem(value: 'copy', child: Text(L10n.t('复制全文', 'Copy full text'))),
            ],
          ),
        ),
      ];

  Widget _body() {
    final c = DshPalette.of(context);
    if (_loading) return const DshLoading();

    final err = _error;
    if (err != null) {
      return DshError(
        message: L10n.t('打开失败：$err', 'Failed to open: $err'),
        onRetry: () {
          setState(() {
            _loading = true;
            _error = null;
          });
          _load();
        },
      );
    }

    final doc = _doc;
    if (doc == null) return const SizedBox.shrink();

    // v3.2.4：把「去哪儿取图」交给渲染器 ——
    // 本地文档用所在目录解析 `![](图/x.png)`，网络文档用其基址解析相对 URL。
    // 必须用 p.windows：文档在电脑上，是 Windows 路径（App 本身跑在 Android）。
    final ctx = DocRenderCtx(
      scale: _scale,
      api: widget.api,
      baseDir: widget.remotePath == null ? null : p.windows.dirname(widget.remotePath!),
      baseUrl: widget.httpUrl,
      tree: _treeCtrl,
    );

    // 电子表格：多表用胶囊选择器切换
    final sheet = doc.sheet;
    if (doc.format == DocFormat.xlsx && sheet != null && sheet.sheets.isNotEmpty) {
      final idx = _sheetIndex.clamp(0, sheet.sheets.length - 1);
      return Column(
        children: [
          if (sheet.sheets.length > 1)
            SizedBox(
              height: DshSpace.controlLg,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: DshSpace.pageH),
                itemCount: sheet.sheets.length,
                itemBuilder: (_, i) => Padding(
                  padding: const EdgeInsets.only(right: DshSpace.sm),
                  child: Center(
                    child: DshPill(
                      label: sheet.sheets[i].name,
                      active: i == idx,
                      onTap: () => setState(() => _sheetIndex = i),
                    ),
                  ),
                ),
              ),
            ),
          Expanded(child: SheetView(sheet.sheets[idx], ctx: ctx)),
        ],
      );
    }

    // 正文：docPreview 底 + 一张 DshCard「纸张」（layer1 + 发丝边 + R20）
    return Scrollbar(
      controller: _scroll,
      child: SingleChildScrollView(
        controller: _scroll,
        padding: const EdgeInsets.fromLTRB(
          DshSpace.pageH,
          DshSpace.md,
          DshSpace.pageH,
          DshSpace.xxxl,
        ),
        child: DshCard(
          // 「纸张」：layer1 填充 + line4 发丝边 + R20（官方独立卡片档）
          fill: c.layer1,
          padding: const EdgeInsets.symmetric(
            horizontal: DshSpace.lg,
            vertical: DshSpace.xl,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (doc.warnings.isNotEmpty) ...[
                DshBanner(
                  message: doc.warnings.join('\n'),
                  tone: DshBannerTone.warn,
                  icon: Icons.warning_amber_rounded,
                ),
                const SizedBox(height: DshSpace.md),
              ],
              DocBlocks(doc.blocks, ctx: ctx, headingKeys: _headingKeys),
            ],
          ),
        ),
      ),
    );
  }
}
