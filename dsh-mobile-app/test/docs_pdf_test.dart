// PDF 阅读（v3.2.16）的落地测试。
//
// 分三层：
//   ① 格式识别：扩展名 / 内容嗅探（没有后缀的 PDF 也要认得）；
//   ② 加载器：loadDocument 对 PDF 不该抛、不该当文本读，要返回 format=pdf 的空文档；
//   ③ 阅读页：用 mock 的原生通道跑通「打开 → 渲染 → 页码」整条链，
//      并验证平台没实现时给的是可读提示而不是崩。
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dsh_mobile_app/docs/loader.dart';
import 'package:dsh_mobile_app/docs/model.dart';
import 'package:dsh_mobile_app/docs/pdf_view.dart';
import 'package:dsh_mobile_app/screens/doc_viewer_screen.dart';

/// 最小可解码的 1x1 PNG（Image.memory 在测试里要能真解码）。
final Uint8List kTinyPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+ip1sAAAAASUVORK5CYII=',
);

/// 最小 PDF 头（嗅探只看 %PDF- 魔数，不需要真能渲染）。
Uint8List minimalPdf() => Uint8List.fromList(utf8.encode('%PDF-1.4\n1 0 obj\n<<>>\nendobj\n%%EOF\n'));

void main() {
  group('PDF 格式识别', () {
    test('扩展名识别（大小写都认）', () {
      expect(detectFormat('论文.pdf'), DocFormat.pdf);
      expect(detectFormat('C:/Users/x/REPORT.PDF'), DocFormat.pdf);
      expect(detectFormat('a.Pdf'), DocFormat.pdf);
    });

    test('pdf 在可读扩展名清单里（分享/打开方式的入口靠它）', () {
      expect(kReadableExtensions, contains('pdf'));
      expect(isReadableFormat('x.pdf'), isTrue);
    });

    test('没有扩展名时按 %PDF- 魔数嗅探', () {
      final doc = loadDocument(minimalPdf(), 'download.bin');
      expect(doc.format, DocFormat.pdf);
    });
  });

  group('loadDocument 对 PDF 的处理', () {
    test('不当文本解析：blocks 为空、不抛', () {
      final doc = loadDocument(minimalPdf(), 'paper.pdf');
      expect(doc.format, DocFormat.pdf);
      expect(doc.blocks, isEmpty);
      expect(doc.title, 'paper'); // 标题取文件名去掉扩展名
    });

    test('空字节仍然走「文件为空」的兜底（不因为 pdf 特判而崩）', () {
      final doc = loadDocument(Uint8List(0), 'empty.pdf');
      expect(doc.format, DocFormat.unknown);
    });
  });

  group('PdfView 阅读页（mock 原生通道）', () {
    const channel = MethodChannel('dsh/pdf');
    late List<String> calls;
    late List<Object?> closedIds;

    setUp(() {
      calls = <String>[];
      closedIds = <Object?>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        switch (call.method) {
          case 'open':
            return <String, Object>{'id': 7, 'pages': 3, 'width': 595, 'height': 842};
          case 'render':
            return kTinyPng;
          case 'close':
            closedIds.add(call.arguments is Map ? (call.arguments as Map)['id'] : null);
            return true;
        }
        return null;
      });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    testWidgets('打开 → 显示页码 1 / 3，并真的请求过渲染', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: PdfView(bytes: minimalPdf(), name: 'paper.pdf')),
      ));
      await tester.pumpAndSettle();

      expect(find.text('1 / 3'), findsOneWidget);
      expect(calls, contains('open'));
      expect(calls, contains('render'));
    });

    testWidgets('离开页面会 close（原生句柄不泄漏）', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: PdfView(bytes: minimalPdf(), name: 'paper.pdf')),
      ));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      await tester.pumpAndSettle();
      expect(calls, contains('close'));
      // 关的是自己这一份会话（不是「关全部」的旧语义）
      expect(closedIds, contains(7));
    });

    testWidgets('跳页后翻到第 2 页', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: PdfView(bytes: minimalPdf(), name: 'paper.pdf')),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.chevron_right));
      await tester.pumpAndSettle();
      expect(find.text('2 / 3'), findsOneWidget);
    });


    testWidgets('双击放大：InteractiveViewer 的缩放从 1 变 2 倍', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: PdfView(bytes: minimalPdf(), name: 'paper.pdf')),
      ));
      await tester.pumpAndSettle();

      double maxScale() => tester
          .widgetList<Transform>(find.descendant(
            of: find.byType(InteractiveViewer),
            matching: find.byType(Transform),
          ))
          .map((t) => t.transform.getMaxScaleOnAxis())
          .fold<double>(1.0, (a, b) => a > b ? a : b);

      expect(maxScale(), lessThan(1.01));
      final center = tester.getCenter(find.byType(PdfPageImage));
      await tester.tapAt(center);
      await tester.pump(const Duration(milliseconds: 80));
      await tester.tapAt(center);
      await tester.pumpAndSettle();
      expect(maxScale(), greaterThan(1.8));
    });

    testWidgets('原生没实现时给可读提示，不崩', (tester) async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        throw MissingPluginException('no impl');
      });
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: PdfView(bytes: minimalPdf(), name: 'paper.pdf')),
      ));
      await tester.pumpAndSettle();
      expect(find.textContaining('暂不支持 PDF'), findsOneWidget);
    });
  });

  group('阅读页分派', () {
    testWidgets('DocViewerScreen 打开 pdf 时切到 PdfView（不走块级渲染）', (tester) async {
      const channel = MethodChannel('dsh/pdf');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        switch (call.method) {
          case 'open':
            return <String, Object>{'id': 9, 'pages': 1, 'width': 595, 'height': 842};
          case 'render':
            return kTinyPng;
          case 'close':
            return true;
        }
        return null;
      });
      addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null));

      await tester.pumpWidget(MaterialApp(
        home: DocViewerScreen(name: 'paper.pdf', bytes: minimalPdf()),
      ));
      await tester.pumpAndSettle();

      expect(find.byType(PdfView), findsOneWidget);
    });
  });
}
