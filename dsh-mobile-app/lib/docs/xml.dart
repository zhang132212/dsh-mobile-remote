// XML 读取器（v3.2.8）——把 XML 及其方言（xsd / xsl / plist / rss / csproj /
// resx / xaml …）解析成 docs/model.dart 的 DocTree，在阅读页里以**可折叠树**
// 呈现，而不是丢一坨源码让人自己数缩进。
//
// 设计取舍：
//   · 只依赖 `xml` 包（pubspec 已有，docx/xlsx 同款），不引第三方渲染库；
//   · 纯 Dart、不 import Flutter —— 与 docs/ 其余解析器一致，可单测；
//   · 节点数设上限：宁可截断并给出告警，也不把手机内存拖死。
import 'package:xml/xml.dart';

import 'model.dart';

/// 树节点总数上限（达到后不再向下展开）。
const int kMaxXmlNodes = 4000;

/// 单段文本的显示上限（属性值 / 文本节点）。
const int kMaxXmlTextLen = 400;

/// 解析 XML 文本 → Document。**不抛异常**。
Document parseXml(String text, String title) {
  XmlDocument doc;
  try {
    doc = XmlDocument.parse(text);
  } catch (e) {
    // 语法错也不给闭门羹：原文按代码块给出，至少可读、可复制
    return Document(title, DocFormat.xml, [
      DocPara([DocText('XML 解析失败：$e')]),
      DocCode(text, lang: 'xml'),
    ]);
  }

  final counter = _Counter();
  final nodes = <TreeNode>[];

  // 声明、注释、DOCTYPE、处理指令都按顶层伪节点保留 —— 对齐「绝不吞内容」
  final decl = doc.declaration;
  if (decl != null) {
    nodes.add(TreeNode('#declaration', text: _clip(decl.toString())));
  }
  for (final node in doc.children) {
    if (node is XmlElement) {
      nodes.add(_element(node, counter));
    } else if (node is XmlComment) {
      nodes.add(TreeNode('#comment', text: _clip(node.value)));
    } else if (node is XmlProcessing) {
      // package:xml 6.x 的处理指令类型是 XmlProcessing（target + value），
      // 不是 XmlProcessingInstruction。
      nodes.add(TreeNode('?${node.target}', text: _clip(node.value)));
    } else if (node is XmlDoctype) {
      nodes.add(TreeNode('!DOCTYPE', text: _clip(node.toString())));
    }
  }

  if (nodes.isEmpty) {
    return Document(title, DocFormat.xml, const [DocRaw('（XML 里没有可显示的元素）')]);
  }

  final warnings = <String>[];
  if (counter.value >= kMaxXmlNodes) {
    warnings.add('节点过多，仅展开前 $kMaxXmlNodes 个');
  }
  return Document(title, DocFormat.xml, [DocTree(nodes)], warnings: warnings);
}

/// 元素 → 树节点（递归；超上限即止，并留一条说明）。
TreeNode _element(XmlElement el, _Counter counter) {
  counter.value++;
  final attrs = <TreeAttr>[
    for (final a in el.attributes) TreeAttr(a.name.qualified, _clip(a.value)),
  ];

  if (counter.value >= kMaxXmlNodes) {
    return TreeNode(el.name.qualified, attrs: attrs, text: '（已达节点上限，未展开）');
  }

  final children = <TreeNode>[];
  final buf = StringBuffer();
  for (final child in el.children) {
    if (child is XmlElement) {
      children.add(_element(child, counter));
    } else if (child is XmlText) {
      buf.write(child.value);
    } else if (child is XmlCDATA) {
      buf.write(child.value);
    } else if (child is XmlComment) {
      children.add(TreeNode('#comment', text: _clip(child.value)));
    }
  }

  final txt = _collapse(buf.toString());
  return TreeNode(
    el.name.qualified,
    text: txt.isEmpty ? null : _clip(txt),
    attrs: attrs,
    children: children,
  );
}

class _Counter {
  int value = 0;
}

/// 折空白：XML 里为缩进而生的换行/多空格不该在手机上占掉半屏。
String _collapse(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim();

/// 截断超长文本，保留尾部省略号。
String _clip(String s) =>
    s.length <= kMaxXmlTextLen ? s : '${s.substring(0, kMaxXmlTextLen)}…';
