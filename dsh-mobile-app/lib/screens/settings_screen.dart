// 设置页（对齐网页端 settings screen）：连接/默认配置/账户/显示/关于
//
// 版式沿用官方设置页：DshSectionHeader 分组 + DshCardGroup（R20 卡片）收行，
// 行内统一 DshTile（左图标 20 + 标题 s14 + 副标题 xs13 + 右侧值/开关/箭头）。
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api.dart';
import '../dsh_kit.dart';
import '../floating.dart';
import '../fmt.dart';
import '../l10n.dart';
import '../logger.dart';
import '../models.dart';
import '../store.dart';
import '../theme.dart';
import '../toast.dart';
import '../update/update_ui.dart';
import 'providers_screen.dart';
import 'sheets.dart';
import 'usage_screen.dart';

class SettingsScreen extends StatefulWidget {
  final AppStore store;
  final Future<void> Function() onReconfigure;
  const SettingsScreen({
    super.key,
    required this.store,
    required this.onReconfigure,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  UsageSnapshot? _usage;
  String? _usageError; // partial | outdated | failed；build 时再翻译
  bool _usageBusy = false; // 用量与额度刷新中
  bool _alertShown = false; // 本次会话内余额预警已提示过
  Map<String, dynamic>? _diag;
  bool _diagLoaded = false;
  String _diagTime = '';
  String _appVersion = ''; // App 自身版本（package_info_plus，构建时打包）
  bool _bubbleOn = false; // 悬浮球开关状态（与服务实际运行状态同步）

  @override
  void initState() {
    super.initState();
    _refreshUsage();
    _loadAppVersion();
    _initBubbleState();
    // 连接状态等 store 变化实时刷新（修复：旧版离开页面重进才能看到状态更新）
    widget.store.addListener(_onStoreChanged);
  }

  Future<void> _initBubbleState() async {
    final on = await Floating.isRunning();
    final want = widget.store.floatingEnabled;
    final canOverlay = await Floating.canDrawOverlay();
    // v2.7.2：偏好是开但服务没跑（清理后台/重启后）→ 自动拉起，开关保持开
    if (want && !on && canOverlay) {
      await Floating.start();
      unawaited(
        Floating.setBalanceAlert(
          widget.store.balanceAlert,
          widget.store.balanceThreshold,
        ),
      );
    }
    // v2.7.2 review(M7)：权限被撤销时开关显示关（此前 want||on 会假开——球实际不在）
    if (mounted) setState(() => _bubbleOn = on || (want && canOverlay));
  }

  /// 悬浮球开关：打开需悬浮窗权限（未授权 → 居中弹窗引导），关闭即停止服务。
  Future<void> _toggleBubble(bool v) async {
    if (v) {
      final ok = await Floating.canDrawOverlay();
      if (!ok) {
        if (!mounted) return;
        final go = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(L10n.t('需要悬浮窗权限', 'Overlay permission needed')),
            content: Text(
              L10n.t(
                '开启悬浮球需要在系统设置中允许「显示在其他应用上层」。\n点击【去开启】跳转系统设置。',
                'The floating bubble needs the "display over other apps" permission.\nTap Open Settings to grant it.',
              ),
              style: DshType.s14.copyWith(
                color: DshPalette.of(ctx).ink2,
              ),
            ),
            actions: [
              DshButton(
                label: L10n.t('取消', 'Cancel'),
                variant: DshButtonVariant.ghost,
                size: DshButtonSize.sm,
                onPressed: () => Navigator.of(ctx).pop(false),
              ),
              DshButton(
                label: L10n.t('去开启', 'Open Settings'),
                size: DshButtonSize.sm,
                onPressed: () => Navigator.of(ctx).pop(true),
              ),
            ],
          ),
        );
        if (go == true) {
          await Floating.openOverlaySettings();
        }
        return; // 授权后由用户重新打开开关（或重进页面状态同步）
      }
      try {
        await Floating.start();
      } catch (e) {
        if (mounted) {
          setState(() => _bubbleOn = false);
          showToast(
            context,
            '${L10n.t('悬浮球启动失败：', 'Bubble start failed: ')}$e',
          );
        }
        return;
      }
      await widget.store.setFloatingEnabled(true); // v2.7.2：持久化开关（await 确保落盘）
      if (mounted) setState(() => _bubbleOn = true);
    } else {
      await Floating.stop();
      await widget.store.setFloatingEnabled(false); // v2.7.2：持久化开关
      if (mounted) setState(() => _bubbleOn = false);
    }
  }

  @override
  void dispose() {
    widget.store.removeListener(_onStoreChanged);
    super.dispose();
  }

  void _onStoreChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadAppVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() {
        _appVersion = '${info.version}+${info.buildNumber}';
      });
    } catch (_) {
      // 读取失败时版本行显示 App 端为「…」
    }
  }

  /// 手动切换连接地址（回家想切回局域网 / 出门想切蒲公英时用）。
  Future<void> _pickAddress() async {
    final candidates = api.baseUrls;
    if (candidates.isEmpty) return;
    final current = api.baseUrl;
    final c = DshPalette.of(context);
    final choice = await showDshSheet<String>(
      context: context,
      builder: (ctx) => DshSheet(
        title: L10n.t('选择连接地址', 'Choose address'),
        child: DshCardGroup(
          margin: EdgeInsets.zero,
          children: [
            for (final addr in candidates)
              DshTile(
                dense: true,
                title: addr,
                selected: addr == current,
                trailing: addr == current
                    ? Icon(Icons.check, size: 16, color: c.brand)
                    : null,
                onTap: () => Navigator.of(ctx).pop(addr),
              ),
          ],
        ),
      ),
    );
    if (choice == null || choice == current || !mounted) return;
    final err = await widget.store.switchBase(choice);
    if (!mounted) return;
    if (err != null) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: Text(err),
            duration: const Duration(milliseconds: 2000),
            behavior: SnackBarBehavior.floating,
          ),
        );
    } else {
      showToast(context, L10n.t('已切换 → ', 'Switched to ') + choice);
    }
  }

  Future<void> _refreshUsage() async {
    if (_usageBusy) return;
    setState(() {
      _usageBusy = true;
      _usageError = null;
    });
    try {
      final snapshot = await api.accountUsage();
      if (!mounted) return;
      final deepSeek = snapshot.sourceOf('deepseek');
      final total = deepSeek?.amountNumber;
      setState(() {
        _usage = snapshot;
        _usageError = snapshot.failedCount > 0 ? 'partial' : null;
      });
      // 余额联动悬浮球与预警仍只使用 DeepSeek 金额余额。
      if (total != null) unawaited(Floating.notifyBalance(total));
      if (widget.store.balanceAlert &&
          total != null &&
          total < widget.store.balanceThreshold &&
          !_alertShown) {
        _alertShown = true;
        showToast(
          context,
          L10n.t('余额不足 ¥', 'Low balance ¥') +
              total.toStringAsFixed(1) +
              L10n.t('，建议及时充值', ' — consider topping up'),
        );
      }
    } catch (e) {
      if (!mounted) return;
      final oldPlugin = e is ApiException && e.code == 'not-found';
      setState(() {
        // 保留最后一次成功快照，避免短暂网络失败把账户摘要清空。
        _usageError = oldPlugin ? 'outdated' : 'failed';
      });
    } finally {
      if (mounted) setState(() => _usageBusy = false);
    }
  }

  /// 阈值显示格式：整数不带小数（¥10），非整数两位（¥12.50）。
  String _fmtThreshold(double v) =>
      v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(2);

  /// v3.1.2：发送测试通知——逐个通道验证（服务端绕过节流）。
  Future<void> _sendTestPush() async {
    try {
      final r = await api.pushTest();
      final results = (r['results'] as List? ?? []).whereType<Map>().toList();
      final okCount = results.where((e) => e['ok'] == true).length;
      if (mounted) {
        showToast(
          context,
          L10n.t(
            '测试通知已发送（$okCount/${results.length} 个通道成功）',
            'Test sent ($okCount/${results.length} channels OK)',
          ),
        );
      }
    } catch (e) {
      if (mounted) showToast(context, '${L10n.t('发送失败：', 'Send failed: ')}$e');
    }
  }

  /// 余额预警阈值选择：¥5 / ¥10 / ¥20 / ¥50 / 自定义输入。
  Future<void> _pickThreshold() async {
    final presets = [5.0, 10.0, 20.0, 50.0];
    final current = widget.store.balanceThreshold;
    final c = DshPalette.of(context);
    final selected = await showDshSheet<double>(
      context: context,
      builder: (ctx) => DshSheet(
        title: L10n.t('余额预警阈值', 'Low-balance threshold'),
        child: DshCardGroup(
          margin: EdgeInsets.zero,
          children: [
            for (final p in presets)
              DshTile(
                dense: true,
                title: '¥${_fmtThreshold(p)}',
                selected: p == current,
                trailing: p == current
                    ? Icon(Icons.check, size: 16, color: c.brand)
                    : null,
                onTap: () => Navigator.of(ctx).pop(p),
              ),
            DshTile(
              dense: true,
              title: L10n.t('自定义…', 'Custom…'),
              onTap: () async {
                Navigator.of(ctx).pop();
                final ctrl = TextEditingController(
                  text: current == current.roundToDouble()
                      ? current.round().toString()
                      : current.toStringAsFixed(2),
                );
                final v = await showDialog<String>(
                  context: context,
                  builder: (dctx) => AlertDialog(
                    title: Text(L10n.t('自定义阈值（元）', 'Custom threshold (¥)')),
                    content: TextField(
                      controller: ctrl,
                      autofocus: true,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(hintText: '10'),
                    ),
                    actions: [
                      DshButton(
                        label: L10n.t('取消', 'Cancel'),
                        variant: DshButtonVariant.ghost,
                        size: DshButtonSize.sm,
                        onPressed: () => Navigator.of(dctx).pop(),
                      ),
                      DshButton(
                        label: L10n.t('确定', 'OK'),
                        size: DshButtonSize.sm,
                        onPressed: () => Navigator.of(dctx).pop(ctrl.text),
                      ),
                    ],
                  ),
                );
                if (v != null && v.trim().isNotEmpty) {
                  final parsed = double.tryParse(v.trim());
                  if (parsed != null && parsed > 0) {
                    await widget.store.setBalanceThreshold(parsed);
                    if (mounted) {
                      showToast(
                        context,
                        L10n.t('阈值已设为 ¥', 'Threshold set to ¥') +
                            _fmtThreshold(parsed),
                      );
                    }
                  } else if (mounted) {
                    showToast(
                      context,
                      L10n.t('请输入大于 0 的金额', 'Enter an amount greater than 0'),
                    );
                  }
                }
              },
            ),
          ],
        ),
      ),
    );
    if (selected != null) {
      await widget.store.setBalanceThreshold(selected);
    }
  }

  bool get _deepSeekLow => widget.store.balanceAlert &&
      ((_usage?.sourceOf('deepseek')?.amountNumber ?? double.infinity) < widget.store.balanceThreshold);

  String? get _usageErrorText => switch (_usageError) {
        'partial' => L10n.t('部分额度来源刷新失败', 'Some usage sources failed to refresh'),
        'outdated' => L10n.t('电脑端插件版本过旧', 'Desktop plugin is outdated'),
        'failed' => L10n.t('额度查询失败', 'Usage query failed'),
        _ => null,
      };

  /// 用量与额度摘要（build 时求值：语言切换后即时换语言）。
  String get _usageLabel {
    if (_usageBusy && _usage == null) return L10n.t('查询中…', 'Loading…');
    if (_usageErrorText != null) return _usageErrorText!;
    final sources = _usage?.sources;
    if (sources == null) return L10n.t('尚未查询', 'Not queried yet');
    final count = sources.where((source) => source.available).length;
    if (count == 0) return L10n.t('暂无可用额度来源', 'No usage sources');
    return L10n.t(
      '$count 个来源可用',
      '$count source${count == 1 ? '' : 's'} available',
    );
  }

  Future<void> _openUsage() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => UsageScreen(store: widget.store, initial: _usage),
      ),
    );
    if (mounted) unawaited(_refreshUsage());
  }

  Future<void> _loadDiag() async {
    try {
      final d = await api.diagnostics();
      if (!mounted) return;
      final now = DateTime.now();
      setState(() {
        _diag = d;
        _diagLoaded = true;
        _diagTime =
            '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
      });
    } catch (e) {
      // 刷新失败：清空旧数据，明确显示「检测失败」而非静默展示过期结果
      if (!mounted) return;
      setState(() {
        _diag = null;
        _diagTime = '';
      });
      AppLog.instance.log('环境诊断失败: $e');
    }
  }

  String get _diagText {
    final d = _diag;
    if (d == null) return L10n.t('检测失败', 'Check failed');
    final buf = StringBuffer();
    final runtime = d['runtime'] as Map<String, dynamic>? ?? {};
    final form = runtime['form'];
    final formText = form == 'desktop'
        ? 'desktop · ${L10n.t('桌面版', 'DSH Desktop')}'
        : form == 'cli'
        ? 'cli · ${L10n.t('命令行/网页', 'CLI / Web')}'
        : '${form ?? '?'}';
    buf.writeln(
      '${L10n.t('运行形态: ', 'Mode: ')}$formText${runtime['authEnabled'] == true ? L10n.t(' · 口令已启用', ' · auth on') : L10n.t(' · 口令未启用', ' · auth off')}',
    );
    buf.writeln(
      '${L10n.t('监听: ', 'Listen: ')}${runtime['host']}:${runtime['port']}',
    );
    buf.writeln('${L10n.t('进程目录: ', 'CWD: ')}${runtime['cwd']}');
    final metrics = runtime['metrics'] as Map<String, dynamic>?;
    if (metrics != null && metrics.isNotEmpty) {
      buf.writeln();
      buf.writeln(L10n.t('实时指标:', 'Live metrics:'));
      metrics.forEach((k, v) {
        final n = _metricsName(k);
        buf.writeln('  • $n（$k）= $v');
      });
    }
    buf.writeln();
    final services = d['services'] as Map<String, dynamic>? ?? {};
    buf.writeln(L10n.t('服务:', 'Services:'));
    services.forEach((k, v) {
      final n = _diagName('services', k);
      buf.writeln('  ${v == true ? '✅' : '❌'} ${k == n ? n : '$n ($k)'}');
    });
    buf.writeln();
    final checks = d['checks'] as Map<String, dynamic>? ?? {};
    buf.writeln(L10n.t('端点实测:', 'Endpoint checks:'));
    checks.forEach((k, v) {
      final n = _diagName('checks', k);
      final shown = k == n ? n : '$n ($k)';
      if (k == 'approvalMode') {
        // v3.1.3：审批策略取值说明（both 双端同卡 / mobile 手机独占 / desktop 仅桌面）
        final m = v == 'both'
            ? L10n.t('both · 双端同卡，先答生效', 'both · both ends, first answer wins')
            : v == 'mobile'
            ? L10n.t('mobile · 手机在线独占', 'mobile · phone-exclusive while online')
            : v == 'desktop'
            ? L10n.t('desktop · 仅桌面 GUI', 'desktop · desktop GUI only')
            : '${v ?? '?'}';
        buf.writeln('  ℹ $shown：$m');
      } else if (v == true) {
        buf.writeln('  ✅ $shown');
      } else if (v == false) {
        buf.writeln('  ❌ $shown');
      } else if (v is num) {
        // 计数字段（如 pendingFrames 挂起待答数）：0 正常，>0 表示有问询/审批待处理
        buf.writeln(
          '  ${v == 0 ? '✅' : '⚠'} $shown = $v${v == 0 ? '' : L10n.t('（有审批/问询待处理）', ' (approval/question pending)')}',
        );
      } else {
        // v3.1.3（issue #9）：策略/状态字符串字段（如 approvalMode = both）友好直读
        buf.writeln('  ℹ $shown = $v');
      }
    });
    final notes = d['notes'] as List? ?? [];
    if (notes.isNotEmpty) {
      buf.writeln();
      buf.writeln(L10n.t('备注:', 'Notes:'));
      for (final n in notes) {
        buf.writeln('  • $n');
      }
    }
    final plugin = d['plugin'] as Map<String, dynamic>? ?? {};
    buf.writeln();
    buf.writeln(
      '${L10n.t('插件: ', 'Plugin: ')}${plugin['name']} v${plugin['version']}',
    );
    return buf.toString();
  }

  /// 实时指标中文名（v3.1.3 runtime.metrics）。未知 key 原样返回。
  String _metricsName(String key) {
    switch (key) {
      case 'mobileOnline':
        return L10n.t('手机在线连接', 'Phone connections');
      case 'agents':
        return L10n.t('运行中 Agent', 'Live agents');
      case 'sessions':
        return L10n.t('会话数', 'Sessions');
      case 'workspaces':
        return L10n.t('工作区数', 'Workspaces');
      case 'pushChannels':
        return L10n.t('推送通道', 'Push channels');
      default:
        return key;
    }
  }

  /// 服务/实测项中文名（环境诊断可读化，v3.1.3+）。未知 key 原样返回。
  /// 渲染时保留英文 key 便于复制粘贴排障（issue/日志对照）。
  String _diagName(String section, String key) {
    switch (section) {
      case 'services':
        switch (key) {
          case 'webServer':
            return L10n.t('网页服务', 'Web server');
          case 'agents':
            return L10n.t('Agent 服务', 'Agents');
          case 'sessions':
            return L10n.t('会话服务', 'Sessions');
          case 'llm':
            return L10n.t('模型服务', 'LLM');
          case 'permissionPresets':
            return L10n.t('权限预设', 'Permission presets');
          case 'agentPresets':
            return L10n.t('Agent 预设', 'Agent presets');
          case 'workspaceRegistry':
            return L10n.t('工作区服务', 'Workspaces');
          case 'approval':
            return L10n.t('审批服务', 'Approval');
          case 'credentials':
            return L10n.t('凭据服务', 'Credentials');
          case 'messageFeedback':
            return L10n.t('消息反馈', 'Message feedback');
          case 'userQuestions':
            return L10n.t('问询服务', 'Questions');
          case 'apiProxy':
            return L10n.t(
              '旧帧桥 apiProxy（0.1.1 内核）',
              'Legacy apiProxy (0.1.1 kernel)',
            );
          default:
            return key;
        }
      default:
        switch (key) {
          case 'modelsRpc':
            return L10n.t('模型目录 RPC', 'Model catalog RPC');
          case 'sessionsList':
            return L10n.t('会话列表', 'Session list');
          case 'directories':
            return L10n.t('目录浏览', 'Directory browse');
          case 'workspaces':
            return L10n.t('工作区列表', 'Workspace list');
          case 'notifications':
            return L10n.t('通知中心', 'Notifications');
          case 'actions':
            return L10n.t('动作区', 'Actions');
          case 'approvalMode':
            return L10n.t('审批策略', 'Approval mode');
          case 'remoteEvents':
            return L10n.t('双端审批通道', 'Dual-end channel');
          case 'respondBridge':
            return L10n.t('旧帧桥应答（0.1.1 内核）', 'Legacy respond (0.1.1 kernel)');
          case 'frameBridge':
            return L10n.t(
              '旧帧桥循环（0.1.1 内核）',
              'Legacy frame loop (0.1.1 kernel)',
            );
          case 'pendingFrames':
            return L10n.t('挂起待答', 'Pending frames');
          default:
            return key;
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    final c = DshPalette.of(context);

    String permName(String? id) => permNameOf(id) ?? '…';
    String presetName(String? id) => switch (id) {
      'standard' => L10n.t('标准模式', 'Standard'),
      'code' => L10n.t('PTC 模式', 'PTC'),
      'minimal' => L10n.t('极简模式', 'Minimal'),
      'cordis' => L10n.t('创造模式', 'Creative'),
      _ => '…',
    };

    // 右侧取值文本（语言、模型名、预设名）：xs13 · tertiary。
    Widget value(String text) =>
        Text(text, style: DshType.xs13.copyWith(color: c.ink3));

    final connColor = switch (store.connState) {
      'connected' => c.ok,
      'connecting' => c.warn,
      _ => c.ink3,
    };
    final connText = switch (store.connState) {
      'connected' => L10n.t('已连接', 'Connected'),
      'connecting' => L10n.t('连接中…', 'Connecting…'),
      _ => L10n.t('离线 · 自动重连', 'Offline · reconnecting'),
    };

    return ListView(
      padding: const EdgeInsets.only(bottom: DshSpace.xxl),
      children: [
        // ── 连接 ──
        DshSectionHeader(L10n.t('连接', 'Connection')),
        DshCardGroup(
          children: [
            DshTile(
              leading: const Icon(Icons.computer_outlined),
              title: L10n.t('电脑地址', 'PC address'),
              subtitle: api.baseUrls.length > 1
                  ? L10n.t(
                      '${api.baseUrl} · 共 ${api.baseUrls.length} 个地址自动切换 · 点按手动切换',
                      '${api.baseUrl} · ${api.baseUrls.length} addresses · tap to switch',
                    )
                  : api.baseUrl,
              chevron: true,
              // 连接状态实时显示（修复：旧版写死「已连接」，断线也显示绿色已连接）
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DshStatusDot(color: connColor),
                  const SizedBox(width: DshSpace.xs),
                  Text(
                    connText,
                    style: DshType.xs13.copyWith(color: connColor),
                  ),
                ],
              ),
              onTap: () => _pickAddress(),
            ),
            DshTile(
              leading: const Icon(Icons.settings_outlined),
              title: L10n.t('重新配置连接', 'Reconfigure connection'),
              subtitle: L10n.t('更换电脑地址或访问口令', 'Change PC address or token'),
              chevron: true,
              onTap: () => widget.onReconfigure(),
            ),
          ],
        ),
        // v3.1.2：推送通道自检（配置在电脑端 cordis.patch.yml 的 pushUrls）
        DshSectionHeader(L10n.t('通知', 'Notifications')),
        DshCardGroup(
          children: [
            DshTile(
              leading: const Icon(Icons.notifications_active_outlined),
              title: L10n.t('发送测试通知', 'Send test notification'),
              subtitle: L10n.t(
                '验证推送通道（电脑端 cordis.patch.yml 配置）',
                'Verify push channels (configured on the PC)',
              ),
              chevron: true,
              onTap: _sendTestPush,
            ),
          ],
        ),
        DshSectionHeader(L10n.t('默认配置', 'Defaults')),
        DshCardGroup(
          children: [
            DshTile(
              leading: const Icon(Icons.security_outlined),
              title: L10n.t('默认权限预设', 'Default permission'),
              subtitle: L10n.t('作用于之后新建的会话', 'Applies to new sessions'),
              chevron: true,
              trailing: value(
                permName(store.catalog?.defaults['permissionPreset'] as String?),
              ),
              onTap: () => _pickDefaultPerm(store),
            ),
            DshTile(
              leading: const Icon(Icons.bolt_outlined),
              title: L10n.t('默认 Agent 预设', 'Default agent preset'),
              subtitle: L10n.t('作用于之后新建的会话', 'Applies to new sessions'),
              chevron: true,
              trailing: value(
                presetName(store.catalog?.defaults['agentPreset'] as String?),
              ),
              onTap: () => _pickDefaultPreset(store),
            ),
            DshTile(
              leading: const Icon(Icons.dns_outlined),
              title: L10n.t('模型提供商', 'Model providers'),
              subtitle: L10n.t(
                '与 PC 端「设置 → 模型」同一配置通道',
                'Same channel as PC Settings → Models',
              ),
              chevron: true,
              onTap: () {
                // Phase 2：与模型弹层共用提供商页打开入口
                openProviders(context, store);
              },
            ),
          ],
        ),
        DshSectionHeader(L10n.t('账户', 'Account')),
        DshCardGroup(
          children: [
            DshTile(
              leading: const Icon(Icons.account_balance_wallet_outlined),
              title: L10n.t('用量与额度', 'Usage & allowance'),
              subtitle: _usageLabel,
              chevron: true,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _usage == null
                        ? '—'
                        : '${_usage!.sources.where((source) => source.available).length}',
                    style: DshType.xs13.copyWith(
                      color: _deepSeekLow ? c.danger : c.ink3,
                    ),
                  ),
                  if (_usageBusy)
                    const Padding(
                      padding: EdgeInsets.only(left: DshSpace.sm),
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                ],
              ),
              onTap: _openUsage,
            ),
            DshTile(
              leading: const Icon(Icons.add_card_outlined),
              title: L10n.t('充值', 'Top up'),
              subtitle: L10n.t(
                '跳转 DeepSeek 开放平台',
                'Go to DeepSeek Open Platform',
              ),
              chevron: true,
              onTap: () => launchUrl(
                // 以电脑端插件配置为准（catalog.rechargeUrl），缺省回退官方充值页
                Uri.parse(
                  store.catalog?.rechargeUrl ??
                      'https://platform.deepseek.com/top_up',
                ),
                mode: LaunchMode.externalApplication,
              ),
            ),
            DshTile(
              leading: const Icon(Icons.notifications_active_outlined),
              title: L10n.t('余额预警', 'Low-balance alert'),
              // v2.7.1：副标题动态显示当前阈值
              subtitle:
                  L10n.t('余额低于 ¥', 'Remind to top up when balance is below ¥') +
                  _fmtThreshold(store.balanceThreshold) +
                  L10n.t(' 时提醒充值（点此修改）', ' — tap to change'),
              trailing: DshSwitch(
                value: store.balanceAlert,
                onChanged: (v) => store.setBalanceAlert(v),
              ),
              onTap: _pickThreshold,
            ),
          ],
        ),
        DshSectionHeader(L10n.t('显示', 'Display')),
        DshCardGroup(
          children: [
            DshTile(
              leading: const Icon(Icons.psychology_outlined),
              title: L10n.t('思考内容', 'Thinking content'),
              subtitle: L10n.t(
                '活动条思考状态展开时是否显示思考原文（默认关：只显示状态）',
                'Show raw thinking text when expanded (default off: status only)',
              ),
              trailing: DshSwitch(
                value: store.showReasoning,
                onChanged: (v) => store.setShowReasoning(v),
              ),
            ),
            DshTile(
              leading: const Icon(Icons.account_tree_outlined),
              title: L10n.t('思维链默认展开', 'Thinking chain default expanded'),
              subtitle: L10n.t(
                '回复里的「思维链」块默认折叠还是展开（单条消息仍可点按切换）',
                'Whether the thinking-chain block in replies is expanded by default (each message stays toggleable)',
              ),
              trailing: DshSwitch(
                value: store.reasoningDefaultExpanded,
                onChanged: (v) => store.setReasoningDefaultExpanded(v),
              ),
            ),
            DshTile(
              leading: const Icon(Icons.bug_report_outlined),
              title: L10n.t('对话调试模式', 'Conversation debug mode'),
              subtitle: L10n.t(
                '显示工具原始参数、结果、事件序号与未知可见事件（默认关闭）',
                'Show raw tool IO, event metadata and unknown visible events (off by default)',
              ),
              trailing: DshSwitch(
                value: store.timelineDebug,
                onChanged: (v) => store.setTimelineDebug(v),
              ),
            ),
            DshTile(
              leading: const Icon(Icons.dark_mode_outlined),
              title: L10n.t('深色模式', 'Dark mode'),
              subtitle: switch (store.darkMode) {
                'dark' => L10n.t('已选深色', 'Dark'),
                'light' => L10n.t('已选浅色', 'Light'),
                _ => L10n.t('跟随系统', 'System'),
              },
              // 三态循环：点右侧取值在 系统 → 深色 → 浅色 之间切换
              trailing: GestureDetector(
                onTap: () {
                  final next = switch (store.darkMode) {
                    'system' => 'dark',
                    'dark' => 'light',
                    _ => 'system',
                  };
                  store.setDarkMode(next);
                },
                child: value(switch (store.darkMode) {
                  'dark' => L10n.t('深色', 'Dark'),
                  'light' => L10n.t('浅色', 'Light'),
                  _ => L10n.t('跟随系统', 'System'),
                }),
              ),
            ),
            DshTile(
              leading: const Icon(Icons.language_outlined),
              title: L10n.t('语言', 'Language'),
              subtitle: L10n.t(
                '界面显示语言（即时生效）',
                'UI language (applies immediately)',
              ),
              chevron: true,
              trailing: value(store.language == 'en' ? 'English' : '中文'),
              onTap: () => _pickLanguage(store),
            ),
            DshTile(
              leading: const Icon(Icons.bubble_chart_outlined),
              title: L10n.t('悬浮球', 'Floating bubble'),
              subtitle: L10n.t(
                '桌面悬浮球：agent 运行/通知/余额低时亮起，单击展开面板（默认关）',
                'Floating bubble: lights up on activity, tap to open panel (off by default)',
              ),
              trailing: DshSwitch(value: _bubbleOn, onChanged: _toggleBubble),
            ),
            DshTile(
              leading: const Icon(Icons.help_outline),
              title: L10n.t('悬浮球操作说明', 'Bubble guide'),
              subtitle: L10n.t('状态含义与手势操作', 'Status meaning and gestures'),
              chevron: true,
              onTap: _showBubbleGuide,
            ),
          ],
        ),
        DshSectionHeader(L10n.t('关于', 'About')),
        DshCardGroup(
          children: [
            DshTile(
              leading: const Icon(Icons.info_outline),
              title: L10n.t('版本', 'Version'),
              subtitle:
                  'App v${_appVersion.isEmpty ? '…' : _appVersion}'
                  ' · ${L10n.t('插件', 'plugin')} v${api.pluginVersion.isEmpty ? '…' : api.pluginVersion}',
            ),
            // v3.2.1：应用内更新入口——检测到新版后可直接覆盖安装（同签名，无需卸载）
            DshTile(
              leading: const Icon(Icons.system_update_alt),
              title: L10n.t('检查更新', 'Check for updates'),
              subtitle: L10n.t(
                '有新版本会提示，可直接覆盖安装',
                'Prompts on new versions; installs right over the current app',
              ),
              trailing: DshButton(
                label: L10n.t('检查', 'Check'),
                size: DshButtonSize.sm,
                variant: DshButtonVariant.outline,
                onPressed: () {
                  checkUpdateInteractive(context);
                },
              ),
            ),
            DshTile(
              leading: const Icon(Icons.monitor_heart_outlined),
              title: L10n.t('环境诊断', 'Diagnostics'),
              subtitle: _diagLoaded
                  ? '${L10n.t('检测完成 · ', 'Done · ')}$_diagTime'
                  : L10n.t('检测当前环境各项能力', 'Check environment capabilities'),
              trailing: DshButton(
                label: L10n.t('查看', 'View'),
                size: DshButtonSize.sm,
                variant: DshButtonVariant.outline,
                onPressed: _openDiag,
              ),
            ),
            DshTile(
              leading: const Icon(Icons.article_outlined),
              title: L10n.t('应用日志', 'App log'),
              subtitle: L10n.t(
                '启动/连接/加载事件（排障用）',
                'Startup/connection/load events (troubleshooting)',
              ),
              trailing: DshButton(
                label: L10n.t('查看', 'View'),
                size: DshButtonSize.sm,
                variant: DshButtonVariant.outline,
                onPressed: _openLog,
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ── 环境诊断：状态圆点 + 分组卡片（官方设置卡片版式） ──

  /// 诊断分组：小节标题 + 一张 R20 卡片。
  Widget _diagSection(String title, List<Widget> rows) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DshSectionHeader(
          title,
          padding: const EdgeInsets.only(
            top: DshSpace.lg,
            bottom: DshSpace.sm,
          ),
        ),
        DshCardGroup(margin: EdgeInsets.zero, children: rows),
      ],
    );
  }

  /// 诊断信息行：标签 + 取值（短值走右侧 trailing，长值走副标题换行省略）。
  Widget _diagValueTile(String label, String value, {bool inline = false}) {
    final c = DshPalette.of(context);
    return DshTile(
      dense: true,
      title: label,
      subtitle: inline ? null : value,
      trailing:
          inline ? Text(value, style: DshType.xs13.copyWith(color: c.ink3)) : null,
    );
  }

  /// 服务项行：✅/❌ 统一用状态圆点（c.ok / c.danger）+ 服务名。
  Widget _diagServiceTile(String key, bool ok) {
    final c = DshPalette.of(context);
    final name = _diagName('services', key);
    return DshTile(
      dense: true,
      leading: DshStatusDot(color: ok ? c.ok : c.danger),
      title: name,
      subtitle: key == name ? null : key,
    );
  }

  /// 端点实测行：布尔 → 圆点；数值 → 0 正常/否则警告；其余按值直读。
  Widget _diagCheckTile(String key, dynamic v) {
    final c = DshPalette.of(context);
    final name = _diagName('checks', key);
    final shown = key == name ? name : '$name ($key)';
    if (key == 'approvalMode') {
      // v3.1.3：审批策略取值说明（both 双端同卡 / mobile 手机独占 / desktop 仅桌面）
      final m = v == 'both'
          ? L10n.t('both · 双端同卡，先答生效', 'both · both ends, first answer wins')
          : v == 'mobile'
          ? L10n.t('mobile · 手机在线独占', 'mobile · phone-exclusive while online')
          : v == 'desktop'
          ? L10n.t('desktop · 仅桌面 GUI', 'desktop · desktop GUI only')
          : '${v ?? '?'}';
      return DshTile(
        dense: true,
        leading: const Icon(Icons.info_outline),
        title: shown,
        subtitle: m,
      );
    }
    if (v is bool) {
      return DshTile(
        dense: true,
        leading: DshStatusDot(color: v ? c.ok : c.danger),
        title: shown,
      );
    }
    if (v is num) {
      // 计数字段（如 pendingFrames 挂起待答数）：0 正常，>0 表示有问询/审批待处理
      return DshTile(
        dense: true,
        leading: DshStatusDot(color: v == 0 ? c.ok : c.warn),
        title: shown,
        subtitle: v == 0
            ? '$v'
            : '$v · ${L10n.t('有审批/问询待处理', 'approval/question pending')}',
      );
    }
    return DshTile(
      dense: true,
      leading: const Icon(Icons.info_outline),
      title: shown,
      subtitle: '${v ?? '?'}',
    );
  }

  /// 诊断内容（底部弹层正文）。
  Widget _diagContent() {
    final c = DshPalette.of(context);
    final d = _diag;
    if (d == null) {
      return DshBanner(
        message: L10n.t(
          '检测失败：无法读取电脑端环境信息，请确认连接后重试。',
          'Check failed: could not read the desktop environment. Reconnect and retry.',
        ),
        icon: Icons.error_outline,
        tone: DshBannerTone.danger,
      );
    }
    final runtime = d['runtime'] as Map<String, dynamic>? ?? const {};
    final form = runtime['form'];
    final formText = form == 'desktop'
        ? 'desktop · ${L10n.t('桌面版', 'DSH Desktop')}'
        : form == 'cli'
        ? 'cli · ${L10n.t('命令行/网页', 'CLI / Web')}'
        : '${form ?? '?'}';
    final authText = runtime['authEnabled'] == true
        ? L10n.t('口令已启用', 'auth on')
        : L10n.t('口令未启用', 'auth off');
    final metrics = runtime['metrics'] as Map<String, dynamic>? ?? const {};
    final services = d['services'] as Map<String, dynamic>? ?? const {};
    final checks = d['checks'] as Map<String, dynamic>? ?? const {};
    final notes = d['notes'] as List? ?? const [];
    final plugin = d['plugin'] as Map<String, dynamic>? ?? const {};

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_diagTime.isNotEmpty)
          Text(
            '${L10n.t('检测完成 · ', 'Done · ')}$_diagTime',
            style: DshType.xs13.copyWith(color: c.ink3),
          ),
        _diagSection(L10n.t('运行环境', 'Runtime'), [
          _diagValueTile('${L10n.t('运行形态', 'Mode')} · $authText', formText),
          _diagValueTile(
            L10n.t('监听', 'Listen'),
            '${runtime['host']}:${runtime['port']}',
            inline: true,
          ),
          _diagValueTile(L10n.t('进程目录', 'CWD'), '${runtime['cwd']}'),
        ]),
        if (metrics.isNotEmpty)
          _diagSection(L10n.t('实时指标', 'Live metrics'), [
            for (final e in metrics.entries)
              _diagValueTile(_metricsName(e.key), '${e.value}', inline: true),
          ]),
        if (services.isNotEmpty)
          _diagSection(L10n.t('服务', 'Services'), [
            for (final e in services.entries)
              _diagServiceTile(e.key, e.value == true),
          ]),
        if (checks.isNotEmpty)
          _diagSection(L10n.t('端点实测', 'Endpoint checks'), [
            for (final e in checks.entries) _diagCheckTile(e.key, e.value),
          ]),
        if (notes.isNotEmpty)
          _diagSection(L10n.t('备注', 'Notes'), [
            for (final n in notes)
              DshTile(dense: true, title: '$n', maxTitleLines: 4),
          ]),
        if (plugin.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: DshSpace.md),
            child: Text(
              '${L10n.t('插件', 'Plugin')} ${plugin['name']} v${plugin['version']}',
              style: DshType.xs13.copyWith(color: c.ink3),
            ),
          ),
      ],
    );
  }

  /// 修改默认 Agent 预设（作用于之后新建的会话）
  void _pickDefaultPreset(AppStore store) {
    final cat = store.catalog;
    if (cat == null) return;
    final current = cat.defaults['agentPreset'] as String?;
    final msgr = ScaffoldMessenger.of(context);
    showChoiceSheet(
      context,
      title: L10n.t('默认 Agent 预设', 'Default agent preset'),
      items: [
        for (final p in cat.agentPresets)
          (id: p.id, name: p.name, sub: p.description),
      ],
      selectedId: current,
      footnote: L10n.t('作用于之后新建的会话', 'Applies to new sessions'),
      onPick: (id) async {
        try {
          await api.updateDefaults(agentPreset: id);
          await store.refreshAll();
          showToastAt(msgr, L10n.t('已设置默认预设', 'Default preset set'));
        } catch (e) {
          showToastAt(msgr, '${L10n.t('设置失败：', 'Failed: ')}$e');
        }
      },
    );
  }

  /// 修改默认权限预设（作用于之后新建的会话）
  void _pickDefaultPerm(AppStore store) {
    final cat = store.catalog;
    if (cat == null) return;
    final current = cat.defaults['permissionPreset'] as String?;
    final msgr = ScaffoldMessenger.of(context);
    showChoiceSheet(
      context,
      title: L10n.t('默认权限预设', 'Default permission preset'),
      items: [
        for (final p in cat.permissionPresets)
          (id: p.id, name: p.name, sub: p.description),
      ],
      selectedId: current,
      footnote: L10n.t('作用于之后新建的会话', 'Applies to new sessions'),
      onPick: (id) async {
        try {
          await api.updateDefaults(permissionPreset: id);
          await store.refreshAll();
          showToastAt(msgr, L10n.t('已设置默认权限', 'Default permission set'));
        } catch (e) {
          showToastAt(msgr, '${L10n.t('设置失败：', 'Failed: ')}$e');
        }
      },
    );
  }

  /// 悬浮球操作说明弹窗（状态含义 + 手势操作）。
  void _showBubbleGuide() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(L10n.t('悬浮球操作说明', 'Floating bubble guide')),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _guideSection(L10n.t('状态', 'Status'), [
                (
                  L10n.t('灰色鲸鱼', 'Gray whale'),
                  L10n.t('一切正常，空闲', 'All good, idle'),
                ),
                (
                  L10n.t('蓝色鲸鱼', 'Blue whale'),
                  L10n.t(
                    'agent 运行中 / 有新通知 / 余额不足',
                    'Agent running / new notification / low balance',
                  ),
                ),
                (
                  L10n.t('红色角标', 'Red badge'),
                  L10n.t('未读通知数（60 秒后自动消退）', 'Unread count (clears after 60s)'),
                ),
              ]),
              const SizedBox(height: DshSpace.md),
              _guideSection(L10n.t('手势', 'Gestures'), [
                (
                  L10n.t('单击', 'Tap'),
                  L10n.t('展开 / 收起面板', 'Open / close panel'),
                ),
                (
                  L10n.t('拖动', 'Drag'),
                  L10n.t(
                    '移动位置，松手贴边，5 秒无操作自动缩进',
                    'Move; snaps to edge, auto-hides after 5s',
                  ),
                ),
                (L10n.t('双击', 'Double tap'), L10n.t('打开 App', 'Open the app')),
                (
                  L10n.t('长按', 'Long press'),
                  L10n.t('退出悬浮球', 'Exit the bubble'),
                ),
              ]),
              const SizedBox(height: DshSpace.md),
              _guideSection(L10n.t('面板', 'Panel'), [
                (
                  L10n.t('内容', 'Content'),
                  L10n.t(
                    '运行中会话 / 最近通知 / 用量与额度 / 打开 App / 去充值',
                    'Active sessions / notifications / usage & allowance / open app / top up',
                  ),
                ),
                (
                  L10n.t('关闭', 'Close'),
                  L10n.t('点面板外任意位置', 'Tap anywhere outside'),
                ),
              ]),
            ],
          ),
        ),
        actions: [
          DshButton(
            label: L10n.t('知道了', 'Got it'),
            size: DshButtonSize.sm,
            onPressed: () => Navigator.of(ctx).pop(),
          ),
        ],
      ),
    );
  }

  Widget _guideSection(String title, List<(String, String)> rows) {
    final c = DshPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: DshType.xsStrong13.copyWith(color: c.ink3)),
        const SizedBox(height: DshSpace.xs),
        for (final (k, v) in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: DshSpace.xs),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 88,
                  child: Text(k, style: DshType.xs13.copyWith(color: c.ink2)),
                ),
                Expanded(
                  child: Text(v, style: DshType.xs13.copyWith(color: c.ink3)),
                ),
              ],
            ),
          ),
      ],
    );
  }

  /// 选择界面语言（中文 / English），即时生效 + 持久化。
  Future<void> _pickLanguage(AppStore store) async {
    final c = DshPalette.of(context);
    final choice = await showDshSheet<String>(
      context: context,
      builder: (ctx) => DshSheet(
        title: L10n.t('选择语言', 'Choose language'),
        child: DshCardGroup(
          margin: EdgeInsets.zero,
          children: [
            for (final (id, name) in [('zh', '中文'), ('en', 'English')])
              DshTile(
                dense: true,
                title: name,
                selected: store.language == id,
                trailing: store.language == id
                    ? Icon(Icons.check, size: 16, color: c.brand)
                    : null,
                onTap: () => Navigator.of(ctx).pop(id),
              ),
          ],
        ),
      ),
    );
    if (choice != null) await store.setLanguage(choice);
  }

  /// 应用日志：查看 / 复制 / 清空
  Future<void> _openLog() async {
    final text = await AppLog.instance.readAll();
    if (!mounted) return;
    final msgr = ScaffoldMessenger.of(context);
    final c = DshPalette.of(context);
    await showDshSheet<void>(
      context: context,
      builder: (ctx) => DshSheet(
        title: L10n.t('应用日志', 'App log'),
        actions: Row(
          children: [
            Expanded(
              child: DshButton(
                label: L10n.t('清空', 'Clear'),
                size: DshButtonSize.sm,
                variant: DshButtonVariant.danger,
                onPressed: () async {
                  await AppLog.instance.clear();
                  showToastAt(msgr, L10n.t('日志已清空', 'Log cleared'));
                },
              ),
            ),
            const SizedBox(width: DshSpace.sm),
            Expanded(
              child: DshButton(
                label: L10n.t('复制', 'Copy'),
                icon: Icons.content_copy_outlined,
                size: DshButtonSize.sm,
                variant: DshButtonVariant.outline,
                onPressed: () => _copy(text),
              ),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${L10n.t('最近 ', 'Last ')}${AppLog.instance.lines.length}${L10n.t(' 条 · 文件 dsh_mobile.log', ' entries · file dsh_mobile.log')}',
              style: DshType.xs13.copyWith(color: c.ink3),
            ),
            const SizedBox(height: DshSpace.sm),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 320),
              child: SingleChildScrollView(
                // v3.0.0：日志倒序展示——最新日志在最上面，不用每次翻到底部
                child: SelectableText(
                  text.isEmpty ? L10n.t('（暂无日志）', '(No logs)') : _reverseLog(text),
                  style: DshType.mdCodeSmall.copyWith(color: c.ink),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// v3.0.0：日志倒序展示（最新在上，省去翻到底部）——逐行倒排，丢弃尾部空行。
  static String _reverseLog(String text) {
    final lines = text.split('\n');
    return lines.reversed.where((l) => l.isNotEmpty).join('\n');
  }

  Future<void> _openDiag() async {
    // 每次打开都实时拉取（修复：旧版只在首次加载，之后永远显示过期版本）
    await _loadDiag();
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    await showDshSheet<void>(
      context: context,
      builder: (ctx) => DshSheet(
        title: L10n.t('环境诊断', 'Diagnostics'),
        actions: DshButton(
          label: L10n.t('复制诊断信息', 'Copy diagnostics'),
          icon: Icons.content_copy_outlined,
          size: DshButtonSize.sm,
          variant: DshButtonVariant.outline,
          expanded: true,
          onPressed: () => _copy(_diagText),
        ),
        child: _diagContent(),
      ),
    );
  }

  Future<void> _copy(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      showToast(context, L10n.t('已复制', 'Copied'));
    }
  }
}
