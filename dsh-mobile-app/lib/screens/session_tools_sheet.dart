// 会话工具弹层（v2.7）：任务（后台任务）/ 子代理 / 目标 三个页签。
// 数据与 PC 端同源：任务走 session/jobs 帧 + /api/jobs；子代理/目标走插件端点。
//
// 版式：统一 showDshSheet + DshSheet（R28 顶角 + 拖拽把手 + 标题），
// 页签用官方 DshSegmented（外框 R12 + 4px 内衬 + R8 段），行与卡片走 DshTile/DshCard。
import 'dart:async';

import 'package:flutter/material.dart';
import '../api.dart';
import '../dsh_kit.dart';
import '../l10n.dart';
import '../store.dart';
import '../theme.dart';
import '../toast.dart';
import 'chat_screen.dart';

/// 打开会话工具面板。
///
/// [onTitleChanged] 由调用方（聊天页）透传：跳进子代理会话后，标题变化仍能同步到会话列表。
/// [apiClient] 仅供测试注入（与 `ChatScreen.apiClient` 同款）；生产路径传 null 即用全局 `api`。
void showSessionToolsSheet(BuildContext context, AppStore store, String sessionId,
    {VoidCallback? onTitleChanged, Api? apiClient}) {
  // 面板关闭与子会话跳转都挂在**调用方上下文**上——面板自己的 ctx 在 pop 之后就不能再用。
  final navigator = Navigator.of(context);
  showDshSheet<void>(
    context: context,
    builder: (ctx) => _SessionToolsSheet(
      store: store,
      sessionId: sessionId,
      apiClient: apiClient,
      // #11 复核补正：子代理行可点 → 跳到该子代理会话。
      // 走统一入口 openChat，返回时恢复原会话（与「分支」流程同款语义：顺路看一眼，不改主会话）。
      onOpenSubagent: (childId) {
        navigator.pop();
        unawaited(openChat(context, store, childId,
            onTitleChanged: onTitleChanged ?? () {},
            apiClient: apiClient,
            onReturn: () async {
          if (sessionId != childId) await store.setSession(sessionId);
        }));
      },
    ),
  );
}

class _SessionToolsSheet extends StatefulWidget {
  final AppStore store;
  final String sessionId;
  final void Function(String childSessionId) onOpenSubagent;
  final Api? apiClient;
  const _SessionToolsSheet({
    required this.store,
    required this.sessionId,
    required this.onOpenSubagent,
    this.apiClient,
  });

  @override
  State<_SessionToolsSheet> createState() => _SessionToolsSheetState();
}

class _SessionToolsSheetState extends State<_SessionToolsSheet>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this);
  // 分段控件的高亮下标：与 TabController 同步（左右滑动切页时也要跟上）
  int _segIndex = 0;

  @override
  void initState() {
    super.initState();
    _tabs.addListener(_syncIndex);
  }

  void _syncIndex() {
    if (mounted && _tabs.index != _segIndex) {
      setState(() => _segIndex = _tabs.index);
    }
  }

  @override
  void dispose() {
    _tabs.removeListener(_syncIndex);
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 把手 + 标题 + 分段控件占高：面板整体高度与旧版（0.62 屏高）持平
    final bodyHeight =
        (MediaQuery.of(context).size.height * 0.62 - 104).clamp(200.0, 720.0).toDouble();
    return DshSheet(
      title: L10n.t('会话工具', 'Session Tools'),
      scrollable: false,
      padding: EdgeInsets.zero,
      child: SizedBox(
        height: bodyHeight,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                DshSpace.xl,
                0,
                DshSpace.xl,
                DshSpace.md,
              ),
              child: DshSegmented(
                items: [
                  L10n.t('任务', 'Jobs'),
                  L10n.t('子代理', 'Subagents'),
                  L10n.t('目标', 'Goal'),
                ],
                index: _segIndex,
                onChanged: (i) => _tabs.animateTo(i),
              ),
            ),
            Expanded(
              child: TabBarView(
                controller: _tabs,
                children: [
                  _JobsTab(store: widget.store, sessionId: widget.sessionId),
                  _SubagentsTab(
                    sessionId: widget.sessionId,
                    onOpenSubagent: widget.onOpenSubagent,
                    apiClient: widget.apiClient,
                  ),
                  _GoalTab(sessionId: widget.sessionId, apiClient: widget.apiClient),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 页签内容的统一内衬（外层弹层已去掉内衬，列表回到行内衬 12 + 8 = 20，与标题对齐）。
const EdgeInsets _tabPadding = EdgeInsets.fromLTRB(
  DshSpace.sm,
  DshSpace.sm,
  DshSpace.sm,
  DshSpace.lg,
);

/// 元信息行（12/18 · tertiary）。
Widget _meta(String text) => Builder(
      builder: (context) => Text(
        text,
        style: DshType.xxs12.copyWith(color: DshPalette.of(context).ink3),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
    );

// ── 任务页签 ──
class _JobsTab extends StatefulWidget {
  final AppStore store;
  final String sessionId;
  const _JobsTab({required this.store, required this.sessionId});

  @override
  State<_JobsTab> createState() => _JobsTabState();
}

class _JobsTabState extends State<_JobsTab> {
  List<Map<String, dynamic>>? _jobs;
  String? _error;
  // v3.0.0 review：取消任务在途锁（防连点重复请求/闪烁）
  bool _killBusy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // v2.7.2 review：弹层可下滑关闭,异步回调后必须防 setState-after-dispose
    if (!mounted) return;
    setState(() => _jobs = null);
    try {
      final list = await api.jobs(widget.sessionId);
      if (!mounted) return;
      setState(() => _jobs = list);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    }
  }

  Future<void> _kill(Map<String, dynamic> job) async {
    if (_killBusy) return;
    _killBusy = true;
    try {
      await api.jobKill(widget.sessionId, job['id'] as String? ?? '');
      if (mounted) showToast(context, L10n.t('已请求取消任务', 'Cancel requested'));
      if (mounted) _load();
    } catch (e) {
      if (mounted) showToast(context, '${L10n.t('取消失败：', 'Cancel failed: ')}$e');
    } finally {
      _killBusy = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = DshPalette.of(context);
    if (_error != null) {
      return DshError(
        message: '${L10n.t('加载失败：', 'Failed to load: ')}$_error',
        onRetry: _load,
      );
    }
    final jobs = _jobs;
    if (jobs == null) return const DshLoading();
    if (jobs.isEmpty) {
      return DshEmpty(icon: Icons.history_toggle_off_outlined, title: L10n.t('暂无任务', 'No jobs'));
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: _tabPadding,
        itemCount: jobs.length,
        separatorBuilder: (_, _) => const DshDivider(
          indent: DshSpace.md,
          endIndent: DshSpace.md,
        ),
        itemBuilder: (context, i) {
          final j = jobs[i];
          final status = j['status'] as String? ?? '';
          final running = status == 'running' || status == 'stopping';
          // 运行中 → business（脉冲）、成功 → ok、失败 → danger，其余按未激活处理
          final dotColor = status == 'completed'
              ? c.ok
              : running
                  ? c.business
                  : status == 'failed'
                      ? c.danger
                      : c.idle;
          final label = (j['label'] as String? ?? j['id'] as String? ?? L10n.t('任务', 'Job')).toString();
          final kind = j['kind'] as String?;
          return DshTile(
            dense: true,
            // 与官方 leading 图标同尺寸的占位：脉冲环扩张时不挤压标题
            leading: SizedBox(
              width: DshSpace.xl,
              height: DshSpace.xl,
              child: Center(child: DshStatusDot(color: dotColor, pulse: running)),
            ),
            title: label,
            subtitleWidget: _meta([if (kind != null && kind.isNotEmpty) kind, status].join(' · ')),
            trailing: status == 'running'
                ? DshButton(
                    label: L10n.t('取消', 'Cancel'),
                    variant: DshButtonVariant.danger,
                    size: DshButtonSize.sm,
                    onPressed: () => _kill(j),
                  )
                : null,
          );
        },
      ),
    );
  }
}

// ── 子代理页签 ──
class _SubagentsTab extends StatefulWidget {
  final String sessionId;
  final void Function(String childSessionId) onOpenSubagent;
  final Api? apiClient;
  const _SubagentsTab({required this.sessionId, required this.onOpenSubagent, this.apiClient});

  @override
  State<_SubagentsTab> createState() => _SubagentsTabState();
}

class _SubagentsTabState extends State<_SubagentsTab> {
  List<Map<String, dynamic>>? _subs;
  String? _error;
  // v3.0.0 review：中断在途锁（防连点重复请求/闪烁）
  bool _interruptBusy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _subs = null);
    try {
      final list = await (widget.apiClient ?? api).subagents(widget.sessionId);
      if (!mounted) return;
      setState(() => _subs = list);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    }
  }

  Future<void> _interrupt(String childId) async {
    if (_interruptBusy) return;
    _interruptBusy = true;
    try {
      await (widget.apiClient ?? api).subagentInterrupt(widget.sessionId, childId);
      if (mounted) showToast(context, L10n.t('已请求中断子代理', 'Interrupt requested'));
    } catch (e) {
      if (mounted) showToast(context, '${L10n.t('中断失败：', 'Interrupt failed: ')}$e');
    } finally {
      _interruptBusy = false;
    }
  }

  /// 子代理状态标签（`DshTag`）：运行中 business、失败 danger，其余中性。
  (String, Color, Color) _statusTag(DshPalette c, String status) => switch (status) {
        'running' => (L10n.t('运行中', 'Running'), c.business, c.bubble),
        'inactive' => (L10n.t('已结束', 'Inactive'), c.ink3, c.tag),
        'failed' || 'error' => (L10n.t('失败', 'Failed'), c.danger, c.dangerSoft),
        _ => (status, c.ink3, c.tag),
      };

  @override
  Widget build(BuildContext context) {
    final c = DshPalette.of(context);
    if (_error != null) {
      return DshError(
        message: '${L10n.t('加载失败：', 'Failed to load: ')}$_error',
        onRetry: _load,
      );
    }
    final subs = _subs;
    if (subs == null) return const DshLoading();
    if (subs.isEmpty) {
      return DshEmpty(icon: Icons.polyline_outlined, title: L10n.t('暂无子代理', 'No subagents'));
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: _tabPadding,
        itemCount: subs.length,
        separatorBuilder: (_, _) => const DshDivider(
          indent: DshSpace.md,
          endIndent: DshSpace.md,
        ),
        itemBuilder: (context, i) {
          final s = subs[i];
          final id = (s['id'] as String? ?? '').toString();
          final status = (s['status'] as String? ?? '').toString();
          final running = status == 'running';
          final (tagLabel, tagFg, tagBg) = _statusTag(c, status);
          return DshTile(
            dense: true,
            leading: const Icon(Icons.polyline_outlined),
            // v3.1.5（#11 复核补正）：整行可点 → 跳到该子代理会话；右侧箭头提示可进入。
            onTap: id.isEmpty ? null : () => widget.onOpenSubagent(id),
            titleWidget: Row(
              children: [
                Flexible(
                  child: Text(
                    (s['title'] as String? ?? id).toString(),
                    style: DshType.s14.copyWith(color: c.ink),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (tagLabel.isNotEmpty) ...[
                  const SizedBox(width: DshSpace.sm),
                  DshTag(
                    dense: true,
                    label: tagLabel,
                    color: tagFg,
                    background: tagBg,
                  ),
                ],
              ],
            ),
            subtitleWidget: id.isEmpty ? null : _meta(id),
            trailing: running
                ? DshButton(
                    label: L10n.t('中断', 'Interrupt'),
                    variant: DshButtonVariant.danger,
                    size: DshButtonSize.sm,
                    onPressed: () => _interrupt(id),
                  )
                : null,
            chevron: id.isNotEmpty,
          );
        },
      ),
    );
  }
}

// ── 目标页签 ──
class _GoalTab extends StatefulWidget {
  final String sessionId;
  final Api? apiClient;
  const _GoalTab({required this.sessionId, this.apiClient});

  @override
  State<_GoalTab> createState() => _GoalTabState();
}

class _GoalTabState extends State<_GoalTab> {
  Map<String, dynamic>? _goal;
  String? _error;
  bool _loaded = false; // 区分「加载中」与「已加载但无目标」（goal 为 null 是合法状态）
  final _objCtrl = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _objCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loaded = false;
      _error = null;
    });
    try {
      final g = await (widget.apiClient ?? api).goal(widget.sessionId);
      if (!mounted) return;
      setState(() {
        _goal = g;
        _loaded = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    }
  }

  Future<void> _act(String action, {String? objective}) async {
    setState(() => _busy = true);
    try {
      await (widget.apiClient ?? api).goalAction(action, sessionId: widget.sessionId, objective: objective);
      if (mounted) showToast(context, '${L10n.t('已', '')}${action == 'create' ? L10n.t('创建', 'Created') : action}');
      if (action == 'create') _objCtrl.clear();
    } catch (e) {
      if (mounted) showToast(context, '${L10n.t('操作失败：', 'Action failed: ')}$e');
    } finally {
      // 无论成败都刷新：PC/目标驱动可能已改变状态（如轮次耗尽→受阻），UI 需反映真实情况
      // v2.7.2 review：弹层可下滑关闭,await 后必须防 setState-after-dispose
      if (mounted) await _load();
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 目标状态 → `DshTag` 配色（进行中 business、已完成 ok、暂停 warn、受阻 danger）。
  static (Color, Color) _phaseTone(DshPalette c, String phase) => switch (phase) {
        'active' => (c.business, c.bubble),
        'complete' => (c.ok, c.okSoft),
        'paused' => (c.warnLabel, c.warnSoft),
        'blocked' => (c.danger, c.dangerSoft),
        _ => (c.ink3, c.tag),
      };

  @override
  Widget build(BuildContext context) {
    final c = DshPalette.of(context);
    if (_error != null) {
      return DshError(
        message: '${L10n.t('加载失败：', 'Failed to load: ')}$_error',
        onRetry: _load,
      );
    }
    final goal = _goal;
    if (!_loaded) return const DshLoading();
    // 内核 GoalView 状态字段是 phase（active/paused/blocked/complete）
    final phase = (goal?['phase'] as String? ?? '').toString();
    String phaseLabel(String p) => switch (p) {
          'active' => L10n.t('进行中', 'Active'),
          'paused' => L10n.t('已暂停', 'Paused'),
          'blocked' => L10n.t('受阻', 'Blocked'),
          'complete' => L10n.t('已完成', 'Complete'),
          _ => p,
        };
    final footnote = Text(
      L10n.t('目标与 PC 端同源（goal 服务）；修改即时生效。',
          'Goal data is synced with the desktop app (goal service); changes take effect immediately.'),
      style: DshType.xxs12.copyWith(color: c.ink3),
    );

    if (goal == null || goal.isEmpty) {
      return ListView(
        padding: _tabPadding,
        children: [
          DshEmpty(
            compact: true,
            icon: Icons.flag_outlined,
            title: L10n.t('当前没有目标', 'No goal yet'),
          ),
          const SizedBox(height: DshSpace.lg),
          TextField(
            controller: _objCtrl,
            style: DshType.s14.copyWith(color: c.ink),
            maxLines: 2,
            decoration: InputDecoration(hintText: L10n.t('输入目标…', 'Enter a goal…')),
          ),
          const SizedBox(height: DshSpace.md),
          DshButton(
            label: L10n.t('创建目标', 'Create Goal'),
            icon: Icons.add,
            variant: DshButtonVariant.primary,
            expanded: true,
            onPressed: _busy ? null : () => _act('create', objective: _objCtrl.text.trim()),
          ),
          const SizedBox(height: DshSpace.lg),
          footnote,
        ],
      );
    }

    final rounds = (goal['roundsStarted'] as num?)?.toInt() ?? 0;
    final maxRounds = (goal['maxGoalRounds'] as num?)?.toInt();
    final (tagFg, tagBg) = _phaseTone(c, phase);
    return ListView(
      padding: _tabPadding,
      children: [
        DshCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      (goal['objective'] as String? ?? '').toString(),
                      style: DshType.sStrong14.copyWith(color: c.ink),
                    ),
                  ),
                  const SizedBox(width: DshSpace.sm),
                  DshTag(label: phaseLabel(phase), color: tagFg, background: tagBg),
                ],
              ),
              const SizedBox(height: DshSpace.sm),
              _meta('${L10n.t('轮次 ', 'Rounds: ')}$rounds/${maxRounds ?? '∞'}'),
              if (maxRounds != null && maxRounds > 0) ...[
                const SizedBox(height: DshSpace.sm),
                DshProgressBar(value: rounds / maxRounds, color: c.business),
              ],
              if (phase == 'blocked' && goal['blockedReason'] is Map) ...[
                const SizedBox(height: DshSpace.md),
                DshBanner(
                  message:
                      ((goal['blockedReason'] as Map)['message'] as String? ?? '').toString(),
                  icon: Icons.error_outline,
                  tone: DshBannerTone.danger,
                ),
              ],
              const SizedBox(height: DshSpace.lg),
              Row(
                children: [
                  Expanded(
                    child: DshButton(
                      label: phase == 'paused' ? L10n.t('继续', 'Resume') : L10n.t('暂停', 'Pause'),
                      variant: DshButtonVariant.outline,
                      expanded: true,
                      onPressed:
                          _busy ? null : () => _act(phase == 'paused' ? 'resume' : 'pause'),
                    ),
                  ),
                  const SizedBox(width: DshSpace.md),
                  Expanded(
                    child: DshButton(
                      label: L10n.t('标记完成', 'Mark Complete'),
                      variant: DshButtonVariant.primary,
                      expanded: true,
                      onPressed: _busy ? null : () => _act('complete'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: DshSpace.md),
        footnote,
      ],
    );
  }
}
