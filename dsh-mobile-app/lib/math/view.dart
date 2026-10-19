// 数学公式渲染包装（v3.2.0）。
//
// 渲染引擎用 flutter_math_fork（KaTeX 级排版 + 内置 KaTeX 字体，纯 Dart、
// 不依赖 WebView、不需要联网）——这是本模块唯一引入的渲染类第三方依赖，
// 已做过供应链审计（SHA256 校验 pub.dev 官方哈希 + 危险模式扫描：无网络/无子进程）。
//
// 设计要点：
//  · 解析失败**绝不吞内容**——降级为等宽原文展示，保证「至少可读」；
//  · 颜色/字号跟随 App 主题与**所在文本**（变量/运算符用 c.ink，不写死字号，
//    一律按当前 TextStyle.fontSize 的比例缩放），深浅色都可读；
//  · 显示式公式可横向滚动（长公式在窄屏上不会溢出报错）。
//
// 说明：flutter_math_fork 0.7.4 的 MathOptions 只有**一个** color（分数线、根号线
// 与字形同色），无法逐元素指定；因此统一用 c.ink，深色下不再是黑字。
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
    final c = DshPalette.of(context);
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
          padding: const EdgeInsets.only(left: DshSpace.sm),
          // 编号跟随公式字号按比例缩放（不写死字号）
          child: Text(
            tag!,
            style: style.copyWith(
              color: style.color ?? c.ink3,
              fontSize: _baseSize(style) * _tagScale,
            ),
          ),
        ),
      ],
    );
  }
}

/// 公式基准字号：调用方已给定字号就用它，否则退回 Markdown 正文字号令牌。
double _baseSize(TextStyle style) => style.fontSize ?? DshType.mdBase.fontSize!;

/// 公式编号相对基准字号的缩放比。
const double _tagScale = 0.9;

/// 解析失败降级文案相对基准字号的缩放比。
const double _fallbackScale = 0.92;

class _MathBody extends StatelessWidget {
  final String tex;
  final TextStyle style;
  final bool display;
  const _MathBody({required this.tex, required this.style, required this.display});

  @override
  Widget build(BuildContext context) {
    final c = DshPalette.of(context);
    // 变量/运算符主色：主题 ink；字号跟随所在文本（Math.tex 内部按 fontSize 缩放整套排版）。
    final effective = style.copyWith(
      color: style.color ?? c.ink,
      fontSize: _baseSize(style),
    );
    // 解析失败/排版异常时的降级：原文 + 轻底色，用户仍能读到公式内容
    Widget fallback(FlutterMathException err) => Container(
          padding: const EdgeInsets.symmetric(
            horizontal: DshSpace.xs,
            vertical: DshSpace.xxs,
          ),
          decoration: BoxDecoration(
            color: c.inlineCode,
            borderRadius: DshRadius.rXs,
          ),
          child: Text(
            tex,
            style: effective.copyWith(
              fontFamilyFallback: DshType.monoFallback,
              fontSize: _baseSize(style) * _fallbackScale,
            ),
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
