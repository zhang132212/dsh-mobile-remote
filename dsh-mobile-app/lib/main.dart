// DSH Remote — 手机远程操作 DeepSeek Harness
// 原生 App：抽屉导航（首页/会话/设置）+ 通知 + 连接配置 + 扫码连接。
// 界面与功能对齐网页端 dsh-mobile-remote（DeepSeek 配色，Claude 式布局）。
import 'dart:async';
import 'dart:io' show HttpException, SocketException;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'l10n.dart';
import 'api.dart';
import 'store.dart';
import 'floating.dart';
import 'dsh_kit.dart';
import 'theme.dart';
import 'logger.dart';
import 'platform_support.dart';
import 'scan_screen.dart';
import 'toast.dart';
import 'update/update_ui.dart';
import 'screens/chat_screen.dart';
import 'screens/doc_viewer_screen.dart';
import 'screens/home_screen.dart';
import 'screens/sessions_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/notifications_screen.dart';
import 'screens/sheets.dart';
import 'screens/usage_screen.dart';

final AppStore store = AppStore();

/// 全局导航 key（悬浮球面板等跨页面入口用）。
final rootNavigatorKey = GlobalKey<NavigatorState>();

/// Phase 2(A8)：打开通知页（抽屉/悬浮球/banner 三入口共用，可选"打开会话后"回调）。
void openNotificationsScreen({VoidCallback? onOpenSession}) {
  final nav = rootNavigatorKey.currentState;
  if (nav == null) return;
  nav.push(MaterialPageRoute(
    builder: (_) => NotificationsScreen(store: store, onOpenSession: onOpenSession ?? () {}),
  ));
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppLog.instance.init();
  AppLog.instance.log('main: 启动，baseUrl=${api.baseUrl.isNotEmpty ? "已配置" : "空"}');
  // 全局错误边界：build/布局异常不再白屏或静默闪退，直接显示错误文本（调试用）
  ErrorWidget.builder = (details) {
    AppLog.instance.log('build 异常: ${details.exceptionAsString()}');
    // v3.2.3 排障（来自发行线 677bad5）：只记异常消息定位不到代码 —— 把堆栈也记下来
    // （多行，logcat 可直接看）。那次「整条回答永久不显示」就是靠它才拿到行号。
    AppLog.instance.log('build 栈:\n${details.stack ?? "(无栈)"}');
    return _ErrorFallback(details.exceptionAsString());
  };
  await api.load();
  await store.loadPrefs();
  // v2.7.1：启动即把余额预警配置同步给悬浮球（可能已在后台运行，判定以 App 端设置为准）。
  // iOS 无系统悬浮球：Floating 内部已 no-op，这里显式跳过，避免无意义的通道调用。
  if (Floating.isSupported) {
    unawaited(Floating.setBalanceAlert(store.balanceAlert, store.balanceThreshold));
  }
  // v2.7.2：上次开过悬浮球 → 自动恢复服务（清理后台/重启 App 后无需手动重开）
  unawaited(store.restoreFloating());
  runApp(const DshApp());
}

class DshApp extends StatefulWidget {
  const DshApp({super.key});

  @override
  State<DshApp> createState() => _DshAppState();
}

class _DshAppState extends State<DshApp> {
  // v2.7.1：通知横幅全局状态（MaterialApp.builder 渲染在所有 route 之上；
  // 页面内 Stack 会被 push 的聊天页/通知页遮挡，OverlayEntry 又有 remove 残留 bug）
  int? _bannerCount;
  Timer? _bannerTimer;
  DateTime _lastBannerAt = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    store.addListener(_onStore);
    // 新增未读通知 → 全局顶部横幅
    store.onNewNotifications = _onNewNotifications;
    // 悬浮球迷你面板动作（原生 → Flutter）：打开会话 / 去充值。
    // iOS：不支持系统悬浮球、dsh/floating 通道不存在——不注册 handler（动作调用也已全部 no-op）。
    if (Floating.isSupported) {
      const MethodChannel('dsh/floating').setMethodCallHandler(_onFloatingCall);
    }
    // v2.7.2 review：冷启动面板动作兜底——Dart handler 注册晚于原生 deliver，
    // 首帧后主动拉取原生暂存的动作（可能已被 handler 消费，幂等）
    WidgetsBinding.instance.addPostFrameCallback((_) => _consumePendingFloatingAction());

    // v3.2.0 文档阅读器：原生「用本 App 打开文档」入口。
    // 原生侧（MainActivity）从 VIEW/SEND intent 读出 content:// 字节后，
    // 经 dsh/files 通道的 openDocument 投递过来；冷启动时序不一定谁先谁后，
    // 所以「事件推送」与「首帧主动拉取」两条路都要，靠下面的去重兜住重复。
    const MethodChannel('dsh/files').setMethodCallHandler((call) async {
      if (call.method == 'openDocument') {
        await _openIncomingDoc(call.arguments);
      }
      return null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _pullPendingDoc());

    // v3.2.1：启动静默检查更新——有新版才弹窗，6 小时内不重复打扰；
    // 网络/验签失败一律静默（手动「检查更新」时才把原因告诉用户）。
    // 延后 3 秒：等首帧与连接状态稳定后再弹，避免和启动动画/扫码引导抢注意力。
    Future<void>.delayed(const Duration(seconds: 3), () async {
      final c = rootNavigatorKey.currentContext;
      if (c != null && c.mounted) await checkUpdateSilent(c);
    });
  }

  /// 悬浮球迷你面板动作（热启动路径）：原生 → Flutter，打开会话 / 去充值 / 通知页 / 用量页。
  Future<dynamic> _onFloatingCall(MethodCall call) async {
    final nav = rootNavigatorKey.currentState;
    if (nav == null) return null;
    switch (call.method) {
      case 'openSessionRequested':
        final id = call.arguments as String?;
        if (id == null || id.isEmpty) break;
        await _handleFloatingAction('session:$id');
        break;
      case 'openChargeRequested':
        await _handleFloatingAction('charge');
        break;
      case 'openNotifsRequested':
        // 打开通知页（与抽屉入口同款：先切到首页再推通知页）
        await _handleFloatingAction('notifs');
        break;
      case 'openUsageRequested':
        // 悬浮球面板「用量与额度」区块 → App 用量页
        await _handleFloatingAction('usage');
        break;
    }
    return null;
  }

  /// 外部文档「同一次投递」去重（cross-review F3 + C3）：
  /// 原生带 deliveryId 时按 id 精确去重（事件推送 + 首帧拉取只开一次）；
  /// 无 id（Android 旧原生）时回退同名同大小 + 1s 短窗口。详见 IncomingDocDeduper。
  final IncomingDocDeduper _docDeduper = IncomingDocDeduper();

  /// 冷启动兜底：原生已暂存但事件早于 handler 注册时，首帧后主动取一次。
  Future<void> _pullPendingDoc() async {
    try {
      final data = await FileBridge.getIncomingFile();
      if (data == null) return;
      AppLog.instance.log('[doc] 首帧拉取到原生暂存文档: ${data['name']} '
          'bytes=${(data['bytes'] as List?)?.length ?? 0} err=${data['error']}');
      await _openIncomingDoc(data);
    } catch (e) {
      // 原生未实现该通道（旧版本 App / 桌面端）时静默忽略——FileBridge 已把异常
      // 转成可读文案，这里只记日志，不打扰用户（首帧拉取属于兜底路径）。
      AppLog.instance.log('[doc] 拉取原生暂存文档失败: $e');
    }
  }

  /// 打开外部传入的文档：推到统一的文档阅读页。
  Future<void> _openIncomingDoc(dynamic args) async {
    if (args is! Map) return;
    // cross-review F3：「同一次投递」去重（只认原生可选的 deliveryId）。
    // 不用时间窗——否则「打开文档→返回→5s 内再打开同一文件」会被静默吞掉。
    if (!_docDeduper.shouldAccept(args)) {
      AppLog.instance.log('[doc] 同一次投递的重复回调，忽略');
      return;
    }
    final name = args['name'];
    AppLog.instance.log('[doc] 收到外部文档 name=$name '
        'bytes=${(args['bytes'] as List?)?.length ?? 0} err=${args['error']}');

    // 原生读文件失败（权限不足 / 分享的临时 uri 过期 / 空文件 / 超过 24MB 上限）
    // ——必须给用户一个可操作的归因，不能统一说成「权限不足/链接失效」（cross-review C6）。
    final err = args['error'];
    if (err != null) {
      final code = err is String ? err : err.toString();
      final reason = switch (code) {
        'too-large' => L10n.t('文件超过 24MB 上限', 'the file exceeds the 24MB limit'),
        'empty' => L10n.t('文件为空', 'the file is empty'),
        'read-failed' => L10n.t('无法读取（可能无权限或文件已失效）',
            'cannot read it (permission denied or unavailable)'),
        _ => L10n.t('权限不足或链接已失效', 'permission denied or the link has expired'),
      };
      final msgr = _rootMessenger();
      if (msgr != null) {
        showToastAt(
          msgr,
          L10n.t(
            '无法打开该文件${name is String ? '（$name）' : ''}：$reason',
            'Cannot open the file${name is String ? ' ($name)' : ''}: $reason',
          ),
        );
      }
      try {
        await FileBridge.clearIncomingFile();
      } catch (_) {/* 清理失败不影响提示 */}
      return;
    }

    final bytes = args['bytes'];
    if (bytes is! Uint8List || name is! String || bytes.isEmpty) {
      AppLog.instance.log('[doc] 参数不完整，忽略（bytes/name 缺失）');
      return;
    }
    var nav = rootNavigatorKey.currentState;
    if (nav == null) {
      // cross-review F4：导航器未就绪不能直接丢弃（否则这次「用 DSH Remote 打开」
      // 永久丢失、原生暂存字节常驻）。等一帧 + 300ms 兜底重试一次。
      AppLog.instance.log('[doc] 导航器未就绪，等待首帧后重试一次');
      await _waitForNavigatorRetry();
      if (!mounted) return;
      nav = rootNavigatorKey.currentState;
    }
    if (nav == null) {
      // 重试仍不就绪：清理原生暂存并给用户可读提示（不能静默丢）。
      AppLog.instance.log('[doc] 重试后导航器仍未就绪：清理暂存并提示用户');
      try {
        await FileBridge.clearIncomingFile();
      } catch (_) {/* 清理失败不影响提示 */}
      final msgr = _rootMessenger();
      if (msgr != null) {
        showToastAt(
          msgr,
          L10n.t(
            '无法打开该文件：界面尚未就绪，请重新打开',
            'Cannot open the file: the app UI is not ready yet, please try again',
          ),
        );
      }
      return;
    }
    try {
      await FileBridge.clearIncomingFile();
    } catch (_) {/* 清理失败不影响打开 */}
    AppLog.instance.log('[doc] 打开阅读页: $name (${bytes.length} 字节)');
    await nav.push(
      MaterialPageRoute<void>(
        builder: (_) => DocViewerScreen(name: name, bytes: bytes),
      ),
    );
  }

  /// 等首帧（navigator/Overlay 首帧后才可用）+ 300ms 兜底，供外部文档投递重试一次用。
  Future<void> _waitForNavigatorRetry() {
    final done = Completer<void>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!done.isCompleted) done.complete();
    });
    Future<void>.delayed(const Duration(milliseconds: 300), () {
      if (!done.isCompleted) done.complete();
    });
    return done.future;
  }

  /// 取一个可用的 ScaffoldMessenger（用于无页面 context 的异步回调里弹提示）。
  ScaffoldMessengerState? _rootMessenger() {
    final ctx = rootNavigatorKey.currentContext;
    if (ctx == null) return null;
    return ScaffoldMessenger.maybeOf(ctx);
  }

  /// 统一处理悬浮球面板动作（热启动 handler 与冷启动 consume 共用）。
  Future<void> _handleFloatingAction(String action) async {
    final nav = rootNavigatorKey.currentState;
    if (nav == null) return;
    if (action.startsWith('session:')) {
      final id = action.substring(8);
      if (id.isEmpty) return;
      final prev = store.sessionId;
      // Phase 2(A4)：统一打开会话流程；返回后恢复原会话（悬浮球进入的会话页不改变主会话）
      await openChat(nav.context, store, id,
          onReturn: () async {
        if (prev != null && prev != id) await store.setSession(prev);
      });
    } else if (action == 'charge') {
      await launchUrl(
        Uri.parse(store.catalog?.rechargeUrl ?? 'https://platform.deepseek.com/top_up'),
        mode: LaunchMode.externalApplication,
      );
    } else if (action == 'notifs') {
      // 打开通知页（与抽屉入口同款：先切到首页再推通知页）
      await store.refreshNotifs();
      openNotificationsScreen();
    } else if (action == 'usage') {
      // 悬浮球面板区块 → 用量与额度详情页（每次进入都重新拉取）
      nav.push(MaterialPageRoute(builder: (_) => UsageScreen(store: store)));
    }
  }

  /// 冷启动兜底：拉取原生暂存的面板动作（configureFlutterEngine 投递时 Dart 侧可能未就绪）。
  Future<void> _consumePendingFloatingAction() async {
    if (!Floating.isSupported) return;
    final action = await Floating.consumeOpenPanel();
    if (action == null || action.isEmpty) return;
    AppLog.instance.log('Floating: 冷启动消费动作 $action');
    await _handleFloatingAction(action);
  }

  @override
  void dispose() {
    _bannerTimer?.cancel();
    _bannerTimer = null;
    store.removeListener(_onStore);
    super.dispose();
  }

  void _onStore() {
    if (mounted) setState(() {});
  }

  /// 新增未读通知横幅：顶部滑入，6 秒自动消失（可左右滑动手动关闭），点击跳通知页；10 秒内不重复。
  /// force=true（悬浮球跳转/回前台）时绕过防抖——"错过的也提醒"。
  void _onNewNotifications(int count, {bool force = false}) {
    final now = DateTime.now();
    if (!force && now.difference(_lastBannerAt).inSeconds < 10) {
      AppLog.instance.log('Banner: 防抖拦截（距上次 ${now.difference(_lastBannerAt).inSeconds}s）');
      return;
    }
    _lastBannerAt = now;
    _bannerTimer?.cancel();
    _bannerTimer = null;
    if (!mounted) return;
    setState(() => _bannerCount = count);
    AppLog.instance.log('Banner: 出现 count=$count');
    // v2.8.0：滞留 6 秒自动消失（可左右滑动手动关闭，所以敢放长）；同时更新未读基线防反复弹。
    _bannerTimer = Timer(const Duration(milliseconds: 6000), () {
      _bannerTimer = null;
      AppLog.instance.log('Banner: 到期 timer 触发');
      if (!mounted) return;
      setState(() => _bannerCount = null);
      store.markNotifsSeen();
      AppLog.instance.log('Banner: 到期清理完成');
    });
  }

  @override
  Widget build(BuildContext context) {
    final mode = switch (store.darkMode) {
      'dark' => ThemeMode.dark,
      'light' => ThemeMode.light,
      _ => ThemeMode.system,
    };
    return MaterialApp(
      title: 'DSH Remote',
      debugShowCheckedModeBanner: false,
      navigatorKey: rootNavigatorKey,
      theme: DshTheme.light(),
      darkTheme: DshTheme.dark(),
      themeMode: mode,
      home: const RootScreen(),
      // 全局横幅：渲染在 Navigator（所有 route）之上
      builder: (bannerContext, child) {
        final bannerCount = _bannerCount;
        if (bannerCount != null) {
          AppLog.instance.log('Banner: builder 渲染中 count=$bannerCount');
        }
        if (bannerCount == null) return child!;
        // 注意：这里必须用 builder 的 context（MaterialApp 之下）取主题
        final c = DshPalette.of(bannerContext);
        return Stack(
          children: [
            child!,
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    DshSpace.md,
                    DshSpace.sm,
                    DshSpace.md,
                    0,
                  ),
                  // v2.8.0：左右滑动关闭横幅（Dismissible，横向双向）；滑掉即消失+清未读基线
                  child: Dismissible(
                    key: const ValueKey('notif-banner'),
                    direction: DismissDirection.horizontal,
                    onDismissed: (_) {
                      AppLog.instance.log('Banner: 滑动关闭');
                      _bannerTimer?.cancel();
                      _bannerTimer = null;
                      if (!mounted) return;
                      setState(() => _bannerCount = null);
                      store.markNotifsSeen();
                    },
                    child: Material(
                      color: Colors.transparent,
                      child: GestureDetector(
                        onTap: () {
                          AppLog.instance.log('Banner: 点击关闭');
                          _bannerTimer?.cancel();
                          _bannerTimer = null;
                          if (!mounted) return;
                          setState(() => _bannerCount = null);
                          store.markNotifsSeen();
                          // Phase 2(A8)：与抽屉/悬浮球入口共用通知页打开逻辑
                          openNotificationsScreen();
                        },
                        // 官方 toast：深底 + onToast 文字 + R12 + 发丝边 + 浮层阴影
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: DshSpace.md,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: c.toast,
                            borderRadius: DshRadius.rMd,
                            boxShadow: DshShadow.prominent,
                            border: Border.fromBorderSide(DshStroke.side(c.line3)),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.notifications_active, size: 16, color: c.onToast),
                              const SizedBox(width: DshSpace.sm),
                              Expanded(
                                child: Text(
                                  L10n.t('有 $bannerCount 条新通知', '$bannerCount new notification${bannerCount > 1 ? 's' : ''}'),
                                  style: DshType.xs13.copyWith(color: c.onToast),
                                ),
                              ),
                              Icon(Icons.chevron_right, size: 16, color: c.onToast),
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
      },
    );
  }
}

class RootScreen extends StatefulWidget {
  const RootScreen({super.key});

  @override
  State<RootScreen> createState() => _RootScreenState();
}

class _RootScreenState extends State<RootScreen> with WidgetsBindingObserver {
  bool _configured = false;
  int _index = 0;
  bool _reconfiguring = false; // 重新配置进行中：显示连接页但保留旧配置，取消可回退
  final _drawerKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // 全局状态变化（工作区切换、未读数、连接状态等）→ 重建自身（含抽屉），
    // 否则 const RootScreen 会被父级重建跳过，抽屉里的工作区选中态不会跟着变。
    store.addListener(_onStore);
    _configured = api.baseUrl.isNotEmpty && api.token.isNotEmpty;
    if (_configured) {
      _boot();
    }
  }

  void _onStore() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    store.removeListener(_onStore);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // App 回到前台：主动探测电脑端在线状态（PC 退出/恢复实时反映，无需清后台重进）
    if (state == AppLifecycleState.resumed && _configured) {
      store.resume().then((_) {
        // v2.7.1：错过的也提醒——悬浮球跳转/切回 App 时若有未读（后台期间错过的），
        // 强制弹横幅（绕过防抖；后台时横幅已触发过但用户没看到，基线已同步所以增量不触发）
        if (store.unread > 0) {
          store.onNewNotifications?.call(store.unread, force: true);
        }
      });
    }
  }

  void _boot() {
    store.connect();
    store.refreshAll();
    store.onSessionsChanged = () {
      if (mounted) setState(() {});
    };
  }

  void _recheck() {
    setState(() {
      _configured = api.baseUrl.isNotEmpty && api.token.isNotEmpty;
      _reconfiguring = false;
      if (_configured) _boot();
    });
  }

  Future<void> _reconfigure() async {
    // 修复：旧版在此立即清空已保存的连接信息，若用户未完成新配置就退出，
    // App 变成空配置永远连不上。现改为：进入连接页时保留旧配置，
    // 只有新配置保存成功才覆盖（连接页提供「返回」放弃操作）。
    store.disposeBridge();
    setState(() => _reconfiguring = true);
  }

  void _openNewSession() {
    showNewSessionSheet(context, store, (id) async {
      // Phase 2(A4)：openChat 内统一 setSession+refreshSessionConfig+push，这里只刷列表
      store.refreshSessions();
      if (!mounted) return;
      await openChat(context, store, id);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_configured || _reconfiguring) {
      return Scaffold(
        body: ConnectionSheet(
          onConnected: _recheck,
          // 重新配置时允许放弃：保留旧配置返回主界面
          onCancel: _reconfiguring
              ? () => setState(() => _reconfiguring = false)
              : null,
        ),
      );
    }
    final titles = ['DSH', L10n.t('会话', 'Sessions'), L10n.t('设置', 'Settings')];
    final c = DshPalette.of(context);
    // 返回键：非首页 tab 按返回 → 先回首页；首页再按返回 → 退出 App
    return PopScope(
      canPop: _index == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _index != 0) {
          setState(() => _index = 0);
        }
      },
      child: Scaffold(
      key: _drawerKey,
      // 官方标题栏：52 高、无阴影、底部 0.5px 发丝线，标题 16/24·500
      appBar: AppBar(
        toolbarHeight: 52,
        backgroundColor: c.bg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        leadingWidth: 52,
        leading: DshIconButton(
          icon: Icons.menu,
          tooltip: L10n.t('菜单', 'Menu'),
          onTap: () => _drawerKey.currentState?.openDrawer(),
        ),
        // 去掉默认 16px 标题间距：状态点紧贴抽屉菜单按钮右侧
        titleSpacing: 0,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 电脑在线状态点：贴上抽屉图标；点按立即探测/重连，长按看状态文字
            Tooltip(
              message: switch (store.connState) {
                'connected' => L10n.t('电脑在线', 'PC online'),
                'connecting' => L10n.t('连接中…', 'Connecting…'),
                _ => L10n.t('电脑离线 · 点按重连', 'PC offline · tap to reconnect'),
              },
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () => store.resume(),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: DshSpace.xs,
                    vertical: DshSpace.sm,
                  ),
                  child: DshStatusDot(
                    color: switch (store.connState) {
                      'connected' => c.ok,
                      'connecting' => c.warn,
                      _ => c.ink3,
                    },
                    pulse: store.connState == 'connecting',
                  ),
                ),
              ),
            ),
            const SizedBox(width: DshSpace.sm),
            Text(
              titles[_index],
              style: DshType.m16.copyWith(color: c.ink),
            ),
          ],
        ),
        actions: [
          DshIconButton(
            icon: Icons.notifications_none,
            badge: store.unread,
            tooltip: L10n.t('通知', 'Notifications'),
            onTap: () => openNotificationsScreen(onOpenSession: () {
              // 通知页里打开会话后回到首页 tab（原抽屉入口行为）
              if (mounted) setState(() => _index = 0);
            }),
          ),
          const SizedBox(width: DshSpace.sm),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(DshStroke.hairline),
          child: Container(height: DshStroke.hairline, color: c.line2),
        ),
      ),
      // 官方侧栏：sidebar 底、无投影、右侧发丝线
      drawer: Drawer(
        backgroundColor: c.sidebar,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.zero,
          side: DshStroke.side(c.line2),
        ),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  DshSpace.xl,
                  DshSpace.xl,
                  DshSpace.xl,
                  DshSpace.md,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('DSH', style: DshType.xl24.copyWith(color: c.ink)),
                    const SizedBox(height: DshSpace.md),
                    DshButton(
                      label: L10n.t('＋ 新建会话', '+ New Session'),
                      variant: DshButtonVariant.primary,
                      size: DshButtonSize.lg,
                      expanded: true,
                      onPressed: () {
                        Navigator.of(context).pop();
                        _openNewSession();
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: DshSpace.xs),
              // 工作区快速切换（对齐 PC 端 workspace 切换；≥2 个工作区时显示）
              // 封顶 35% 屏高 + 可滚动：工作区再多也不会把下方导航挤出屏幕
              if (store.workspaces.length >= 2) ...[
                DshSectionHeader(
                  L10n.t('工作区', 'Workspaces'),
                  padding: const EdgeInsets.fromLTRB(
                    DshSpace.md,
                    DshSpace.sm,
                    DshSpace.md,
                    DshSpace.xs,
                  ),
                ),
                ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.35),
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      _workspaceItem(null),
                      for (final w in store.workspaces) _workspaceItem(w),
                    ],
                  ),
                ),
                const SizedBox(height: DshSpace.sm),
              ],
              _drawerItem(Icons.home_outlined, L10n.t('首页', 'Home'), 0),
              _drawerItem(Icons.history, L10n.t('会话', 'Sessions'), 1),
              _drawerItem(Icons.settings_outlined, L10n.t('设置', 'Settings'), 2),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.all(DshSpace.lg),
                child: Text(
                  L10n.t('本机直连 · DeepSeek Harness', 'Direct connection · DeepSeek Harness'),
                  style: DshType.xxs12.copyWith(color: c.caption),
                ),
              ),
            ],
          ),
        ),
      ),
      body: IndexedStack(
        index: _index,
        children: [
          HomeScreen(store: store, onOpenSession: () {
            if (mounted) setState(() {});
          }),
          SessionsScreen(store: store, onOpenSession: () {
            if (mounted) setState(() {});
          }),
          SettingsScreen(store: store, onReconfigure: _reconfigure),
        ],
      ),
      ),
    );
  }

  /// 侧栏导航项：R12 整行、选中底 navActive、图标 20px ink2、文字 14（选中加粗+ink）。
  Widget _drawerItem(IconData icon, String label, int index) {
    final c = DshPalette.of(context);
    final selected = _index == index;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: DshSpace.sm,
        vertical: DshSpace.xxs,
      ),
      child: Material(
        color: selected ? c.navActive : Colors.transparent,
        borderRadius: DshRadius.rMd,
        child: InkWell(
          borderRadius: DshRadius.rMd,
          splashFactory: NoSplash.splashFactory,
          highlightColor: c.hover,
          hoverColor: c.navHover,
          onTap: () {
            setState(() => _index = index);
            Navigator.of(context).pop();
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: DshSpace.md,
              vertical: DshSpace.sm,
            ),
            child: Row(
              children: [
                Icon(icon, size: 20, color: c.ink2),
                const SizedBox(width: DshSpace.md),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: (selected ? DshType.sStrong14 : DshType.s14)
                        .copyWith(color: c.ink),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 工作区切换项（null = 全部工作区）：侧栏行的紧凑变体，副标题是工作区路径。
  Widget _workspaceItem(Map<String, dynamic>? w) {
    final c = DshPalette.of(context);
    final isAll = w == null;
    final path = w?['path'] as String? ?? '';
    final title = isAll ? L10n.t('全部工作区', 'All Workspaces') : ((w['title'] as String?) ?? path);
    // v3.1.1(issue #5)：原始路径做展示，规范化后与 workspacePath（归一存储）匹配
    final selected = isAll ? store.workspacePath == null : store.workspacePath == AppStore.normPath(path);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: DshSpace.sm,
        vertical: DshSpace.xxs,
      ),
      child: Material(
        color: selected ? c.navActive : Colors.transparent,
        borderRadius: DshRadius.rMd,
        child: InkWell(
          borderRadius: DshRadius.rMd,
          splashFactory: NoSplash.splashFactory,
          highlightColor: c.hover,
          hoverColor: c.navHover,
          onTap: () {
            store.setWorkspace(isAll ? null : path);
            Navigator.of(context).pop();
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: DshSpace.md,
              vertical: DshSpace.sm,
            ),
            child: Row(
              children: [
                Icon(
                  isAll ? Icons.folder_open_outlined : Icons.folder_outlined,
                  size: 20,
                  color: c.ink2,
                ),
                const SizedBox(width: DshSpace.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: (selected ? DshType.sStrong14 : DshType.s14)
                              .copyWith(color: c.ink)),
                      if (!isAll)
                        Text(path,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: DshType.xs13.copyWith(color: c.ink3)),
                    ],
                  ),
                ),
                if (selected) Icon(Icons.check, size: 18, color: c.ink3),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 连接设置（首次进入/重新配置时显示）
class ConnectionSheet extends StatefulWidget {
  final VoidCallback onConnected;
  /// 非空时显示「返回」按钮：放弃重新配置、保留旧配置返回主界面。
  final VoidCallback? onCancel;
  const ConnectionSheet({super.key, required this.onConnected, this.onCancel});

  @override
  State<ConnectionSheet> createState() => _ConnectionSheetState();
}

class _ConnectionSheetState extends State<ConnectionSheet> {
  final _baseCtrl = TextEditingController();
  final _tokenCtrl = TextEditingController();
  String _status = '';
  bool _busy = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    if (api.baseUrl.isNotEmpty) _baseCtrl.text = api.baseUrl;
    if (api.token.isNotEmpty) _tokenCtrl.text = api.token;
  }

  /// 首连失败提示：iOS 首次连接最大的坑是「本地网络」权限（Android 无此概念）。
  /// 只有 iOS 的网络类错误才给本地网络归因；其它错误给通用检查建议（cross-review C1）。
  String _connectFailureHint(Object error) {
    if (DshPlatform.isIOS) {
      final networkError = error is SocketException ||
          error is HttpException ||
          error is TimeoutException;
      if (networkError) {
        return L10n.t(
          '\n若系统询问「查找并连接本地网络上的设备」请选择「允许」；若已拒绝，请到 '
          '设置 → 隐私与安全性 → 本地网络 打开 DSH Remote，然后点「重试」。',
          '\nIf iOS asks for local network access, allow it. If you denied it, open '
          'Settings → Privacy & Security → Local Network and enable DSH Remote, then tap Retry.',
        );
      }
      return L10n.t(
        '\n请检查地址与访问口令；若系统询问本地网络权限请选择「允许」。',
        '\nCheck the address and token; allow local network access if iOS asks.',
      );
    }
    // Android 原文案保持不变（MiUI 智能网络/蜂窝分流表现为超时或 404）。
    return L10n.t(
      '；请确认手机与电脑在同一 Wi-Fi，并关闭手机流量/智能网络后重试',
      '; make sure the phone is on the same Wi-Fi as the PC, and turn off mobile data / smart network switch',
    );
  }

  /// 首次连接。iOS 网络类失败会自动重试一次（1.5s）：首次局域网访问时系统弹窗
  /// 「未决」阶段可能先失败一次，允许后重试即可成功；仍失败则展示本地网络引导 + 重试按钮。
  Future<void> _connect() async {
    var base = _baseCtrl.text.trim();
    if (!base.startsWith('http')) base = 'http://$base';
    base = base.replaceAll(RegExp(r'/+$'), '');
    if (base.endsWith('/m')) base = base.substring(0, base.length - 2);
    setState(() {
      _busy = true;
      _failed = false;
      _status = L10n.t('连接中…', 'Connecting…');
    });
    Object? lastError;
    for (var attempt = 1; attempt <= 2; attempt++) {
      try {
        // v3.0.0：探测客户端与 save() 同源的地址/路径规范化（防 /m 重复拼接 404）
        final probe = Api.forProbe(base, _tokenCtrl.text.trim());
        await probe.getJson('/api/bootstrap');
        await api.save(base: base, token: _tokenCtrl.text.trim());
        if (!mounted) return;
        setState(() {
          _status = L10n.t('✅ 已连接', '✅ Connected');
          _busy = false;
          _failed = false;
        });
        widget.onConnected();
        return;
      } catch (e) {
        lastError = e;
        final retryable = DshPlatform.isIOS &&
            attempt == 1 &&
            (e is SocketException || e is HttpException || e is TimeoutException);
        if (!retryable) break;
        if (!mounted) return;
        setState(() => _status = L10n.t(
            '连接失败，正在自动重试…（请允许本地网络访问）',
            'Connection failed, retrying… (please allow local network access)'));
        await Future<void>.delayed(const Duration(milliseconds: 1500));
        if (!mounted) return;
      }
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _failed = true;
      _status =
          '${L10n.t('连接失败：', 'Connection failed:')}$lastError${_connectFailureHint(lastError!)}';
    });
  }

  Future<void> _onScanned(String base, String token) async {
    _baseCtrl.text = base;
    _tokenCtrl.text = token;
    if (mounted) Navigator.of(context).pop();
    await _connect();
  }

  Future<void> _scan() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ScanScreen(onScanned: _onScanned)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = DshPalette.of(context);
    return SafeArea(
      child: Column(
        children: [
          // 返回按钮固定在左上角（重新配置时可见，放弃保留原配置）
          if (widget.onCancel != null)
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(left: DshSpace.sm, top: DshSpace.sm),
                child: DshIconButton(
                  icon: Icons.arrow_back,
                  onTap: widget.onCancel,
                  tooltip: L10n.t('返回（保留原配置）', 'Back (keep current settings)'),
                ),
              ),
            ),
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                // 键盘弹出/小屏时表单可滚动，避免连接页溢出
                padding: const EdgeInsets.all(DshSpace.xl),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
            Text('DSH Remote',
                textAlign: TextAlign.center,
                style: DshType.xl24.copyWith(color: c.ink)),
            const SizedBox(height: DshSpace.sm),
            Text(L10n.t('手机远程操作 DeepSeek Harness', 'Control DeepSeek Harness from your phone'), textAlign: TextAlign.center, style: DshType.xs13.copyWith(color: c.ink3)),
            const SizedBox(height: DshSpace.xxl),
            DshButton(
              label: L10n.t('扫码连接', 'Scan to Connect'),
              icon: Icons.qr_code_scanner,
              variant: DshButtonVariant.primary,
              size: DshButtonSize.lg,
              expanded: true,
              onPressed: _busy ? null : _scan,
            ),
            const SizedBox(height: DshSpace.lg),
            Row(
              children: [
                const Expanded(child: DshDivider()),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: DshSpace.md),
                  child: Text(L10n.t('或手动输入', 'Or enter manually'), style: DshType.xxs12.copyWith(color: c.ink3)),
                ),
                const Expanded(child: DshDivider()),
              ],
            ),
            const SizedBox(height: DshSpace.lg),
            TextField(
              controller: _baseCtrl,
              keyboardType: TextInputType.url,
              decoration: InputDecoration(
                labelText: L10n.t('电脑地址', 'Computer Address'),
                hintText: 'http://192.168.x.x:3080',
              ),
            ),
            const SizedBox(height: DshSpace.md),
            TextField(
              controller: _tokenCtrl,
              obscureText: true,
              decoration: InputDecoration(
                labelText: L10n.t('访问口令', 'Token'),
              ),
            ),
            const SizedBox(height: DshSpace.xl),
            DshButton(
              label: _busy ? L10n.t('连接中…', 'Connecting…') : L10n.t('连接', 'Connect'),
              variant: DshButtonVariant.primary,
              size: DshButtonSize.lg,
              expanded: true,
              onPressed: _busy ? null : _connect,
            ),
            const SizedBox(height: DshSpace.md),
            Text(_status, textAlign: TextAlign.center, style: DshType.xs13.copyWith(color: c.ink2)),
            // C1：失败后给显式「重试」按钮（iOS 本地网络权限放行后无需重填表单）。
            if (_failed) ...[
              const SizedBox(height: DshSpace.md),
              DshButton(
                label: L10n.t('重试', 'Retry'),
                icon: Icons.refresh,
                variant: DshButtonVariant.outline,
                size: DshButtonSize.lg,
                expanded: true,
                onPressed: _busy ? null : _connect,
              ),
            ],
          ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 全局 build 异常兜底界面：bg 底 + ink 文字（无 Theme 祖先时按亮色令牌渲染）。
class _ErrorFallback extends StatelessWidget {
  const _ErrorFallback(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    final c = DshPalette.of(context);
    return ColoredBox(
      color: c.bg,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(DshSpace.xxl),
          child: SelectableText(
            '${L10n.t('界面异常：', 'UI error:')}\n$message',
            style: DshType.s14.copyWith(color: c.ink),
          ),
        ),
      ),
    );
  }
}
