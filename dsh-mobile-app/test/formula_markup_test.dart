// 公式标记规范的可执行版本（docs/formula-markup.md 的测试对应）。
//
// 规范原文见 docs/formula-markup.md；本文件是它的**唯一权威实现说明**——
// 规范改了就改这里，两边不允许漂移。
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xml/xml.dart';

import 'package:dsh_mobile_app/docs/docx_writer.dart';
import 'package:dsh_mobile_app/docs/markdown.dart';
import 'package:dsh_mobile_app/docs/model.dart';
import 'package:dsh_mobile_app/math/omml.dart';
import 'package:dsh_mobile_app/math/tex.dart';

void main() {
  group('规范：定界符识别', () {
    test('行内：夹在正文里 → 行内式', () {
      final segs = findMathSegments(r'黄金比是 /"\varphi=\frac{1+\sqrt5}{2}"/ 这样');
      expect(segs.length, 1);
      expect(segs.first.display, isFalse);
      expect(segs.first.tex, r'\varphi=\frac{1+\sqrt5}{2}');
    });

    test('独占一行 → 显示式', () {
      final segs = findMathSegments('/"E=mc^2"/');
      expect(segs.length, 1);
      expect(segs.first.display, isTrue);
      expect(segs.first.tex, 'E=mc^2');
    });

    test('前后只有空白也算独占一行', () {
      final segs = findMathSegments('   /"a+b"/   ');
      expect(segs.single.display, isTrue);
    });

    test('前后有其它文字 → 行内式', () {
      final segs = findMathSegments('见 /"a+b"/ 式');
      expect(segs.single.display, isFalse);
    });

    test('容错：全角斜杠 ／ + 中文弯引号 “ ”', () {
      final segs = findMathSegments('／“x^2”／');
      expect(segs.length, 1);
      expect(segs.single.tex, 'x^2');
    });

    test('容错：混用半角斜杠与弯引号', () {
      final segs = findMathSegments('/“a_i”/');
      expect(segs.length, 1);
      expect(segs.single.tex, 'a_i');
    });

    test('长公式可跨行（作者换行书写）', () {
      final segs = findMathSegments('/"\\int_0^1 x\\,dx\n= \\frac{1}{2}"/');
      expect(segs.length, 1);
      expect(segs.single.tex.contains(r'\int_0^1'), isTrue);
      expect(segs.single.tex.contains(r'\frac{1}{2}'), isTrue);
    });

    test('空内容不识别（/""/ 就是普通字符）', () {
      expect(findMathSegments('/""/').isEmpty, isTrue);
    });

    test('未闭合不吞内容（漏写闭标记时后面整段必须保留）', () {
      const text = '开头 /"a+b 后面还有很长的正文，绝对不能被当成公式吃掉';
      expect(findMathSegments(text).isEmpty, isTrue);
    });

    test('跨行搜索有上限，避免漏标记时吞掉整篇', () {
      final huge = '/"${'x' * 5000}';
      expect(findMathSegments(huge).isEmpty, isTrue);
    });

    test('普通斜杠与引号不误报', () {
      expect(findMathSegments('路径 C:/Users/Administrator 与 "引号" 都正常').isEmpty, isTrue);
      expect(findMathSegments('http://example.com/a/b').isEmpty, isTrue);
    });
  });

  group('规范：优先级', () {
    test('显式标记优先于 \$...\$（标记内部原样当 TeX）', () {
      final segs = findMathSegments(r'/"$x$ 字面美元"/');
      expect(segs.length, 1);
      expect(segs.single.tex, r'$x$ 字面美元');
    });

    test('标记与 \$\$ 混排时各自独立识别', () {
      final segs = findMathSegments(r'/"a"/ 和 $$b$$');
      expect(segs.length, 2);
      expect(segs[0].tex, 'a');
      expect(segs[0].display, isFalse);
      expect(segs[1].tex, 'b');
      expect(segs[1].display, isTrue);
    });

    test(r'整行标记判定：formulaMarkupWholeLine', () {
      expect(formulaMarkupWholeLine('/"a+b"/'), 'a+b');
      expect(formulaMarkupWholeLine('  /"a+b"/  '), 'a+b');
      expect(formulaMarkupWholeLine('见 /"a+b"/'), isNull);
      expect(formulaMarkupWholeLine('普通文字'), isNull);
      expect(formulaMarkupWholeLine('/"a"/ 后缀'), isNull);
    });
  });

  group('规范：Markdown 渲染', () {
    test('整行标记 → 块级公式（DocMathBlock）', () {
      final doc = parseMarkdown('前文\n\n/"E=mc^2"/\n\n后文', 'x');
      final blocks = doc.blocks.whereType<DocMathBlock>().toList();
      expect(blocks.length, 1);
      expect(blocks.first.tex, 'E=mc^2');
    });

    test('行内标记 → 行内公式（DocMathInline），与文字顺序正确', () {
      final doc = parseMarkdown(r'设 /"\varphi"/ 为黄金比', 'x');
      final para = doc.blocks.whereType<DocPara>().first;
      final maths = para.spans.whereType<DocMathInline>().toList();
      expect(maths.length, 1);
      expect(maths.first.tex, r'\varphi');
      expect(para.spans.first is DocText, isTrue);
    });

    test(r'反引号内的标记不解析（代码优先于公式，写语法说明的常见场景）', () {
      final doc = parseMarkdown(r'写法是 `/"…"/` 这样', 'x');
      final para = doc.blocks.whereType<DocPara>().first;
      expect(para.spans.whereType<DocMathInline>().isEmpty, isTrue);
      final code = para.spans.whereType<DocText>().where((s) => s.code).toList();
      expect(code.length, 1);
    });

    test('围栏代码块内的标记不解析', () {
      final doc = parseMarkdown('```\n/"x^2"/\n```', 'x');
      expect(doc.blocks.whereType<DocCode>().length, 1);
      expect(doc.blocks.whereType<DocMathBlock>().isEmpty, isTrue);
    });
  });

  group('规范：转换为 Word 原生公式（OMML）', () {
    test('标记内容导出为 m:oMath（Alt+= 可编辑）', () {
      final tex = findMathSegments(r'/"\frac{a}{b}"/').single.tex;
      final xml = texToOmmlXml(tex);
      final doc = XmlDocument.parse(xml);
      expect(doc.rootElement.name.local, 'oMath');
      expect(xml.contains('<m:f>'), isTrue);
      expect(xml.contains(r'\frac'), isFalse, reason: '不应残留 LaTeX 源码');
    });

    test('整篇 Markdown（含标记公式）导出 docx：公式落成 OMML', () {
      final md = '''
# 标记测试

行内 /"a^2+b^2=c^2"/ 结束。

/"\\boxed{\\int_0^1 x\\,dx = \\frac{1}{2}}"/>
''';
      final doc = parseMarkdown(md, '标记测试');
      final bytes = buildDocx(doc);
      final body = docxPart(bytes, 'word/document.xml');
      expect(body, isNotNull);
      expect(body!.contains('<m:oMath'), isTrue);
      expect(body.contains('borderBox'), isTrue, reason: r'\boxed 应为可见边框公式');
      expect(body.contains(r'\boxed'), isFalse);
      expect(body.contains(r'\int'), isFalse);
    });

    test(r'行内标记与 $$ 公式产出等价的 OMML 结构', () {
      final viaMarkup = texToOmmlXml(findMathSegments(r'/"\frac{1}{2}"/').single.tex);
      final viaDollar = texToOmmlXml(findMathSegments(r'$\frac{1}{2}$').single.tex);
      expect(viaMarkup, viaDollar);
    });
  });

  group('规范：端到端（用户实例公式用新标记）', () {
    const userFormula = r'\boxed{\;\int\frac{dx}{x^5+1}=\frac15\ln|x+1|'
        r'+\frac{\ln\left(x^2-\varphi x+1\right)}{10\varphi}'
        r'-\frac{\varphi^{-1}\sin\frac{2\pi}{5}}{5}\arctan\frac{x-\varphi/2}{\sin\frac{2\pi}{5}}+C\;}';

    test('用标记包裹后：能识别、能解析、能导出 OMML', () {
      final text = '/"$userFormula"/';
      final segs = findMathSegments(text);
      expect(segs.length, 1);
      expect(segs.single.display, isTrue);

      final el = texToOmmlElement(segs.single.tex);
      expect(el.name.local, 'oMath');
      final xml = el.toXmlString();
      expect(xml.contains('borderBox'), isTrue);
      expect(xml.contains('<m:nary>'), isTrue);
      expect(xml.contains('φ'), isTrue);
      expect(xml.contains('arctan'), isTrue);
    });

    test('OMML 能回读为 TeX（读 docx 时公式仍可渲染）', () {
      final tex = findMathSegments('/"$userFormula"/').single.tex;
      final back = ommlToTex(texToOmmlElement(tex));
      expect(back.contains('φ'), isTrue);
      expect(() => parseTex(back), returnsNormally);
    });
  });
}

/// 从 docx 字节里取某个部件（测试内的 zip 解包样板）。
String? docxPart(Uint8List bytes, String path) {
  final archive = ZipDecoder().decodeBytes(bytes);
  for (final f in archive.files) {
    if (f.name == path) return utf8.decode(f.content as List<int>);
  }
  return null;
}
