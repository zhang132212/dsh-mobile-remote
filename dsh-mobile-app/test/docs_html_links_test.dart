// HTML 链接可点测试（v3.2.12）：相对/本地/网络链接解析 + 页内锚点 + 点击行为。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dsh_mobile_app/docs/html.dart';
import 'package:dsh_mobile_app/docs/link.dart';
import 'package:dsh_mobile_app/docs/model.dart';
import 'package:dsh_mobile_app/docs/render.dart';
import 'package:dsh_mobile_app/screens/doc_viewer_screen.dart';

void main() {
  group('resolveDocHref：相对链接解析', () {
    test('本地文档：相对路径 / ./ / ../ 都按所在目录解析', () {
      const ctx = DocRenderCtx(baseDir: r'D:\docs');
      for (final (href, want) in <(String, String)>[
        ('other.html', r'D:\docs\other.html'),
        ('./sub/page.html', r'D:\docs\sub\page.html'),
        ('../up.html', r'D:\up.html'),
        ('note.md', r'D:\docs\note.md'),
      ]) {
        final resolved = resolveDocHref(href, ctx);
        expect(resolved, isNotNull, reason: href);
        final parsed = parseDocLink(resolved!);
        expect(parsed?.localPath, want, reason: href);
      }
    });

    test('本地文档：根相对挂盘符根；Windows 绝对路径直接可用', () {
      const ctx = DocRenderCtx(baseDir: r'D:\docs\site');
      final root = parseDocLink(resolveDocHref('/index.html', ctx)!);
      expect(root?.localPath, r'D:\index.html');

      final win = resolveDocHref(r'C:\site\a.html', ctx)!;
      expect(parseDocLink(win)?.localPath, r'C:\site\a.html');

      final forward = resolveDocHref('C:/site/a.html', ctx)!;
      expect(parseDocLink(forward)?.localPath, r'C:\site\a.html');
    });

    test('file:// URI 转成本地文档', () {
      final resolved = resolveDocHref('file:///C:/site/a.html', const DocRenderCtx());
      expect(resolved, isNotNull);
      expect(parseDocLink(resolved!)?.localPath, r'C:\site\a.html');
    });

    test('网络文档：相对/根相对按 baseUrl 解析；绝对外链原样保留', () {
      const ctx = DocRenderCtx(baseUrl: 'https://example.com/docs/index.html');
      expect(resolveDocHref('other.html', ctx), 'https://example.com/docs/other.html');
      expect(resolveDocHref('/root.html', ctx), 'https://example.com/root.html');
      expect(resolveDocHref('https://other.com/x.html', ctx), 'https://other.com/x.html');
      final parsed = parseDocLink(resolveDocHref('other.html', ctx)!);
      expect(parsed?.httpUrl, 'https://example.com/docs/other.html');
    });

    test('页内锚点 / 无法定位的裸链接不返回文档地址', () {
      expect(resolveDocHref('#sec', const DocRenderCtx()), isNull);
      expect(resolveDocHref('page.html', const DocRenderCtx()), isNull);
      expect(resolveDocHref('javascript:alert(1)', const DocRenderCtx()), isNull);
      expect(resolveDocHref('mailto:a@b.c', const DocRenderCtx()), isNull);
    });
  });

  group('HTML 锚点解析', () {
    test('标题 / 段落 / 空锚点元素都能带出 anchor', () {
      final doc = parseHtml(
        '<h2 id="install">安装</h2>'
        '<p id="step1">第一步</p>'
        '<div id="anchor-only"></div>'
        '<p id="step2">第二步</p>',
        'a',
      );
      final anchors = <String>[];
      for (final b in doc.blocks) {
        switch (b) {
          case DocHeading(:final anchor):
            if (anchor != null) anchors.add(anchor);
          case DocPara(:final anchor):
            if (anchor != null) anchors.add(anchor);
          default:
            break;
        }
      }
      expect(anchors, containsAll(['install', 'step1', 'anchor-only', 'step2']));
    });
  });

  group('点击行为', () {
    testWidgets('页内 #hash 链接点击 → 走 onAnchor 回调', (tester) async {
      final doc = parseHtml(
        '<h2 id="sec">章节</h2><p><a href="#sec">跳过去</a></p>',
        'a',
      );
      String? jumped;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: DocBlocks(
              doc.blocks,
              ctx: DocRenderCtx(onAnchor: (a) => jumped = a),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('跳过去'), findsOneWidget);
      await tester.tap(find.text('跳过去'));
      await tester.pumpAndSettle();
      expect(jumped, 'sec');
    });

    testWidgets('相对链接点击 → 按 baseDir 打开目标文档（弹出阅读器）', (tester) async {
      final doc = parseHtml('<p><a href="other.html">打开另一页</a></p>', 'a');
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: DocBlocks(
              doc.blocks,
              ctx: const DocRenderCtx(baseDir: r'D:\docs'),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('打开另一页'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      // 打开的是抽屉里的 DocViewerScreen；文件读取会失败（测试环境无真实 API），
      // 但「点击 → 打开目标」这条链路必须成立。
      expect(find.byType(DocViewerScreen), findsOneWidget);
      await tester.pumpAndSettle();
    });
  });
}
