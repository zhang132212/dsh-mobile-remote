// JSON 读取器测试（v3.2.11）：类型标注、JSONC 容错、失败兜底。
import 'package:flutter_test/flutter_test.dart';

import 'package:dsh_mobile_app/docs/json.dart';
import 'package:dsh_mobile_app/docs/model.dart';

void main() {
  group('JSON 读取器', () {
    test('对象 / 数组 / 标量按类型标注', () {
      const src = '{"name":"demo","count":3,"ok":true,"nil":null,'
          '"items":[1,"two",{"deep":false}]}';
      final doc = parseJson(src, 'conf');
      expect(doc.format, DocFormat.json);

      final tree = doc.blocks.single as DocTree;
      final root = tree.roots.single;
      expect(root.name, '#document');
      expect(root.kind, 'object');

      final byName = {for (final c in root.children) c.name: c};
      expect(byName['name']!.kind, 'string');
      expect(byName['name']!.text, 'demo');
      expect(byName['count']!.kind, 'number');
      expect(byName['count']!.text, '3');
      expect(byName['ok']!.kind, 'boolean');
      expect(byName['nil']!.kind, 'null');

      final items = byName['items']!;
      expect(items.kind, 'array');
      expect(items.children, hasLength(3));
      expect(items.children[0].kind, 'number');
      expect(items.children[1].kind, 'string');
      expect(items.children[2].kind, 'object');
    });

    test('JSONC：行/块注释与尾逗号容错', () {
      const src = '{\n  // 行注释\n  "a": 1, /* 块注释 */\n  "b": [1, 2,],\n}';
      final doc = parseJson(src, 'jsonc');
      final tree = doc.blocks.single as DocTree;
      final root = tree.roots.single;
      expect(root.children.map((c) => c.name), containsAll(['a', 'b']));
    });

    test('字符串里的 // 与逗号不被误伤', () {
      const src = '{"url":"https://example.com/a,b","tail":"x,}"}';
      final doc = parseJson(src, 'strings');
      final root = (doc.blocks.single as DocTree).roots.single;
      final byName = {for (final c in root.children) c.name: c};
      expect(byName['url']!.text, 'https://example.com/a,b');
      expect(byName['tail']!.text, 'x,}');
    });

    test('解析失败按源码兜底，不抛', () {
      final doc = parseJson('{oops}', 'bad');
      expect(doc.format, DocFormat.json);
      expect(doc.blocks.first, isA<DocPara>());
      expect(doc.blocks.whereType<DocCode>(), isNotEmpty);
    });
  });
}
