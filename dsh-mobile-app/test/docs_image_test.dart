// v3.2.4：文档内图片渲染的回归测试。
//
// 背景：此前文档里的 `![](图片.png)` 只会显示成一个「🖼 文件名」占位 chip，
// 原因是三处叠加 —— ① markdown 解析器不认图片语法；② docx 读取器丢了二进制；
// ③ 渲染器只用了 alt 且 ctx 里没有取图能力。本测试盯住 ① 和 ③ 的降级行为。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dsh_mobile_app/docs/markdown.dart';
import 'package:dsh_mobile_app/docs/model.dart';
import 'package:dsh_mobile_app/docs/render.dart';

List<DocImage> imagesOf(Document doc) {
  final out = <DocImage>[];
  for (final b in doc.blocks) {
    if (b is DocPara) {
      for (final s in b.spans) {
        if (s is DocImage) out.add(s);
      }
    }
  }
  return out;
}

void main() {
  test('图片语法解析成 DocImage（且不被链接规则抢先吃掉）', () {
    final doc = parseMarkdown('看这张图：\n\n![图5 电路](图/图5-电路.png)\n\n结束', 't');
    final imgs = imagesOf(doc);
    expect(imgs.length, 1, reason: '![...](...) 必须解析成 DocImage');
    expect(imgs.first.url, '图/图5-电路.png');
    expect(imgs.first.alt, '图5 电路');
  });

  test('行内图片、多张图片、无 alt 都能解析', () {
    final doc = parseMarkdown('前面 ![](a.png) 中间 ![第二个](b.png) 后面', 't');
    final imgs = imagesOf(doc);
    expect(imgs.length, 2);
    expect(imgs[0].url, 'a.png');
    expect(imgs[0].alt, isNull);
    expect(imgs[1].alt, '第二个');
  });

  test('普通链接不受影响（回归：别把 [文字](url) 也当图片）', () {
    final doc = parseMarkdown('见 [文档](dsh-doc:D:\\x.md)', 't');
    expect(imagesOf(doc), isEmpty);
  });

  test('相对路径必须按 Windows 语境解析（回归：曾拼出 ./图.png 导致取图 404）', () {
    // 文档在电脑上，路径是 Windows 形式；App 跑在 Android（POSIX）。
    // 用默认 path 上下文会把 baseDir 解析成 `.`，拼出 `./图5.png`。
    expect(
      resolveDocImagePath(src: '图5-受控源电路.png', baseDir: r'D:\DSH-文档'),
      r'D:\DSH-文档\图5-受控源电路.png',
    );
    expect(
      resolveDocImagePath(src: '../图/x.png', baseDir: r'D:\DSH-文档\编程'),
      r'D:\DSH-文档\编程\../图/x.png',
    );
    // 绝对路径原样返回
    expect(
      resolveDocImagePath(src: r'D:\a\b.png', baseDir: r'D:\other'),
      r'D:/a/b.png',
    );
    // 没有 baseDir 时解析不出来（交给降级占位）
    expect(resolveDocImagePath(src: 'x.png', baseDir: null), isNull);
    expect(resolveDocImagePath(src: '   ', baseDir: r'D:\x'), isNull);
  });

  testWidgets('取不到图时降级成占位 chip，不崩、不留空白', (tester) async {
    final doc = parseMarkdown('![电路图](不存在的目录/不存在的图.png)', 't');
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: DocBlocks(doc.blocks, ctx: const DocRenderCtx()),
        ),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(tester.takeException(), isNull, reason: '取不到图也必须安全降级');
    expect(find.textContaining('电路图'), findsWidgets, reason: '降级后至少要显示 alt');
  });

  testWidgets('相对路径但没有 ctx 能力时，同样安全降级', (tester) async {
    final doc = parseMarkdown('![](图/图5.png)', 't');
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: DocBlocks(doc.blocks, ctx: const DocRenderCtx(scale: 1.2)),
        ),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(tester.takeException(), isNull);
  });

  testWidgets('http 图片在测试环境取不到也不崩（降级占位）', (tester) async {
    final doc = parseMarkdown('![远程图](https://example.invalid/x.png)', 't');
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: DocBlocks(doc.blocks, ctx: const DocRenderCtx()),
        ),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(tester.takeException(), isNull);
  });
}
