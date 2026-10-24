// HTML 读取器测试（v3.2.11）：语义映射、行内样式、跳过脚本、容错。
import 'package:flutter_test/flutter_test.dart';

import 'package:dsh_mobile_app/docs/html.dart';
import 'package:dsh_mobile_app/docs/model.dart';

void main() {
  group('HTML 读取器', () {
    test('标题 / 段落 / 行内样式 / 列表 / 表格 / 链接 / 图片', () {
      const html = '<html><head><title>t</title><style>.a{}</style></head>'
          '<body><h1>标题</h1>'
          '<p>hi <b>bold</b> <i>it</i></p>'
          '<ul><li>a</li><li>b</li></ul>'
          '<table><tr><th>x</th></tr><tr><td>y</td></tr></table>'
          '<a href="https://example.com/docs">link</a>'
          '<img src="pic.png" alt="图片">'
          '<script>alert(1)</script>'
          '</body></html>';
      final doc = parseHtml(html, 'page');
      expect(doc.format, DocFormat.html);

      final heading = doc.blocks.whereType<DocHeading>().firstWhere((h) => h.level == 1);
      expect(_textOf(heading.spans), '标题');

      final para = doc.blocks
          .whereType<DocPara>()
          .firstWhere((p) => _textOf(p.spans).startsWith('hi'));
      final bold = para.spans.whereType<DocText>().firstWhere((s) => s.bold);
      expect(bold.text, 'bold');

      final list = doc.blocks.whereType<DocList>().single;
      expect(list.ordered, isFalse);
      expect(list.items, hasLength(2));

      final table = doc.blocks.whereType<DocTable>().single;
      expect(table.headerRow, isTrue);
      expect(table.rows, hasLength(2));

      final link = findInline<DocLink>(doc);
      expect(link, isNotNull);
      expect(link!.url, 'https://example.com/docs');

      final image = findInline<DocImage>(doc);
      expect(image, isNotNull);
      expect(image!.url, 'pic.png');
      expect(image.alt, '图片');

      // script/style 内容不得糊进正文
      final plain = _textOf(doc.blocks.whereType<DocPara>().expand((p) => p.spans).toList());
      expect(plain.contains('alert'), isFalse);
      expect(plain.contains('.a{}'), isFalse);
    });

    test('没有 body 时按全文读；空正文有兜底提示', () {
      final doc = parseHtml('<p>裸片段</p>', 'frag');
      expect(doc.blocks.whereType<DocPara>(), isNotEmpty);
      final empty = parseHtml('<html><body></body></html>', 'empty');
      expect(empty.format, DocFormat.html);
    });

    test('未闭合标签 / 裸 & 不抛异常', () {
      final doc = parseHtml('<div><p>unclosed & raw <b>x', 'broken');
      expect(doc.format, DocFormat.html);
      expect(doc.blocks, isNotEmpty);
    });
  });
}

String _textOf(List<DocInline> spans) {
  final b = StringBuffer();
  for (final s in spans) {
    switch (s) {
      case DocText(:final text):
        b.write(text);
      case DocLink(:final spans):
        b.write(_textOf(spans));
      case DocMathInline(:final tex):
        b.write(tex);
      default:
        break;
    }
  }
  return b.toString();
}

T? findInline<T extends DocInline>(Document doc) {
  for (final b in doc.blocks) {
    final spans = switch (b) {
      DocPara(:final spans) => spans,
      DocHeading(:final spans) => spans,
      DocQuote(:final spans) => spans,
      _ => const <DocInline>[],
    };
    for (final s in spans) {
      if (s is T) return s;
      if (s is DocLink) {
        for (final inner in s.spans) {
          if (inner is T) return inner;
        }
      }
    }
  }
  return null;
}
