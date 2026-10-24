// JSON 读取器（v3.2.11）——把 JSON / JSONC / GeoJSON 解析成 docs/model.dart 的
// DocTree，在阅读页里以**可折叠树**呈现：对象是分组、数组是子节点列表、标量带
// 类型标签（string / number / boolean / null），一眼能分清「键」和「值」。
//
// 设计取舍：
//   · 只用 dart:convert，不引第三方 JSON 库；
//   · 容错：JSONC（// 与 /* */ 注释、尾逗号）先轻量剥离再解析——编辑器里拷出来的
//     配置片段也能直接看；解析失败按源码兜底，绝不给闭门羹；
//   · 节点数 / 文本长度上限与 XML 一致，避免超大文件拖死手机。
import 'dart:convert';

import 'model.dart';

/// 树节点总数上限（达到后不再向下展开）。
const int kMaxJsonNodes = 4000;

/// 单段文本的显示上限（键名 / 标量值）。
const int kMaxJsonTextLen = 400;

/// 解析 JSON 文本 → Document。**不抛异常**。
Document parseJson(String text, String title) {
  Object? value;
  try {
    value = jsonDecode(_stripJsonc(text));
  } catch (e) {
    return Document(title, DocFormat.json, [
      DocPara([DocText('JSON 解析失败：$e')]),
      DocCode(text, lang: 'json'),
    ]);
  }

  final counter = _Counter();
  final roots = <TreeNode>[_node('#document', value, counter)];
  final warnings = <String>[];
  if (counter.value >= kMaxJsonNodes) {
    warnings.add('节点过多，仅展开前 $kMaxJsonNodes 个');
  }
  return Document(title, DocFormat.json, [DocTree(roots)], warnings: warnings);
}

TreeNode _node(String name, Object? value, _Counter counter) {
  counter.value++;
  if (counter.value >= kMaxJsonNodes) {
    return TreeNode(name, kind: _kindOf(value), text: '（已达节点上限，未展开）');
  }
  if (value is Map) {
    final children = <TreeNode>[];
    for (final entry in value.entries) {
      if (counter.value >= kMaxJsonNodes) break;
      children.add(_node(_clip('${entry.key}'), entry.value, counter));
    }
    return TreeNode(name, kind: 'object', children: children);
  }
  if (value is List) {
    final children = <TreeNode>[];
    for (var i = 0; i < value.length; i++) {
      if (counter.value >= kMaxJsonNodes) break;
      children.add(_node('$i', value[i], counter));
    }
    return TreeNode(name, kind: 'array', children: children);
  }
  return TreeNode(name, kind: _kindOf(value), text: _scalar(value));
}

String _kindOf(Object? value) {
  if (value is Map) return 'object';
  if (value is List) return 'array';
  if (value is String) return 'string';
  if (value is num) return 'number';
  if (value is bool) return 'boolean';
  return 'null';
}

String _scalar(Object? value) {
  if (value == null) return 'null';
  if (value is String) return _clip(value);
  return _clip(value.toString());
}

String _clip(String s) =>
    s.length <= kMaxJsonTextLen ? s : '${s.substring(0, kMaxJsonTextLen)}…';

class _Counter {
  int value = 0;
}

/// 去掉 JSONC 的注释与尾逗号（字符串里的 // 与 , 不动）。
///
/// 只做**词法层**的轻量剥离：状态机扫描一遍，不解析结构——即便文件本身
/// 有语法错，这里也不会误伤；真正的合法性交给 jsonDecode 裁决。
String _stripJsonc(String input) {
  final out = StringBuffer();
  var inString = false;
  var escaped = false;
  const backslash = 0x5C; // '\\'
  for (var i = 0; i < input.length; i++) {
    final ch = input[i];
    if (inString) {
      out.write(ch);
      if (escaped) {
        escaped = false;
      } else if (ch.codeUnitAt(0) == backslash) {
        escaped = true;
      } else if (ch == '"') {
        inString = false;
      }
      continue;
    }
    if (ch == '"') {
      inString = true;
      out.write(ch);
      continue;
    }
    if (ch == '/' && i + 1 < input.length) {
      final next = input[i + 1];
      if (next == '/') {
        while (i < input.length && input[i] != '\n') {
          i++;
        }
        out.write('\n');
        continue;
      }
      if (next == '*') {
        i += 2;
        while (i + 1 < input.length && !(input[i] == '*' && input[i + 1] == '/')) {
          i++;
        }
        i++;
        continue;
      }
    }
    // 尾逗号：逗号后（跳过空白）紧跟 } 或 ] 时丢弃——避免 jsonDecode 报错。
    if (ch == ',') {
      var j = i + 1;
      while (j < input.length && ' \t\n\r'.contains(input[j])) {
        j++;
      }
      if (j < input.length && (input[j] == '}' || input[j] == ']')) continue;
    }
    out.write(ch);
  }
  return out.toString();
}
