// 文档阅读页 widget 测试（v3.2.0）——验证「打开 → 解析 → 渲染」整条链路真的出画面。
//
// 为什么要有这层：单元测试证明了 parser/OMML 的正确性，但**没有证明界面上真的
// 渲染出公式**（公式是 WidgetSpan + flutter_math_fork 的 Math widget，很容易
// 因为尺寸/基线问题静默降级成原文）。这里用真实 build 把这条链路钉住。
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dsh_mobile_app/md.dart';
import 'package:dsh_mobile_app/screens/doc_viewer_screen.dart';

const String kSampleMd = r'''# 一元五次分式积分

$$\boxed{\;\int\frac{dx}{x^5+1}=\frac15\ln|x+1|+\frac{\varphi^{-1}\sin\frac{2\pi}{5}}{5}\arctan\frac{x-\varphi/2}{\sin\frac{2\pi}{5}}+C\;}$$

行内公式：设 $\varphi=\frac{1+\sqrt5}{2}$，则 $\varphi^2=\varphi+1$。

- **加粗**、*斜体*、`代码`
- 链接：[示例](https://example.com/a)

| 项目 | 值 |
|---|---|
| φ | 1.618 |

> 引用块

```python
x = 1
```
''';

Uint8List bytesOf(String s) => Uint8List.fromList(utf8.encode(s));

void main() {
  testWidgets('Markdown 阅读页渲染出标题、正文与**真公式**（非降级原文）', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: DocViewerScreen(name: 'sample.md', bytes: bytesOf(kSampleMd)),
    ));
    await tester.pumpAndSettle();

    // 标题与正文进画面
    expect(find.textContaining('一元五次分式积分'), findsWidgets);
    expect(find.textContaining('行内公式'), findsWidgets);

    // 关键：公式由 flutter_math_fork 的 Math widget 渲染（说明没走降级分支）
    expect(find.byType(Math), findsWidgets, reason: '显示式与行内公式都应是 Math widget');

    // 列表标记与代码块
    expect(find.text('•'), findsWidgets);
    expect(find.text('python'), findsOneWidget);
  });

  testWidgets('阅读页不崩：文本/公式/表格/代码混合内容', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: DocViewerScreen(name: 'sample.md', bytes: bytesOf(kSampleMd)),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('字号放大后仍能渲染（缩放路径不炸）', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: DocViewerScreen(name: 'sample.md', bytes: bytesOf(kSampleMd)),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('放大字号'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(Math), findsWidgets);
  });

  testWidgets('纯文本文件也能打开', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: DocViewerScreen(name: 'note.txt', bytes: bytesOf('第一行\n见 https://example.com/x')),
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('第一行'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('坏字节 → 显示可读的失败说明而不是崩溃', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: DocViewerScreen(name: 'x.bin', bytes: Uint8List.fromList(List.filled(64, 7))),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.textContaining('暂不支持'), findsWidgets);
  });

  testWidgets('聊天 Markdown：行内代码里的 \$\$ 不被渲染成公式（回归）', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (c) => SingleChildScrollView(
            child: Column(children: renderMarkdownBlocks(r'用 `$$x^2$$` 包裹公式', c)),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    // 代码块里的 $ 不是公式 → 不应出现 Math widget
    expect(find.byType(Math), findsNothing, reason: r'反引号内的 $$ 必须是代码而非公式');
    expect(find.textContaining(r'$$x^2$$'), findsWidgets);
  });

  testWidgets('聊天 Markdown：真正的 \$\$ 显示式仍然渲染成公式', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (c) => SingleChildScrollView(
            child: Column(children: renderMarkdownBlocks('\$\$a^2+b^2=c^2\$\$', c)),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byType(Math), findsWidgets);
  });
}
