// 通知中心页（对齐网页端 notifications screen）
// 布局：官方标题栏 + 单行列表（状态图标 / 标题 / 详情 / 右侧时间）；未读用状态点。
// 删除：长按单条删除；右上角垃圾桶 → 批量多选删除 / 清空全部（插件端 /notifications/delete）。
import 'package:flutter/material.dart';
import '../l10n.dart';
import '../dsh_kit.dart';
import '../toast.dart';
import '../api.dart';
import '../models.dart';
import '../store.dart';
import '../theme.dart';
import 'chat_screen.dart';

class NotificationsScreen extends StatefulWidget {
  final AppStore store;
  final VoidCallback onOpenSession;
  const NotificationsScreen({super.key, required this.store, required this.onOpenSession});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<AppNotification> _items = [];
  bool _loaded = false;
  bool _deleting = false;
  bool _selecting = false; // 批量删除选择模式
  final Set<String> _selected = {};
  // v2.9.0 review(M5)：错误态（API 失败不误报"暂无通知"） + store 联动静默同步
  bool _error = false;
  int? _syncedUnread;

  @override
  void initState() {
    super.initState();
    widget.store.addListener(_onStoreChanged);
    _refresh();
  }

  @override
  void dispose() {
    widget.store.removeListener(_onStoreChanged);
    super.dispose();
  }

  void _onStoreChanged() {
    // v2.9.0 review(M5)：未读数变化（SSE 通知事件/角标刷新）→ 静默同步本页列表，不打断浏览
    if (!mounted || _deleting) return;
    final u = widget.store.unread;
    if (_syncedUnread == u) return;
    _syncedUnread = u;
    _silentRefresh();
  }

  Future<void> _silentRefresh() async {
    try {
      final items = await api.notifications();
      if (!mounted) return;
      setState(() {
        _items = items;
        _error = false;
        final alive = items.map((n) => n.id).toSet();
        _selected.removeWhere((id) => !alive.contains(id));
        if (_items.isEmpty) _selecting = false;
      });
    } catch (_) {
      // 静默失败：保留现有列表
    }
  }

  Future<void> _refresh() async {
    try {
      final items = await api.notifications();
      if (!mounted) return;
      setState(() {
        _items = items;
        _loaded = true;
        _error = false;
        // 已删除/新到的条目与选择集求交，防止残留选中
        final alive = items.map((n) => n.id).toSet();
        _selected.removeWhere((id) => !alive.contains(id));
        if (_items.isEmpty) _selecting = false;
      });
      widget.store.refreshNotifs();
    } catch (_) {
      // v2.9.0 review(M5)：失败记错误态（build 区分展示），不再静默吞掉
      if (mounted) {
        setState(() {
          _loaded = true;
          _error = true;
        });
      }
    }
  }

  Future<void> _open(AppNotification n) async {
    if (_selecting) {
      setState(() {
        if (!_selected.add(n.id)) _selected.remove(n.id);
      });
      return;
    }
    try {
      await api.markNotifsRead(ids: [n.id]);
      _refresh();
    } catch (_) {}
    if (!mounted) return;
    // Phase 2(A4)：统一打开会话流程（openChat 内 setSession+refreshSessionConfig+push+onReturn）
    await openChat(context, widget.store, n.sessionId,
        onTitleChanged: widget.onOpenSession,
        onReturn: () => widget.store.refreshSessions());
  }

  Future<void> _readAll() async {
    try {
      await api.markNotifsRead(all: true);
      _refresh();
      if (mounted) {
        showToast(context, L10n.t('已全部标记为已读', 'All marked as read'));
      }
    } catch (_) {}
  }

  /// 删除通知记录（插件端执行；桌面端插件重启后新接口才可用）。
  Future<void> _delete({List<String>? ids, bool all = false}) async {
    if (_deleting) return;
    _deleting = true;
    try {
      await api.deleteNotifs(ids: ids, all: all);
      // v3.0.0：await 后必须查 mounted——删除请求在途时用户按返回，页面已 dispose
      if (!mounted) return;
      setState(() {
        _selected.clear();
        _selecting = false;
      });
      await _refresh();
      if (mounted) {
        showToast(context, all ? L10n.t('已清空全部通知', 'All notifications cleared') : '${L10n.t('已删除 ', 'Deleted ')}${ids?.length ?? 0}${L10n.t(' 条通知', ' notifications')}');
      }
    } catch (_) {
      if (mounted) {
        showToast(context, L10n.t('删除失败：请先重启电脑端 dsh 以启用删除接口', 'Delete failed: restart dsh on the computer to enable deletion'));
      }
    } finally {
      _deleting = false;
    }
  }

  /// 长按单条 → 删除该条（官方底部弹层）。
  void _confirmDeleteOne(AppNotification n) {
    showDshSheet<void>(
      context: context,
      builder: (ctx) => DshSheet(
        title: n.title,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DshTile(
              leading: const Icon(Icons.delete_outline),
              title: L10n.t('删除这条通知', 'Delete this notification'),
              danger: true,
              onTap: () {
                Navigator.of(ctx).pop();
                _delete(ids: [n.id]);
              },
            ),
            DshTile(
              leading: const Icon(Icons.close),
              title: L10n.t('取消', 'Cancel'),
              onTap: () => Navigator.of(ctx).pop(),
            ),
          ],
        ),
      ),
    );
  }

  /// 右上角垃圾桶 → 批量多选 / 清空全部。
  void _showDeleteMenu() {
    showDshSheet<void>(
      context: context,
      builder: (ctx) => DshSheet(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DshTile(
              leading: const Icon(Icons.checklist),
              title: L10n.t('批量删除…', 'Batch delete…'),
              onTap: () {
                Navigator.of(ctx).pop();
                setState(() => _selecting = true);
              },
            ),
            DshTile(
              leading: const Icon(Icons.delete_sweep_outlined),
              title: L10n.t('清空全部通知', 'Clear all notifications'),
              danger: true,
              onTap: () {
                Navigator.of(ctx).pop();
                _confirmClearAll();
              },
            ),
            DshTile(
              leading: const Icon(Icons.close),
              title: L10n.t('取消', 'Cancel'),
              onTap: () => Navigator.of(ctx).pop(),
            ),
          ],
        ),
      ),
    );
  }

  /// 确认对话框：面/圆角/文字走 dialogTheme（R28 + 发丝边），按钮用官方按钮。
  void _confirmClearAll() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(L10n.t('清空全部通知', 'Clear all notifications')),
        content: Text(L10n.t('将删除全部通知记录，此操作不可恢复。', 'All notification records will be deleted. This cannot be undone.')),
        actionsPadding: const EdgeInsets.fromLTRB(
          DshSpace.xxl,
          DshSpace.md,
          DshSpace.xxl,
          DshSpace.xl,
        ),
        actions: [
          DshButton(
            label: L10n.t('取消', 'Cancel'),
            variant: DshButtonVariant.ghost,
            size: DshButtonSize.md,
            onPressed: () => Navigator.of(ctx).pop(),
          ),
          DshButton(
            label: L10n.t('清空', 'Clear'),
            variant: DshButtonVariant.danger,
            size: DshButtonSize.md,
            onPressed: () {
              Navigator.of(ctx).pop();
              _delete(all: true);
            },
          ),
        ],
      ),
    );
  }

  void _confirmDeleteSelected() {
    final n = _selected.length;
    if (n == 0) return;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(L10n.t('删除所选通知', 'Delete selected notifications')),
        content: Text('${L10n.t('将删除选中的 ', 'Delete the selected ')}$n${L10n.t(' 条通知记录，此操作不可恢复。', ' notification records. This cannot be undone.')}'),
        actionsPadding: const EdgeInsets.fromLTRB(
          DshSpace.xxl,
          DshSpace.md,
          DshSpace.xxl,
          DshSpace.xl,
        ),
        actions: [
          DshButton(
            label: L10n.t('取消', 'Cancel'),
            variant: DshButtonVariant.ghost,
            size: DshButtonSize.md,
            onPressed: () => Navigator.of(ctx).pop(),
          ),
          DshButton(
            label: L10n.t('删除', 'Delete'),
            variant: DshButtonVariant.danger,
            size: DshButtonSize.md,
            onPressed: () {
              Navigator.of(ctx).pop();
              _delete(ids: _selected.toList());
            },
          ),
        ],
      ),
    );
  }

  void _toggleSelectAll() {
    setState(() {
      if (_selected.length == _items.length) {
        _selected.clear();
      } else {
        _selected.addAll(_items.map((n) => n.id));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = DshPalette.of(context);
    final unreadCount = _items.where((n) => n.unread).length;
    final allSelected = _selecting && _selected.length == _items.length;

    return Scaffold(
      backgroundColor: c.bg,
      appBar: DshAppBar(
        title: _selecting
            ? '${L10n.t('已选 ', 'Selected ')}${_selected.length}${L10n.t(' 条', '')}'
            : L10n.t('通知', 'Notifications'),
        actions: [
          if (_selecting)
            DshButton(
              label: allSelected ? L10n.t('取消全选', 'Deselect all') : L10n.t('全选', 'Select all'),
              variant: DshButtonVariant.ghost,
              size: DshButtonSize.sm,
              onPressed: _toggleSelectAll,
            ),
          if (_selecting)
            DshButton(
              label: L10n.t('完成', 'Done'),
              variant: DshButtonVariant.ghost,
              size: DshButtonSize.sm,
              onPressed: () => setState(() {
                _selecting = false;
                _selected.clear();
              }),
            ),
          if (!_selecting && unreadCount > 0)
            DshButton(
              label: L10n.t('全部已读', 'Mark all read'),
              variant: DshButtonVariant.ghost,
              size: DshButtonSize.sm,
              onPressed: _readAll,
            ),
          if (!_selecting && _loaded && _items.isNotEmpty)
            DshIconButton(
              icon: Icons.delete_outline,
              tooltip: L10n.t('删除', 'Delete'),
              onTap: _showDeleteMenu,
            ),
          const SizedBox(width: DshSpace.sm),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: _loaded && _items.isEmpty
                  // v2.9.0 review(M5)：错误态与空态区分；错误态给重试入口
                  ? DshEmpty(
                      icon: _error ? Icons.cloud_off_outlined : Icons.notifications_none,
                      title: _error
                          ? L10n.t('通知加载失败', 'Failed to load notifications')
                          : L10n.t('暂无通知', 'No notifications'),
                      message: _error ? L10n.t('请检查与电脑的连接后重试', 'Check the connection to your PC and retry') : null,
                      action: _error
                          ? DshButton(
                              label: L10n.t('重试', 'Retry'),
                              variant: DshButtonVariant.outline,
                              size: DshButtonSize.sm,
                              onPressed: _refresh,
                            )
                          : null,
                      compact: true,
                    )
                  : RefreshIndicator(
                      onRefresh: _refresh,
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(
                          DshSpace.sm,
                          DshSpace.xs,
                          DshSpace.sm,
                          DshSpace.xl,
                        ),
                        itemCount: _items.length,
                        itemBuilder: (context, i) => _notificationRow(context, _items[i], c),
                      ),
                    ),
            ),
            // 批量删除底部操作条
            if (_selecting)
              DecoratedBox(
                decoration: BoxDecoration(
                  color: c.bg,
                  border: Border(top: DshStroke.side(c.line2)),
                ),
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      DshSpace.pageH,
                      DshSpace.sm,
                      DshSpace.pageH,
                      DshSpace.sm,
                    ),
                    child: Row(
                      children: [
                        Text(
                          '${L10n.t('已选 ', 'Selected ')}${_selected.length}${L10n.t(' 条', '')}',
                          style: DshType.xs13.copyWith(color: c.ink2),
                        ),
                        const Spacer(),
                        // 删除动作统一 danger
                        DshButton(
                          label: _deleting ? L10n.t('删除中…', 'Deleting…') : L10n.t('删除所选', 'Delete selected'),
                          variant: DshButtonVariant.danger,
                          size: DshButtonSize.md,
                          onPressed: _selected.isEmpty || _deleting ? null : _confirmDeleteSelected,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// 通知行：leading 状态图标 + 标题 + 详情 + 右侧时间（xxs12/caption）。
  /// 多选态铺 navAccent 底；未读用业务蓝点（不脉冲）。
  Widget _notificationRow(BuildContext context, AppNotification n, DshPalette c) {
    final (icon, color) = switch (n.kind) {
      'completed' => (Icons.check_circle_outline, c.ok),
      'failed' => (Icons.error_outline, c.danger),
      _ => (Icons.warning_amber_rounded, c.warn),
    };
    final dt = DateTime.fromMillisecondsSinceEpoch(n.time).toLocal();
    final tm = '${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    final selected = _selected.contains(n.id);

    return Padding(
      padding: const EdgeInsets.only(bottom: DshSpace.xxs),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: _selecting && selected ? c.navAccent : Colors.transparent,
          borderRadius: DshRadius.rMd,
        ),
        child: DshTile(
          leading: _selecting
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DshIconButton(
                      icon: selected ? Icons.check_circle : Icons.circle_outlined,
                      selected: selected,
                      iconSize: 20,
                    ),
                    const SizedBox(width: DshSpace.sm),
                    Icon(icon, color: color),
                  ],
                )
              : Icon(icon, color: color),
          title: n.title,
          subtitle: n.detail.isNotEmpty ? n.detail : null,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(tm, style: DshType.xxs12.copyWith(color: c.caption)),
              if (n.unread) ...[
                const SizedBox(width: DshSpace.sm),
                DshStatusDot(color: c.business, pulse: false),
              ],
            ],
          ),
          onTap: () => _open(n),
          onLongPress: _selecting ? null : () => _confirmDeleteOne(n),
        ),
      ),
    );
  }
}
