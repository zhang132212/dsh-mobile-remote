// iOS 模拟器端到端冒烟测试（T7，integration_test）。
//
// 运行方式（macOS CI / 本地有设备时）：
//   flutter test integration_test/app_smoke_test.dart -d <iOS Simulator 设备 id>
// 或整目录：flutter test integration_test -d <设备 id>
//
// 本机（Windows）无 iOS 模拟器，也没有 windows/ 桌面工程与 VS C++ 工具链，
// 因此本文件在本地只做 dart analyze 校验，真机形态执行交给 macOS CI。
//
// 设计（保证 iOS 模拟器上稳定、不依赖任何系统权限弹窗）：
//   1) 在测试进程内起一个最小 DSH 插件 mock 服务（127.0.0.1 随机端口）：
//      /m/api/bootstrap（握手探测）+ /m/api/events（SSE hello 帧）+ 其余接口一律 ok:true；
//   2) SharedPreferences 用内存 mock —— 每次从「未配置连接」的冷启动态开始，
//      不污染模拟器持久数据，也不会因为上一次跑过而跳过连接页；
//   3) 启动真实 App（app.main()）→ 断言连接/配置页渲染 → 填入 mock 地址连上
//      → 断言主界面（抽屉按钮出现）→ 抽屉进设置页无异常；
//   4) iOS 上额外断言 T3 的两条显式降级文案（悬浮球/Bark、更新/App Store）确实渲染出来。
//   不碰相机/相册/推送/通知权限，全部是最小 UI + 本机回环网络。
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dsh_mobile_app/floating.dart';
import 'package:dsh_mobile_app/main.dart' as app;
import 'package:dsh_mobile_app/screens/settings_screen.dart';
import 'package:dsh_mobile_app/update/updater.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late _MockDshServer server;

  setUp(() async {
    // 内存 prefs：保证 App 每次都以「未配置连接」的冷启动态启动（连接页必现），
    // 且不会把测试写入的地址持久化到模拟器上影响后续运行。
    SharedPreferences.setMockInitialValues(<String, Object>{});
    server = await _MockDshServer.start();
  });

  tearDown(() async {
    await server.close();
  });

  testWidgets('冷启动 → 连接页 → 连上本地 mock 服务 → 主界面 → 设置页', (tester) async {
    // flutter_test 在测试结束时会校验「测试没有改动全局 ErrorWidget.builder」；
    // 而 app.main() 会安装全局错误兜底界面 —— 先存档、测试结束前恢复（否则 CI 必红）。
    final errorWidgetBuilderBeforeTest = ErrorWidget.builder;

    // ── 1) 启动真实 App，断言连接/配置页渲染 ──
    // app.main() 返回 void（内部 runApp 后即返回），后续用 _pumpUntil 等首帧。
    app.main();
    await _pumpUntil(tester, find.text('DSH Remote'), reason: '连接页出现');
    expect(find.text('扫码连接'), findsOneWidget);
    expect(find.text('电脑地址'), findsOneWidget);
    expect(find.text('访问口令'), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(2));
    expect(tester.takeException(), isNull);

    // ── 2) 填入 mock 服务地址 + token，点「连接」──
    await tester.enterText(find.byType(TextField).at(0), server.baseUrl);
    await tester.enterText(find.byType(TextField).at(1), 'smoke-token');
    await tester.ensureVisible(find.text('连接'));
    await tester.tap(find.text('连接'));

    // ── 3) 配置成功 → RootScreen 主界面（AppBar 左侧抽屉按钮）──
    await _pumpUntil(tester, find.byIcon(Icons.menu), reason: '主界面（连接成功）');
    expect(find.text('DSH'), findsWidgets);
    expect(tester.takeException(), isNull);

    // ── 4) 抽屉 → 设置页，断言顶部卡片渲染、无异常 ──
    await tester.tap(find.byIcon(Icons.menu));
    await _pumpUntil(tester, find.text('设置'), reason: '抽屉「设置」入口');
    await tester.tap(find.text('设置').last);
    await _pumpUntil(tester, find.text('重新配置连接'), reason: '设置页渲染');
    expect(find.text('电脑地址'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // ── 5) iOS 专属：T3 的两条显式降级说明必须真实渲染（列表懒加载，滚动到可见）──
    if (Platform.isIOS) {
      final settingsScrollable = find
          .descendant(of: find.byType(SettingsScreen), matching: find.byType(Scrollable))
          .first;
      final bubbleHint = find.text(Floating.unsupportedHint);
      await tester.scrollUntilVisible(bubbleHint, 300, scrollable: settingsScrollable);
      expect(bubbleHint, findsOneWidget);

      final updateHint = find.text(UpdateSupport.unsupportedMessage);
      await tester.scrollUntilVisible(updateHint, 300, scrollable: settingsScrollable);
      expect(updateHint, findsOneWidget);
      expect(tester.takeException(), isNull);
    }

    // 收尾：停掉 SSE/重连定时器，避免测试清理阶段继续打 mock 服务；
    // 再恢复 main() 改写的全局错误兜底（见测试开头说明）。
    app.store.disposeBridge();
    ErrorWidget.builder = errorWidgetBuilderBeforeTest;
  });
}

/// 轮询 pump 直到 [finder] 命中（真实网络/异步初始化需要真实时间流逝）。
///
/// 不用 pumpAndSettle：App 里有常驻动画（状态点脉冲、连接中环），settle 会一直等。
Future<void> _pumpUntil(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 30),
  String? reason,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 50));
    if (finder.evaluate().isNotEmpty) return;
    // 让出真实事件循环：HTTP/SSE 响应、插件回调都靠它推进。
    await Future<void>.delayed(const Duration(milliseconds: 25));
  }
  final tail = reason == null ? '' : '（$reason）';
  fail('等待超时$tail：$finder');
}

/// 最小 DSH 插件 mock 服务（只满足 App 启动/连接/渲染所需的最小契约）。
///
/// 真实插件接口形如 /m/api/...；App 连接前会用 /m/api/bootstrap 探测，
/// 连上后建 /m/api/events SSE 长连接并拉 sessions/catalog 等数据。
class _MockDshServer {
  _MockDshServer._(this._server, this.baseUrl);

  final HttpServer _server;
  final String baseUrl;
  final List<HttpResponse> _sseResponses = [];
  Timer? _pingTimer;

  static Future<_MockDshServer> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final port = server.port;
    final mock = _MockDshServer._(server, 'http://127.0.0.1:$port');
    server.listen((req) {
      // 单请求异常不能把整个测试进程打挂（客户端提前断开很常见）。
      unawaited(mock._handle(req).catchError((_) {}));
    });
    return mock;
  }

  Future<void> _handle(HttpRequest req) async {
    final path = req.uri.path;
    if (path.endsWith('/api/events')) {
      await _handleSse(req);
      return;
    }
    final body = jsonEncode(_jsonForPath(path));
    req.response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = ContentType.json
      ..write(body);
    await req.response.close();
  }

  /// SSE 长连接：先推一条 hello 帧（App 收到后置 connected），之后周期性 ping 保活。
  Future<void> _handleSse(HttpRequest req) async {
    req.response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = ContentType('text', 'event-stream', charset: 'utf-8')
      ..headers.set('cache-control', 'no-cache')
      ..bufferOutput = false;
    _sseResponses.add(req.response);
    req.response.write(_helloEvent);
    await req.response.flush();
    _pingTimer ??= Timer.periodic(const Duration(seconds: 3), (_) {
      for (final res in _sseResponses) {
        try {
          res.write(': ping\n\n');
          unawaited(res.flush());
        } catch (_) {
          // 已关闭的连接忽略
        }
      }
    });
    // 不 close：保持长连接，测试结束由 close() 兜底。
  }

  /// 最小接口契约（足够字段让 App 不抛解析异常；列表类返回空数组）。
  Map<String, dynamic> _jsonForPath(String path) {
    if (path.endsWith('/api/bootstrap')) {
      return {
        'ok': true,
        'server': {'urls': <String>[], 'path': '/m'},
        'plugin': {'version': '0.2.1'},
        'capabilities': <String, Object>{},
        'agents': <Object>[],
      };
    }
    if (path.endsWith('/api/sessions')) return {'ok': true, 'sessions': <Object>[]};
    if (path.endsWith('/api/notifications')) return {'ok': true, 'items': <Object>[]};
    if (path.endsWith('/api/workspaces')) return {'ok': true, 'workspaces': <Object>[]};
    if (path.endsWith('/api/actions')) return {'ok': true, 'actions': <Object>[]};
    if (path.endsWith('/api/catalog')) {
      return {
        'ok': true,
        'defaults': <String, Object>{},
        'models': <Object>[],
        'providers': <Object>[],
        'agentPresets': <Object>[],
        'permissionPresets': <Object>[],
      };
    }
    return {'ok': true};
  }

  Future<void> close() async {
    _pingTimer?.cancel();
    _pingTimer = null;
    for (final res in _sseResponses) {
      try {
        await res.close();
      } catch (_) {}
    }
    _sseResponses.clear();
    await _server.close(force: true);
  }

  static const String _helloEvent = 'data: {"type":"hello","capabilities":{}}\n\n';
}
