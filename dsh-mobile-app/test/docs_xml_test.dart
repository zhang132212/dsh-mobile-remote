// XML 读取器测试（v3.2.11）：树形映射、伪节点保留、容错与节点上限。
import 'package:flutter_test/flutter_test.dart';

import 'package:dsh_mobile_app/docs/model.dart';
import 'package:dsh_mobile_app/docs/xml.dart';

void main() {
  group('XML 读取器', () {
    test('声明 / 注释 / 根元素 / 属性 / 子元素 / 文本 / CDATA 都保留', () {
      const xml = '<?xml version="1.0" encoding="UTF-8"?>\n'
          '<!-- top comment -->\n'
          '<root id="1" name="demo">\n'
          '  <child>hello</child>\n'
          '  <cdata><![CDATA[a < b & c]]></cdata>\n'
          '</root>';
      final doc = parseXml(xml, 'sample');
      expect(doc.format, DocFormat.xml);
      expect(doc.title, 'sample');
      expect(doc.warnings, isEmpty);

      final tree = doc.blocks.single as DocTree;
      final names = tree.roots.map((n) => n.name).toList();
      expect(names, containsAll(['#declaration', '#comment', 'root']));

      final root = tree.roots.firstWhere((n) => n.name == 'root');
      expect(root.attrs.map((a) => a.name), containsAll(['id', 'name']));
      expect(root.children, hasLength(2));

      final child = root.children.firstWhere((n) => n.name == 'child');
      expect(child.text, 'hello');
      expect(child.isLeaf, isTrue);

      final cdata = root.children.firstWhere((n) => n.name == 'cdata');
      expect(cdata.text, 'a < b & c');
    });

    test('处理指令按伪节点保留', () {
      const xml = '<?xml version="1.0"?><?xml-stylesheet href="a.xsl"?><r/>';
      final doc = parseXml(xml, 'pi');
      final tree = doc.blocks.single as DocTree;
      expect(tree.roots.any((n) => n.name.startsWith('?xml-stylesheet')), isTrue);
    });

    test('语法错误不抛异常，按源码兜底可读', () {
      final doc = parseXml('<root><unclosed>', 'bad');
      expect(doc.format, DocFormat.xml);
      expect(doc.blocks.first, isA<DocPara>());
      expect(doc.blocks.whereType<DocCode>(), isNotEmpty);
    });

    test('节点上限：超限截断并给出告警', () {
      final b = StringBuffer('<root>');
      for (var i = 0; i < kMaxXmlNodes + 50; i++) {
        b.write('<n/>');
      }
      b.write('</root>');
      final doc = parseXml(b.toString(), 'big');
      expect(doc.warnings, isNotEmpty);
    });
  });
}
