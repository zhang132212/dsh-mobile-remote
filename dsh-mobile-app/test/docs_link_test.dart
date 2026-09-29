// 文档链接就地阅读测试（v3.2.1）——聊天里点链接 → 底部抽屉里读，对话不关闭。
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dsh_mobile_app/docs/link.dart';
import 'package:dsh_mobile_app/docs/sheet.dart';
import 'package:dsh_mobile_app/md.dart';
import 'package:dsh_mobile_app/screens/doc_viewer_screen.dart';

void main() {
  group('规则：什么样的链接算「文档链接」', () {
    test('dsh-doc: + Windows 绝对路径', () {
      final t = parseDocLink(r'dsh-doc:C:\Users\Administrator\Desktop\项目\验收.md');
      expect(t, isNotNull);
      expect(t!.name, '验收.md');
      expect(t.localPath, r'C:\Users\Administrator\Desktop\项目\验收.md');
      expect(t.httpUrl, isNull);
    });

    test('dsh-doc: + 正斜杠路径', () {
      final t = parseDocLink('dsh-doc:C:/Users/a/b/note.txt');
      expect(t!.name, 'note.txt');
      expect(t.localPath, 'C:/Users/a/b/note.txt');
    });

    test('容忍多写的两斜杠 dsh-doc://（但不吃掉盘符的冒号）', () {
      final t = parseDocLink('dsh-doc://C:/x/y.docx');
      expect(t!.localPath, 'C:/x/y.docx');
      expect(t.name, 'y.docx');
    });

    test('百分号转义会被还原（中文/空格路径）', () {
      final t = parseDocLink('dsh-doc:C:/a%20b/%E9%AA%8C%E6%94%B6.md');
      expect(t!.localPath, 'C:/a b/验收.md');
      expect(t.name, '验收.md');
    });

    test('大小写不敏感', () {
      expect(parseDocLink('DSH-DOC:C:/a/b.md'), isNotNull);
    });

    test('http(s) 且扩展名可读 → 文档链接', () {
      for (final u in [
        'https://example.com/a/b.md',
        'http://example.com/x.docx',
        'https://raw.githubusercontent.com/o/r/main/d.xlsx',
        'https://example.com/note.txt',
      ]) {
        final t = parseDocLink(u);
        expect(t, isNotNull, reason: u);
        expect(t!.httpUrl, u);
      }
    });

    test('普通网页链接**不**算文档链接（行为不变，仍走浏览器）', () {
      for (final u in [
        'https://example.com/',
        'https://example.com/page.html',
        'https://www.deepseek.com/',
        'https://github.com/o/r/releases/tag/v1.0.0',
      ]) {
        expect(parseDocLink(u), isNull, reason: u);
      }
    });

    test('其它 scheme 一律不认（安全边界）', () {
      for (final u in [
        'file:///C:/secret.md',
        'tel:10086',
        'intent://x#Intent;end',
        'javascript:alert(1)',
        'content://media/external/file/1',
      ]) {
        expect(parseDocLink(u), isNull, reason: u);
      }
    });

    test('空内容不认', () {
      expect(parseDocLink('dsh-doc:'), isNull);
      expect(parseDocLink('dsh-doc:   '), isNull);
      expect(parseDocLink(''), isNull);
    });

    test('反向构造：docLinkFor 能被 parseDocLink 还原', () {
      const path = r'C:\Users\Administrator\Desktop\项目\公式标记验收.md';
      final link = docLinkFor(path);
      final back = parseDocLink(link);
      expect(back!.localPath, path);
      expect(back.name, '公式标记验收.md');
    });
  });

  group('聊天里的呈现与点击', () {
    testWidgets('文档链接带 📄 前缀，且点击会弹出阅读抽屉（对话不关闭）', (tester) async {
      const md = '点这里读：[验收文档](dsh-doc:C:/tmp/验收.md)';
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (c) => SingleChildScrollView(
              child: Column(children: renderMarkdownBlocks(md, c)),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      // 呈现：📄 前缀 + 可点
      expect(find.textContaining('📄'), findsOneWidget);
      expect(find.textContaining('验收文档'), findsOneWidget);

      // 点击 → 抽屉打开（底部弹出 DocViewerScreen 的嵌入式形态）
      await tester.tap(find.textContaining('📄'));
      await tester.pumpAndSettle();

      expect(find.byType(DocViewerScreen), findsOneWidget);
      final viewer = tester.widget<DocViewerScreen>(find.byType(DocViewerScreen));
      expect(viewer.embedded, isTrue, reason: '必须是嵌入式（对话仍在下面存活）');
      expect(viewer.name, '验收.md');
      expect(viewer.remotePath, 'C:/tmp/验收.md');

      expect(tester.takeException(), isNull);
    });

    testWidgets('普通网页链接**不**带 📄 前缀（不与文档链接混淆）', (tester) async {
      const md = '看官网：[DeepSeek](https://www.deepseek.com/)';
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (c) => SingleChildScrollView(
              child: Column(children: renderMarkdownBlocks(md, c)),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.textContaining('📄'), findsNothing);
      expect(find.textContaining('DeepSeek'), findsOneWidget);
    });

    testWidgets('http 文档直链也能就地打开（带上 httpUrl）', (tester) async {
      const md = '[远程文档](https://example.com/a/notes.md)';
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (c) => SingleChildScrollView(
              child: Column(children: renderMarkdownBlocks(md, c)),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('📄'));
      await tester.pumpAndSettle();
      final viewer = tester.widget<DocViewerScreen>(find.byType(DocViewerScreen));
      expect(viewer.httpUrl, 'https://example.com/a/notes.md');
      expect(viewer.remotePath, isNull);
    });
  });

  group('抽屉接口', () {
    testWidgets('showDocSheet 传参正确落到阅读器', (tester) async {
      late BuildContext captured;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(builder: (c) {
            captured = c;
            return const SizedBox();
          }),
        ),
      ));
      // 不 await：抽屉要留在屏幕上供断言
      unawaited(showDocSheet(
        captured,
        name: 'a.md',
        localPath: 'C:/tmp/a.md',
        bytes: Uint8List.fromList(utf8.encode('# 标题')),
      ));
      await tester.pumpAndSettle();
      expect(find.byType(DocViewerScreen), findsOneWidget);
      expect(find.text('a.md'), findsWidgets); // 头部显示文件名
      expect(tester.takeException(), isNull);
    });

    testWidgets('showDocLinkSheet：非文档链接返回 false（调用方继续走浏览器）', (tester) async {
      late BuildContext captured;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(builder: (c) {
            captured = c;
            return const SizedBox();
          }),
        ),
      ));
      final handled = await showDocLinkSheet(captured, 'https://example.com/');
      expect(handled, isFalse);
    });
  });
}

/// 本地 unawaited（避免为一个调用引入额外依赖）。
void unawaited(Future<void> f) {}
