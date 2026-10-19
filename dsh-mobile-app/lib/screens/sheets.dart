// 底部弹层组：模型与推理 / 权限预设（含风险确认）/ 新建会话 / 目录选择 / 新建文件夹 / 执行动作。
//
// 统一规格（见 UI_STYLE_GUIDE.md）：一律 showDshSheet 弹出 + DshSheet 容器——
// R28 顶角、36×4 拖拽把手、m16 标题、底部动作区；遮罩走 mask，
// 弹层自身不加投影，靠 layer1 填充 + 发丝边分层。
import 'package:flutter/material.dart';
import '../api.dart';
import '../dsh_kit.dart';
import '../fmt.dart';
import '../l10n.dart';
import '../models.dart';
import '../store.dart';
import '../theme.dart';
import '../toast.dart';
import 'providers_screen.dart';

/// 通用底部弹层容器（官方 DshSheet：R28 顶角 + 拖拽把手 + 标题 + 可滚动内容）。
void showSheet(BuildContext context, String title, List<Widget> children) {
  showDshSheet<void>(
    context: context,
    builder: (_) => DshSheet(
      title: title,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    ),
  );
}

/// 卡片式单选项（预设/权限）：选中态描边转 `ink3`，危险项走 `danger` 语义色。
class _OptionCard extends StatelessWidget {
  const _OptionCard({
    required this.title,
    this.subtitle,
    this.selected = false,
    this.danger = false,
    required this.onTap,
  });

  final String title;
  final String? subtitle;
  final bool selected;
  final bool danger;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = DshPalette.of(context);
    final sub = subtitle;
    return DshCard(
      onTap: onTap,
      selected: selected,
      padding: const EdgeInsets.symmetric(
        horizontal: DshSpace.lg,
        vertical: DshSpace.md,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: DshType.sStrong14.copyWith(
                    color: danger ? c.danger : c.ink,
                  ),
                ),
                if (sub != null && sub.isNotEmpty) ...[
                  const SizedBox(height: DshSpace.xxs),
                  Text(sub, style: DshType.xs13.copyWith(color: c.ink3)),
                ],
              ],
            ),
          ),
          if (selected) ...[
            const SizedBox(width: DshSpace.sm),
            Icon(Icons.check, size: 16, color: c.brand),
          ],
        ],
      ),
    );
  }
}

/// 通用单项选择弹层（用于设置页修改默认 Agent 预设 / 默认权限预设）。
void showChoiceSheet(
  BuildContext context, {
  required String title,
  required List<({String id, String name, String? sub})> items,
  required String? selectedId,
  required void Function(String id) onPick,
  String? footnote,
}) {
  showDshSheet<void>(
    context: context,
    builder: (sheetCtx) => DshSheet(
      title: title,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final it in items)
            Padding(
              padding: const EdgeInsets.only(bottom: DshSpace.sm),
              child: _OptionCard(
                title: it.name,
                subtitle: it.sub,
                danger: it.id == 'danger-full-access',
                selected: selectedId == it.id,
                onTap: () {
                  Navigator.of(sheetCtx).pop();
                  onPick(it.id);
                },
              ),
            ),
          if (footnote != null)
            Padding(
              padding: const EdgeInsets.only(top: DshSpace.xs),
              child: Text(
                footnote,
                textAlign: TextAlign.center,
                style: DshType.xs13.copyWith(color: DshPalette.of(sheetCtx).ink3),
              ),
            ),
        ],
      ),
    ),
  );
}

/// 弹层底部动作区：左「取消」（outline）+ 右「主操作」（primary）。
Widget _actionsRow(Widget left, [Widget? right]) {
  return Row(
    children: [
      Expanded(child: left),
      if (right != null) ...[
        const SizedBox(width: DshSpace.md),
        Expanded(child: right),
      ],
    ],
  );
}

/// 弹层内的分组标题（内衬 4，避免与弹层 20 内衬叠加过宽）。
Widget _groupHeader(String title) => DshSectionHeader(
      title,
      padding: const EdgeInsets.fromLTRB(
        DshSpace.xs,
        DshSpace.md,
        DshSpace.xs,
        DshSpace.xs,
      ),
    );

// ── 模型与推理 ──

/// 模型行：选中态整行高亮 + 右侧 `Icons.check`（品牌色），图片能力以图标标注。
class _ModelTile extends StatelessWidget {
  const _ModelTile({
    required this.model,
    required this.active,
    required this.onTap,
  });

  final CatalogModel model;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = DshPalette.of(context);
    return DshTile(
      dense: true,
      selected: active,
      title: model.name,
      // v3.0.0 图像链路：图片能力标注（PC 端目录同源 inputModalities）
      subtitle: model.imageSupported
          ? '${model.id} · ${L10n.t('支持图片', 'images')}'
          : model.id,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (model.imageSupported)
            Icon(Icons.image_outlined, size: 16, color: c.ink3),
          if (active) ...[
            if (model.imageSupported) const SizedBox(width: DshSpace.sm),
            Icon(Icons.check, size: 16, color: c.brand),
          ],
        ],
      ),
      onTap: onTap,
    );
  }
}

void showModelSheet(BuildContext context, AppStore store) {
  final cat = store.catalog;
  if (cat == null) return;
  // v2.6：按提供商分组显示（组名来自 catalog.providers，与 PC 端目录同源）
  final providerNames = <String, String>{};
  final dormantIds = <String>{};
  for (final p in cat.providers) {
    providerNames[p.id] = p.name;
    if (p.dormant) dormantIds.add(p.id);
  }
  final groups = <String, List<CatalogModel>>{};
  final groupOrder = <String>[];
  for (final m in cat.models) {
    final pid = m.provider;
    if (!groups.containsKey(pid)) {
      groups[pid] = [];
      groupOrder.add(pid);
    }
    groups[pid]!.add(m);
  }
  showDshSheet<void>(
    context: context,
    builder: (sheetCtx) {
      final c = DshPalette.of(sheetCtx);
      return DshSheet(
        title: L10n.t('模型与推理', 'Model & Reasoning'),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final pid in groupOrder) ...[
              _groupHeader(providerNames[pid] ?? pid),
              for (final model in groups[pid]!)
                _ModelTile(
                  model: model,
                  active: store.sessionConfig.provider == model.provider &&
                      store.sessionConfig.model == model.id,
                  onTap: () {
                    final msgr = ScaffoldMessenger.of(context);
                    Navigator.of(sheetCtx).pop();
                    store
                        .applySessionConfig(
                            {'provider': model.provider, 'model': model.id})
                        .then((_) => showToastAt(
                            msgr, L10n.t('已切换模型', 'Model switched')))
                        .catchError((e) => showToastAt(
                            msgr, '${L10n.t('切换失败：', 'Switch failed: ')}$e'));
                  },
                ),
            ],
            // 未配置提供商收敛为一条入口（不再逐条列出）
            if (dormantIds.isNotEmpty) ...[
              const SizedBox(height: DshSpace.xs),
              DshTile(
                leading: const Icon(Icons.settings_outlined),
                title:
                    '${L10n.t('还有 ', '')}${dormantIds.length}${L10n.t(' 个提供商未配置', ' more providers not configured')}',
                trailing: Text(
                  L10n.t('前往设置', 'Go to Settings'),
                  style: DshType.xs13.copyWith(color: c.link),
                ),
                chevron: true,
                onTap: () {
                  Navigator.of(sheetCtx).pop();
                  // Phase 2：与设置页共用提供商页打开入口
                  openProviders(context, store);
                },
              ),
            ],
            _groupHeader(L10n.t('推理强度', 'Reasoning Effort')),
            Row(
              children: [
                for (final e in cat.reasoningEfforts)
                  Expanded(
                    child: Padding(
                      padding:
                          const EdgeInsets.symmetric(horizontal: DshSpace.xs),
                      child: DshPill(
                        label: e,
                        active: store.sessionConfig.reasoningEffort == e,
                        onTap: () {
                          final msgr = ScaffoldMessenger.of(context);
                          Navigator.of(sheetCtx).pop();
                          store
                              .applySessionConfig({'reasoningEffort': e})
                              .catchError((err) => showToastAt(msgr,
                                  '${L10n.t('切换失败：', 'Switch failed: ')}$err'));
                        },
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: DshSpace.md),
            Text(
              L10n.t('与桌面端模型目录一致', 'Same model catalog as the desktop app'),
              textAlign: TextAlign.center,
              style: DshType.xs13.copyWith(color: c.ink3),
            ),
          ],
        ),
      );
    },
  );
}

/// 权限预设卡片列表（含「完全访问」风险提示），供设置页与新会话弹层复用。
List<Widget> _permOptionCards(
  BuildContext context,
  Catalog catalog, {
  required String? current,
  required void Function(PermissionPreset preset) onPick,
}) {
  return [
    for (final p in catalog.permissionPresets)
      Padding(
        padding: const EdgeInsets.only(bottom: DshSpace.sm),
        child: _OptionCard(
          title: p.name,
          subtitle: p.description,
          danger: p.id == 'danger-full-access',
          selected: current == p.id,
          onTap: () => onPick(p),
        ),
      ),
    Padding(
      padding: const EdgeInsets.only(top: DshSpace.xs),
      child: DshBanner(
        message: L10n.t('选择完全访问需确认风险',
            'Selecting Full Access requires a risk confirmation'),
        icon: Icons.warning_amber_outlined,
        tone: DshBannerTone.warn,
      ),
    ),
  ];
}

// ── 权限预设（danger 需风险确认） ──
void showPermSheet(BuildContext context, AppStore store) {
  final cat = store.catalog;
  if (cat == null) return;
  showDshSheet<void>(
    context: context,
    builder: (sheetCtx) => DshSheet(
      title: L10n.t('权限预设', 'Permission Presets'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: _permOptionCards(
          context,
          cat,
          current: store.sessionConfig.permissionPreset,
          onPick: (p) {
            final msgr = ScaffoldMessenger.of(context);
            Navigator.of(sheetCtx).pop();
            if (p.id == 'danger-full-access') {
              _showDangerConfirm(context, store);
              return;
            }
            store
                .applySessionConfig({'permissionPreset': p.id})
                .catchError((e) => showToastAt(
                    msgr, '${L10n.t('切换失败：', 'Switch failed: ')}$e'));
          },
        ),
      ),
    ),
  );
}

/// issue #6：风险确认弹层（可复用，返回结果承载确认意图）——确认 true / 取消 false。
Future<bool?> _askDangerConfirm(BuildContext context) {
  return showDshSheet<bool>(
    context: context,
    builder: (sheetCtx) {
      final c = DshPalette.of(sheetCtx);
      return DshSheet(
        title: L10n.t('⚠ 风险确认', '⚠ Risk Confirmation'),
        actions: Row(
          children: [
            Expanded(
              child: DshButton(
                label: L10n.t('取消', 'Cancel'),
                variant: DshButtonVariant.outline,
                expanded: true,
                onPressed: () => Navigator.of(sheetCtx).pop(false),
              ),
            ),
            const SizedBox(width: DshSpace.md),
            Expanded(
              child: DshButton(
                label: L10n.t('我理解风险，启用', 'Enable — I understand the risk'),
                variant: DshButtonVariant.danger,
                expanded: true,
                onPressed: () => Navigator.of(sheetCtx).pop(true),
              ),
            ),
          ],
        ),
        child: Text(
          L10n.t(
            '完全访问将允许 agent 在电脑上执行任何操作，包括修改或删除工作区以外的文件。',
            'Full Access lets the agent perform any operation on this computer, including modifying or deleting files outside the workspace.',
          ),
          style: DshType.s14.copyWith(color: c.ink2),
        ),
      );
    },
  );
}

void _showDangerConfirm(BuildContext context, AppStore store) {
  final msgr = ScaffoldMessenger.of(context);
  _askDangerConfirm(context).then((ok) {
    if (ok != true) {
      // 取消 / 关闭：回到权限预设列表（与旧行为一致）
      if (context.mounted) showPermSheet(context, store);
      return;
    }
    store
        .applySessionConfig(
            {'permissionPreset': 'danger-full-access', 'confirmDanger': true})
        .then((_) =>
            showToastAt(msgr, L10n.t('已启用完全访问', 'Full Access enabled')))
        .catchError((e) => showToastAt(
            msgr, '${L10n.t('切换失败：', 'Switch failed: ')}$e'));
  });
}

/// issue #6：新建会话弹层的权限预设选择——danger 先过风险确认（与设置页一致），
/// 确认后回调 (id, true)；普通预设直接回调 (id, false)。
void _pickPermForSession(
  BuildContext context,
  Catalog catalog,
  void Function(String id, bool confirmed) onPick, {
  String? current,
}) {
  showDshSheet<void>(
    context: context,
    builder: (sheetCtx) => DshSheet(
      title: L10n.t('权限预设', 'Permission Presets'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: _permOptionCards(
          context,
          catalog,
          current: current,
          onPick: (p) {
            Navigator.of(sheetCtx).pop();
            if (p.id == 'danger-full-access') {
              _askDangerConfirm(context).then((ok) {
                if (ok == true) onPick('danger-full-access', true);
              });
              return;
            }
            onPick(p.id, false);
          },
        ),
      ),
    ),
  );
}

/// 新建会话弹层里的「点开某项设置」行（工作目录 / 模型与推理 / 权限预设）。
Widget _settingRow({
  required IconData icon,
  required String title,
  required String subtitle,
  required VoidCallback onTap,
}) {
  return Builder(
    builder: (context) => DshTile(
      leading: Icon(icon),
      title: title,
      subtitle: subtitle,
      trailing: Text(
        L10n.t('选择', 'Choose'),
        style: DshType.xs13.copyWith(color: DshPalette.of(context).link),
      ),
      chevron: true,
      onTap: onTap,
    ),
  );
}

// ── 新建会话 ──
Future<void> showNewSessionSheet(
  BuildContext context,
  AppStore store,
  Future<void> Function(String sessionId) onCreated,
) async {
  String? pendingMode;
  String? pendingDir;
  // issue #6：本次会话的权限预设（默认跟随设置页的默认预设）。
  // danger-full-access 必须先过风险确认（permConfirmed），doCreate 才带 confirmDanger: true；
  // 旧版整条链路缺失 → 默认预设设成完全访问后，新建会话必 400 risk-confirmation-required（死锁）。
  String? pendingPerm;
  var permConfirmed = false;
  // 默认工作目录 = 当前选中的工作区（未选时回退第一个已注册工作区）。
  // v3.1.1(issue #5)：条目保留服务端原始路径（规范化只用于匹配比较）——
  // 旧实现把 path 归一成 `\` 形态存入，WSL/Linux 上 `\home\user` 会直接被当作 cwd 发回服务端。
  var ws = store.workspaces;
  if (ws.isEmpty) {
    try {
      ws = await api.workspaces();
    } catch (_) {}
  }
  if (ws.isNotEmpty) {
    final selected = store.workspacePath;
    Map<String, dynamic>? hit;
    if (selected != null) {
      for (final w in ws) {
        if (AppStore.normPath(w['path'] as String? ?? '') == selected) {
          hit = w;
          break;
        }
      }
    }
    pendingDir = hit?['path'] as String? ?? ws.first['path'] as String?;
  }
  if (!context.mounted) return;

  // v3.0.0：创建中标志——连点「创建会话」会并发建两个会话（无撤销），先到先得
  var creating = false;
  Future<void> doCreate() async {
    if (creating) return;
    creating = true;
    final preset = pendingMode ?? store.catalog?.defaults['agentPreset'] ?? 'standard';
    final name = switch (preset) {
      'standard' => L10n.t('标准模式', 'Standard'),
      'code' => L10n.t('PTC 模式', 'PTC Mode'),
      'minimal' => L10n.t('极简模式', 'Minimal'),
      'cordis' => L10n.t('创造模式', 'Creative'),
      _ => preset,
    };
    try {
      // issue #6：目标预设为完全访问且未经本弹层确认时，先弹风险确认；
      // 确认后显式带 confirmDanger: true（服务端契约，lib/index.js:1753）。
      // 默认预设即完全访问（设置页已确认）也不再默认放行——本会话仍须显式确认。
      final perm = pendingPerm ?? 'workspace-write';
      if (perm == 'danger-full-access' && !permConfirmed) {
        final ok = await _askDangerConfirm(context);
        if (ok != true) return; // finally 会复位 creating
        permConfirmed = true;
      }
      // v3.2.6：新建会话必须携带完整模型身份（provider + model）——旧实现只发 model，
      // 新版服务端插件（≥3.2.0）会 400 "provider and model required together"。
      // 要么两者都发，要么都不发（由服务端用部署默认模型），不发送已下线的兜底 model id。
      final selModel = store.sessionConfig.model;
      final selProvider = store.sessionConfig.provider;
      final hasModelSelection = selModel != null && selModel.isNotEmpty && selProvider != null && selProvider.isNotEmpty;
      final created = await api.createSession({
        'preset': preset,
        'cwd': ?pendingDir,
        if (hasModelSelection) 'provider': selProvider,
        if (hasModelSelection) 'model': selModel,
        if (hasModelSelection) 'reasoningEffort': store.sessionConfig.reasoningEffort ?? 'max',
        'permissionPreset': perm,
        if (perm == 'danger-full-access') 'confirmDanger': true,
      });
      if (!context.mounted) return;
      final msgr = ScaffoldMessenger.of(context);
      Navigator.of(context).pop();
      showToastAt(msgr, '${L10n.t('已用「', 'Created session: ')}$name${L10n.t('」新建会话', '')}');
      await onCreated(created['sessionId'] as String);
    } catch (e) {
      if (context.mounted) showToastAt(ScaffoldMessenger.of(context), '${L10n.t('新建失败：', 'Failed to create: ')}$e');
    } finally {
      creating = false;
    }
  }

  // 弹层内状态用 StatefulBuilder 驱动
  // 目录未加载（启动时 PC 忙/超时常见）：先补拉，而不是静默无反应
  var cat = store.catalog;
  if (cat == null) {
    cat = await store.refreshCatalog();
    if (!context.mounted) return;
  }
  if (cat == null) {
    showToastAt(ScaffoldMessenger.of(context), L10n.t('模型目录加载失败，请检查连接后下拉刷新重试', 'Failed to load the model catalog. Check the connection and pull to refresh.'));
    return;
  }
  final catalog = cat; // 非空最终引用，供弹层闭包使用
  pendingPerm ??= catalog.defaults['permissionPreset'] as String?;
  await showDshSheet<void>(
    context: context,
    builder: (sheetCtx) => StatefulBuilder(
      builder: (sheetCtx, setSheet) {
        void refresh() => setSheet(() {});
        final c = DshPalette.of(sheetCtx);
        return DshSheet(
          title: L10n.t('新建会话', 'New Session'),
          scrollable: false,
          actions: Row(
            children: [
              Expanded(
                child: DshButton(
                  label: L10n.t('取消', 'Cancel'),
                  variant: DshButtonVariant.outline,
                  expanded: true,
                  onPressed: () => Navigator.of(sheetCtx).pop(),
                ),
              ),
              const SizedBox(width: DshSpace.md),
              Expanded(
                child: DshButton(
                  label: L10n.t('创建会话', 'Create Session'),
                  variant: DshButtonVariant.primary,
                  expanded: true,
                  onPressed: doCreate,
                ),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Flexible(
                // 预设列表可滚动（预设多时不溢出）；取消/创建按钮固定在底部动作区
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _groupHeader(L10n.t('Agent 预设', 'Agent preset')),
                      for (final p in catalog.agentPresets)
                        Padding(
                          padding: const EdgeInsets.only(bottom: DshSpace.sm),
                          child: _OptionCard(
                            title: p.name,
                            subtitle: p.description,
                            selected: (pendingMode ??
                                    catalog.defaults['agentPreset']) ==
                                p.id,
                            onTap: () {
                              pendingMode = p.id;
                              refresh();
                            },
                          ),
                        ),
                      _groupHeader(L10n.t('会话设置', 'Session settings')),
                      DshCardGroup(
                        margin: EdgeInsets.zero,
                        children: [
                          _settingRow(
                            icon: Icons.folder_outlined,
                            title: L10n.t('工作目录', 'Working Directory'),
                            subtitle: pendingDir ??
                                L10n.t('默认（当前工作区）',
                                    'Default (current workspace)'),
                            onTap: () => showDirPicker(context, store, (path) {
                              pendingDir = path;
                              refresh();
                            }),
                          ),
                          // v2.7.1：模型与推理入口（新建会话时选模型/调推理强度；选择写入 sessionConfig，
                          // doCreate 会带上）
                          _settingRow(
                            icon: Icons.smart_toy_outlined,
                            title:
                                L10n.t('模型与推理强度', 'Model & Reasoning Effort'),
                            subtitle:
                                '${store.sessionConfig.model ?? L10n.t('选择模型', 'Select model')}'
                                ' · ${store.sessionConfig.reasoningEffort ?? 'max'}',
                            onTap: () {
                              showModelSheet(context, store);
                              // showModelSheet 选择后 pop 返回，刷新本弹层显示当前值
                              Future<void>.delayed(
                                  const Duration(milliseconds: 400), () {
                                if (sheetCtx.mounted) refresh();
                              });
                            },
                          ),
                          // issue #6：新建会话可单独选择权限预设（danger 走风险确认）；
                          // 未选择时跟随设置页默认预设，doCreate 兜底校验
                          _settingRow(
                            icon: Icons.shield_outlined,
                            title: L10n.t('权限预设', 'Permission Preset'),
                            subtitle:
                                '${permNameOf(pendingPerm) ?? L10n.t('默认（工作区写入）', 'Default (Workspace Write)')}'
                                '${pendingPerm == 'danger-full-access' && !permConfirmed ? L10n.t(' · 需风险确认', ' · confirm required') : ''}',
                            onTap: () => _pickPermForSession(
                              context,
                              catalog,
                              (id, confirmed) {
                                pendingPerm = id;
                                permConfirmed = confirmed;
                                refresh();
                              },
                              current: pendingPerm,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: DshSpace.sm),
                      Text(
                        L10n.t('新会话将使用上面的预设与目录',
                            'The new session uses the preset and directory above'),
                        style: DshType.xs13.copyWith(color: c.ink3),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    ),
  );
}

// ── 目录选择器（StatefulWidget：initState 即加载，修复旧版无限转圈） ──

/// v3.1.1(issue #5)：按服务端分隔符拼接当前目录与子目录名。
/// WSL/Linux 用 `/`（旧实现写死 `\`，根 `/` 下选 home 会拼成 `/\home` → 读目录报错）。
String joinDirPath(String current, String name, String sep) {
  if (current.isEmpty) return name;
  return current.endsWith(sep) ? current + name : '$current$sep$name';
}

/// v3.1.1(issue #5)：确定路径分隔符——优先服务端返回的 sep；
/// 旧版插件未返回时按根视图推断（POSIX 根为 `/`，Windows 盘符为 `C:\`），
/// 两者都没有时按 Windows 习惯兜底。
String dirSepOf(List<String> roots, String? serverSep) {
  if (serverSep != null && serverSep.isNotEmpty) return serverSep;
  for (final r in roots) {
    if (r.contains('/')) return '/';
  }
  return '\\';
}

/// 当前浏览位置的显示名（根视图按分隔符区分盘符/POSIX）。
String _rootLabel(String sep) => sep == '/'
    ? L10n.t('根目录', 'Root')
    : L10n.t('根目录（选择盘符）', 'Root (choose a drive)');

Future<void> showDirPicker(
  BuildContext context,
  AppStore store,
  void Function(String path) onPicked,
) async {
  await showDshSheet<void>(
    context: context,
    builder: (_) => _DirPickerSheet(store: store, onPicked: onPicked),
  );
}

class _DirPickerSheet extends StatefulWidget {
  final AppStore store;
  final void Function(String path) onPicked;
  const _DirPickerSheet({required this.store, required this.onPicked});

  @override
  State<_DirPickerSheet> createState() => _DirPickerSheetState();
}

/// v3.1.2：文件选择器（与目录选择器独立的专用组件：盘符/目录树导航 + 文件列表点选）。
Future<String?> showFilePicker(BuildContext context) async {
  return await showDshSheet<String>(
    context: context,
    builder: (_) => const _FilePickerSheet(),
  );
}

class _DirPickerSheetState extends State<_DirPickerSheet> {
  final dirStack = <String>[];
  String current = '';
  List<String> dirs = [];
  List<Map<String, dynamic>> workspaces = [];
  // v3.1.1(issue #5)：路径分隔符，根视图加载时按服务端返回设置（默认 Windows 习惯）
  String sep = '\\';
  bool loading = true;
  String? error;

  @override
  void initState() {
    super.initState();
    load('');
  }

  Future<void> load(String path) async {
    setState(() {
      current = path;
      loading = true;
      error = null;
      dirs = [];
    });
    try {
      if (path.isEmpty) {
        try {
          workspaces = await api.workspaces();
        } catch (_) {
          workspaces = [];
        }
        final listing = await api.directories('');
        dirs = listing.dirs;
        sep = dirSepOf(dirs, listing.sep);
      } else {
        workspaces = [];
        final listing = await api.directories(path);
        dirs = listing.dirs;
      }
    } catch (e) {
      error = '${L10n.t('读取失败：', 'Failed to read: ')}$e';
    }
    if (mounted) setState(() => loading = false);
  }

  void _goUp() {
    if (dirStack.isEmpty) {
      Navigator.of(context).pop();
      return;
    }
    load(dirStack.removeLast());
  }

  void _openDir(String name) {
    if (current.isEmpty) {
      dirStack.add('');
      load(name);
    } else {
      dirStack.add(current);
      load(joinDirPath(current, name, sep));
    }
  }

  /// 是否是当前已选工作目录（用于行高亮）。
  bool _isWorkspace(String path) {
    final selected = widget.store.workspacePath;
    return selected != null && AppStore.normPath(path) == selected;
  }

  @override
  Widget build(BuildContext context) {
    final c = DshPalette.of(context);
    return DshSheet(
      title: L10n.t('选择工作目录', 'Choose Working Directory'),
      scrollable: false,
      actions: _actionsRow(
        DshButton(
          label: L10n.t('取消', 'Cancel'),
          variant: DshButtonVariant.outline,
          expanded: true,
          onPressed: () => Navigator.of(context).pop(),
        ),
        DshButton(
          label: L10n.t('选这里', 'Select Here'),
          variant: DshButtonVariant.primary,
          expanded: true,
          onPressed: () {
            if (current.isNotEmpty) {
              widget.onPicked(current);
            }
            Navigator.of(context).pop();
          },
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: DshTag(
                    dense: true,
                    icon: Icons.folder_outlined,
                    color: c.ink2,
                    label: current.isEmpty ? _rootLabel(sep) : current,
                  ),
                ),
              ),
              const SizedBox(width: DshSpace.sm),
              DshButton(
                label: L10n.t('上级', 'Up'),
                icon: Icons.arrow_upward,
                variant: DshButtonVariant.ghost,
                size: DshButtonSize.sm,
                onPressed: _goUp,
              ),
            ],
          ),
          const SizedBox(height: DshSpace.md),
          SizedBox(
            height: 320,
            child: loading
                ? const DshLoading()
                : error != null
                    ? DshError(message: error!)
                    : ListView(
                        padding: EdgeInsets.zero,
                        children: [
                          if (current.isEmpty && workspaces.isNotEmpty) ...[
                            _groupHeader(
                                L10n.t('已注册工作区', 'Registered Workspaces')),
                            for (final w in workspaces)
                              DshTile(
                                leading: const Icon(Icons.star_border),
                                title: w['path'] as String? ?? '',
                                subtitle: w['title'] as String?,
                                selected: _isWorkspace(w['path'] as String? ?? ''),
                                chevron: true,
                                onTap: () {
                                  widget.onPicked(w['path'] as String);
                                  Navigator.of(context).pop();
                                },
                              ),
                            _groupHeader(sep == '/'
                                ? L10n.t('根目录', 'Root')
                                : L10n.t('所有盘符', 'All Drives')),
                          ],
                          if (dirs.isEmpty && !loading && error == null)
                            DshEmpty(
                              compact: true,
                              icon: Icons.folder_off_outlined,
                              title: L10n.t('没有子目录', 'No subdirectories'),
                            ),
                          for (final name in dirs)
                            DshTile(
                              leading: const Icon(Icons.folder_outlined),
                              title: name,
                              selected:
                                  _isWorkspace(joinDirPath(current, name, sep)),
                              chevron: true,
                              onTap: () => _openDir(name),
                            ),
                        ],
                    ),
          ),
          const SizedBox(height: DshSpace.md),
          DshButton(
            label: L10n.t('新建文件夹', 'New Folder'),
            icon: Icons.create_new_folder_outlined,
            variant: DshButtonVariant.outline,
            size: DshButtonSize.sm,
            expanded: true,
            onPressed: () => _showNewFolder(context, current, (createdPath) {
              load(createdPath);
            }),
          ),
        ],
      ),
    );
  }
}

/// v3.1.2：文件选择器（独立组件）。盘符/目录树导航同目录选择器，
/// 但：不展示「已注册工作区」快捷区、无「新建文件夹/选这里」，点文件即返回全路径。
class _FilePickerSheet extends StatefulWidget {
  const _FilePickerSheet();

  @override
  State<_FilePickerSheet> createState() => _FilePickerSheetState();
}

class _FilePickerSheetState extends State<_FilePickerSheet> {
  final dirStack = <String>[];
  String current = '';
  List<String> dirs = [];
  List<String> files = [];
  String sep = '\\';
  bool loading = true;
  String? error;

  @override
  void initState() {
    super.initState();
    load('');
  }

  Future<void> load(String path) async {
    setState(() {
      current = path;
      loading = true;
      error = null;
      dirs = [];
      files = [];
    });
    try {
      final listing = path.isEmpty ? await api.directories('') : await api.directories(path);
      dirs = listing.dirs;
      files = listing.files;
      sep = dirSepOf(dirs, listing.sep);
    } catch (e) {
      error = '${L10n.t('读取失败：', 'Failed to read: ')}$e';
    }
    if (mounted) setState(() => loading = false);
  }

  void _goUp() {
    if (dirStack.isEmpty) {
      Navigator.of(context).pop();
      return;
    }
    load(dirStack.removeLast());
  }

  void _openDir(String name) {
    if (current.isEmpty) {
      dirStack.add('');
      load(name);
    } else {
      dirStack.add(current);
      load(joinDirPath(current, name, sep));
    }
  }

  void _pickFile(String name) {
    final full = current.isEmpty ? name : joinDirPath(current, name, sep);
    Navigator.of(context).pop(full);
  }

  @override
  Widget build(BuildContext context) {
    final c = DshPalette.of(context);
    return DshSheet(
      title: L10n.t('选择文件', 'Choose File'),
      scrollable: false,
      actions: _actionsRow(
        DshButton(
          label: L10n.t('取消', 'Cancel'),
          variant: DshButtonVariant.outline,
          expanded: true,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: DshTag(
                    dense: true,
                    icon: Icons.folder_outlined,
                    color: c.ink2,
                    label: current.isEmpty ? _rootLabel(sep) : current,
                  ),
                ),
              ),
              const SizedBox(width: DshSpace.sm),
              DshButton(
                label: L10n.t('上级', 'Up'),
                icon: Icons.arrow_upward,
                variant: DshButtonVariant.ghost,
                size: DshButtonSize.sm,
                onPressed: _goUp,
              ),
            ],
          ),
          const SizedBox(height: DshSpace.md),
          SizedBox(
            height: 320,
            child: loading
                ? const DshLoading()
                : error != null
                    ? DshError(message: error!)
                    : ListView(
                        padding: EdgeInsets.zero,
                        children: [
                          if (current.isEmpty)
                            _groupHeader(L10n.t('所有盘符', 'All Drives')),
                          for (final name in dirs)
                            DshTile(
                              leading: const Icon(Icons.folder_outlined),
                              title: name,
                              chevron: true,
                              onTap: () => _openDir(name),
                            ),
                          if (files.isNotEmpty) ...[
                            _groupHeader(L10n.t('文件', 'Files')),
                            for (final name in files)
                              DshTile(
                                leading:
                                    const Icon(Icons.insert_drive_file_outlined),
                                title: name,
                                trailing: Text(
                                  L10n.t('选择', 'Choose'),
                                  style: DshType.xs13.copyWith(color: c.link),
                                ),
                                chevron: true,
                                onTap: () => _pickFile(name),
                              ),
                          ],
                          if (dirs.isEmpty &&
                              files.isEmpty &&
                              !loading &&
                              error == null)
                            DshEmpty(
                              compact: true,
                              icon: Icons.folder_off_outlined,
                              title: L10n.t('该目录为空', 'Empty directory'),
                            ),
                        ],
                    ),
          ),
        ],
      ),
    );
  }
}

void _showNewFolder(BuildContext context, String current, void Function(String) onCreated) {
  final ctrl = TextEditingController();
  showDshSheet<void>(
    context: context,
    builder: (sheetCtx) => StatefulBuilder(
      builder: (sheetCtx, setFolder) {
        // v3.0.0：busy 锁（防连点双建目录）+ 客户端文件名合法性校验（与服务端一致：拒绝
        // Windows 保留字符与 . / ..，避免一路提交到拒绝/产生重复目录才报错）
        var busy = false;
        Future<void> create() async {
          if (busy) return;
          final name = ctrl.text.trim();
          if (name.isEmpty) return;
          if (name == '.' || name == '..' || RegExp(r'[\\/:*?"<>|]').hasMatch(name)) {
            if (sheetCtx.mounted) {
              showToastAt(ScaffoldMessenger.of(sheetCtx),
                  L10n.t('文件夹名包含非法字符（\\ / : * ? " < > |）', 'Folder name contains invalid characters (\\ / : * ? " < > |)'));
            }
            return;
          }
          busy = true;
          setFolder(() {});
          final parent = current.isEmpty ? null : current;
          try {
            await api.createDirectory(path: parent, name: name);
            if (sheetCtx.mounted) Navigator.of(sheetCtx).pop();
            onCreated(parent ?? name);
          } catch (e) {
            if (sheetCtx.mounted) showToastAt(ScaffoldMessenger.of(sheetCtx), '${L10n.t('创建失败：', 'Failed to create: ')}$e');
          } finally {
            busy = false;
            if (sheetCtx.mounted) setFolder(() {});
          }
        }

        return DshSheet(
          title: L10n.t('新建文件夹', 'New Folder'),
          scrollable: false,
          // 键盘避让由 DshSheet 内置（MediaQuery.viewInsets），这里不再重复顶起。
          padding: const EdgeInsets.fromLTRB(
            DshSpace.xl,
            DshSpace.sm,
            DshSpace.xl,
            DshSpace.xl,
          ),
          actions: _actionsRow(
            DshButton(
              label: L10n.t('取消', 'Cancel'),
              variant: DshButtonVariant.outline,
              expanded: true,
              onPressed: busy ? null : () => Navigator.of(sheetCtx).pop(),
            ),
            DshButton(
              label: busy ? L10n.t('创建中…', 'Creating…') : L10n.t('创建', 'Create'),
              variant: DshButtonVariant.primary,
              expanded: true,
              onPressed: busy ? null : create,
            ),
          ),
          child: TextField(
            controller: ctrl,
            autofocus: true,
            decoration: InputDecoration(
              labelText: L10n.t('文件夹名称', 'Folder Name'),
              hintText: L10n.t('如：my-project', 'e.g. my-project'),
            ),
          ),
        );
      },
    ),
  );
}

// ── 执行动作 ──
void showActionSheet(BuildContext context, Map<String, dynamic> action) {
  final fields = (action['fields'] as List? ?? []).map((e) => e as Map<String, dynamic>).toList();
  final ctrls = {for (final f in fields) f['key'] as String: TextEditingController()};
  showDshSheet<void>(
    context: context,
    builder: (sheetCtx) => DshSheet(
      title: action['title'] as String? ?? L10n.t('执行动作', 'Execute Action'),
      actions: _actionsRow(
        DshButton(
          label: L10n.t('取消', 'Cancel'),
          variant: DshButtonVariant.outline,
          expanded: true,
          onPressed: () => Navigator.of(sheetCtx).pop(),
        ),
        DshButton(
          label: L10n.t('执行', 'Execute'),
          variant: DshButtonVariant.primary,
          expanded: true,
          onPressed: () async {
            final msgr = ScaffoldMessenger.of(context);
            final args = {for (final f in fields) f['key'] as String: ctrls[f['key'] as String]!.text};
            Navigator.of(sheetCtx).pop();
            try {
              await api.invokeAction(action['id'] as String, args);
              showToastAt(msgr, '${L10n.t('已发送给 agent：', 'Sent to agent: ')}${action['title']}');
            } catch (e) {
              showToastAt(msgr, '${L10n.t('执行失败：', 'Execution failed: ')}$e');
            }
          },
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (fields.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: DshSpace.sm),
              child: Text(
                L10n.t('直接执行，无需参数', 'Runs directly, no parameters needed'),
                textAlign: TextAlign.center,
                style:
                    DshType.xs13.copyWith(color: DshPalette.of(sheetCtx).ink2),
              ),
            ),
          for (final f in fields)
            Padding(
              padding: const EdgeInsets.only(bottom: DshSpace.md),
              child: TextField(
                controller: ctrls[f['key'] as String],
                decoration: InputDecoration(
                  labelText: f['label'] as String? ?? f['key'] as String,
                  hintText: f['placeholder'] as String? ?? '',
                ),
              ),
            ),
        ],
      ),
    ),
  );
}
