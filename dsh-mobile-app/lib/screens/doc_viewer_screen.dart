// 文档阅读页（v3.2.0）——md / txt / docx / xlsx 的统一只读阅读器。
//
// 只读定位（用户明确说「不要求有顺畅的编辑能力，至少可读」），但把「可读」做扎实：
//   · 目录跳转（长文档不再靠手滑）
//   · 字号缩放（手机上小字公式也能看清）
//   · 超链接可点（md/docx/xlsx 全支持）
//   · 公式真排版（flutter_math_fork，KaTeX 级）
//   · 导出 .docx，公式落成 Word 原生 OMML（Alt+= 可继续编辑）
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../api.dart';
import '../docs/docx_writer.dart';
import '../docs/loader.dart';
import '../docs/model.dart';
import '../docs/render.dart';
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

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _scroll.dispose();
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
            throw Exception('缺少文件来源');
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
      throw Exception('下载失败 HTTP ${res.statusCode}');
    }
    if (res.bodyBytes.isEmpty) throw Exception('下载内容为空');
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
          duration: const Duration(milliseconds: 240), alignment: 0.02);
    }
  }

  Future<void> _showOutline() async {
    if (_outline.isEmpty) {
      showToast(context, '本文档没有标题结构');
      return;
    }
    final picked = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Text(L10n.t('目录', 'Contents'),
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            ),
            for (var i = 0; i < _outline.length; i++)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.only(left: 16.0 + (_outline[i].$1 - 1) * 16, right: 16),
                title: Text(
                  _outline[i].$2,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: (15.0 - (_outline[i].$1 - 1) * 0.8).clamp(12.5, 15.0),
                    fontWeight: _outline[i].$1 == 1 ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
                onTap: () => Navigator.of(c).pop(i),
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
        DocRule() => '',
      };

  @override
  Widget build(BuildContext context) {
    final doc = _doc;
    if (doc != null) _ensureOutline(doc);

    if (widget.embedded) {
      // 抽屉模式：紧凑头部 + 正文。对话在抽屉下面保持存活，划下去就回到聊天。
      return Column(
        children: [
          _embeddedHeader(context, doc),
          Expanded(child: _body()),
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.name.split(RegExp(r'[\\/]')).last,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: _actions(doc),
      ),
      body: _body(),
    );
  }

  /// 抽屉内的紧凑头部：左侧下拉提示 + 文件名 + 与全屏页一致的操作 + 关闭。
  Widget _embeddedHeader(BuildContext context, Document? doc) {
    final line = DshColors.line(context);
    final ink2 = DshColors.ink2(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: line))),
      child: Row(
        children: [
          Icon(Icons.drag_handle, size: 18, color: ink2),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              widget.name.split(RegExp(r'[\\/]')).last,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
          ),
          ..._actions(doc),
          IconButton(
            tooltip: L10n.t('收起', 'Close'),
            visualDensity: VisualDensity.compact,
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.keyboard_arrow_down),
          ),
        ],
      ),
    );
  }

  /// 全屏页与抽屉共用的操作按钮。
  List<Widget> _actions(Document? doc) => [
        if (doc != null && doc.format != DocFormat.xlsx)
          IconButton(
            tooltip: L10n.t('目录', 'Contents'),
            onPressed: _showOutline,
            icon: const Icon(Icons.list_alt_outlined),
          ),
        PopupMenuButton<String>(
          tooltip: L10n.t('更多', 'More'),
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
            PopupMenuItem(
              value: 'word',
              child: Text(L10n.t('导出 Word（公式原生）', 'Export Word (native equations)')),
            ),
            PopupMenuItem(value: 'save', child: Text(L10n.t('另存原文件', 'Save original file'))),
            if (doc != null && doc.format != DocFormat.xlsx)
              PopupMenuItem(value: 'copy', child: Text(L10n.t('复制全文', 'Copy full text'))),
          ],
        ),
      ];

  Widget _body() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final err = _error;
    if (err != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 40, color: DshColors.danger(context)),
              const SizedBox(height: 12),
              Text(L10n.t('打开失败：$err', 'Failed to open: $err'),
                  textAlign: TextAlign.center, style: const TextStyle(fontSize: 14)),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () {
                  setState(() {
                    _loading = true;
                    _error = null;
                  });
                  _load();
                },
                child: Text(L10n.t('重试', 'Retry')),
              ),
            ],
          ),
        ),
      );
    }

    final doc = _doc;
    if (doc == null) return const SizedBox.shrink();

    final ctx = DocRenderCtx(scale: _scale);

    // 电子表格：多表用 Tab 切换
    final sheet = doc.sheet;
    if (doc.format == DocFormat.xlsx && sheet != null && sheet.sheets.isNotEmpty) {
      final idx = _sheetIndex.clamp(0, sheet.sheets.length - 1);
      return Column(
        children: [
          if (sheet.sheets.length > 1)
            SizedBox(
              height: 44,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                itemCount: sheet.sheets.length,
                itemBuilder: (c, i) => Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 6),
                  child: ChoiceChip(
                    label: Text(sheet.sheets[i].name),
                    selected: i == idx,
                    onSelected: (_) => setState(() => _sheetIndex = i),
                  ),
                ),
              ),
            ),
          Expanded(child: SheetView(sheet.sheets[idx], ctx: ctx)),
        ],
      );
    }

    return Scrollbar(
      controller: _scroll,
      child: SingleChildScrollView(
        controller: _scroll,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 48),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (doc.warnings.isNotEmpty)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: DshColors.warn(context).withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  doc.warnings.join('\n'),
                  style: TextStyle(fontSize: 12, color: DshColors.warn(context), height: 1.5),
                ),
              ),
            DocBlocks(doc.blocks, ctx: ctx, headingKeys: _headingKeys),
          ],
        ),
      ),
    );
  }
}
