// docx 读取器测试（v3.2.0）：用 ZipEncoder 现场拼一个最小 docx（不依赖外部样本文件），
// 覆盖契约里的硬需求——正文/run 样式/标题/对齐/列表/超链接/OMML 公式/表格/图片/空段落，
// 以及「坏字节绝不抛异常」的健壮性承诺。
//
// 为什么现场构造而不是塞一个二进制样本：样本没法在 diff 里审阅，而且改一个属性就得
// 重新生成文件；写在测试里能一眼看出「哪个 XML 对应哪条断言」。
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dsh_mobile_app/docs/docx.dart';
import 'package:dsh_mobile_app/docs/model.dart';

// ══════════════════════════════════════════════════════════════════
// 最小 docx 的各个部件
// ══════════════════════════════════════════════════════════════════

const String kWmlNs = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';
const String kMathNs = 'http://schemas.openxmlformats.org/officeDocument/2006/math';
const String kRelNs = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships';

/// 真实 docx 必备的部件表（解析器不读它，但缺了就不是合法的 OOXML 包）。
const String kContentTypes = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
</Types>''';

/// 关系表：rId9 是超链接（Target 就是断言里期望的 URL）。
const String kRels = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId9" Type="$kRelNs/hyperlink" Target="https://example.com/docx" TargetMode="External"/>
  <Relationship Id="rId1" Type="$kRelNs/image" Target="media/image1.png"/>
</Relationships>''';

/// 编号表：numId=1 → ilvl0 是 decimal（有序列表）。
const String kNumbering = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:numbering xmlns:w="$kWmlNs">
  <w:abstractNum w:abstractNumId="7">
    <w:lvl w:ilvl="0"><w:start w:val="1"/><w:numFmt w:val="decimal"/><w:lvlText w:val="%1."/></w:lvl>
  </w:abstractNum>
  <w:num w:numId="1"><w:abstractNumId w:val="7"/></w:num>
</w:numbering>''';

/// 样式表：docDefaults 的正文 11pt（sz=22 半磅）——sizeScale 的分母靠它。
const String kStyles = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:styles xmlns:w="$kWmlNs">
  <w:docDefaults>
    <w:rPrDefault><w:rPr><w:sz w:val="22"/></w:rPr></w:rPrDefault>
  </w:docDefaults>
  <w:style w:type="paragraph" w:styleId="Heading1">
    <w:name w:val="heading 1"/><w:pPr><w:outlineLvl w:val="0"/></w:pPr>
  </w:style>
</w:styles>''';

/// 正文主体：块顺序 = 断言里用的下标顺序（见「块顺序」测试）。
const String kBody = '''
    <w:p>
      <w:r><w:t>开头 </w:t></w:r>
      <w:r><w:rPr><w:b/></w:rPr><w:t xml:space="preserve">粗体 </w:t></w:r>
      <w:r><w:rPr><w:i/><w:u w:val="single"/><w:strike/></w:rPr><w:t>斜体组合</w:t></w:r>
      <w:r><w:rPr><w:color w:val="ff0000"/><w:sz w:val="24"/></w:rPr><w:t>红字</w:t></w:r>
      <w:r><w:rPr><w:vertAlign w:val="superscript"/></w:rPr><w:t>上标</w:t></w:r>
    </w:p>
    <w:p><w:pPr><w:pStyle w:val="Heading1"/></w:pPr><w:r><w:t>第一章</w:t></w:r></w:p>
    <w:p><w:pPr><w:pStyle w:val="Title"/></w:pPr><w:r><w:t>标题样式 Title</w:t></w:r></w:p>
    <w:p><w:pPr><w:jc w:val="center"/></w:pPr><w:r><w:t>居中段落</w:t></w:r></w:p>
    <w:p>
      <w:pPr><w:numPr><w:ilvl w:val="0"/><w:numId w:val="1"/></w:numPr></w:pPr>
      <w:r><w:rPr><w:b/></w:rPr><w:t>第一项</w:t></w:r>
    </w:p>
    <w:p>
      <w:pPr><w:numPr><w:ilvl w:val="0"/><w:numId w:val="1"/></w:numPr></w:pPr>
      <w:r><w:t>第二项</w:t></w:r>
    </w:p>
    <w:p>
      <w:r><w:t>公式 </w:t></w:r>
      <m:oMath><m:f><m:num><m:r><m:t>a</m:t></m:r></m:num><m:den><m:r><m:t>b</m:t></m:r></m:den></m:f></m:oMath>
      <w:r><w:t> 与 </w:t></w:r>
      <w:hyperlink r:id="rId9" w:history="1">
        <w:r><w:rPr><w:u w:val="single"/></w:rPr><w:t>链接文字</w:t></w:r>
      </w:hyperlink>
    </w:p>
    <w:p><m:oMathPara><m:oMath><m:r><m:t>x</m:t></m:r></m:oMath></m:oMathPara></w:p>
    <w:p>
      <w:r><w:t>第一行</w:t></w:r>
      <w:r><w:br/><w:t>换行后</w:t></w:r>
      <w:r><w:tab/><w:t>制表</w:t></w:r>
      <w:r><w:br w:type="page"/><w:t>分页后</w:t></w:r>
      <w:r><w:drawing><wp:inline><wp:docPr id="1" name="图 1" descr="一张示意图"/></wp:inline></w:drawing></w:r>
    </w:p>
    <w:p>
      <w:r><w:t>锚点</w:t></w:r>
      <w:hyperlink w:anchor="sec1"><w:r><w:t>内部跳转文字</w:t></w:r></w:hyperlink>
    </w:p>
    <w:p/>
    <w:p><w:r><w:br/></w:r></w:p>
    <w:p><w:r><w:sym w:font="Wingdings" w:char="F0E0"/><w:instrText>HYPERLINK "x"</w:instrText></w:r></w:p>
    <w:tbl>
      <w:tblPr><w:tblW w:w="0" w:type="auto"/></w:tblPr>
      <w:tr>
        <w:trPr><w:tblHeader/></w:trPr>
        <w:tc><w:tcPr><w:tcW w:w="2000" w:type="dxa"/></w:tcPr><w:p><w:r><w:t>甲</w:t></w:r></w:p></w:tc>
        <w:tc><w:tcPr><w:jc w:val="center"/></w:tcPr><w:p><w:r><w:t>乙</w:t></w:r></w:p></w:tc>
      </w:tr>
      <w:tr>
        <w:tc><w:p><w:r><w:t>丙</w:t></w:r></w:p><w:p><w:r><w:t>丙二</w:t></w:r></w:p></w:tc>
        <w:tc><w:p><w:r><w:t>丁</w:t></w:r></w:p></w:tc>
      </w:tr>
      <w:tr>
        <w:tc><w:tcPr><w:gridSpan w:val="2"/></w:tcPr><w:p><w:r><w:t>跨两列</w:t></w:r></w:p></w:tc>
      </w:tr>
    </w:tbl>
    <w:tbl>
      <w:tr><w:tc><w:p><w:r><w:t>无表头</w:t></w:r></w:p></w:tc></w:tr>
      <w:tr><w:tc><w:p><w:r><w:t>数据</w:t></w:r></w:p></w:tc></w:tr>
    </w:tbl>''';

/// 把若干部件打包成 docx 字节（模拟真实文件的容器结构）。
Uint8List buildDocx(Map<String, String> parts) {
  final archive = Archive();
  for (final entry in parts.entries) {
    final data = Uint8List.fromList(utf8.encode(entry.value));
    archive.addFile(ArchiveFile(entry.key, data.length, data));
  }
  return Uint8List.fromList(ZipEncoder().encode(archive) ?? const <int>[]);
}

/// 拼接 word/document.xml（命名空间声明齐全，贴近 Word 的真实输出）。
String documentXml(String body) => '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document xmlns:w="$kWmlNs" xmlns:m="$kMathNs" xmlns:r="$kRelNs"
    xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing"
    xmlns:v="urn:schemas-microsoft-com:vml">
  <w:body>$body
    <w:sectPr><w:pgSz w:w="11906" w:h="16838"/></w:sectPr>
  </w:body>
</w:document>''';

/// 主样本：齐活的最小 docx。
Uint8List mainDocx() => buildDocx(<String, String>{
      '[Content_Types].xml': kContentTypes,
      'word/document.xml': documentXml(kBody),
      'word/_rels/document.xml.rels': kRels,
      'word/numbering.xml': kNumbering,
      'word/styles.xml': kStyles,
    });

// ── 断言小工具 ────────────────────────────────────────────────────

/// 单元格/片段里的可见文字（DocBreak 等非文本元素跳过）。
String textOf(List<DocInline> spans) {
  final b = StringBuffer();
  for (final s in spans) {
    if (s is DocText) {
      b.write(s.text);
    } else if (s is DocLink) {
      b.write(textOf(s.spans));
    }
  }
  return b.toString();
}

void main() {
  final doc = parseDocx(mainDocx(), '示例.docx');

  group('块顺序与基本结构', () {
    test('w:p / w:tbl 按文档顺序产出，空段落被丢弃', () {
      expect(
        doc.blocks.map((b) => b.runtimeType.toString()).toList(),
        <String>[
          'DocPara', // 混合 run
          'DocHeading', // Heading1
          'DocHeading', // Title
          'DocPara', // 居中
          'DocList', // 两个列表项合并
          'DocPara', // 行内公式 + 超链接
          'DocMathBlock', // oMathPara
          'DocPara', // br / tab / 分页符 / 图片
          'DocPara', // 锚点超链接
          'DocTable', // 3 行（含 tblHeader 与 gridSpan）
          'DocTable', // 无表头
        ],
      );
    });

    test('title 去掉路径与扩展名；format 是 docx', () {
      final d = parseDocx(mainDocx(), r'C:\Users\x\我的 文档.v2.docx');
      expect(d.title, '我的 文档.v2');
      expect(d.format, DocFormat.docx);

      expect(parseDocx(mainDocx(), '').title, '未命名文档');
    });
  });

  group('run 样式', () {
    test('粗体/斜体/下划线/删除线/上标/颜色/字号', () {
      final para = doc.blocks[0] as DocPara;
      final spans = para.spans.whereType<DocText>().toList();

      // 首尾空格必须保留（xml:space="preserve"）
      expect(spans[1].text, '粗体 ');
      expect(spans[1].bold, isTrue);
      expect(spans[1].italic, isFalse);

      expect(spans[2].text, '斜体组合');
      expect(spans[2].italic, isTrue);
      expect(spans[2].underline, isTrue);
      expect(spans[2].strike, isTrue);

      expect(spans[3].colorHex, 'FF0000');
      // sz=24 半磅 = 12pt；正文 11pt（styles.xml docDefaults）→ 12/11
      expect(spans[3].sizeScale, closeTo(12 / 11, 0.001));

      expect(spans[4].superscript, isTrue);
      expect(spans[4].subscript, isFalse);
      // 默认段落的 run 不带字号 → null（渲染层用主题字号）
      expect(spans[0].sizeScale, isNull);
      expect(textOf(para.spans), '开头 粗体 斜体组合红字上标');
    });
  });

  group('标题与对齐', () {
    test('Heading1 → level 1；Title 视为 level 1', () {
      final h1 = doc.blocks[1] as DocHeading;
      expect(h1.level, 1);
      expect(textOf(h1.spans), '第一章');

      final title = doc.blocks[2] as DocHeading;
      expect(title.level, 1);
      expect(textOf(title.spans), '标题样式 Title');
    });

    test('w:jc center → DocPara.align', () {
      expect((doc.blocks[3] as DocPara).align, 'center');
      expect((doc.blocks[0] as DocPara).align, isNull);
    });
  });

  group('列表', () {
    test('连续 numPr 段落合并成一个有序 DocList（numbering.xml 判 decimal）', () {
      final list = doc.blocks[4] as DocList;
      expect(list.ordered, isTrue);
      expect(list.items.length, 2);
      expect(textOf(list.items[0]), '第一项');
      expect(textOf(list.items[1]), '第二项');
      // 列表项内部保留行内样式
      expect((list.items[0].single as DocText).bold, isTrue);
    });

    test('查不到编号定义时退化为无序列表，绝不丢成普通段落', () {
      final bytes = buildDocx(<String, String>{
        'word/document.xml': documentXml('''
    <w:p><w:pPr><w:numPr><w:numId w:val="99"/></w:numPr></w:pPr><w:r><w:t>没定义的编号</w:t></w:r></w:p>'''),
      });
      final d = parseDocx(bytes, 'list.docx');
      expect(d.blocks.single, isA<DocList>());
      expect((d.blocks.single as DocList).ordered, isFalse);
      expect(textOf((d.blocks.single as DocList).items.single), '没定义的编号');
    });
  });

  group('超链接', () {
    test('r:id → rels 的 Target；内部 run 样式照常解析', () {
      final para = doc.blocks[5] as DocPara;
      final link = para.spans.whereType<DocLink>().single;
      expect(link.url, 'https://example.com/docx');
      final inner = link.spans.single as DocText;
      expect(inner.text, '链接文字');
      expect(inner.underline, isTrue);
    });

    test('w:anchor（同文档锚点）→ url 为 null，仍包成 DocLink', () {
      final para = doc.blocks[8] as DocPara;
      final link = para.spans.whereType<DocLink>().single;
      expect(link.url, isNull);
      expect(textOf(link.spans), '内部跳转文字');
    });
  });

  group('公式', () {
    test('m:oMath → 行内公式，且与前后 run 保持顺序', () {
      final para = doc.blocks[5] as DocPara;
      expect(para.spans[0], isA<DocText>());
      expect(para.spans[1], isA<DocMathInline>());
      expect((para.spans[1] as DocMathInline).tex, r'\frac{a}{b}');
      expect((para.spans[2] as DocText).text, ' 与 ');
      expect(para.spans[3], isA<DocLink>());
    });

    test('m:oMathPara → 块级公式，该段不再产出 DocPara', () {
      final math = doc.blocks[6] as DocMathBlock;
      expect(math.tex, 'x');
    });
  });

  group('表格', () {
    test('2×2（+gridSpan 行）：文本/多段 DocBreak/对齐/补空格', () {
      final table = doc.blocks[9] as DocTable;
      expect(table.rows.length, 3);
      expect(table.rows[0].length, 2);

      // 第一行带 w:trPr/w:tblHeader → headerRow
      expect(table.headerRow, isTrue);
      expect(table.rows[0][0].header, isTrue);
      expect(textOf(table.rows[0][0].spans), '甲');
      expect(table.rows[0][1].align, 'center');
      expect(textOf(table.rows[1][1].spans), '丁');

      // 单元格内多段：用 DocBreak 连接
      expect(table.rows[1][0].spans[1], isA<DocBreak>());
      expect(textOf(table.rows[1][0].spans), '丙丙二');

      // gridSpan=2：首格留文本，被覆盖的列补空单元格以保证列对齐
      expect(textOf(table.rows[2][0].spans), '跨两列');
      expect(table.rows[2].length, 2);
      expect(table.rows[2][1].spans, isEmpty);
    });

    test('第一行没有 tblHeader → headerRow 为 false', () {
      final table = doc.blocks[10] as DocTable;
      expect(table.headerRow, isFalse);
      expect(textOf(table.rows[0][0].spans), '无表头');
      expect(textOf(table.rows[1][0].spans), '数据');
    });
  });

  group('换行/制表/图片/忽略项', () {
    test('w:br → DocBreak；w:tab → \\t；分页符与标志性元素被忽略；图片留占位', () {
      final para = doc.blocks[7] as DocPara;
      final breaks = para.spans.whereType<DocBreak>().length;
      // 只有 w:br（无 type）产出换行；w:br w:type="page" 不算
      expect(breaks, 1);

      final text = textOf(para.spans);
      expect(text.contains('\t'), isTrue);
      expect(text.contains('分页后'), isTrue);

      final image = para.spans.whereType<DocImage>().single;
      expect(image.url, isNull);
      expect(image.alt, '一张示意图');
    });

    test('只含 w:sym / w:instrText 的段落不产出空 DocPara', () {
      // 上面 body 里那一段既没有可见文字，也没被解析成块——不崩、不产空行
      expect(doc.blocks.whereType<DocPara>().length, 5);
      expect(doc.warnings, isEmpty);
    });
  });

  group('命名空间与容器兼容', () {
    test('换命名空间前缀（ns0:）照样能读——匹配按 local 名，不假设前缀', () {
      final xml = '<?xml version="1.0"?>'
          '<ns0:document xmlns:ns0="$kWmlNs"><ns0:body>'
          '<ns0:p><ns0:r><ns0:rPr><ns0:b/></ns0:rPr><ns0:t>换前缀也能读</ns0:t></ns0:r></ns0:p>'
          '</ns0:body></ns0:document>';
      final d = parseDocx(buildDocx(<String, String>{'word/document.xml': xml}), 'prefix.docx');
      final span = (d.blocks.single as DocPara).spans.single as DocText;
      expect(span.text, '换前缀也能读');
      expect(span.bold, isTrue);
    });

    test('w:sdt（内容控件）包着的段落不会整块丢掉', () {
      final bytes = buildDocx(<String, String>{
        'word/document.xml': documentXml('''
    <w:sdt><w:sdtPr><w:alias w:val="封面"/></w:sdtPr><w:sdtContent>
      <w:p><w:r><w:t>控件里的段落</w:t></w:r></w:p>
      <w:tbl><w:tr><w:tc><w:p><w:r><w:t>控件里的表格</w:t></w:r></w:p></w:tc></w:tr></w:tbl>
    </w:sdtContent></w:sdt>'''),
      });
      final d = parseDocx(bytes, 'sdt.docx');
      expect(d.blocks.length, 2);
      expect(textOf((d.blocks[0] as DocPara).spans), '控件里的段落');
      expect(textOf((d.blocks[1] as DocTable).rows[0][0].spans), '控件里的表格');
    });

    test('列表定义挂在段落样式上时同样进列表（numPr 继承自 styles.xml）', () {
      final bytes = buildDocx(<String, String>{
        'word/document.xml': documentXml(
            '<w:p><w:pPr><w:pStyle w:val="ListParagraph"/></w:pPr><w:r><w:t>样式带的列表</w:t></w:r></w:p>'),
        'word/numbering.xml': kNumbering,
        'word/styles.xml': '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:styles xmlns:w="$kWmlNs">
  <w:style w:type="paragraph" w:styleId="ListParagraph">
    <w:pPr><w:numPr><w:ilvl w:val="0"/><w:numId w:val="1"/></w:numPr></w:pPr>
  </w:style>
</w:styles>''',
      });
      final d = parseDocx(bytes, 'stylelist.docx');
      final list = d.blocks.single as DocList;
      expect(list.ordered, isTrue);
      expect(textOf(list.items.single), '样式带的列表');
    });
  });

  group('健壮性', () {
    test('空字节 / 纯文本 / 缺 word/document.xml → DocRaw，不抛异常', () {
      final empty = parseDocx(Uint8List(0), '空.docx');
      expect(empty.blocks.single, isA<DocRaw>());
      expect(empty.title, '空');
      expect(empty.warnings, isNotEmpty);

      final plain = parseDocx(Uint8List.fromList(utf8.encode('这不是一个 docx 文件，只是一段文本。')), '假.docx');
      expect(plain.blocks.single, isA<DocRaw>());

      // 合法 zip，但没有 word/document.xml
      final zipNoDoc = buildDocx(<String, String>{'hello.txt': 'hi'});
      final noBody = parseDocx(zipNoDoc, 'a/b/没有正文.docx');
      expect(noBody.blocks.single, isA<DocRaw>());
      expect((noBody.blocks.single as DocRaw).text, contains('word/document.xml'));
      expect(noBody.title, '没有正文');
      expect(noBody.warnings, isNotEmpty);
    });

    test('document.xml 坏 XML / 缺 w:body → DocRaw 降级', () {
      final broken = parseDocx(
        buildDocx(<String, String>{'word/document.xml': '<w:document><w:body>'}),
        '坏xml.docx',
      );
      expect(broken.blocks.single, isA<DocRaw>());

      final noBody = parseDocx(
        buildDocx(<String, String>{'word/document.xml': '<?xml version="1.0"?><w:document xmlns:w="$kWmlNs"/>'}),
        '没有body.docx',
      );
      expect(noBody.blocks.single, isA<DocRaw>());
      expect(noBody.warnings, isNotEmpty);
    });

    test('rels 缺失时超链接仍渲染为文本（url 为 null）', () {
      final bytes = buildDocx(<String, String>{
        'word/document.xml': documentXml(
            '<w:p><w:hyperlink r:id="rId9"><w:r><w:t>没有关系表的链接</w:t></w:r></w:hyperlink></w:p>'),
      });
      final d = parseDocx(bytes, 'nolinks.docx');
      final link = (d.blocks.single as DocPara).spans.whereType<DocLink>().single;
      expect(link.url, isNull);
      expect(textOf(link.spans), '没有关系表的链接');
    });
  });
}
