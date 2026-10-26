// CRLF 回归（v3.2.16）——Windows 上编辑的 md/txt 是 CRLF 换行。
//
// 之前 `# 标题\r` 行尾的 `\r` 让标题 / 列表的正则 `$` 锚点失配，整篇退化成普通段落：
// 用户在手机上看到的是一行行带着 `#`、`-` 的原文，目录也是空的。
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:dsh_mobile_app/docs/loader.dart';
import 'package:dsh_mobile_app/docs/model.dart';

Uint8List bytesOf(String s) => Uint8List.fromList(utf8.encode(s));

void main() {
  test('CRLF 的 Markdown 仍能识别标题与列表', () {
    const crlf = '# 标题\r\n\r\n- 一\r\n- 二\r\n\r\n正文段落。\r\n';
    final doc = loadDocument(bytesOf(crlf), 'crlf.md');
    expect(doc.format, DocFormat.markdown);
    expect(doc.blocks.first, isA<DocHeading>());
    expect(doc.blocks.any((b) => b is DocList), isTrue, reason: '列表不该退化成段落');
    final heading = doc.blocks.first as DocHeading;
    expect(heading.level, 1);
  });

  test('LF 与 CRLF 解析结果一致', () {
    const lf = '# 标题\n\n- 一\n- 二\n\n正文段落。\n';
    const crlf = '# 标题\r\n\r\n- 一\r\n- 二\r\n\r\n正文段落。\r\n';
    final a = loadDocument(bytesOf(lf), 'a.md').blocks.map((b) => b.runtimeType).toList();
    final b = loadDocument(bytesOf(crlf), 'b.md').blocks.map((b) => b.runtimeType).toList();
    expect(b, equals(a));
  });

  test('CRLF 的纯文本不会在行尾留 \\r', () {
    final doc = loadDocument(bytesOf('第一行\r\n第二行\r\n'), 'x.txt');
    expect(doc.format, DocFormat.text);
    final text = doc.blocks.map((b) => b.toString()).join();
    expect(text.contains('\r'), isFalse);
  });
}
