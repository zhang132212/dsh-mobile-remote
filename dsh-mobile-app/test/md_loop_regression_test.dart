// v3.2.3 严重 bug 回归：整行 /"…"/ 公式导致 renderMarkdownBlocks 死循环。
//
// 根因：md.dart 的主循环是 `while (i < lines.length)`，而「整行 /"…"/ 公式」
// 分支漏了 i++ —— 同一行被无限解析、无限 blocks.add，堆被撑爆（真机 OOM），
// 气泡永远构建不完 → 那条消息永久不显示；下次 build 还会撞 _blocks! 报
// 「Null check operator used on a null value」。
//
// 这个测试**必须用块数上界**来断言，不能只靠"跑得完"：死循环会把测试进程拖到 OOM，
// 那属于崩溃而不是失败，定位成本极高（本次排查就吃了这个亏）。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dsh_mobile_app/md.dart';

Future<List<Widget>> parse(WidgetTester tester, String text) async {
  List<Widget>? captured;
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Builder(builder: (c) {
        captured = renderMarkdownBlocks(text, c);
        return SingleChildScrollView(child: Column(children: captured!));
      }),
    ),
  ));
  return captured!;
}

void main() {
  testWidgets('整行 /"…"/ 公式：索引必须推进（不死循环）', (tester) async {
    final text = '前文一段\n\n/"x^2"/\n\n后文一段';
    final blocks = await parse(tester, text);

    // 死循环的典型表现就是块数爆炸 —— 钉死上界，OOM 之前就先失败
    expect(blocks.length, lessThan(20),
        reason: '块数 ${blocks.length} 说明主循环没有推进 i（整行公式分支漏了 i++）');
    expect(blocks.length, greaterThanOrEqualTo(3), reason: '前文/公式/后文都该成块');
  });

  testWidgets(r'整行 $$…$$ 公式：对照用例（一直是对的）', (tester) async {
    final blocks = await parse(tester, '前文\n\n\$\$y=mx+b\$\$\n\n后文');
    expect(blocks.length, lessThan(20));
  });

  testWidgets('多条整行公式连排也不炸', (tester) async {
    final blocks = await parse(tester, '/"a=b"/\n\n/"c=d"/\n\n/"e=f"/');
    expect(blocks.length, lessThan(20), reason: '块数 ${blocks.length}');
    expect(blocks.length, greaterThanOrEqualTo(3));
  });

  testWidgets('算积分那条真实回答：整条能解析完', (tester) async {
    // 真机事故原文（节选：三条整行公式 + 行内公式 + dsh-doc 链接）
    const text = r'''哼，这种题才不困难呢～

核心步骤：先把 /"x^5+1"/ 拆成实因式

/"x^5+1=(x+1)\left(x^2+\alpha x+1\right)\left(x^2-\beta x+1\right)\qquad \alpha=\frac{\sqrt5-1}{2}"/

再部分分式，最后逐项配方积分：

/"\int\frac{dx}{x^5+1}=\frac15\ln|x+1|+\frac{\alpha}{10}\ln\!\left(x^2+\alpha x+1\right)+C"/

最大误差只有 /"8.7\times10^{-11}"/，文档在这里：

[x五次方加一的不定积分](dsh-doc:D:\DSH-文档\数学\x五次方加一的不定积分.md)''';

    final blocks = await parse(tester, text);
    expect(blocks.length, lessThan(40), reason: '块数 ${blocks.length}');
    expect(blocks.length, greaterThanOrEqualTo(5));
  });
}
