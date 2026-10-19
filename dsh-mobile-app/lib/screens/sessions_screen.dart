// 会话列表页（对齐网页端 sessions screen）
// 支持归档：主列表只显示活跃会话，长按可归档/恢复；顶部筛选切换已归档视图。
import 'dart:async';
import 'package:flutter/material.dart';
import '../l10n.dart';
import '../dsh_kit.dart';
import '../toast.dart';
import '../api.dart';
import '../models.dart';
import '../store.dart';
import '../theme.dart';
import '../fmt.dart';
import 'chat_screen.dart';

class SessionsScreen extends StatefulWidget {
  final AppStore store;
  final VoidCallback onOpenSession;
  const SessionsScreen({super.key, required this.store, required this.onOpenSession});

  @override
  State<SessionsScreen> createState() => _SessionsScreenState();
}

class _SessionsScreenState extends State<SessionsScreen> {
  bool _showArchived = false;

  @override
  void initState() {
    super.initState();
    widget.store.addListener(_onStore);
    widget.store.refreshSessions();
  }

  @override
  void dispose() {
    widget.store.removeListener(_onStore);
    super.dispose();
  }

  void _onStore() {
    if (mounted) setState(() {});
  }

  Future<void> _open(Session s) async {
    // Phase 2(A4)：统一打开会话流程（openChat 内 setSession+refreshSessionConfig+push）
    await openChat(context, widget.store, s.id,
        onTitleChanged: widget.onOpenSession,
        onReturn: () => widget.store.refreshSessions());
  }

  Future<void> _showActions(Session s) async {
    final isArchived = s.archived;
    final action = await showDshSheet<String>(
      context: context,
      builder: (ctx) => DshSheet(
        title: s.label,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DshTile(
              leading: const Icon(Icons.chat_bubble_outline),
              title: L10n.t('打开', 'Open'),
              onTap: () => Navigator.of(ctx).pop('open'),
            ),
            DshTile(
              leading: Icon(isArchived ? Icons.unarchive_outlined : Icons.archive_outlined),
              title: isArchived ? L10n.t('恢复（取消归档）', 'Restore (unarchive)') : L10n.t('归档该会话', 'Archive this session'),
              onTap: () => Navigator.of(ctx).pop(isArchived ? 'unarchive' : 'archive'),
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
    if (action == null || !mounted) return;
    if (action == 'open') {
      await _open(s);
      return;
    }
    try {
      await api.archiveSession(s.id, archive: action == 'archive');
      // v2.7.1：乐观更新——本地立即生效（列表秒变），后台静默刷新校准
      // （服务端列表标题折叠 50+ 会话可达数秒，等它会让"归档要等几秒"）
      widget.store.applyArchiveLocally(s.id, archived: action == 'archive');
      unawaited(widget.store.refreshSessions());
      if (!mounted) return;
      showToast(context, action == 'archive' ? L10n.t('已归档', 'Archived') : L10n.t('已恢复', 'Restored'));
    } catch (e) {
      if (!mounted) return;
      // 失败回滚本地状态（刷新真实列表校准）
      unawaited(widget.store.refreshSessions());
      showToast(context, '${L10n.t('操作失败：', 'Operation failed:')}$e${L10n.t('（桌面端插件需要重启生效）', ' (restart the desktop plugin to take effect)')}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    final sessions = _showArchived ? store.archivedSessions : store.activeSessions;
    final c = DshPalette.of(context);

    return Column(
      children: [
        // 工作区筛选（≥2 个工作区时显示，对齐 PC 端快速切换）
        if (store.workspaces.length >= 2) ...[
          DshSectionHeader(
            L10n.t('工作区', 'Workspaces'),
            padding: const EdgeInsets.fromLTRB(
              DshSpace.pageH,
              DshSpace.md,
              DshSpace.pageH,
              DshSpace.sm,
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: DshSpace.pageH),
            child: Row(
              children: [
                _FilterChip(
                  label: L10n.t('全部', 'All'),
                  selected: store.workspacePath == null,
                  onTap: () => store.setWorkspace(null),
                ),
                for (final w in store.workspaces) ...[
                  const SizedBox(width: DshSpace.sm),
                  _FilterChip(
                    label: (w['title'] as String?) ?? (w['path'] as String? ?? ''),
                    // v3.1.1(issue #5)：原始路径做展示，规范化后与 workspacePath（归一存储）匹配
                    selected: store.workspacePath == AppStore.normPath(w['path'] as String? ?? ''),
                    onTap: () => store.setWorkspace(w['path'] as String?),
                  ),
                ],
              ],
            ),
          ),
        ],
        // 活跃 / 已归档 分段控件
        Padding(
          padding: const EdgeInsets.fromLTRB(
            DshSpace.pageH,
            DshSpace.md,
            DshSpace.pageH,
            DshSpace.sm,
          ),
          child: DshSegmented(
            items: [
              '${L10n.t('活跃', 'Active')} ${store.activeSessions.length}',
              '${L10n.t('已归档', 'Archived')} ${store.archivedSessions.length}',
            ],
            index: _showArchived ? 1 : 0,
            onChanged: (i) => setState(() => _showArchived = i == 1),
          ),
        ),
        Expanded(
          // 会话列表是"侧栏类列表"：底色用 sidebar，行靠 R12 选中/hover 底分层
          child: ColoredBox(
            color: c.sidebar,
            child: _showArchived && store.archivedSessions.isEmpty
                ? DshEmpty(
                    icon: Icons.archive_outlined,
                    title: L10n.t('暂无归档会话', 'No archived sessions'),
                    compact: true,
                  )
                : sessions.isEmpty
                    ? DshEmpty(
                        icon: Icons.forum_outlined,
                        title: L10n.t('暂无会话', 'No sessions'),
                        compact: true,
                      )
                    : RefreshIndicator(
                        onRefresh: () => widget.store.refreshSessions(),
                        // 官方侧栏会话行：R12 整行、行间 2px 留白（不用分隔线）
                        child: ListView.separated(
                          padding: const EdgeInsets.fromLTRB(
                            DshSpace.sm,
                            DshSpace.xs,
                            DshSpace.sm,
                            DshSpace.lg,
                          ),
                          itemCount: sessions.length,
                          separatorBuilder: (_, _) => const SizedBox(height: DshSpace.xxs),
                          itemBuilder: (context, i) => _sessionRow(context, sessions[i], c),
                        ),
                      ),
          ),
        ),
      ],
    );
  }

  /// 会话行：标题 s14/ink、副标题（时间 · 工作区）xs13/ink3、整行 R12。
  /// 归档项用 caption 文字降调，不铺灰底。
  Widget _sessionRow(BuildContext context, Session s, DshPalette c) {
    final archived = s.archived;
    final sub = '${relTime(s.sortKey)}${s.cwd != null ? ' · ${s.cwd}' : ''}';
    return DshTile(
      leading: Icon(
        archived ? Icons.archive_outlined : Icons.description_outlined,
        color: archived ? c.caption : c.ink2,
      ),
      titleWidget: Text(
        s.label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: DshType.s14.copyWith(color: archived ? c.caption : c.ink),
      ),
      subtitleWidget: Text(
        sub,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: DshType.xs13.copyWith(color: archived ? c.caption : c.ink3),
      ),
      onTap: () => _open(s),
      onLongPress: () => _showActions(s),
      chevron: true,
    );
  }
}

/// 筛选胶囊：官方胶囊选择器（999px + selector 底，选中主色填充）。
class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _FilterChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return DshPill(label: label, active: selected, onTap: onTap);
  }
}
