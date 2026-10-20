// 改动对比渲染（v3.2.14）——统一的 unified diff 视图，供「变更审阅页」与文档阅读器的
// 「改动」页签共用，保证同一次改动在聊天卡片、审阅页、阅读器里长得一样。
//
// 为什么自己画而不用包：手机端只需要「单栏 unified diff」这一种形态（官方 review tab 的
// 左右对比在 6 寸屏上每侧只剩 15 字符宽），但每一行要带**两侧行号 + 增删标记 + 整行底色**，
// 现成的 diff 包要么只给文本、要么依赖 WebView。逐行 Row 的做法在 400–800 行量级足够快，
// 更大的文件用「分批展开 + 5000 行硬上限」兜住（与 PC 端 review tab 同值）。

import 'package:flutter/material.dart';

import '../l10n.dart';
import '../theme.dart';
import 'model.dart';

/// 标记列宽度（+ / − / 空格）。
const double _markerWidth = 12;

/// 行号列左右内衬。
const double _gutterPad = 6;

/// 单个数字字符的估算宽度（等宽字体 11px 约 6.6，留一点余量避免挤压）。
const double _digitWidth = 6.6;

/// 增删行数徽标（+N / −M），审阅页、卡片、阅读器共用。
class DiffCounts extends StatelessWidget {
  const DiffCounts({super.key, required this.added, required this.deleted, this.binary = false, this.oversized = false, this.compact = false});

  final int added;
  final int deleted;
  final bool binary;
  final bool oversized;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final c = DshPalette.of(context);
    final style = (compact ? DshType.xxs12 : DshType.xs13).copyWith(
      fontFamilyFallback: DshType.monoFallback,
      color: c.ink3,
    );
    if (binary || oversized) {
      return Text(binary ? L10n.t('二进制', 'binary') : L10n.t('过大', 'too large'), style: style);
    }
    // 两个独立 Text 而不是 Text.rich：增删数字要用同一套等宽度量对齐，
    // 富文本里各 span 的字体解析在个别环境会退回默认字体（测试/无等宽字体机型）。
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('+$added', style: style.copyWith(color: c.ok), maxLines: 1),
        const SizedBox(width: DshSpace.xs),
        Text('−$deleted', style: style.copyWith(color: c.danger), maxLines: 1),
      ],
    );
  }
}

/// unified diff 视图：hunk 头 + 逐行（旧行号 / 新行号 / 标记 / 正文）。
class DiffHunksView extends StatefulWidget {
  const DiffHunksView({
    super.key,
    required this.hunks,
    this.initialLines = kDiffChunkLines,
    this.maxLines = kMaxRenderedDiffLines,
    this.padding = const EdgeInsets.symmetric(vertical: DshSpace.xs),
  });

  final List<DiffHunk> hunks;

  /// 初始渲染的行数（超出后按块展开）。
  final int initialLines;

  /// 硬上限（与 PC 端 review tab 一致）。
  final int maxLines;
  final EdgeInsetsGeometry padding;

  @override
  State<DiffHunksView> createState() => _DiffHunksViewState();
}

class _DiffHunksViewState extends State<DiffHunksView> {
  late int _budget = widget.initialLines;

  @override
  void didUpdateWidget(covariant DiffHunksView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 换文件时重置展开进度（否则新文件会继承上一个文件的「全部展开」）。
    if (!identical(oldWidget.hunks, widget.hunks)) _budget = widget.initialLines;
  }

  @override
  Widget build(BuildContext context) {
    final c = DshPalette.of(context);
    final digits = gutterDigits(widget.hunks);
    final gutterWidth = digits * _digitWidth + _gutterPad * 2;
    final total = diffLineCount(widget.hunks);
    final visible = _budget.clamp(0, widget.maxLines);

    final rows = <Widget>[];
    var used = 0;
    for (final hunk in widget.hunks) {
      if (used >= visible) break;
      rows.add(_HunkHeader(header: hunk.header));
      for (final line in hunkLines(hunk)) {
        if (used >= visible) break;
        rows.add(_DiffLineRow(line: line, width: gutterWidth, digits: digits));
        used++;
      }
    }

    final truncated = total > widget.maxLines && _budget >= widget.maxLines;
    final more = total > used && !truncated;

    return Container(
      width: double.infinity,
      padding: widget.padding,
      decoration: BoxDecoration(
        color: c.layer1,
        borderRadius: DshRadius.rMd,
        border: Border.fromBorderSide(DshStroke.side(c.line2)),
      ),
      child: ClipRRect(
        borderRadius: DshRadius.rMd,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ...rows,
            if (more)
              _FooterAction(
                label: L10n.t('显示更多（还有 ${total - used} 行）', 'Show more (${total - used} lines left)'),
                onTap: () => setState(() => _budget += kDiffChunkLines),
              ),
            if (truncated)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: DshSpace.md, vertical: DshSpace.sm),
                child: Text(
                  L10n.t('仅显示前 ${widget.maxLines} 行（与电脑端一致的上限）', 'Showing the first ${widget.maxLines} lines (same cap as desktop)'),
                  style: DshType.xxs12.copyWith(color: c.ink3),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _HunkHeader extends StatelessWidget {
  const _HunkHeader({required this.header});

  final String header;

  @override
  Widget build(BuildContext context) {
    final c = DshPalette.of(context);
    return Container(
      width: double.infinity,
      color: c.module,
      padding: const EdgeInsets.symmetric(horizontal: DshSpace.md, vertical: DshSpace.xs),
      child: Text(
        header,
        style: DshType.mdCodeSmall.copyWith(color: c.ink3),
      ),
    );
  }
}

class _DiffLineRow extends StatelessWidget {
  const _DiffLineRow({required this.line, required this.width, required this.digits});

  final DiffLine line;
  final double width;
  final int digits;

  @override
  Widget build(BuildContext context) {
    final c = DshPalette.of(context);
    final (bg, markerColor) = switch (line.kind) {
      DiffLineKind.add => (c.diffAdded, c.ok),
      DiffLineKind.del => (c.diffDeleted, c.danger),
      DiffLineKind.context => (Colors.transparent, c.ink3),
    };
    final numberStyle = DshType.mdCodeSmall.copyWith(color: c.ink3, fontSize: 10.5);
    final textStyle = DshType.mdCode.copyWith(
      color: line.kind == DiffLineKind.context ? c.ink2 : c.ink,
    );

    return Container(
      color: bg,
      padding: const EdgeInsets.only(right: DshSpace.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _gutter(line.oldNo, width, numberStyle),
          _gutter(line.newNo, width, numberStyle),
          SizedBox(
            width: _markerWidth,
            child: Text(
              line.marker,
              style: DshType.mdCode.copyWith(color: markerColor, fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
          ),
          Expanded(
            child: Text(
              line.text,
              style: textStyle,
              softWrap: true,
            ),
          ),
        ],
      ),
    );
  }

  Widget _gutter(int? no, double width, TextStyle style) => SizedBox(
        width: width,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: _gutterPad),
          child: Text(
            no == null ? '' : '$no',
            textAlign: TextAlign.right,
            style: style,
            maxLines: 1,
          ),
        ),
      );
}

class _FooterAction extends StatelessWidget {
  const _FooterAction({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = DshPalette.of(context);
    return InkWell(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        color: c.hover,
        padding: const EdgeInsets.symmetric(horizontal: DshSpace.md, vertical: DshSpace.sm),
        child: Text(
          label,
          style: DshType.xs13.copyWith(color: c.link, fontWeight: FontWeight.w500),
        ),
      ),
    );
  }
}

/// 对比不可用时的占位行（二进制 / 过大 / 相同 / 读取失败）。
class DiffPlaceholder extends StatelessWidget {
  const DiffPlaceholder({super.key, required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = DshPalette.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: DshSpace.md, vertical: DshSpace.lg),
      decoration: BoxDecoration(
        color: c.layer1,
        borderRadius: DshRadius.rMd,
        border: Border.fromBorderSide(DshStroke.side(c.line2)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: c.ink3),
          const SizedBox(width: DshSpace.sm),
          Expanded(child: Text(text, style: DshType.xs13.copyWith(color: c.ink3))),
        ],
      ),
    );
  }
}
