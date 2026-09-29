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
}
