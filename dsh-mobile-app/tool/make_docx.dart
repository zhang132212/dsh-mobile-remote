// 桌面端 md → docx 转换器。
//
// 为什么放在 App 包内：**直接复用 App 自己的导出器**
// （`lib/docs/markdown.dart` 的解析 + `lib/docs/docx_writer.dart` 的 OMML 写出），
// 保证桌面生成的文件与 App 内「导出 Word」同源，不重复造轮子。
//
// 这两个库只依赖 `package:archive` / `package:xml`，**不依赖 Flutter**，
// 所以可以用纯 `dart run` 在桌面跑。
//
// 用法：
//   dart run tool/make_docx.dart <输入.md> <输出.docx>
import 'dart:io';

import 'package:dsh_mobile_app/docs/docx.dart';
import 'package:dsh_mobile_app/docs/docx_writer.dart';
import 'package:dsh_mobile_app/docs/markdown.dart';
import 'package:dsh_mobile_app/docs/model.dart';

void main(List<String> args) {
  if (args.length < 2) {
    stderr.writeln('用法: dart run tool/make_docx.dart <输入.md> <输出.docx>');
    exit(2);
  }
  final inPath = args[0];
  final outPath = args[1];

  final src = File(inPath);
  if (!src.existsSync()) {
    stderr.writeln('输入不存在：$inPath');
    exit(1);
  }

  final text = src.readAsStringSync();
  // 标题取首个 `# ` 行，退回文件名
  final title = RegExp(r'^#\s+(.+)$', multiLine: true)
          .firstMatch(text)
          ?.group(1)
          ?.trim() ??
      outPath.split(RegExp(r'[\\/]')).last.replaceAll(RegExp(r'\.[^.]+$'), '');

  final doc = parseMarkdown(text, title);
  final bytes = buildDocx(doc, title: title);
  if (bytes.isEmpty) {
    stderr.writeln('生成失败：buildDocx 返回空');
    exit(1);
  }

  File(outPath)
    ..createSync(recursive: true)
    ..writeAsBytesSync(bytes);

  stdout.writeln('已写出 $outPath');
  stdout.writeln('  字节数     : ${bytes.length}');
  stdout.writeln('  块数       : ${doc.blocks.length}');
  stdout.writeln('  显示式公式 : ${doc.blocks.whereType<DocMathBlock>().length}');
  stdout.writeln('  行内公式   : ${doc.blocks.whereType<DocPara>().expand((p) => p.spans).whereType<DocMathInline>().length}');
  stdout.writeln('  解析告警   : ${doc.warnings.isEmpty ? "无" : doc.warnings.join("; ")}');

  // 回读校验：用 App 自己的 .docx 读取器解析刚写出的字节，
  // 确认「导出 → 读回」是闭环（而不是只生成一个能下载、却读不出公式的文件）。
  final back = parseDocx(bytes, outPath);
  final backMath = back.blocks.whereType<DocMathBlock>().length +
      back.blocks
          .whereType<DocPara>()
          .expand((p) => p.spans)
          .whereType<DocMathInline>()
          .length;
  stdout.writeln('  ── 回读校验（App 的 parseDocx）──');
  stdout.writeln('  块数       : ${back.blocks.length}');
  stdout.writeln('  公式       : $backMath 处');
  stdout.writeln('  回读告警   : ${back.warnings.isEmpty ? "无" : back.warnings.join("; ")}');
}
