// SVG 读取器测试（v3.2.11）：视口 / 图元 / 样式 / 变换 / 路径 / 文本与容错。
import 'package:flutter_test/flutter_test.dart';

import 'package:dsh_mobile_app/docs/model.dart';
import 'package:dsh_mobile_app/docs/svg.dart';

const String kSvg = '<svg xmlns="http://www.w3.org/2000/svg" width="200" height="100" '
    'viewBox="0 0 200 100">'
    '<rect x="1" y="2" width="30" height="20" fill="#ff0000"/>'
    '<circle cx="50" cy="50" r="10" stroke="blue" stroke-width="2" fill="none"/>'
    '<g transform="translate(10,20)"><path d="M0 0 L10 0 L10 10 Z"/></g>'
    '<text x="5" y="95" font-size="12">hi</text>'
    '</svg>';

void main() {
  group('SVG 读取器', () {
    test('画布 / viewBox / 图元树', () {
      final doc = parseSvg(kSvg, 'icon');
      expect(doc.format, DocFormat.svg);
      final block = doc.blocks.single as DocSvg;
      expect(block.source, contains('<svg'));

      final svg = block.doc;
      expect(svg.width, 200);
      expect(svg.height, 100);
      expect(svg.viewBoxX, 0);
      expect(svg.viewBoxW, 200);
      expect(svg.nodes, hasLength(4));
    });

    test('矩形 / 圆 / 分组变换 / 路径命令 / 文本', () {
      final doc = parseSvg(kSvg, 'icon');
      final svg = (doc.blocks.single as DocSvg).doc;

      final rect = svg.nodes[0] as SvgShape;
      expect(rect.geometry, isA<SvgRect>());
      expect(rect.style.fill, 0xFFFF0000);

      final circle = svg.nodes[1] as SvgShape;
      expect(circle.geometry, isA<SvgCircle>());
      expect(circle.style.stroke, 0xFF0000FF);
      expect(circle.style.fill, isNull);
      expect(circle.style.strokeWidth, 2);

      final group = svg.nodes[2] as SvgGroup;
      expect(group.transform, isNotNull);
      final pathShape = group.children.single as SvgShape;
      final path = pathShape.geometry as SvgPathGeom;
      expect(path.cmds, hasLength(4));
      expect(path.cmds.first, isA<SvgCmdMove>());
      expect(path.cmds.last, isA<SvgCmdClose>());

      final text = svg.nodes[3] as SvgTextNode;
      expect(text.text, 'hi');
      expect(text.fontSize, 12);
    });

    test('相对路径命令折算成绝对坐标', () {
      final cmds = parsePathData('m 1 2 l 3 4 h 5 v 6');
      final move = cmds[0] as SvgCmdMove;
      expect(move.x, 1);
      expect(move.y, 2);
      final line = cmds[1] as SvgCmdLine;
      expect(line.x, 4);
      expect(line.y, 6);
      final h = cmds[2] as SvgCmdLine;
      expect(h.x, 9);
      expect(h.y, 6);
      final v = cmds[3] as SvgCmdLine;
      expect(v.x, 9);
      expect(v.y, 12);
    });

    test('根不是 svg 时提示可读信息；坏 XML 不抛', () {
      final notSvg = parseSvg('<root/>', 'x');
      expect(notSvg.format, DocFormat.svg);
      expect(notSvg.blocks.first, isA<DocPara>());

      final broken = parseSvg('<svg><', 'bad');
      expect(broken.format, DocFormat.svg);
      expect(broken.blocks.whereType<DocCode>(), isNotEmpty);
    });
  });
}
