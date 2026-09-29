// DOCX 导出器测试（v3.2.0）：产物必须是结构合法、Word 能打开、公式是原生 OMML。
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xml/xml.dart';

import 'package:dsh_mobile_app/docs/docx_writer.dart';
import 'package:dsh_mobile_app/docs/markdown.dart';
import 'package:dsh_mobile_app/docs/model.dart';
import 'package:dsh_mobile_app/math/tex.dart';

const String kUserExample = r'''$$\boxed{\;\int\frac{dx}{x^5+1}
=\frac15\ln|x+1|+\frac{\ln\left(x^2-\varphi x+1\right)}{10\varphi}
-\frac{\ln\left(x^2-\varphi^{-1}x-1\right)}{10\varphi^{-1}}
-\frac{\varphi^{-1}\sin\frac{2\pi}{5}}{5}\arctan\frac{x-\varphi/2}{\sin\frac{2\pi}{5}}
-\frac{\varphi\sin\frac{\pi}{5}\,}{5}\arctan\frac{x+\frac{1}{2\varphi^{-1}}}{\sin\frac{\pi}{5}}+C\;}$$''';

/// 解包 docx 的某个部件为字符串。
String? part(Uint8List bytes, String path) {
  final a = ZipDecoder().decodeBytes(bytes);
  for (final f in a.files) {
    if (f.name == path) return utf8.decode(f.content as List<int>);
  }
  return null;
}

void main() {
  group('DOCX 导出：结构合法性', () {
    late Uint8List docx;

    setUp(() {
      final doc = Document('测试', DocFormat.markdown, [
        const DocHeading(1, [DocText('标题一')]),
        DocPara([
          const DocText('正文里有'),
          const DocText('粗体', bold: true),
          const DocText('与'),
          const DocText('斜体', italic: true),
          const DocText('，还有链接：'),
          const DocLink([DocText('示例站点')], 'https://example.com/a?b=1&c=2'),
          const DocText('。'),
        ]),
        const DocMathBlock(r'\int_0^1 x^2\,dx = \frac{1}{3}'),
        const DocPara([DocText('行内公式 '), DocMathInline(r'a^2+b^2=c^2'), DocText(' 结束。')]),
        DocList(const [
          [DocText('第一项')],
          [DocText('第二项')],
        ]),
        DocTable(const [
          [DocCell([DocText('列A')], header: true), DocCell([DocText('列B')], header: true)],
          [DocCell([DocText('1')]), DocCell([DocText('2')])],
        ], headerRow: true),
      ]);
      docx = buildDocx(doc);
    });

    test('是合法 zip 且包含全部必需部件', () {
      expect(docx.isNotEmpty, isTrue);
      for (final p in [
        '[Content_Types].xml',
        '_rels/.rels',
        'word/document.xml',
        'word/styles.xml',
        'word/_rels/document.xml.rels',
      ]) {
        expect(part(docx, p), isNotNull, reason: '缺少部件 $p');
      }
    });

    test('所有部件都是良构 XML', () {
      final a = ZipDecoder().decodeBytes(docx);
      for (final f in a.files) {
        final text = utf8.decode(f.content as List<int>);
        expect(() => XmlDocument.parse(text), returnsNormally, reason: '部件 ${f.name} 不是良构 XML');
      }
    });

    test('document.xml 声明了 w / r / m 三个命名空间', () {
      final xml = part(docx, 'word/document.xml')!;
      expect(xml.contains('xmlns:w='), isTrue);
      expect(xml.contains('xmlns:r='), isTrue);
      expect(xml.contains('xmlns:m='), isTrue,
          reason: '缺 xmlns:m 的 OMML 前缀在 Word 里属于命名空间错误');
    });

    test('docx 的每个 r:id 都能在 rels 里找到（否则 Word 报文档损坏）', () {
      final doc = part(docx, 'word/document.xml')!;
      final rels = part(docx, 'word/_rels/document.xml.rels')!;
      final used = RegExp(r'r:id="([^"]+)"').allMatches(doc).map((m) => m.group(1)!).toSet();
      final defined = RegExp(r'Id="([^"]+)"').allMatches(rels).map((m) => m.group(1)!).toSet();
      expect(used.isNotEmpty, isTrue, reason: '样例里应有超链接');
      for (final id in used) {
        expect(defined.contains(id), isTrue, reason: 'r:id=$id 未在 rels 中定义');
      }
    });

    test('超链接以 External 关系 + w:hyperlink 正确写出', () {
      final rels = part(docx, 'word/_rels/document.xml.rels')!;
      expect(rels.contains('TargetMode="External"'), isTrue);
      // & 必须被转义
      expect(rels.contains('b=1&amp;c=2'), isTrue);
      expect(part(docx, 'word/document.xml')!.contains('<w:hyperlink r:id='), isTrue);
    });

    test('公式写成 Word 原生 OMML（不是图片、不是 LaTeX 纯文本）', () {
      final xml = part(docx, 'word/document.xml')!;
      expect(xml.contains('<m:oMath'), isTrue, reason: '必须含 OMML 公式');
      expect(xml.contains('<m:oMathPara>'), isTrue, reason: '显示式公式应包在 oMathPara 里');
      expect(xml.contains('<m:nary>'), isTrue, reason: r'\int 应转成 nary');
      expect(xml.contains('<m:f>'), isTrue, reason: r'\frac 应转成分式');
      expect(xml.contains('m:chr m:val="∫"'), isTrue);
      // 不得回退成纯文本 LaTeX
      expect(xml.contains(r'\frac'), isFalse, reason: '不应残留 LaTeX 源码');
      expect(xml.contains(r'\int'), isFalse);
    });

    test('m:oMathPara 只出现在 w:p 内部（OOXML 结构要求）', () {
      final doc = XmlDocument.parse(part(docx, 'word/document.xml')!);
      for (final para in doc.findAllElements('m:oMathPara')) {
        expect(para.parentElement?.name.local, 'p',
            reason: 'oMathPara 的父元素必须是 w:p');
      }
    });

    test('表格单元格都至少含一个 w:p', () {
      final doc = XmlDocument.parse(part(docx, 'word/document.xml')!);
      // 注意：findAllElements 匹配的是**限定名**（w:tc），这里按 local 名筛
      final tcs = doc.descendantElements.where((e) => e.name.local == 'tc').toList();
      expect(tcs.isNotEmpty, isTrue);
      for (final tc in tcs) {
        expect(tc.childElements.any((e) => e.name.local == 'p'), isTrue);
      }
    });

    test('相邻表格之间有分隔段落（Word 硬要求）', () {
      final xml = part(docx, 'word/document.xml')!;
      // 本样例只有一个表格，验证「表格后必有段落」这一约定
      final idx = xml.lastIndexOf('</w:tbl>');
      expect(idx > 0, isTrue);
      expect(xml.substring(idx).contains('<w:p>'), isTrue);
    });
  });

  group('DOCX 导出：用户实例公式端到端', () {
    test(r'Markdown（含 $$ 公式）→ docx，公式成为可编辑 OMML', () {
      final md = '''
# 一元五次积分

下面这个结果来自部分分式分解：

$kUserExample

其中 \$\\varphi\$ 是黄金比相关的常数。
''';
      final doc = parseMarkdown(md, '积分结果');
      final docx = buildDocx(doc);
      final xml = part(docx, 'word/document.xml')!;

      // 用户的公式必须完整落成 OMML
      expect(xml.contains('<m:borderBox>'), isTrue, reason: r'\boxed 应为可见边框公式');
      expect(xml.contains('<m:nary>'), isTrue);
      expect(xml.contains('<m:f>'), isTrue);
      expect(xml.contains('φ'), isTrue, reason: r'\varphi 应转成 φ 字符');
      expect(xml.contains('arctan'), isTrue);
      expect(xml.contains('ln'), isTrue);
      // 标题写成 Heading 样式（Word 导航窗格里能看到）
      expect(xml.contains('<w:pStyle w:val="Heading1"/>'), isTrue);
      // 圈定的 LaTeX 不应原样残留
      expect(xml.contains(r'\boxed'), isFalse);
      expect(xml.contains(r'\varphi'), isFalse);
    });

    test('导出可被再次解包且各部分 XML 良构（模拟阅读器/Word 打开）', () {
      final doc = parseMarkdown('# T\n\n\$\$x^2\$\$\n', 'T');
      final docx = buildDocx(doc);
      final a = ZipDecoder().decodeBytes(docx);
      expect(a.files.isNotEmpty, isTrue);
      for (final f in a.files) {
        expect(() => XmlDocument.parse(utf8.decode(f.content as List<int>)), returnsNormally);
      }
    });
  });

  group('Markdown / 纯文本读取器', () {
    test('块级元素齐全', () {
      final doc = parseMarkdown('''
# 标题

段落一。

- 项目 A
- 项目 B

> 引用

```dart
var x = 1;
```

| a | b |
|---|---|
| 1 | 2 |

---
''', 'x');
      expect(doc.blocks.whereType<DocHeading>().length, 1);
      expect(doc.blocks.whereType<DocList>().length, 1);
      expect(doc.blocks.whereType<DocQuote>().length, 1);
      expect(doc.blocks.whereType<DocCode>().length, 1);
      expect(doc.blocks.whereType<DocTable>().length, 1);
      expect(doc.blocks.whereType<DocRule>().length, 1);
    });

    test(r'$$ 独占块 → DocMathBlock', () {
      final doc = parseMarkdown('前文\n\n\$\$E=mc^2\$\$\n\n后文', 'x');
      final math = doc.blocks.whereType<DocMathBlock>().toList();
      expect(math.length, 1);
      expect(math.first.tex, 'E=mc^2');
    });

    test(r'行内 $..$ → DocMathInline，且与文字顺序正确', () {
      final doc = parseMarkdown(r'设 $x^2$ 为平方', 'x');
      final para = doc.blocks.whereType<DocPara>().first;
      expect(para.spans.whereType<DocMathInline>().length, 1);
      final first = para.spans.first;
      expect(first is DocText && first.text.contains('设'), isTrue);
    });

    test('纯文本保留换行并识别 URL', () {
      final doc = parsePlainText('第一行\n第二行\n见 https://example.com/x 谢谢', 'x');
      final para = doc.blocks.whereType<DocPara>().first;
      final links = para.spans.whereType<DocLink>().toList();
      expect(links.length, 1);
      expect(links.first.url, 'https://example.com/x');
    });

    test('CSV 自动成表', () {
      final doc = parsePlainText('a,b,c\n1,2,3\n4,5,6', 'x');
      final t = doc.blocks.whereType<DocTable>().toList();
      expect(t.length, 1);
      expect(t.first.rows.length, 3);
    });

    test('中文散文不会被误判成 CSV', () {
      final doc = parsePlainText(
        '这是一段普通的中文说明，里面有逗号，也有顿号、句号。\n'
        '第二行同样是散文，不应该被当成表格，因为列数并不一致。',
        'x',
      );
      expect(doc.blocks.whereType<DocTable>().isEmpty, isTrue);
    });

    test('目录提取', () {
      final doc = parseMarkdown('# 一\n## 二\n正文\n### 三', 'x');
      final outline = outlineOf(doc.blocks);
      expect(outline.length, 3);
      expect(outline[0].$2, '一');
      expect(outline[2].$1, 3);
    });

    test(r'行内代码里的 $$ 不被当成公式（写公式语法说明的高频场景）', () {
      // 回归：此前是先做公式探测再切代码，导致 `$$...$$` 被当显示式公式、
      // 反引号变成字面量。模拟器上肉眼验收时发现并修复。
      final doc = parseMarkdown(r'下面用 `$$...$$` 包裹公式', 'x');
      final para = doc.blocks.whereType<DocPara>().first;
      expect(para.spans.whereType<DocMathInline>().isEmpty, isTrue,
          reason: r'反引号内的 $$ 必须原样当代码，不能进公式渲染');
      final code = para.spans.whereType<DocText>().where((s) => s.code).toList();
      expect(code.length, 1);
      expect(code.first.text, r'$$...$$');
    });

    test(r'行内代码里的单个 $ 同样不触发公式', () {
      final doc = parseMarkdown(r'价格写成 `$5` 到 `$10`', 'x');
      final para = doc.blocks.whereType<DocPara>().first;
      expect(para.spans.whereType<DocMathInline>().isEmpty, isTrue);
    });
  });

  group('公式探测在文档场景下的表现', () {
    test('文档正文里的公式能被探测到', () {
      final segs = findMathSegments(kUserExample);
      expect(segs.length, 1);
      expect(segs.first.tex.length > 100, isTrue);
    });
  });
}
