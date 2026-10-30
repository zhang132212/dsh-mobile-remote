// PDF 阅读页（v3.2.16）——一页一屏 + 双指缩放 + 跳页。
//
// 交互取舍：
//   · **一页一屏**（PageView）而不是长列表：PDF 是分页排版，跨页滚动会让「第几页」失去意义，
//     而 PDF 的页码又常常是汇报/论文里要念出来的东西。
//   · 双指缩放用 InteractiveViewer；**未放大时单指留给翻页**（panEnabled 只在放大后开），
//     否则缩放组件会把横向滑动全吃掉，用户会觉得「翻不动页」。
//   · 每页按屏幕像素宽度请求原生渲染（上限 1800px），LRU 缓存几页，回翻不闪。
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../dsh_kit.dart';
import '../l10n.dart';
import '../theme.dart';
import 'pdf.dart';

class PdfView extends StatefulWidget {
  const PdfView({super.key, required this.bytes, required this.name});

  /// 原始 PDF 字节（阅读页已经从本地/工作区/直链拿齐）。
  final Uint8List bytes;

  /// 文件名，仅用于错误提示。
  final String name;

  @override
  State<PdfView> createState() => _PdfViewState();
}

class _PdfViewState extends State<PdfView> {
  final PageController _pc = PageController();
  /// 键是「页号@渲染宽度」——转屏后宽度变了，旧图不能复用（否则会糊）
  final Map<String, Uint8List> _cache = <String, Uint8List>{};
  PdfSession? _session;
  String? _error;
  bool _loading = true;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _open();
  }

  @override
  void dispose() {
    _pc.dispose();
    // 只关自己这一份：抽屉里可能还开着另一份 PDF，不能把别人的会话关掉
    final session = _session;
    if (session != null) PdfBridge.close(session.id);
    super.dispose();
  }

  Future<void> _open() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final session = await PdfBridge.open(widget.bytes);
      if (!mounted) return;
      setState(() {
        _session = session;
        _index = 0;
        _cache.clear();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _friendlyOpenError(e);
        _loading = false;
      });
    }
  }

  /// 原生异常 → 用户能看懂的一句话（不把 PlatformException(...) 直接甩到脸上）。
  static String _friendlyOpenError(Object e) {
    if (e is PlatformException) {
      final msg = (e.message ?? '').toLowerCase();
      if (msg.contains('password')) {
        return L10n.t('这份 PDF 有密码保护，暂不支持打开', 'This PDF is password protected');
      }
      if (msg.contains('corrupt') ||
          msg.contains('not in pdf format') ||
          msg.contains('format')) {
        return L10n.t('文件已损坏，或不是有效的 PDF', 'The file is corrupted or not a valid PDF');
      }
      return L10n.t('PDF 打开失败（${e.message ?? e.code}）', 'Failed to open PDF (${e.message ?? e.code})');
    }
    return '$e';
  }

  void _goTo(int page) {
    final info = _session?.info;
    if (info == null) return;
    final target = page.clamp(0, info.pages - 1);
    _pc.animateToPage(target,
        duration: DshMotion.normal, curve: Curves.easeOutCubic);
  }

  Future<void> _askPage() async {
    final info = _session?.info;
    if (info == null) return;
    final controller = TextEditingController(text: '${_index + 1}');
    final picked = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(L10n.t('跳到第几页', 'Go to page')),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            hintText: L10n.t('1 – ${info.pages}', '1 – ${info.pages}'),
          ),
          onSubmitted: (v) => Navigator.of(ctx).pop(int.tryParse(v)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(L10n.t('取消', 'Cancel')),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(ctx).pop(int.tryParse(controller.text)),
            child: Text(L10n.t('跳转', 'Go')),
          ),
        ],
      ),
    );
    controller.dispose();
    if (picked != null) _goTo(picked - 1);
  }

  /// 渲染宽度：屏幕物理像素宽，夹在 800–1800 之间（再大只会吃内存）。
  int _pixelWidth(BuildContext context) {
    final mq = MediaQuery.of(context);
    final px = (mq.size.width * mq.devicePixelRatio).round();
    return px.clamp(800, 1800);
  }

  @override
  Widget build(BuildContext context) {
    final c = DshPalette.of(context);
    if (_loading) {
      return DshLoading(label: L10n.t('正在解析 PDF…', 'Opening PDF…'));
    }
    final err = _error;
    if (err != null) {
      return DshError(
        message: L10n.t('PDF 打开失败：$err', 'Failed to open PDF: $err'),
        onRetry: _open,
      );
    }
    final session = _session;
    final info = session?.info;
    if (session == null || info == null) return const SizedBox.shrink();

    final width = _pixelWidth(context);
    return Stack(
      children: [
        Positioned.fill(
          child: PageView.builder(
            controller: _pc,
            itemCount: info.pages,
            onPageChanged: (i) => setState(() => _index = i),
            itemBuilder: (_, i) => Padding(
              padding: const EdgeInsets.fromLTRB(
                DshSpace.md,
                DshSpace.md,
                DshSpace.md,
                DshSpace.xxl * 2,
              ),
              child: PdfPageImage(
                sessionId: session.id,
                index: i,
                pixelWidth: width,
                info: info,
                cache: _cache,
              ),
            ),
          ),
        ),
        // 页码 / 翻页：贴在底部，不挡正文（正文上下都留了 pad）
        Positioned(
          left: 0,
          right: 0,
          bottom: DshSpace.md,
          child: SafeArea(
            top: false,
            child: Center(
              child: _PageBar(
                index: _index,
                pages: info.pages,
                onPrev: _index > 0 ? () => _goTo(_index - 1) : null,
                onNext: _index < info.pages - 1 ? () => _goTo(_index + 1) : null,
                onTapLabel: _askPage,
              ),
            ),
          ),
        ),
        // 右下角缩放提示：只在第一页露一次，不打扰
        if (_index == 0 && info.pages > 0)
          Positioned(
            right: DshSpace.md,
            top: DshSpace.sm,
            child: IgnorePointer(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: DshSpace.sm,
                  vertical: DshSpace.xs,
                ),
                decoration: BoxDecoration(
                  color: c.layer1.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(DshRadius.sm),
                  border: Border.all(color: c.line4),
                ),
                child: Text(
                  L10n.t('双指放大', 'Pinch to zoom'),
                  style: DshType.xxs12.copyWith(color: c.ink3),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// 底部页码条：‹ 3 / 12 ›，点中间可以直接跳页。
class _PageBar extends StatelessWidget {
  const _PageBar({
    required this.index,
    required this.pages,
    required this.onPrev,
    required this.onNext,
    required this.onTapLabel,
  });

  final int index;
  final int pages;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;
  final VoidCallback onTapLabel;

  @override
  Widget build(BuildContext context) {
    final c = DshPalette.of(context);
    return Container(
      decoration: BoxDecoration(
        color: c.layer1,
        borderRadius: BorderRadius.circular(DshRadius.pill),
        border: Border.all(color: c.line4),
      ),
      padding: const EdgeInsets.symmetric(horizontal: DshSpace.xs),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          DshIconButton(
            icon: Icons.chevron_left,
            tooltip: L10n.t('上一页', 'Previous page'),
            onTap: onPrev,
            color: onPrev == null ? c.dimmed : c.ink2,
          ),
          InkWell(
            onTap: onTapLabel,
            borderRadius: BorderRadius.circular(DshRadius.sm),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: DshSpace.sm,
                vertical: DshSpace.xs,
              ),
              child: Text(
                '${index + 1} / $pages',
                style: DshType.s14.copyWith(color: c.ink2),
              ),
            ),
          ),
          DshIconButton(
            icon: Icons.chevron_right,
            tooltip: L10n.t('下一页', 'Next page'),
            onTap: onNext,
            color: onNext == null ? c.dimmed : c.ink2,
          ),
        ],
      ),
    );
  }
}

/// 单页：按需向原生要 JPEG，并做「未放大时单指翻页 / 放大后单指拖动」的手势切换。
class PdfPageImage extends StatefulWidget {
  const PdfPageImage({
    super.key,
    required this.sessionId,
    required this.index,
    required this.pixelWidth,
    required this.info,
    required this.cache,
  });

  final int sessionId;
  final int index;
  final int pixelWidth;
  final PdfInfo info;
  final Map<String, Uint8List> cache;

  @override
  State<PdfPageImage> createState() => _PdfPageImageState();
}

class _PdfPageImageState extends State<PdfPageImage> {
  Uint8List? _bytes;
  String? _error;
  bool _loading = true;
  bool _zoomed = false;
  final TransformationController _tc = TransformationController();

  @override
  void initState() {
    super.initState();
    _tc.addListener(_onTransform);
    _load();
  }

  @override
  void didUpdateWidget(covariant PdfPageImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pixelWidth != widget.pixelWidth ||
        oldWidget.index != widget.index) {
      _load();
    }
  }

  @override
  void dispose() {
    _tc.removeListener(_onTransform);
    _tc.dispose();
    super.dispose();
  }

  void _onTransform() {
    final zoomed = _tc.value.getMaxScaleOnAxis() > 1.02;
    if (zoomed != _zoomed) setState(() => _zoomed = zoomed);
  }

  String get _cacheKey => '${widget.index}@${widget.pixelWidth}';

  Future<void> _load() async {
    final cached = widget.cache[_cacheKey];
    if (cached != null) {
      setState(() {
        _bytes = cached;
        _loading = false;
        _error = null;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final bytes = await PdfBridge.render(
        sessionId: widget.sessionId,
        index: widget.index,
        width: widget.pixelWidth,
      );
      if (!mounted) return;
      if (bytes == null || bytes.isEmpty) {
        setState(() {
          _error = L10n.t('这一页渲染为空', 'Empty page render');
          _loading = false;
        });
        return;
      }
      // 简单 LRU：只留最近 6 页，避免长文档把内存吃满
      widget.cache[_cacheKey] = bytes;
      while (widget.cache.length > 6) {
        widget.cache.remove(widget.cache.keys.first);
      }
      setState(() {
        _bytes = bytes;
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

  @override
  Widget build(BuildContext context) {
    final c = DshPalette.of(context);
    // 先按页面比例占位：渲染完成前后高度不跳
    final ratio = widget.info.aspect;
    Widget placeholder = Center(
      child: SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: c.ink3.withValues(alpha: 0.5),
        ),
      ),
    );
    final err = _error;
    if (err != null) {
      placeholder = Center(
        child: Text(
          err,
          textAlign: TextAlign.center,
          style: DshType.xxs12.copyWith(color: c.ink3),
        ),
      );
    }
    final bytes = _bytes;
    return LayoutBuilder(
      builder: (context, box) {
        final maxW = box.maxWidth;
        final maxH = box.maxHeight;
        // 以「宽度撑满、高度不超过可用区」定纸张尺寸，保持比例
        var w = maxW;
        var h = w / ratio;
        if (h > maxH) {
          h = maxH;
          w = h * ratio;
        }
        return Center(
          child: GestureDetector(
            onDoubleTap: () {
              if (_zoomed) {
                _tc.value = Matrix4.identity();
              } else {
                _tc.value = Matrix4.identity()..scaleByDouble(2.0, 2.0, 2.0, 1.0);
              }
            },
            child: Container(
              width: w,
              height: h,
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: DshShadow.lv1,
                borderRadius: BorderRadius.circular(DshRadius.xs),
              ),
              clipBehavior: Clip.antiAlias,
              child: _loading || bytes == null
                  ? placeholder
                  : InteractiveViewer(
                      transformationController: _tc,
                      minScale: 1.0,
                      maxScale: 4.0,
                      // 只有放大后才允许单指拖动，否则会把 PageView 的翻页手势吃掉
                      panEnabled: _zoomed,
                      child: Image.memory(
                        bytes,
                        fit: BoxFit.contain,
                        gaplessPlayback: true,
                        filterQuality: FilterQuality.medium,
                      ),
                    ),
            ),
          ),
        );
      },
    );
  }
}
