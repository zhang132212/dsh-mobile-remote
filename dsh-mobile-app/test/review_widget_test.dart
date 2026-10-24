// 本轮改动 UI 的 widget 测试（v3.2.14）——卡片、diff 渲染、审阅页三段链路。
//
// 这一层要钉住的是「agent 跑完之后用户真的能 review」：卡片给汇总、点开能进审阅、
// 审阅页逐文件出 diff（+/- 标记、两侧行号、新建/删除状态）。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dsh_mobile_app/api.dart';
import 'package:dsh_mobile_app/review/changes_card.dart';
import 'package:dsh_mobile_app/review/changes_screen.dart';
import 'package:dsh_mobile_app/review/diff_view.dart';
import 'package:dsh_mobile_app/review/model.dart';

/// 只覆盖两个改动接口的假客户端：不联网，数据直接给。
class _FakeApi extends Api {
  _FakeApi({this.summary, this.diffs = const {}});

  final TurnChanges? summary;
  final Map<int, FileDiff> diffs;
  int diffCalls = 0;

  @override
  Future<TurnChanges?> changesSummary(String sessionId, int seq) async => summary;

  @override
  Future<FileDiff?> changesDiff(String sessionId, int seq, int index) async {
    diffCalls++;
    return diffs[index];
  }
}

TurnChanges _summaryOf(List<ChangedFile> files, {int? total, int added = 12, int deleted = 3}) => TurnChanges(
      turn: 4,
      cwd: r'C:\work\demo',
      files: files,
      total: total ?? files.length,
      added: added,
      deleted: deleted,
    );

FileDiff _diffOf(ChangedFile file, {bool before = true, bool after = true}) => FileDiff(
      kind: FileDiffKind.text,
      path: file.path,
      display: file.display,
      before: before,
      after: after,
      hunks: const [
        DiffHunk(
          oldStart: 10,
          oldLines: 2,
          newStart: 10,
          newLines: 3,
          lines: [' keep', '-old line', '+new line', '+another'],
        ),
      ],
    );

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('改动卡片：多文件显示总数与逐行列数，超过 4 行可展开', (tester) async {
    final files = [
      for (var i = 0; i < 6; i++)
        ChangedFile(path: 'src/f$i.dart', display: 'src/f$i.dart', added: i + 1, deleted: 1),
    ];
    await tester.pumpWidget(_host(TurnChangesCard(
      sessionId: 's1',
      seq: 21,
      api: Api(),
      loader: () async => _summaryOf(files, added: 21, deleted: 6),
    )));
    await tester.pumpAndSettle();

    expect(find.text('6 个文件'), findsOneWidget);
    expect(find.text('src/f0.dart'), findsOneWidget);
    // 折叠时只画 4 行
    expect(find.text('src/f4.dart'), findsNothing);
    expect(find.text('显示全部 6 个文件'), findsOneWidget);

    await tester.tap(find.text('显示全部 6 个文件'));
    await tester.pumpAndSettle();
    expect(find.text('src/f5.dart'), findsOneWidget);
  });

  testWidgets('改动卡片：单文件写成「已编辑 文件名」且不铺列表', (tester) async {
    final file = ChangedFile(path: 'lib/main.dart', display: 'lib/main.dart', added: 9, deleted: 2);
    await tester.pumpWidget(_host(TurnChangesCard(
      sessionId: 's1',
      seq: 22,
      api: Api(),
      loader: () async => _summaryOf([file], added: 9, deleted: 2),
    )));
    await tester.pumpAndSettle();

    expect(find.text('已编辑 main.dart'), findsOneWidget);
    expect(find.text('lib/main.dart'), findsNothing);
  });

  testWidgets('改动卡片：没有摘要就不占位（空卡片 = 什么都不画）', (tester) async {
    await tester.pumpWidget(_host(TurnChangesCard(
      sessionId: 's1',
      seq: 23,
      api: Api(),
      loader: () async => null,
    )));
    await tester.pumpAndSettle();
    expect(find.textContaining('个文件'), findsNothing);
    expect(find.textContaining('已编辑'), findsNothing);
  });

  testWidgets('diff 渲染：hunk 头、+/- 标记与两侧行号都在', (tester) async {
    final diff = _diffOf(const ChangedFile(path: 'a.dart', display: 'a.dart'));
    await tester.pumpWidget(_host(SingleChildScrollView(child: DiffHunksView(hunks: diff.hunks))));
    await tester.pumpAndSettle();

    expect(find.text('@@ -10,2 +10,3 @@'), findsOneWidget);
    expect(find.text('+'), findsNWidgets(2));
    expect(find.text('−'), findsOneWidget);
    expect(find.text('keep'), findsOneWidget);
    expect(find.text('old line'), findsOneWidget);
    expect(find.text('new line'), findsOneWidget);
    // 旧侧 10/11，新侧 10/11/12
    expect(find.text('10'), findsNWidgets(2));
    expect(find.text('12'), findsOneWidget);
  });

  testWidgets('diff 渲染：超过初始行数给「显示更多」，点了才继续画', (tester) async {
    final lines = <String>[for (var i = 0; i < 600; i++) '+line $i'];
    final hunk = DiffHunk(oldStart: 1, oldLines: 0, newStart: 1, newLines: 600, lines: lines);
    await tester.pumpWidget(_host(SingleChildScrollView(
      child: DiffHunksView(hunks: [hunk], initialLines: 100),
    )));
    await tester.pumpAndSettle();

    expect(find.text('line 0'), findsOneWidget);
    expect(find.text('line 599'), findsNothing);
    expect(find.textContaining('显示更多'), findsOneWidget);

    // 页脚在首屏之外：先滚到可见再点（真实用户也是滑到底才点得到）。
    await tester.ensureVisible(find.textContaining('显示更多'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('显示更多'));
    await tester.pumpAndSettle();
    expect(find.text('line 199'), findsOneWidget);
  });

  testWidgets('审阅页：文件选择器 + 新建文件状态 + 逐行对比', (tester) async {
    final a = ChangedFile(path: 'lib/a.dart', display: 'lib/a.dart', added: 2, deleted: 1);
    final b = ChangedFile(path: 'assets/logo.png', display: 'assets/logo.png', binary: true);
    final api = _FakeApi(
      summary: _summaryOf([a, b], added: 2, deleted: 1),
      diffs: {
        0: _diffOf(a),
        1: const FileDiff(kind: FileDiffKind.binary, path: 'assets/logo.png', display: 'assets/logo.png'),
      },
    );

    await tester.pumpWidget(MaterialApp(
      home: ChangesReviewScreen(sessionId: 's1', seq: 30, turn: 4, api: api),
    ));
    await tester.pumpAndSettle();

    expect(find.text('第 4 轮 · 2 个文件'), findsOneWidget);
    expect(find.text('lib/a.dart'), findsOneWidget);
    expect(find.text('new line'), findsOneWidget);

    // 切到二进制文件：给说明而不是空框
    await tester.tap(find.text('logo.png'));
    await tester.pumpAndSettle();
    expect(find.textContaining('二进制文件'), findsOneWidget); // 只在占位行出现一次
    expect(api.diffCalls, 2);
  });

  testWidgets('审阅页：没有改动时给空状态', (tester) async {
    final api = _FakeApi(summary: const TurnChanges(turn: 4));
    await tester.pumpWidget(MaterialApp(
      home: ChangesReviewScreen(sessionId: 's1', seq: 31, turn: 4, api: api),
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('本轮没有改动文件'), findsOneWidget);
  });
}

