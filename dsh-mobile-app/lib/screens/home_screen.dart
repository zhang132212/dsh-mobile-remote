// 首页：欢迎 + 连接状态 + 最近会话 + 新建会话
import 'package:flutter/material.dart';
import '../l10n.dart';
import '../dsh_kit.dart';
import '../toast.dart';
import '../models.dart';
import '../store.dart';
import '../theme.dart';
import '../fmt.dart';
import 'chat_screen.dart';
import 'doc_browser_screen.dart';
import 'sheets.dart';

class HomeScreen extends StatefulWidget {
  final AppStore store;
  final VoidCallback onOpenSession;
  const HomeScreen({super.key, required this.store, required this.onOpenSession});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // v3.0.0 review：新建会话弹层打开中标志（双击防抖）
  bool _openingSheet = false;

  @override
  void initState() {
    super.initState();
    widget.store.addListener(_onStore);
  }

  @override
  void dispose() {
    widget.store.removeListener(_onStore);
    super.dispose();
  }

  void _onStore() {
    if (mounted) setState(() {});
  }

  Future<void> _openSession(Session s) async {
    // Phase 2(A4)：统一打开会话流程（openChat 内 setSession+refreshSessionConfig+push）
    await openChat(context, widget.store, s.id,
        onTitleChanged: widget.onOpenSession,
        onReturn: () => widget.store.refreshSessions());
  }

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    final c = DshPalette.of(context);
    // 连接状态：与顶栏状态点同源（纯展示，点按重连仍在顶栏）
    final (connColor, connLabel) = switch (store.connState) {
      'connected' => (c.ok, L10n.t('电脑在线', 'PC online')),
      'connecting' => (c.warn, L10n.t('连接中…', 'Connecting…')),
      _ => (c.ink3, L10n.t('电脑离线', 'PC offline')),
    };
    final recentTitle = store.workspaceTitle != null
        ? '${L10n.t('最近会话', 'Recent Sessions')} · ${store.workspaceTitle}'
        : L10n.t('最近会话', 'Recent Sessions');

    return Column(
      children: [
        Expanded(
          // 下拉刷新：探测 → 自愈（轮换地址/重建连接）→ 拉数据；仅失败时提示
          child: RefreshIndicator(
            onRefresh: () async {
              final ok = await widget.store.refreshAll();
              if (!ok && context.mounted) {
                showToast(context, L10n.t('电脑连接不上，正在自动重连…', 'Cannot reach your PC, reconnecting…'));
              }
            },
            child: LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                // 内容不满一屏时整体垂直居中（去掉底部输入框后主页不再空底）；
                // alignment.y=-0.6 让内容块明显偏上（logo 贴近顶部，下半留白）
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: Align(
                    alignment: const Alignment(0, -0.6),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: DshSpace.pageH,
                        vertical: DshSpace.xxl,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // 官方 logo（DeepSeek 官网 favicon 转 PNG，蓝鲸标志）
                          Center(
                            child: Image.asset(
                              'assets/deepseek-logo.png',
                              width: 72,
                              height: 72,
                            ),
                          ),
                          const SizedBox(height: DshSpace.lg),
                          // 欢迎
                          Text(
                            L10n.t('今天打算设计什么？', 'What are you designing today?'),
                            textAlign: TextAlign.center,
                            style: DshType.l20.copyWith(color: c.ink),
                          ),
                          const SizedBox(height: DshSpace.md),
                          // 连接状态：状态点 + 标签
                          Center(
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                DshStatusDot(
                                  color: connColor,
                                  pulse: store.connState == 'connecting',
                                ),
                                const SizedBox(width: DshSpace.sm),
                                DshTag(label: connLabel, color: connColor),
                              ],
                            ),
                          ),
                          const SizedBox(height: DshSpace.xxl),
                          // 最近会话（分组标题 + 官方设置卡片）
                          DshSectionHeader(
                            recentTitle,
                            padding: const EdgeInsets.only(
                              left: DshSpace.xs,
                              right: DshSpace.xs,
                              bottom: DshSpace.sm,
                            ),
                          ),
                          DshCard(
                            padding: const EdgeInsets.symmetric(
                              vertical: DshSpace.xs,
                            ),
                            child: store.activeSessions.isEmpty
                                ? Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: DshSpace.xxl,
                                    ),
                                    child: Center(
                                      child: Text(
                                        L10n.t('暂无会话，点下方新建', 'No sessions yet, create one below'),
                                        style: DshType.xs13.copyWith(color: c.ink3),
                                      ),
                                    ),
                                  )
                                // 恰好完整显示 3 行（3×H64+发丝线），第 4 行露边提示可滑动
                                : ConstrainedBox(
                                    constraints: const BoxConstraints(
                                      maxHeight: DshSpace.rowMinTwoLine * 3,
                                    ),
                                    child: ListView.separated(
                                      shrinkWrap: true,
                                      padding: EdgeInsets.zero,
                                      itemCount: store.activeSessions.length,
                                      separatorBuilder: (_, _) => const DshDivider(
                                        indent: DshSpace.md,
                                        endIndent: DshSpace.md,
                                      ),
                                      itemBuilder: (context, i) => _SessionRow(
                                        session: store.activeSessions[i],
                                        workspace: store.workspaceLabelOf(store.activeSessions[i]),
                                        onTap: () => _openSession(store.activeSessions[i]),
                                      ),
                                    ),
                                  ),
                          ),
                          const SizedBox(height: DshSpace.lg),
                          // 新建会话
                          DshButton(
                            label: L10n.t('＋ 新建会话', '+ New Session'),
                            variant: DshButtonVariant.primary,
                            size: DshButtonSize.lg,
                            expanded: true,
                            // v3.0.0 review：双击防抖——连点会并行弹出两个新建会话弹层
                            onPressed: () {
                              if (_openingSheet) return;
                              _openingSheet = true;
                              showNewSessionSheet(context, store, (id) async {
                                // Phase 2(A4)：openChat 内统一 setSession+refreshSessionConfig+push，这里只刷列表
                                store.refreshSessions();
                                if (!context.mounted) return;
                                await openChat(context, store, id,
                                    onTitleChanged: widget.onOpenSession);
                              }).whenComplete(() => _openingSheet = false);
                            },
                          ),
                          const SizedBox(height: DshSpace.sm),
                          // v3.2.0：文档阅读入口——浏览电脑工作区里的
                          // md / txt / docx / xlsx 并直接在手机上阅读（公式真排版、
                          // 超链接可点、可导出带 Word 原生公式的 .docx）
                          DshButton(
                            label: L10n.t('文档阅读', 'Read Documents'),
                            icon: Icons.menu_book_outlined,
                            variant: DshButtonVariant.outline,
                            size: DshButtonSize.lg,
                            expanded: true,
                            onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(builder: (_) => const DocBrowserScreen()),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// 最近会话行：官方列表行几何（H64 双行、标题 14/ink、副标题 13/ink3、R12）。
class _SessionRow extends StatelessWidget {
  final Session session;
  final String? workspace; // 所属工作区标题（null = 无工作区概念，不显示）
  final VoidCallback onTap;
  const _SessionRow({required this.session, this.workspace, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return DshTile(
      leading: const Icon(Icons.description_outlined),
      title: session.label,
      subtitle: workspace == null
          ? relTime(session.sortKey)
          : '${relTime(session.sortKey)} · $workspace',
      onTap: onTap,
      chevron: true,
    );
  }
}
