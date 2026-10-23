// iOS 平台适配回归测试（T3）。
//
// 背景：Flutter 的 `Platform` 来自 dart:io，是编译期判定、单测无法 mock。
// 生产代码把平台能力集中在 lib/platform_support.dart 的 [DshPlatform]，
// 并提供 @visibleForTesting 的 override；本文件用它在 Windows/macOS 测试机上
// 覆盖 iOS 分支，钉住以下契约：
//   · floating：iOS 下查询返回安全值、动作 no-op，绝不抛 MissingPluginException；
//   · files：FileBridge 成功文案按平台区分；通道缺失/平台异常都转成用户可读提示；
//   · update：iOS 下 check 直接抛 UpdateUnsupportedException（不发网络请求）、
//     install 返回 unsupportedPlatform；
//   · 设置页：iOS 下悬浮球开关消失并显示 Bark 说明；「检查更新」按钮消失并显示
//     TestFlight/App Store 说明。
//
// 注意：所有断言都建立在 override 之上，非 iOS 默认行为另有测试兜底，
// 因此 Windows 上既有 golden / widget 测试的渲染结果不受影响（iOS 门控不生效）。
import 'dart:io';

import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dsh_mobile_app/dsh_kit.dart';
import 'package:dsh_mobile_app/floating.dart';
import 'package:dsh_mobile_app/l10n.dart';
import 'package:dsh_mobile_app/main.dart' show ConnectionSheet;
import 'package:dsh_mobile_app/platform_support.dart';
import 'package:dsh_mobile_app/screens/settings_screen.dart';
import 'package:dsh_mobile_app/store.dart';
import 'package:dsh_mobile_app/theme.dart';
import 'package:dsh_mobile_app/update/installer.dart';
import 'package:dsh_mobile_app/update/updater.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    DshPlatform.debugOverrideIsIOS = null;
    L10n.lang = 'zh';
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(FileBridge.channel, null);
  });

  group('DshPlatform · 平台判定', () {
    test('默认跟随 dart:io Platform（测试机为桌面端，非 iOS）', () {
      DshPlatform.debugOverrideIsIOS = null;
      expect(DshPlatform.isIOS, Platform.isIOS);
      if (!Platform.isIOS) {
        expect(DshPlatform.supportsSystemFloatingBubble, isTrue);
        expect(DshPlatform.supportsInAppApkUpdate, isTrue);
      }
    });

    test('override 后可模拟 iOS（且只影响判定，不污染真实 Platform）', () {
      DshPlatform.debugOverrideIsIOS = true;
      expect(DshPlatform.isIOS, isTrue);
      expect(DshPlatform.supportsSystemFloatingBubble, isFalse);
      expect(DshPlatform.supportsInAppApkUpdate, isFalse);
    });
  });

  group('Floating · iOS 安全降级', () {
    setUp(() => DshPlatform.debugOverrideIsIOS = true);

    test('isSupported=false，降级说明提到 Bark 推送', () {
      expect(Floating.isSupported, isFalse);
      expect(Floating.unsupportedHint, contains('Bark'));
      expect(Floating.unsupportedHint, contains('iOS'));
    });

    test('查询类返回安全值（未注册通道也不会 MissingPluginException）', () async {
      // 测试环境没有 dsh/floating 通道：若实现触碰通道会抛异常 → 正好验证守卫。
      expect(await Floating.isRunning(), isFalse);
      expect(await Floating.canDrawOverlay(), isFalse);
      expect(await Floating.consumeOpenPanel(), isNull);
    });

    test('动作类全部 no-op 且不抛异常', () async {
      await expectLater(Floating.start(), completes);
      await expectLater(Floating.stop(), completes);
      await expectLater(Floating.openOverlaySettings(), completes);
      await expectLater(Floating.notifyBalance(12.34), completes);
      await expectLater(Floating.setBalanceAlert(true, 10.0), completes);
    });

    test('非 iOS 平台保持支持（Windows 上设置页仍显示开关）', () {
      DshPlatform.debugOverrideIsIOS = null;
      if (!Platform.isIOS) {
        expect(Floating.isSupported, isTrue);
      }
    });
  });

  group('FileBridge · 文件通道降级', () {
    test('iOS 保存文案：只有一层「已保存到 App 文稿：」前缀（T2 返回 DSH-Remote/<name>）', () {
      DshPlatform.debugOverrideIsIOS = true;
      // T2 契约（2026-10-23 更新）：原生返回「DSH-Remote/<name>」这种相对 App 文稿的短串，
      // Dart 侧只拼一次前缀，避免出现「App 文稿/App 文稿/...」重复。
      final msg = FileBridge.savedMessage('DSH-Remote/报告.docx');
      expect(msg, startsWith('已保存到 App 文稿：DSH-Remote/报告.docx'));
      expect(msg, contains('文件'));
      expect('App 文稿'.allMatches(msg).length, 1);
    });

    test('iOS 保存文案：原生未返回位置时也给完整说明', () {
      DshPlatform.debugOverrideIsIOS = true;
      final msg = FileBridge.savedMessage(null);
      expect(msg, startsWith('已保存到 App 文稿'));
      expect(msg, contains('文件'));
    });

    test('非 iOS 保存文案保持「已保存到手机」', () {
      DshPlatform.debugOverrideIsIOS = null;
      if (!Platform.isIOS) {
        final msg = FileBridge.savedMessage('Download/DSH-Remote/a.md');
        expect(msg, startsWith('已保存到手机'));
      }
    });

    test('saveToDownloads 成功返回原生位置串（默认不弹分享）', () async {
      DshPlatform.debugOverrideIsIOS = true;
      Map<Object?, Object?>? captured;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(FileBridge.channel, (call) async {
        if (call.method != 'saveToDownloads') return null;
        captured = call.arguments as Map<Object?, Object?>;
        expect(captured?['name'], 'a.md');
        expect(captured?['bytes'], isA<Uint8List>());
        return 'DSH-Remote/a.md';
      });
      final where = await FileBridge.saveToDownloads(
        name: 'a.md',
        bytes: Uint8List.fromList([1, 2, 3]),
      );
      expect(where, 'DSH-Remote/a.md');
      expect(FileBridge.savedMessage(where), startsWith('已保存到 App 文稿：DSH-Remote/a.md'));
      expect(captured?.containsKey('share'), isFalse); // 默认静默保存
    });

    test('iOS 用户主动保存 share=true → 透传给原生（弹系统分享面板）', () async {
      DshPlatform.debugOverrideIsIOS = true;
      Map<Object?, Object?>? captured;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(FileBridge.channel, (call) async {
        if (call.method != 'saveToDownloads') return null;
        captured = call.arguments as Map<Object?, Object?>;
        return 'DSH-Remote/a.docx';
      });
      await FileBridge.saveToDownloads(
        name: 'a.docx',
        bytes: Uint8List.fromList([1]),
        share: true,
      );
      expect(captured?['share'], isTrue);
    });

    test('非 iOS 不透传 share（Android 通道参数保持原样）', () async {
      DshPlatform.debugOverrideIsIOS = null;
      if (Platform.isIOS) return;
      Map<Object?, Object?>? captured;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(FileBridge.channel, (call) async {
        if (call.method != 'saveToDownloads') return null;
        captured = call.arguments as Map<Object?, Object?>;
        return 'Download/DSH-Remote/a.docx';
      });
      await FileBridge.saveToDownloads(
        name: 'a.docx',
        bytes: Uint8List.fromList([1]),
        share: true,
      );
      expect(captured?.containsKey('share'), isFalse);
    });

    test('pickFile 解码 name/bytes，用户取消返回 null', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(FileBridge.channel, (call) async {
        if (call.method != 'pickFile') return null;
        return <String, dynamic>{
          'name': 'x.bin',
          'bytes': Uint8List.fromList([9, 8, 7]),
        };
      });
      final picked = await FileBridge.pickFile();
      expect(picked?['name'], 'x.bin');
      expect(picked?['bytes'], isA<Uint8List>());
    });

    test('通道缺失（旧版本 App/桌面端）→ 抛可读 FileBridgeException', () async {
      // 不注册 mock handler：MethodChannel 会抛 MissingPluginException，
      // FileBridge 必须把它转成用户可读文案而不是泄漏原始异常字符串。
      await expectLater(
        FileBridge.saveToDownloads(name: 'a.md', bytes: Uint8List(0)),
        throwsA(
          isA<FileBridgeException>()
              .having((e) => e.message, 'message', contains('不支持'))
              .having((e) => e.toString(), 'toString', isNot(contains('MissingPluginException'))),
        ),
      );
    });

    test('原生 PlatformException → 可读失败提示（带原生原因）', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(FileBridge.channel, (call) async {
        throw PlatformException(code: 'unknown-code', message: '磁盘空间不足');
      });
      await expectLater(
        FileBridge.saveToDownloads(name: 'a.md', bytes: Uint8List(0)),
        throwsA(
          isA<FileBridgeException>()
              .having((e) => e.message, 'message', contains('磁盘空间不足')),
        ),
      );
    });

    test('T2 约定的原生错误码 → 翻译成用户可读提示', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(FileBridge.channel, (call) async {
        throw PlatformException(code: 'read-failed');
      });
      await expectLater(
        FileBridge.pickFile(),
        throwsA(
          isA<FileBridgeException>()
              .having((e) => e.message, 'message', contains('读取文件失败')),
        ),
      );
    });

    test('F5：原生错误码 → 中文可读提示（当前 T2 全部在用码 + 兼容旧码）', () async {
      final expected = <String, String>{
        // T2 2026-10-24 在用码
        'read-failed': '读取文件失败',
        'save-failed': '保存文件失败',
        'pick-failed': '打开文件选择器失败',
        'busy': '正在选择文件',
        'too-large': '文件过大',
        // 兼容旧构建 / 历史码（原 no-view 已被 pick-failed 取代，仍翻译）
        'no-view': '当前界面暂不可用',
        'bad-args': '文件参数异常',
      };
      for (final entry in expected.entries) {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(FileBridge.channel, (call) async {
          throw PlatformException(code: entry.key);
        });
        await expectLater(
          FileBridge.pickFile(),
          throwsA(
            isA<FileBridgeException>()
                .having((e) => e.message, 'message', contains(entry.value)),
          ),
          reason: '错误码 ${entry.key} 必须翻译成中文，不能把英文 code 冒给用户',
        );
      }
    });

    test('F6：Android 取消上传（code=cancelled）→ 等同用户取消返回 null，不弹失败', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(FileBridge.channel, (call) async {
        throw PlatformException(code: 'cancelled');
      });
      expect(await FileBridge.pickFile(), isNull);
    });
  });

  group('Update · iOS 不支持 App 内自更新', () {
    setUp(() => DshPlatform.debugOverrideIsIOS = true);

    test('UpdateSupport：不支持 + TestFlight/App Store 文案', () {
      expect(UpdateSupport.isSupported, isFalse);
      expect(UpdateSupport.unsupportedMessage, contains('TestFlight'));
      expect(UpdateSupport.unsupportedMessage, contains('App Store'));
    });

    test('check() 直接抛 UpdateUnsupportedException（不发起网络请求）', () async {
      await expectLater(
        Updater().check(installedVersionCode: 33),
        throwsA(
          isA<UpdateUnsupportedException>()
              .having((e) => e.message, 'message', contains('TestFlight')),
        ),
      );
    });

    test('install() 返回 unsupportedPlatform（不触碰 dsh/update 通道）', () async {
      final result = await Updater.install(File('dummy.apk'));
      expect(result, ApkInstallResult.unsupportedPlatform);
    });

    test('非 iOS 平台仍支持自更新', () {
      DshPlatform.debugOverrideIsIOS = null;
      if (!Platform.isIOS) {
        expect(UpdateSupport.isSupported, isTrue);
      }
    });
  });

  group('设置页 · iOS 门控', () {
    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      // 非 iOS 分支会探测悬浮球通道：测试环境统一给安全返回值。
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel('dsh/floating'), (call) async {
        return switch (call.method) {
          'isRunning' => false,
          'canDrawOverlay' => false,
          _ => null,
        };
      });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel('dsh/floating'), null);
    });

    Future<void> renderSettings(WidgetTester tester, {required bool ios}) async {
      DshPlatform.debugOverrideIsIOS = ios;
      await tester.binding.setSurfaceSize(const Size(420, 4000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: DshTheme.light(),
          home: Scaffold(
            body: SettingsScreen(store: AppStore(), onReconfigure: () async {}),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
    }

    testWidgets('iOS：悬浮球不显示开关，显示 Bark 降级说明', (tester) async {
      await renderSettings(tester, ios: true);

      final bubbleTile = find.widgetWithText(DshTile, '悬浮球');
      expect(bubbleTile, findsOneWidget);
      expect(
        find.descendant(of: bubbleTile, matching: find.byType(Switch)),
        findsNothing,
      );
      expect(find.text(Floating.unsupportedHint), findsOneWidget);
      expect(find.text('悬浮球操作说明'), findsNothing);

      // B-：iOS 无系统悬浮球 → 余额预警开关一并隐藏（只剩打开 App 时检查一次）。
      final balanceTile = find.widgetWithText(DshTile, '余额预警');
      expect(balanceTile, findsOneWidget);
      expect(
        find.descendant(of: balanceTile, matching: find.byType(Switch)),
        findsNothing,
      );
      expect(find.textContaining('Bark 推送'), findsWidgets);
    });

    testWidgets('iOS：隐藏「检查更新」按钮，显示 App Store 更新说明', (tester) async {
      await renderSettings(tester, ios: true);

      expect(find.widgetWithText(DshTile, '应用更新'), findsOneWidget);
      expect(find.text(UpdateSupport.unsupportedMessage), findsOneWidget);
      expect(find.widgetWithText(DshButton, '检查'), findsNothing);
      expect(find.widgetWithText(DshTile, '检查更新'), findsNothing);
    });

    testWidgets('非 iOS：保持原有开关与检查更新入口（golden 基线不变）', (tester) async {
      if (Platform.isIOS) return; // 仅在桌面测试机上验证
      await renderSettings(tester, ios: false);

      final bubbleTile = find.widgetWithText(DshTile, '悬浮球');
      expect(bubbleTile, findsOneWidget);
      expect(
        find.descendant(of: bubbleTile, matching: find.byType(Switch)),
        findsOneWidget,
      );
      expect(find.text('悬浮球操作说明'), findsOneWidget);
      expect(find.text(UpdateSupport.unsupportedMessage), findsNothing);
      expect(find.widgetWithText(DshButton, '检查'), findsOneWidget);

      // Android：余额预警开关保持原样（C5/B- 只影响 iOS）。
      final balanceTile = find.widgetWithText(DshTile, '余额预警');
      expect(balanceTile, findsOneWidget);
      expect(
        find.descendant(of: balanceTile, matching: find.byType(Switch)),
        findsOneWidget,
      );
    });
  });

  group('主题 · iOS 转场（C2）', () {
    test('iOS 使用 CupertinoPageTransitionsBuilder（保留边缘右滑返回手势）', () {
      final theme = DshTheme.light();
      expect(
        theme.pageTransitionsTheme.builders[TargetPlatform.iOS],
        isA<CupertinoPageTransitionsBuilder>(),
      );
      if (!Platform.isIOS) {
        // Android 保持仓库自定义转场（不在本次修改范围）。
        expect(
          theme.pageTransitionsTheme.builders[TargetPlatform.android],
          isNot(isA<CupertinoPageTransitionsBuilder>()),
        );
      }
    });
  });

  group('连接页 · iOS 本地网络引导（C1）', () {
    testWidgets('iOS 连接失败：提示本地网络权限 + 出现「重试」按钮', (tester) async {
      DshPlatform.debugOverrideIsIOS = true;
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: DshTheme.light(),
          home: Scaffold(body: ConnectionSheet(onConnected: () {})),
        ),
      );
      await tester.pump();
      await tester.enterText(find.byType(TextField).at(0), 'http://127.0.0.1:1');
      await tester.enterText(find.byType(TextField).at(1), 'token');
      await tester.tap(find.text('连接'));
      await tester.pump();
      // 测试环境的 HttpClient 固定返回 400：等 probe 失败落地（非网络类错误不触发
      // iOS 自动重试，直接进入失败分支）。
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        if (find.textContaining('本地网络').evaluate().isNotEmpty) break;
      }
      expect(find.textContaining('本地网络'), findsWidgets,
          reason: 'iOS 失败提示必须包含本地网络权限归因');
      expect(find.widgetWithText(DshButton, '重试'), findsOneWidget);
    });
  });
}
