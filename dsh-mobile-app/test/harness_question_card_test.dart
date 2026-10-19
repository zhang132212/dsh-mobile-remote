import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dsh_mobile_app/models.dart';
import 'package:dsh_mobile_app/theme.dart';
import 'package:dsh_mobile_app/screens/harness_question_card.dart';

final capture = Platform.environment['DSH_CAPTURE_UI'] == '1';
ThemeData reviewTheme(bool dark) {
  final theme = dark ? DshTheme.dark() : DshTheme.light();
  return capture ? theme.copyWith(
    textTheme: theme.textTheme.apply(fontFamily: 'UiReview'),
    filledButtonTheme: FilledButtonThemeData(style: theme.filledButtonTheme.style!.copyWith(
      textStyle: const WidgetStatePropertyAll(TextStyle(fontFamily: 'UiReview', fontSize: 14, fontWeight: FontWeight.w600)))),
  ) : theme;
}
void main() {
  setUpAll(() async {
    if (capture) {
      final font = FontLoader('UiReview')..addFont(File(r'C:\Windows\Fonts\msyh.ttc').readAsBytes().then((bytes) => ByteData.sublistView(bytes)));
      await font.load();
      final icons = FontLoader('MaterialIcons')..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
      await icons.load();
    }
  });
  QuestionRequest request(List<AskQuestion> questions) => QuestionRequest(rpcId: 'q-1', sessionId: 's-1', questions: questions);
  Widget app(QuestionRequest req, Future<void> Function(List<Map<String, dynamic>>) submit, {Key? captureKey, bool dark = false}) =>
    MaterialApp(theme: reviewTheme(dark), home: Scaffold(
      body: RepaintBoundary(key: captureKey, child: ColoredBox(color: dark ? DshTheme.bgDark : DshTheme.bg,
        child: Align(alignment: Alignment.bottomCenter, child: HarnessQuestionCard(request: req, onCancel: () {}, onSubmitted: submit)))),
    ));

  testWidgets('phone question renders options and submits selected plus custom multi-answer', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    List<Map<String, dynamic>>? result;
    final req = request([AskQuestion(id: 'q', header: '界面设置', question: '希望保留哪些会话信息？',
      detail: '选择需要显示的内容，也可以补充其他要求。', multiSelect: true,
      options: [AskOption(label: '子代理汇报', description: '显示来源，点击展开正文'), AskOption(label: '工具执行记录')])]);
    final key = GlobalKey();
    await tester.pumpWidget(app(req, (value) async { result = value; }, captureKey: key));
    expect(find.text('希望保留哪些会话信息？'), findsOneWidget);
    await tester.tap(find.text('子代理汇报'));
    await tester.enterText(find.byType(TextField), '保留失败原因');
    tester.testTextInput.hide();
    await tester.pumpAndSettle();
    if (Platform.environment['DSH_CAPTURE_UI'] == '1') {
      final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await Directory('build/ui-review').create(recursive: true);
        await File('build/ui-review/question-light.png').writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
      });
    }
    await tester.tap(find.text('提交'));
    await tester.pump();
    expect(result, [{'id': 'q', 'selected': ['子代理汇报'], 'custom': '保留失败原因'}]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('multiple questions retain answers across pages and keep footer visible on a small phone', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    List<Map<String, dynamic>>? result;
    final req = request([
      AskQuestion(id: 'first', question: '选择方案', options: [AskOption(label: '方案 A'), AskOption(label: '方案 B')]),
      AskQuestion(id: 'second', question: '补充要求', detail: List.filled(30, '这是可滚动的问题说明。').join()),
    ]);
    await tester.pumpWidget(app(req, (value) async { result = value; }, dark: true));
    await tester.tap(find.text('方案 A'));
    await tester.tap(find.text('下一题'));
    await tester.pump();
    expect(find.text('2 / 2'), findsOneWidget);
    expect(tester.getBottomRight(find.text('提交')).dy, lessThanOrEqualTo(640));
    await tester.drag(find.byType(SingleChildScrollView).first, const Offset(0, -1000));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '第二题答案');
    tester.testTextInput.hide();
    await tester.pumpAndSettle();
    await tester.tap(find.text('提交'));
    await tester.pump();
    expect(result, [{'id': 'first', 'selected': ['方案 A']}, {'id': 'second', 'selected': [], 'custom': '第二题答案'}]);
    expect(tester.takeException(), isNull);
  });

  // 真机反馈（2026-10-19）：选项一多，问询卡会超出屏幕，取消/提交被裁掉。
  // 根因是卡片当时作为聊天页 Column 的固定子节点、高度按「屏高 55%」估算；
  // 现在它是消息区底部的浮层，高度由调用方按可用区域给（maxHeight），内部自己滚动。
  testWidgets('选项很多时卡片不超过给定高度，底栏按钮仍在屏内（回归：对话框超出屏幕）', (tester) async {
    tester.view.physicalSize = const Size(390, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final req = request([
      AskQuestion(
        id: 'q',
        header: '测试确认',
        question: '接下来要做什么？',
        multiSelect: false,
        options: List.generate(
          8,
          (i) => AskOption(label: '选项 $i', description: '这一项的第 $i 条说明文字'),
        ),
      ),
    ]);

    await tester.pumpWidget(MaterialApp(
      theme: reviewTheme(false),
      home: Scaffold(
        // 复刻生产结构：消息区（Expanded + Stack）+ 底部输入框，卡片浮在消息区底部
        body: Column(
          children: [
            Expanded(
              child: Stack(
                children: [
                  const Positioned.fill(child: SizedBox.expand()),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: HarnessQuestionCard(
                      request: req,
                      maxHeight: 300,
                      onCancel: () {},
                      onSubmitted: (_) async {},
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(
              height: 72,
              child: ColoredBox(
                color: Color(0xFFEEEEEE),
                child: Center(child: Text('composer')),
              ),
            ),
          ],
        ),
      ),
    ));

    // 卡片高度受 maxHeight 约束
    final cardRect = tester.getRect(find.byType(HarnessQuestionCard));
    expect(cardRect.height, lessThanOrEqualTo(300.5), reason: '卡片高度应受 maxHeight 约束');

    // 不能压到下方输入框：卡片底边 ≤ 输入框顶边
    final composerTop = tester.getRect(find.text('composer')).top;
    expect(cardRect.bottom, lessThanOrEqualTo(composerTop + 0.5),
        reason: '问询卡越界压到了输入框（真机表现：取消/提交被裁掉）');

    // 底栏两个按钮在屏内
    expect(tester.getRect(find.text('取消')).bottom, lessThanOrEqualTo(700));
    expect(tester.getRect(find.text('提交')).bottom, lessThanOrEqualTo(700));

    // 布局不应抛 overflow
    expect(tester.takeException(), isNull);
  });
}
