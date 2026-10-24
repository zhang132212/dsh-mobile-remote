// 本轮改动模型的纯函数测试（v3.2.14）——解析容错、行号编号、路径还原。
//
// 这一层刻意用「Host 真实会发什么」的原始 JSON 来测：字段缺失、hunk 行没前缀、
// 二进制/过大、超过 maxFiles 的记录，都不该让页面崩或者显示错行号。
import 'package:flutter_test/flutter_test.dart';

import 'package:dsh_mobile_app/review/model.dart';

void main() {
  test('摘要解析：文件、行数、二进制与过大标记', () {
    final changes = TurnChanges.tryParse({
      'turn': 12,
      'cwd': r'C:\work\demo',
      'files': [
        {'path': r'src\main.dart', 'display': 'src/main.dart', 'added': 12, 'deleted': 3},
        {'path': 'logo.png', 'display': 'logo.png', 'binary': true},
        {'path': 'big.json', 'display': 'big.json', 'oversized': true},
      ],
      'total': 3,
      'added': 12,
      'deleted': 3,
    });

    expect(changes, isNotNull);
    expect(changes!.turn, 12);
    expect(changes.cwd, r'C:\work\demo');
    expect(changes.files.length, 3);
    expect(changes.files[0].added, 12);
    expect(changes.files[0].deleted, 3);
    expect(changes.files[0].countsLabel, '+12 −3');
    expect(changes.files[1].binary, isTrue);
    expect(changes.files[1].countsLabel, '二进制');
    expect(changes.files[2].oversized, isTrue);
    expect(changes.isEmpty, isFalse);
    expect(changes.capped, isFalse);
  });

  test('摘要容错：无效文件记录被跳过，total 缺省时回落到实际条数', () {
    final changes = TurnChanges.tryParse({
      'files': [
        {'no-path': true},
        {'path': 'a.dart', 'display': 'a.dart', 'added': 1},
      ],
    });
    expect(changes!.files.length, 1);
    expect(changes.total, 1);
    expect(TurnChanges.tryParse('nope'), isNull);
    expect(ChangedFile.tryParse(null), isNull);
  });

  test('capped：total 大于已列文件数', () {
    final changes = TurnChanges.tryParse({
      'total': 900,
      'files': [
        {'path': 'a', 'display': 'a'},
      ],
    });
    expect(changes!.capped, isTrue);
  });

  test('diff 解析 + 行号编号（上下文两侧计数、删除只算旧侧、新增只算新侧）', () {
    final diff = FileDiff.tryParse({
      'kind': 'text',
      'path': r'src\main.dart',
      'display': 'src/main.dart',
      'before': true,
      'after': true,
      'hunks': [
        {
          'oldStart': 10,
          'oldLines': 3,
          'newStart': 10,
          'newLines': 4,
          'lines': [' ctx-a', '-old', '+new1', '+new2'],
        },
      ],
    });

    expect(diff, isNotNull);
    expect(diff!.kind, FileDiffKind.text);
    expect(diff.hunks.length, 1);
    expect(diff.hunks.first.header, '@@ -10,3 +10,4 @@');

    final rows = hunkLines(diff.hunks.first);
    expect(rows.length, 4);
    expect((rows[0].kind, rows[0].oldNo, rows[0].newNo), (DiffLineKind.context, 10, 10));
    expect((rows[1].kind, rows[1].oldNo, rows[1].newNo), (DiffLineKind.del, 11, null));
    expect((rows[2].kind, rows[2].oldNo, rows[2].newNo), (DiffLineKind.add, null, 11));
    expect((rows[3].kind, rows[3].oldNo, rows[3].newNo), (DiffLineKind.add, null, 12));
    expect(rows[1].text, 'old');
    expect(rows[1].marker, '−');
    expect(diff.lineDelta, (2, 1));
  });

  test('hunk 行缺前缀时按上下文兜底（旧宿主/被裁剪的数据）', () {
    final hunk = DiffHunk.tryParse({
      'oldStart': 1,
      'oldLines': 2,
      'newStart': 1,
      'newLines': 2,
      'lines': ['plain line', ' another'],
    })!;
    final rows = hunkLines(hunk);
    expect(rows.length, 2);
    expect(rows[0].kind, DiffLineKind.context);
    expect(rows[0].text, 'plain line');
    expect(rows[1].text, 'another');
  });

  test('状态说明：新建 / 删除 / 相同 / 二进制 / 过大 / 超时', () {
    const created = FileDiff(kind: FileDiffKind.text, path: 'a', display: 'a', after: true);
    expect(created.statusNote, '本轮新建文件');
    const removed = FileDiff(kind: FileDiffKind.text, path: 'a', display: 'a', before: true);
    expect(removed.statusNote, '本轮删除文件');
    const same = FileDiff(kind: FileDiffKind.text, path: 'a', display: 'a', before: true, after: true);
    expect(same.identical, isTrue);
    expect(same.statusNote, contains('没有变化'));
    const binary = FileDiff(kind: FileDiffKind.binary, path: 'a', display: 'a');
    expect(binary.statusNote, contains('二进制'));
    const oversized = FileDiff(kind: FileDiffKind.oversized, path: 'a', display: 'a');
    expect(oversized.statusNote, contains('2 MB'));
    const coarse = FileDiff(
      kind: FileDiffKind.text,
      path: 'a',
      display: 'a',
      before: true,
      after: true,
      coarse: true,
      hunks: [DiffHunk(oldStart: 1, oldLines: 1, newStart: 1, newLines: 1, lines: ['-x', '+y'])],
    );
    expect(coarse.statusNote, contains('超时'));
  });

  test('absolutePathOf：相对路径按会话工作目录还原，绝对路径原样保留', () {
    const file = ChangedFile(path: r'src\main.dart', display: 'src/main.dart');
    expect(absolutePathOf(file, r'C:\work\demo'), r'C:\work\demo\src\main.dart');
    expect(absolutePathOf(file, r'C:\work\demo\'), r'C:\work\demo\src\main.dart');
    const abs = ChangedFile(path: r'D:\other\x.txt', display: '../other/x.txt');
    expect(absolutePathOf(abs, r'C:\work\demo'), r'D:\other\x.txt');
    const posixRel = ChangedFile(path: 'src/main.dart', display: 'src/main.dart');
    expect(absolutePathOf(posixRel, '/home/me/demo'), '/home/me/demo/src/main.dart');
    expect(absolutePathOf(posixRel, ''), 'src/main.dart');
  });

  test('行号列宽与行数统计', () {
    final hunks = [
      const DiffHunk(oldStart: 1, oldLines: 2, newStart: 1, newLines: 3, lines: [' a', '+b', '-c']),
      const DiffHunk(oldStart: 1200, oldLines: 1, newStart: 1201, newLines: 1, lines: [' x']),
    ];
    expect(gutterDigits(hunks), 4);
    expect(diffLineCount(hunks), 4);
    expect(gutterDigits(const []), 2);
  });
}
