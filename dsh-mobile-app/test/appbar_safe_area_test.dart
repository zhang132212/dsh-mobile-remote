// 标题栏状态栏避让回归测试。
//
// 背景（真机反馈 2026-10-19）：自绘的 DshAppBar 一开始没接管
// `MediaQuery.padding.top`，于是「DeepSeek harness 版本」「用量与额度」等页面
// 的标题被手机状态栏（时间 / 信号 / 电量）压住。
//
// Material 的 Scaffold 会把 `preferredSize.height + 状态栏高度` 一起预留给
// appBar，AppBar 自己补那段内边距；自绘标题栏必须做同样的事。
import 'package:dsh_mobile_app/dsh_kit.dart';
import 'package:dsh_mobile_app/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 模拟一台有刘海/挖孔的手机：状态栏 24、底部手势条 16。
const double _statusBar = 24;
const double _bottomBar = 16;

Widget _host({required Widget child}) {
  return MaterialApp(
    theme: DshTheme.light(),
    home: MediaQuery(
      data: const MediaQueryData(
        size: Size(390, 844),
        padding: EdgeInsets.only(top: _statusBar, bottom: _bottomBar),
        viewPadding: EdgeInsets.only(top: _statusBar, bottom: _bottomBar),
      ),
      child: child,
    ),
  );
}

void main() {
  testWidgets('作为页面主标题栏时，标题不会压在状态栏下面', (tester) async {
    await tester.pumpWidget(_host(
      child: Scaffold(
        appBar: const DshAppBar(title: '用量与额度'),
        body: const SizedBox.expand(),
      ),
    ));

    final titleRect = tester.getRect(find.text('用量与额度'));
    expect(titleRect.top, greaterThanOrEqualTo(_statusBar),
        reason: '标题顶边 ${titleRect.top} 落在状态栏（$_statusBar）里 → 会被时间/电量压住');

    // 顺带钉住原有几何：标题栏本体仍是 52 高 + 发丝分隔线。
    final barRect = tester.getRect(find.byType(DshAppBar));
    expect(barRect.height, closeTo(52 + DshStroke.hairline + _statusBar, 0.01),
        reason: '标题栏总高应为「状态栏 + 52 + 0.5」');
  });

  testWidgets('嵌在抽屉/弹层里（primary: false）时不重复吃状态栏高度', (tester) async {
    await tester.pumpWidget(_host(
      child: Scaffold(
        body: Column(
          children: const [
            DshAppBar(title: '文档.md', primary: false),
            Expanded(child: SizedBox.expand()),
          ],
        ),
      ),
    ));

    final titleRect = tester.getRect(find.text('文档.md'));
    expect(titleRect.top, lessThan(_statusBar),
        reason: 'primary: false 时不加内边距，交给外层安全区处理');

    final barRect = tester.getRect(find.byType(DshAppBar));
    expect(barRect.height, closeTo(52 + DshStroke.hairline, 0.01));
  });

  testWidgets('页面里有底部安全区时，正文不被手势条遮住（Scaffold 负责，回归钉子）',
      (tester) async {
    await tester.pumpWidget(_host(
      child: Scaffold(
        appBar: const DshAppBar(title: '通知'),
        body: const SafeArea(top: false, child: SizedBox.expand()),
      ),
    ));
    final bodyRect = tester.getRect(find.byType(SafeArea));
    expect(bodyRect.bottom, lessThanOrEqualTo(844 - _bottomBar + 0.01));
  });
}
