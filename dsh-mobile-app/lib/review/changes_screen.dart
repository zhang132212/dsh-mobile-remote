// 变更审阅页（v3.2.14）——一轮改动逐文件看 diff，取代「点开文件自己脑补改了什么」。
//
// 产品定位：agent 写完代码后，用户要的是 **review**，不是再读一遍全文。所以这一页按 PC 端
// review tab 的口径组织：摘要（几个文件、增删多少行）→ 文件选择器 → 单个文件的 unified diff
// （两侧行号、+/- 标记、整行底色、三行上下文）。对比是**本轮快照**，不是文件此刻的内容。
//
// 手机端的取舍：
//   · 只做单栏（左右对比在 6 寸屏每侧只剩 15 字符）；
//   · 逐行渲染 + 分批展开（400 行一档），5000 行硬上限与 PC 端同值；
//   · 二进制/过大/内容相同/对比超时各给一条人话说明，不画空框；
//   · 「打开文件」跳到文档阅读器并保留「改动」页签——读全文与看改动一键切换。

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api.dart';
import '../dsh_kit.dart';
import '../l10n.dart';
import '../screens/doc_viewer_screen.dart';
import '../theme.dart';
import '../toast.dart';
import 'diff_view.dart';
import 'model.dart';
import 'ref.dart';

class ChangesReviewScreen extends StatefulWidget {
  const ChangesReviewScreen({
    super.key,
    required this.sessionId,
    required this.seq,
    required this.turn,
    required this.api,
    this.initialIndex = 0,
  });

  final String sessionId;
  final int seq;
  final int turn;
  final Api api;
  final int initialIndex;

  @override
  State<ChangesReviewScreen> createState() => _ChangesReviewScreenState();
}

class _ChangesReviewScreenState extends State<ChangesReviewScreen> {
  TurnChanges? _changes;
  String? _error;
  bool _loading = true;
  int _index = 0;

  /// 每个文件只读一次（PC 端同样按 tab 缓存对比；手机切文件不会再打一次网络）。
  final Map<int, FileDiff> _diffs = {};
  final Map<int, String> _diffErrors = {};
  final Set<int> _diffLoading = {};

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    _loadSummary();
  }

  Future<void> _loadSummary() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final changes = await widget.api.changesSummary(widget.sessionId, widget.seq);
      if (!mounted) return;
      final files = changes?.files.length ?? 0;
      setState(() {
        _changes = changes;
        _loading = false;
        if (files > 0) _index = _index.clamp(0, files - 1);
      });
      if (changes != null && changes.files.isNotEmpty) _loadDiff(_index);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _loadDiff(int index, {bool force = false}) async {
    if (!force && (_diffs.containsKey(index) || _diffLoading.contains(index))) return;
    setState(() {
      _diffLoading.add(index);
      _diffErrors.remove(index);
    });
    try {
      final diff = await widget.api.changesDiff(widget.sessionId, widget.seq, index);
      if (!mounted) return;
      setState(() {
        _diffLoading.remove(index);
        if (diff == null) {
          _diffErrors[index] = L10n.t('对比已不可用（会话已释放或宿主重启过）', 'Comparison no longer available (session released or host restarted)');
        } else {
          _diffs[index] = diff;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _diffLoading.remove(index);
        _diffErrors[index] = '$e';
      });
    }
  }

  void _select(int index) {
    setState(() => _index = index);
    _loadDiff(index);
  }

  ChangedFile? get _currentFile {
    final files = _changes?.files;
    if (files == null || files.isEmpty) return null;
    return files[_index.clamp(0, files.length - 1)];
  }

  /// 打开完整文件（阅读页默认停在「文档」，需要对比时切到「改动」）。
  Future<void> _openFile() async {
    final file = _currentFile;
    final changes = _changes;
    if (file == null || changes == null) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => DocViewerScreen(
        name: file.name,
        remotePath: absolutePathOf(file, changes.cwd),
        api: widget.api,
        review: DocReviewRef(sessionId: widget.sessionId, seq: widget.seq, index: _index),
      ),
    ));
  }

  Future<void> _copyDiff() async {
    final diff = _diffs[_index];
    if (diff == null) return;
    final buffer = StringBuffer('${diff.display}\n');
    for (final hunk in diff.hunks) {
      buffer.writeln(hunk.header);
      for (final line in hunk.lines) {
        buffer.writeln(line);
      }
    }
    await Clipboard.setData(ClipboardData(text: buffer.toString()));
    if (mounted) showToast(context, L10n.t('已复制本文件对比', 'Copied this file diff'));
  }

  @override
  Widget build(BuildContext context) {
    final c = DshPalette.of(context);
    return Scaffold(
      backgroundColor: c.bg,
      appBar: DshAppBar(
        title: L10n.t('本轮改动', 'Changes this turn'),
        actions: [
          Center(
            child: DshIconButton(
              icon: Icons.refresh,
              tooltip: L10n.t('刷新', 'Refresh'),
              onTap: () {
                _diffs.clear();
                _diffErrors.clear();
                _loadSummary();
              },
            ),
          ),
        ],
      ),
      body: _body(c),
    );
  }

  Widget _body(DshPalette c) {
    if (_loading) return const DshLoading();
    final error = _error;
    if (error != null) {
      return DshError(
        message: L10n.t('读取本轮改动失败：$error', 'Failed to read changes: $error'),
        onRetry: _loadSummary,
      );
    }
    final changes = _changes;
    if (changes == null || changes.isEmpty) {
      return DshEmpty(
        icon: Icons.difference_outlined,
        title: L10n.t('本轮没有改动文件', 'No files changed this turn'),
        message: L10n.t(
          '只有文件工具的编辑会被记录；会话释放或电脑重启过之后，旧轮次的对比也会失效。',
          'Only file-tool edits are recorded; after the session is released or the host restarts, older turns lose their comparison.',
        ),
      );
    }

    return Column(
      children: [
        _summaryHeader(c, changes),
        _filePicker(c, changes),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(DshSpace.pageH, DshSpace.sm, DshSpace.pageH, DshSpace.xxxl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _diffHeader(c),
                const SizedBox(height: DshSpace.sm),
                _diffBody(c),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// 顶部摘要：轮次 + 文件数 + 增删合计（卡片同款数字，保证一眼对得上）。
  Widget _summaryHeader(DshPalette c, TurnChanges changes) => Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(DshSpace.pageH, DshSpace.md, DshSpace.pageH, DshSpace.sm),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    L10n.t('第 ${changes.turn} 轮 · ${changes.total} 个文件', 'Turn ${changes.turn} · ${changes.total} files'),
                    style: DshType.sStrong14.copyWith(color: c.ink),
                  ),
                  const SizedBox(height: DshSpace.xxs),
                  Text(
                    L10n.t('对比是本轮快照，不是文件当前内容', 'Comparison is a snapshot of this turn, not the current file'),
                    style: DshType.xxs12.copyWith(color: c.ink3),
                  ),
                ],
              ),
            ),
            DiffCounts(added: changes.added, deleted: changes.deleted),
          ],
        ),
      );

  /// 文件选择器：横向胶囊，文件名 + 各自增删（PC 端 review tab 头部选择器的手机形态）。
  Widget _filePicker(DshPalette c, TurnChanges changes) => SizedBox(
        height: DshSpace.controlLg,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: DshSpace.pageH),
          itemCount: changes.files.length,
          itemBuilder: (_, i) {
            final file = changes.files[i];
            return Padding(
              padding: const EdgeInsets.only(right: DshSpace.sm),
              child: Center(
                child: DshPill(
                  label: file.name,
                  active: i == _index,
                  onTap: () => _select(i),
                  trailing: Text(
                    file.hasCounts ? '+${file.added} −${file.deleted}' : file.countsLabel,
                    style: DshType.xxs12.copyWith(
                      fontFamilyFallback: DshType.monoFallback,
                      color: i == _index ? c.onInk : c.ink3,
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      );

  /// 单文件头：完整路径 + 状态说明 + 操作（上一个/下一个/打开文件/复制）。
  Widget _diffHeader(DshPalette c) {
    final file = _currentFile;
    final changes = _changes;
    if (file == null || changes == null) return const SizedBox.shrink();
    final diff = _diffs[_index];
    // 二进制/过大/内容相同的说明由正文占位行负责，这里只补「新建 / 删除 / 对比超时」——
    // 同一条文案出现两次反而让人以为有两个状态。
    final note = diff != null && diff.kind == FileDiffKind.text && !diff.identical
        ? diff.statusNote
        : null;
    final total = changes.files.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                file.display,
                style: DshType.mdCode.copyWith(color: c.ink, fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(width: DshSpace.sm),
            DshIconButton(
              icon: Icons.chevron_left,
              iconSize: 18,
              tooltip: L10n.t('上一个文件', 'Previous file'),
              onTap: _index > 0 ? () => _select(_index - 1) : null,
            ),
            DshIconButton(
              icon: Icons.chevron_right,
              iconSize: 18,
              tooltip: L10n.t('下一个文件', 'Next file'),
              onTap: _index < total - 1 ? () => _select(_index + 1) : null,
            ),
          ],
        ),
        const SizedBox(height: DshSpace.xs),
        Row(
          children: [
            if (note != null) ...[
              Flexible(
                child: Text(
                  note,
                  style: DshType.xxs12.copyWith(color: c.ink3),
                ),
              ),
              const SizedBox(width: DshSpace.sm),
            ],
            DiffCounts(added: file.added, deleted: file.deleted, binary: file.binary, oversized: file.oversized),
            const Spacer(),
            DshButton(
              label: L10n.t('打开文件', 'Open file'),
              variant: DshButtonVariant.outline,
              size: DshButtonSize.sm,
              onPressed: _openFile,
            ),
            const SizedBox(width: DshSpace.sm),
            DshIconButton(
              icon: Icons.content_copy,
              iconSize: 16,
              tooltip: L10n.t('复制对比', 'Copy diff'),
              onTap: diff == null ? null : _copyDiff,
            ),
          ],
        ),
      ],
    );
  }

  Widget _diffBody(DshPalette c) {
    final file = _currentFile;
    if (file == null) return const SizedBox.shrink();
    if (_diffLoading.contains(_index) && !_diffs.containsKey(_index)) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: DshSpace.xxl),
        child: DshLoading(),
      );
    }
    final error = _diffErrors[_index];
    if (error != null) {
      return DshBanner(
        message: L10n.t('读取对比失败：$error', 'Failed to load comparison: $error'),
        tone: DshBannerTone.danger,
        icon: Icons.error_outline,
        trailing: DshButton(
          label: L10n.t('重试', 'Retry'),
          variant: DshButtonVariant.outline,
          size: DshButtonSize.sm,
          onPressed: () => _loadDiff(_index, force: true),
        ),
      );
    }
    final diff = _diffs[_index];
    if (diff == null) return const SizedBox.shrink();

    if (diff.kind == FileDiffKind.binary) {
      return DiffPlaceholder(icon: Icons.data_array, text: L10n.t('二进制文件，没有逐行对比', 'Binary file — no line comparison'));
    }
    if (diff.kind == FileDiffKind.oversized) {
      return DiffPlaceholder(icon: Icons.unfold_more, text: L10n.t('文件超过 2 MB，未生成对比；可点「打开文件」看原文', 'File exceeds 2 MB — no comparison; tap "Open file" to read it'));
    }
    if (diff.identical) {
      return DiffPlaceholder(icon: Icons.check_circle_outline, text: diff.statusNote ?? L10n.t('本轮内容没有变化', 'No content change this turn'));
    }

    return SelectionArea(child: DiffHunksView(hunks: diff.hunks));
  }
}
