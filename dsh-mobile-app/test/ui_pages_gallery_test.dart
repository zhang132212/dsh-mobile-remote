// 页面级 golden 走查：把重构后的四个页面（首页 / 会话 / 通知 / 设置）渲染成 PNG，
// 用于在没有真机/模拟器时核对官方 DSH 版式（每个页面浅色 + 深色各一张）。
//
// 生成/更新：flutter test --update-goldens test/ui_pages_gallery_test.dart
// 产物：test/goldens/page_<页面>_<light|dark>.png
//
// 三条约定（与 test/ui_gallery_test.dart 同源）：
// 1) 测试环境默认字体把字形画成方块 → 显式注册系统中文字体（等线 Deng）；
// 2) 不用 pumpAndSettle（页面里有无限动画：状态点脉冲 / 加载环）→ 固定 pump(Duration)；
// 3) 数据走假后端，页面跑真实数据通路。这四个页面读的是全局 `api` 单例
//    （不像 ChatScreen 有 apiClient 注入口，且 api 是 final 顶层变量），
//    所以用 http 的 runWithClient 让这个懒初始化单例在"注入客户端"的 zone 里构造。
import 'dart:convert';
import 'dart:io';

import 'package:dsh_mobile_app/api.dart';
import 'package:dsh_mobile_app/models.dart';
import 'package:dsh_mobile_app/screens/home_screen.dart';
import 'package:dsh_mobile_app/screens/notifications_screen.dart';
import 'package:dsh_mobile_app/screens/sessions_screen.dart';
import 'package:dsh_mobile_app/screens/settings_screen.dart';
import 'package:dsh_mobile_app/store.dart';
import 'package:dsh_mobile_app/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 手机画布（逻辑像素；沿用 ui_gallery_test 的默认 DPR，不额外缩放）。
const Size _phone = Size(390, 844);

/// 会话的"最近活跃"用相对当前时刻的固定偏移：
/// relTime 永远渲染成「4 分钟前 / 3 小时前 / 2 天前」，golden 不随运行日期漂移。
int _ago({int minutes = 0, int hours = 0, int days = 0}) => DateTime.now()
    .subtract(Duration(minutes: minutes, hours: hours, days: days))
    .millisecondsSinceEpoch;

/// 通知行显示的是绝对时间（MM-DD HH:mm）→ 用固定时刻才不随运行日期漂移。
final int _notifTime = DateTime(2025, 10, 9, 14, 32).millisecondsSinceEpoch;

// ── 假数据 ────────────────────────────────────────────────────────────────

/// 三条活跃会话 + 一条已归档（归档数决定分段控件右侧计数）。
List<Map<String, dynamic>> _sessionFixtures() => [
  {
    'id': 's-login',
    'title': '修复登录跳转丢失 query',
    'cwd': r'D:\work\dsh-web',
    'createdAt': _ago(days: 2),
    'lastActivity': _ago(minutes: 4),
    'archived': false,
  },
  {
    'id': 's-timeline',
    'title': '时间线工具卡折叠与详情',
    'cwd': r'D:\work\dsh-web',
    'createdAt': _ago(days: 3),
    'lastActivity': _ago(hours: 3),
    'archived': false,
  },
  {
    'id': 's-badge',
    'title': '通知角标未读数不刷新',
    'cwd': r'D:\work\dsh-mobile',
    'createdAt': _ago(days: 5),
    'lastActivity': _ago(days: 2),
    'archived': false,
  },
  {
    'id': 's-old',
    'title': '旧版配色重构',
    'cwd': r'D:\work\dsh-mobile',
    'createdAt': _ago(days: 20),
    'lastActivity': _ago(days: 9),
    'archived': true,
  },
];

/// 两个工作区 → 会话页显示工作区筛选胶囊、首页行显示工作区小字标注。
List<Map<String, dynamic>> _workspaceFixtures() => [
  {
    'id': 'w-web',
    'path': r'D:\work\dsh-web',
    'title': 'dsh-web',
    'sessionIds': ['s-login', 's-timeline'],
  },
  {
    'id': 'w-mobile',
    'path': r'D:\work\dsh-mobile',
    'title': 'dsh-mobile',
    'sessionIds': ['s-badge', 's-old'],
  },
];

/// 三条通知：完成（未读）/ 失败（未读）/ 待确认（已读，且没有详情行）。
List<Map<String, dynamic>> _notifFixtures() => [
  {
    'id': 'n-1',
    'kind': 'completed',
    'sessionId': 's-login',
    'title': '会话已完成：修复登录跳转丢失 query',
    'detail': '改动 3 个文件，测试通过。',
    'time': _notifTime,
    'unread': true,
  },
  {
    'id': 'n-2',
    'kind': 'failed',
    'sessionId': 's-timeline',
    'title': '工具执行失败：shell',
    'detail': '命令返回非 0：dart analyze 仍有 2 处 error。',
    'time': _notifTime - 26 * 60 * 1000,
    'unread': true,
  },
  {
    'id': 'n-3',
    'kind': 'question',
    'sessionId': 's-badge',
    'title': '需要你确认：是否归档旧会话？',
    'detail': '',
    'time': _notifTime - 3 * 60 * 60 * 1000,
    'unread': false,
  },
];

/// 模型目录：给设置页的「默认权限预设 / 默认 Agent 预设」真实取值。
Map<String, dynamic> _catalogJson() => {
  'defaults': {'permissionPreset': 'workspace-write', 'agentPreset': 'code'},
  'rechargeUrl': 'https://platform.deepseek.com/top_up',
  'models': <Object>[],
  'reasoningEfforts': ['low', 'medium', 'high'],
  'agentPresets': [
    {'id': 'standard', 'name': '标准', 'description': '通用对话'},
    {'id': 'code', 'name': 'PTC', 'description': '编码模式'},
  ],
  'permissionPresets': [
    {
      'id': 'workspace-write',
      'name': 'Workspace Write',
      'description': '可写工作区',
    },
  ],
  'providers': <Object>[],
};

/// 假后端：只实现这四个页面真正会打的端点，其余一律 {ok:true}。
Future<http.Response> _handle(http.Request request) async {
  final path = request.url.path;
  final Map<String, dynamic> body;
  if (path.endsWith('/api/sessions')) {
    body = {'ok': true, 'sessions': _sessionFixtures()};
  } else if (path.endsWith('/api/notifications')) {
    body = {'ok': true, 'items': _notifFixtures()};
  } else if (path.endsWith('/api/workspaces')) {
    body = {'ok': true, 'workspaces': _workspaceFixtures()};
  } else if (path.endsWith('/api/catalog')) {
    body = {'ok': true, ..._catalogJson()};
  } else if (path.endsWith('/api/account-usage')) {
    body = {
      'ok': true,
      'fetchedAt': '2025-10-09T14:30:00.000Z',
      'failedCount': 0,
      'sources': [
        {
          'id': 'deepseek',
          'title': 'DeepSeek',
          'kind': 'balance',
          'amount': '86.40',
          'currency': 'CNY',
          'available': true,
          'windows': <Object>[],
        },
      ],
    };
  } else {
    body = {'ok': true};
  }
  return http.Response(
    jsonEncode(body),
    200,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );
}

/// 页面共用的 store：连接正常 + 工作区 + 模型目录 + 未读计数 + 会话列表。
/// （会话同时由假后端返回，SessionsScreen 首屏刷新后内容一致。）
AppStore _fixtureStore() => AppStore()
  ..connState = 'connected'
  ..unread = 2
  ..workspaces = _workspaceFixtures()
  ..catalog = Catalog.fromJson(_catalogJson())
  ..sessions = _sessionFixtures().map(Session.fromJson).toList();

// ── 渲染 ──────────────────────────────────────────────────────────────────

/// 定位 Flutter SDK 里的 MaterialIcons 字体文件（多机器可移植）。
String _materialIconsFontPath() {
  final sep = Platform.pathSeparator;
  const tail = ['bin', 'cache', 'artifacts', 'material_fonts', 'materialicons-regular.otf'];

  String? fromExecutable() {
    try {
      var dir = File(Platform.resolvedExecutable).parent; // dart-sdk/bin
      for (var i = 0; i < 4; i++) {
        dir = dir.parent;
      }
      return dir.path; // flutter root
    } catch (_) {
      return null;
    }
  }

  final roots = <String>[
    if ((Platform.environment['FLUTTER_ROOT'] ?? '').isNotEmpty)
      Platform.environment['FLUTTER_ROOT']!,
    if (fromExecutable() != null) fromExecutable()!,
    r'F:\dsh-build-kit\flutter',
    r'C:\dsh-build-kit\flutter',
  ];
  for (final root in roots) {
    final candidate = <String>[root, ...tail].join(sep);
    if (File(candidate).existsSync()) return candidate;
  }
  return <String>[roots.last, ...tail].join(sep);
}

/// 把字体文件注册到若干族名下（测试环境没有系统字体回退）。
Future<void> _registerFont(String path, List<String> families) async {
  final bytes = File(path).readAsBytesSync();
  for (final family in families) {
    final loader = FontLoader(family)
      ..addFont(Future<ByteData>.value(ByteData.view(bytes.buffer)));
    await loader.load();
  }
}

/// 挂载页面并出图。
///
/// [wrapInScaffold]：首页/会话/设置是 RootScreen 的 body（自身不带 Scaffold 与标题栏，
/// 标题栏在 main.dart 的 RootScreen 里）；通知页自带 Scaffold + DshAppBar。
Future<void> _shoot(
  WidgetTester tester, {
  required Widget Function(AppStore store) page,
  required bool dark,
  required String file,
  bool wrapInScaffold = true,
}) async {
  await tester.binding.setSurfaceSize(_phone);
  final store = _fixtureStore();
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: _theme(dark),
      home: wrapInScaffold ? Scaffold(body: page(store)) : page(store),
    ),
  );
  // 假后端立即返回：推进固定帧数让首屏数据 setState 落地（不用 pumpAndSettle，有无限动画）
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 320));
  await tester.pump(const Duration(milliseconds: 320));
  // 让 Image.asset 真正从 bundle 解码（首页 logo），否则 golden 里是空框
  await tester.runAsync(() async {
    for (final element in find.byType(Image).evaluate()) {
      await precacheImage((element.widget as Image).image, element);
    }
  });
  await tester.pump(const Duration(milliseconds: 16));
  await expectLater(find.byType(MaterialApp), matchesGoldenFile(file));
}

/// 出图用的主题：官方主题 + 中文回退栈兜底。
///
/// 测试环境没有系统字体回退，而主题里少数"裸样式"（`appBarTheme.titleTextStyle`
/// 等）不带 fontFamilyFallback，会落到测试默认字体上画成「□□」。真机上这些字由
/// 系统字体兜底，所以这里补回退栈只影响 golden，不涉及生产代码。
ThemeData _theme(bool dark) {
  final t = dark ? DshTheme.dark() : DshTheme.light();
  final appBar = t.appBarTheme;
  return t.copyWith(
    textTheme: t.textTheme.apply(fontFamilyFallback: DshType.textFallback),
    appBarTheme: appBar.copyWith(
      titleTextStyle: appBar.titleTextStyle
          ?.copyWith(fontFamilyFallback: DshType.textFallback),
      toolbarTextStyle: appBar.toolbarTextStyle
          ?.copyWith(fontFamilyFallback: DshType.textFallback),
    ),
  );
}

void main() {
  setUpAll(() async {
    // 中文字体：官方回退栈里的族名 + 测试环境默认字体族名（'Ahem'/'FlutterTest'）。
    // 少数样式（如 appBarTheme.titleTextStyle）不带 fontFamilyFallback，会落到默认
    // 测试字体上画方块——把默认族名也指向中文字体，标题才不会变成「□□」。
    const families = <String>[
      'Roboto',
      'Microsoft YaHei',
      'PingFang SC',
      'Deng',
      'Ahem',
      'FlutterTest',
    ];
    await _registerFont(r'C:\Windows\Fonts\Deng.ttf', families);
    // 图标字体：测试环境默认不加载 MaterialIcons → 图标会画成空方块（版式走查必须能看见图标）。
    // 路径不能写死：不同机器的 build kit 位置不同（C:/F: 都见过），按 FLUTTER_ROOT +
    // 当前 dart 解释器位置反推，最后才回退到历史路径。
    await _registerFont(_materialIconsFontPath(), const ['MaterialIcons']);

    // 全局 api 是 final 顶层单例（懒初始化）：首次读取时确定 http.Client。
    // 在 runWithClient 的 zone 里做首次读取，之后就固定走 MockClient——
    // 这样不碰任何生产代码也能让页面跑真实数据通路。
    http.runWithClient(
      () => api
        ..baseUrl = 'http://golden.test'
        ..path = '/m'
        ..token = ''
        ..pluginVersion = '0.2.1',
      () => MockClient(_handle),
    );
  });

  setUp(() {
    // 页面初始化会摸平台通道：SharedPreferences（会话缓存）与悬浮球服务。
    SharedPreferences.setMockInitialValues(<String, Object>{});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('dsh/floating'),
      (call) async => switch (call.method) {
        'isRunning' => false,
        'canDrawOverlay' => false,
        _ => null,
      },
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('dsh/floating'), null);
  });

  for (final dark in <bool>[false, true]) {
    final tone = dark ? 'dark' : 'light';
    final label = dark ? '暗色' : '亮色';

    testWidgets('首页 · $label', (tester) async {
      await _shoot(
        tester,
        dark: dark,
        file: 'goldens/page_home_$tone.png',
        page: (store) => HomeScreen(store: store, onOpenSession: () {}),
      );
    });

    testWidgets('会话列表 · $label', (tester) async {
      await _shoot(
        tester,
        dark: dark,
        file: 'goldens/page_sessions_$tone.png',
        page: (store) => SessionsScreen(store: store, onOpenSession: () {}),
      );
    });

    testWidgets('通知中心 · $label', (tester) async {
      await _shoot(
        tester,
        dark: dark,
        file: 'goldens/page_notifications_$tone.png',
        wrapInScaffold: false,
        page: (store) =>
            NotificationsScreen(store: store, onOpenSession: () {}),
      );
    });

    testWidgets('设置 · $label', (tester) async {
      await _shoot(
        tester,
        dark: dark,
        file: 'goldens/page_settings_$tone.png',
        page: (store) =>
            SettingsScreen(store: store, onReconfigure: () async {}),
      );
    });
  }
}
