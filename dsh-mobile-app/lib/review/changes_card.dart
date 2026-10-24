// 本轮改动卡片（v3.2.14）——对话里「AI 跑完之后」的那张改动汇总卡。
//
// 对齐 PC 端（@deepseek-ai/dsh-client-ui-deliverables 的改动文件卡片）：
//   · 只记录一轮里改过的文件；没有摘要就不出现（不占位、不报错）；
//   · 单文件：标题写「已编辑 <文件名>」+ 文件类型图标，不铺文件列表；
//   · 多文件：代码文件图标 +「N 个文件」+ 增删合计，列表默认 4 行、可展开全部；
//   · 行内路径用界面字体、增删用等宽字体；二进制/过大显示状态词而不是假行数；
//   · 点任意一行进审阅页并选中该文件（手机上没有右侧栏和悬浮预览，直接进全屏）。
//
// 数据是**按需读**的：卡片只拿到事件里的 seq，摘要由 /api/changes/summary 拉一次；
// 宿主没挂 workspace-changes（bootstrap capabilities.changes=false）时整张卡不出现。

import 'package:flutter/material.dart';

import '../api.dart';
import '../dsh_kit.dart';
import '../l10n.dart';
import '../theme.dart';
import 'changes_screen.dart';
import 'diff_view.dart';
import 'model.dart';

/// 折叠时最多列几行（与 PC 端卡片一致）。
const int kCardFileRows = 4;

class TurnChangesCard extends StatefulWidget {
  const TurnChangesCard({
    super.key,
    required this.sessionId,
    required this.seq,
    required this.api,
    this.turn,
    this.loader,
  });

  final String sessionId;

  /// 宣告事件 seq（Host 按它保存摘要）。
  final int seq;
  final Api api;

  /// 轮号（仅展示用；旧宿主可能不给）。
  final int? turn;

  /// 测试注入点：默认走 [Api.changesSummary]。
  final Future<TurnChanges?> Function()? loader;

  @override
  State<TurnChangesCard> createState() => _TurnChangesCardState();
}

class _TurnChangesCardState extends State<TurnChangesCard> {
  TurnChanges? _changes;
  bool _expanded = false;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant TurnChangesCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.seq != widget.seq || oldWidget.sessionId != widget.sessionId) {
      _changes = null;
      _done = false;
      _expanded = false;
      _load();
    }
  }

  Future<void> _load() async {
    if (!widget.api.changesSupported && widget.loader == null) {
      // 旧宿主：连请求都不发（只会 501）。
      return;
    }
    try {
      final loader = widget.loader ?? () => widget.api.changesSummary(widget.sessionId, widget.seq);
      final changes = await loader();
      if (!mounted) return;
      setState(() {
        _changes = changes;
        _done = true;
      });
    } catch (_) {
      // 摘要读不到就静默不显示（PC 端同策略：已打不开内容的卡片不显示）。
      if (!mounted) return;
      setState(() => _done = true);
    }
  }

  void _open(int index) {
    final changes = _changes;
    if (changes == null || changes.isEmpty) return;
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => ChangesReviewScreen(
        sessionId: widget.sessionId,
        seq: widget.seq,
        turn: changes.turn,
        api: widget.api,
        initialIndex: index,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final changes = _changes;
    if (!_done || changes == null || changes.isEmpty) return const SizedBox.shrink();
    final c = DshPalette.of(context);
    final files = changes.files;
    final single = files.length == 1;
    final shown = _expanded ? files : files.take(kCardFileRows).toList(growable: false);
    final overflow = files.length > kCardFileRows;

    return Padding(
      padding: const EdgeInsets.only(bottom: DshSpace.md),
      child: DshCard(
        fill: c.layer2,
        radius: DshRadius.lg,
        padding: EdgeInsets.zero,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              onTap: () => _open(0),
              borderRadius: DshRadius.rLg,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(DshSpace.md, DshSpace.md, DshSpace.md, DshSpace.sm),
                child: Row(
                  children: [
                    _iconBox(c, single ? files.first.name : null),
                    const SizedBox(width: DshSpace.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            single
                                ? L10n.t('已编辑 ${files.first.name}', 'Edited ${files.first.name}')
                                : L10n.t('${changes.total} 个文件', '${changes.total} files'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: DshType.sStrong14.copyWith(color: c.ink),
                          ),
                          const SizedBox(height: DshSpace.xxs),
                          Text(
                            L10n.t('本轮改动 · 点开审阅', 'This turn · tap to review'),
                            style: DshType.xxs12.copyWith(color: c.ink3),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: DshSpace.sm),
                    DiffCounts(added: changes.added, deleted: changes.deleted),
                  ],
                ),
              ),
            ),
            if (!single) ...[
              Divider(height: 1, thickness: 0.5, color: c.line2),
              for (var i = 0; i < shown.length; i++) _fileRow(c, shown[i], i),
              if (overflow)
                InkWell(
                  onTap: () => setState(() => _expanded = !_expanded),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: DshSpace.md, vertical: DshSpace.sm),
                    child: Text(
                      _expanded
                          ? L10n.t('收起', 'Show less')
                          : L10n.t('显示全部 ${files.length} 个文件', 'Show all ${files.length} files'),
                      style: DshType.xs13.copyWith(color: c.link, fontWeight: FontWeight.w500),
                    ),
                  ),
                ),
              if (changes.capped)
                Padding(
                  padding: const EdgeInsets.fromLTRB(DshSpace.md, 0, DshSpace.md, DshSpace.sm),
                  child: Text(
                    L10n.t('另有 ${changes.total - files.length} 个文件未列出（电脑端上限）', '${changes.total - files.length} more not listed (desktop cap)'),
                    style: DshType.xxs12.copyWith(color: c.ink3),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _fileRow(DshPalette c, ChangedFile file, int index) => InkWell(
        onTap: () => _open(index),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: DshSpace.md, vertical: DshSpace.sm),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  file.display,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: DshType.xs13.copyWith(color: c.ink2),
                ),
              ),
              const SizedBox(width: DshSpace.sm),
              DiffCounts(added: file.added, deleted: file.deleted, binary: file.binary, oversized: file.oversized, compact: true),
            ],
          ),
        ),
      );

  /// 图标底框：28×28 + module 底 + 发丝边（官方列表行的图形锚点，紧凑版）。
  Widget _iconBox(DshPalette c, String? fileName) => Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: c.module,
          borderRadius: BorderRadius.circular(DshRadius.sm),
          border: Border.fromBorderSide(DshStroke.side(c.line4)),
        ),
        child: Icon(_iconFor(fileName), size: 16, color: c.ink2),
      );

  static IconData _iconFor(String? name) {
    if (name == null) return Icons.difference_outlined;
    final lower = name.toLowerCase();
    final dot = lower.lastIndexOf('.');
    final ext = dot >= 0 ? lower.substring(dot + 1) : '';
    return switch (ext) {
      'md' || 'markdown' => Icons.article_outlined,
      'docx' || 'doc' => Icons.description_outlined,
      'xlsx' || 'xls' || 'csv' => Icons.table_chart_outlined,
      'json' || 'xml' || 'yaml' || 'yml' || 'toml' => Icons.data_object,
      'png' || 'jpg' || 'jpeg' || 'gif' || 'webp' || 'svg' => Icons.image_outlined,
      _ => Icons.code,
    };
  }
}
