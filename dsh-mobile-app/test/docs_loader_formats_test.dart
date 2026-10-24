// 文档加载器格式分派测试（v3.2.11）：扩展名 / 内容嗅探 / 新格式落点。
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:dsh_mobile_app/docs/loader.dart';
import 'package:dsh_mobile_app/docs/model.dart';

Uint8List bytesOf(String s) => Uint8List.fromList(utf8.encode(s));

const String kSvg = '<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10">'
    '<rect width="10" height="10"/></svg>';

void main() {
  group('格式识别', () {
    test('扩展名 → DocFormat', () {
      expect(detectFormat('a.json'), DocFormat.json);
      expect(detectFormat('a.jsonc'), DocFormat.json);
      expect(detectFormat('a.geojson'), DocFormat.json);
      expect(detectFormat('a.xml'), DocFormat.xml);
      expect(detectFormat('a.xsd'), DocFormat.xml);
      expect(detectFormat('a.html'), DocFormat.html);
      expect(detectFormat('a.htm'), DocFormat.html);
      expect(detectFormat('a.svg'), DocFormat.svg);
    });

    test('可读格式清单包含新扩展名', () {
      expect(kReadableExtensions, containsAll(['json', 'xml', 'html', 'svg']));
      expect(isReadableFormat('readme.json'), isTrue);
      expect(isReadableFormat('pic.png'), isFalse);
    });
  });

  group('loadDocument 分派', () {
    test('json / xml / html / svg 各自落到对应解析器', () {
      expect(loadDocument(bytesOf('{"a":1}'), 'a.json').format, DocFormat.json);
      expect(loadDocument(bytesOf('<r a="1"/>'), 'a.xml').format, DocFormat.xml);
      expect(loadDocument(bytesOf('<h1>x</h1>'), 'a.html').format, DocFormat.html);
      expect(loadDocument(bytesOf(kSvg), 'a.svg').format, DocFormat.svg);
    });

    test('无扩展名按内容嗅探（配置片段 / 抓下来的页面也能打开）', () {
      expect(loadDocument(bytesOf('{"a":1}'), 'blob').format, DocFormat.json);
      expect(loadDocument(bytesOf('[1,2,3]'), 'blob').format, DocFormat.json);
      expect(loadDocument(bytesOf('<!doctype html><html><body>x</body></html>'), 'blob').format,
          DocFormat.html);
      expect(loadDocument(bytesOf(kSvg), 'blob').format, DocFormat.svg);
      expect(loadDocument(bytesOf('<?xml version="1.0"?><r/>'), 'blob').format, DocFormat.xml);
      expect(loadDocument(bytesOf('# 标题'), 'blob').format, DocFormat.text);
    });

    test('树 / 图形块落在模型层', () {
      final jsonDoc = loadDocument(bytesOf('{"a":1}'), 'x.json');
      expect(jsonDoc.blocks.whereType<DocTree>(), isNotEmpty);
      expect(documentHasTree(jsonDoc), isTrue);

      final svgDoc = loadDocument(bytesOf(kSvg), 'x.svg');
      expect(svgDoc.blocks.whereType<DocSvg>(), isNotEmpty);
      expect(documentHasTree(svgDoc), isFalse);
    });

    test('空文件 / 不支持格式给可读提示，不抛', () {
      expect(loadDocument(Uint8List(0), 'a.json').format, DocFormat.unknown);
      final bin = Uint8List.fromList([0, 1, 2, 3, 4]);
      expect(loadDocument(bin, 'a.bin').format, DocFormat.unknown);
    });
  });
}
