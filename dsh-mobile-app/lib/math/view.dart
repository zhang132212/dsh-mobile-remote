// 数学公式渲染包装（v3.2.0）。
//
// 渲染引擎用 flutter_math_fork（KaTeX 级排版 + 内置 KaTeX 字体，纯 Dart、
// 不依赖 WebView、不需要联网）——这是本模块唯一引入的渲染类第三方依赖，
// 已做过供应链审计（SHA256 校验 pub.dev 官方哈希 + 危险模式扫描：无网络/无子进程）。
//
// 设计要点：
//  · 解析失败**绝不吞内容**——降级为等宽原文展示，保证「至少可读」；
//  · 颜色/字号跟随 App 主题，深浅色都可读；
//  · 显示式公式可横向滚动（长公式在窄屏上不会溢出报错）。
import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';

import '../theme.dart';

/// 行内公式：随文基线对齐。
class InlineMath extends StatelessWidget {
  final String tex;
  final TextStyle style;
  const InlineMath(this.tex, {super.key, required this.style});

  @override
  Widget build(BuildContext context) => _MathBody(
        tex: tex,
        style: style,
        display: false,
      );
}

/// 独立成行的显示式公式：居中 + 超宽时横向滚动。
class DisplayMath extends StatelessWidget {
  final String tex;
  final TextStyle style;

  /// 公式编号（如 (1)），显示在右侧
  final String? tag;
  const DisplayMath(this.tex, {super.key, required this.style, this.tag});

  @override
  Widget build(BuildContext context) {
    final body = SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: _MathBody(tex: tex, style: style, display: true),
    );
    if (tag == null) {
      return Center(child: body);
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(child: Center(child: body)),
        Padding(
          padding: const EdgeInsets.only(left: 8),
          child: Text(tag!, style: style.copyWith(fontSize: (style.fontSize ?? 15) * 0.9)),
        ),
      ],
    );
  }
}

class _MathBody extends StatelessWidget {
  final String tex;
  final TextStyle style;
  final bool display;
  const _MathBody({required this.tex, required this.style, required this.display});

  @override
  Widget build(BuildContext context) {
    final ink = DshColors.ink(context);
    final effective = style.color == null ? style.copyWith(color: ink) : style;
    // 解析失败/排版异常时的降级：原文 + 轻微底色，用户仍能读到公式内容
    Widget fallback(FlutterMathException err) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
          decoration: BoxDecoration(
            color: DshColors.brandSoft(context),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            tex,
            style: effective.copyWith(fontFamily: 'monospace', fontSize: (effective.fontSize ?? 15) * 0.92),
          ),
        );

    return Math.tex(
      tex,
      mathStyle: display ? MathStyle.display : MathStyle.text,
      textStyle: effective,
      onErrorFallback: fallback,
    );
  }
}
