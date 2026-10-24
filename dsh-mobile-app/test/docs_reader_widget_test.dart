// 树形 / SVG 渲染冒烟测试（v3.2.11）：保证新块真的能画出来、能折叠。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dsh_mobile_app/docs/model.dart';
import 'package:dsh_mobile_app/docs/render.dart';

void main() {
  testWidgets('DocTreeView 默认展开两层，可全部折叠 / 展开', (tester) async {
    final roots = <TreeNode>[
      TreeNode('root', kind: 'object', children: [
        TreeNode('a', kind: 'string', text: 'hello'),
        TreeNode('b', kind: 'array', children: [
          TreeNode('0', kind: 'number', text: '1'),
        ]),
      ]),
    ];
    final ctrl = DocTreeController();
    addTearDown(ctrl.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: DocTreeView(roots: roots, ctx: DocRenderCtx(tree: ctrl)),
        ),
      ),
    ));
    expect(find.text('root'), findsOneWidget);
    expect(find.text('a'), findsOneWidget);
    expect(find.text('0'), findsOneWidget);

    ctrl.collapseAll();
    await tester.pump();
    expect(find.text('root'), findsOneWidget);
    expect(find.text('a'), findsNothing);

    ctrl.expandAll();
    await tester.pump();
    expect(find.text('a'), findsOneWidget);
    expect(find.text('0'), findsOneWidget);
  });

  testWidgets('SvgView 渲染 CustomPaint 不抛异常', (tester) async {
    final doc = SvgDoc(
      width: 100,
      height: 50,
      nodes: const [
        SvgShape(SvgRect(0, 0, 100, 50), style: SvgStyle(fill: 0xFF000000)),
        SvgShape(SvgCircle(20, 20, 8), style: SvgStyle(stroke: 0xFFFF0000)),
      ],
    );
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: SvgView(doc: doc, source: '<svg/>', ctx: const DocRenderCtx()),
        ),
      ),
    ));
    await tester.pump();
    expect(find.byType(CustomPaint), findsWidgets);
  });
}
