// DSH Remote — TUI 终端组件库（字符版 · 照搬 @tomowang/dsh-tui 观感）
//
// 与"线条近似版"的区别：这里是**真字符画**——
//   · 方框线用等宽字符 ╭ ─ ╮ │ ╰ ╯ 逐字符绘制（宽度按显示宽度算，中文占 2 列）
//   · 提示符 ❯ / 状态符号 ● ✓ ✗ ✦ / spinner 盲文帧 ⠋⠙⠹…
//   · 键位用 [Enter] 方括号写法，整屏等宽字符网格
// 左右竖线用 1px 容器绘制（与 │ 字符等价观感），避免内容多行时字符无法拉伸。
import 'dart:async';
import 'package:flutter/material.dart';
import 'theme.dart';

/// 终端 spinner 帧（ASCII 四帧：盲文帧在 Android 上缺字，实测退回 ASCII）。
const List<String> kTuiSpinnerFrames = <String>['|', '/', '-', '\\'];

/// 终端提示符。
const String kTuiPrompt = '❯';

/// 显示宽度：CJK / 全角 / emoji 记 2 列，其余 1 列（对齐真终端的 wcwidth）。
int tuiTextWidth(String s) {
  var w = 0;
  for (final r in s.runes) {
    w += _isWide(r) ? 2 : 1;
  }
  return w;
}

bool _isWide(int r) =>
    (r >= 0x1100 && r <= 0x115F) ||
    (r >= 0x2E80 && r <= 0xA4CF) ||
    (r >= 0xAC00 && r <= 0xD7A3) ||
    (r >= 0xF900 && r <= 0xFAFF) ||
    (r >= 0xFE30 && r <= 0xFE6F) ||
    (r >= 0xFF00 && r <= 0xFF60) ||
    (r >= 0xFFE0 && r <= 0xFFE6) ||
    (r >= 0x1F300 && r <= 0x1FAFF);

/// 当前样式下单个等宽字符的像素宽度（用于把容器宽度换算成列数）。
double tuiCharWidth(TextStyle style) {
  final tp = TextPainter(
    text: TextSpan(text: '─' * 20, style: style),
    textDirection: TextDirection.ltr,
  )..layout();
  return tp.width / 20;
}

/// 终端 spinner：单字符原地翻帧。
class TuiSpinner extends StatefulWidget {
  const TuiSpinner({
    super.key,
    this.color,
    this.size = 12,
    this.interval = const Duration(milliseconds: 100),
  });

  final Color? color;
  final double size;
  final Duration interval;

  @override
  State<TuiSpinner> createState() => _TuiSpinnerState();
}

class _TuiSpinnerState extends State<TuiSpinner> {
  Timer? _timer;
  int _i = 0;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(widget.interval, (_) {
      if (mounted) setState(() => _i = (_i + 1) % kTuiSpinnerFrames.length);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      kTuiSpinnerFrames[_i],
      style: TextStyle(
        fontSize: widget.size,
        height: 1.1,
        fontFamily: DshTheme.mono,
        color: widget.color ?? DshColors.cyan(context),
      ),
    );
  }
}

/// 字符方框线容器：
/// ```
/// ╭─ 标题 ──────────────────╮
/// │ 内容                    │
/// ╰─────────────────────────╯
/// ```
/// 顶边/底边逐字符拼出（按可用宽度算列数），左右竖线用 1px 容器。
class TuiFrame extends StatelessWidget {
  const TuiFrame({
    super.key,
    required this.child,
    this.title,
    this.trailing,
    this.accent,
    this.padding = const EdgeInsets.fromLTRB(6, 6, 6, 6),
    this.margin = EdgeInsets.zero,
    this.filled = false,
  });

  final Widget child;
  final String? title;
  final Widget? trailing;
  final Color? accent;
  final EdgeInsets padding;
  final EdgeInsets margin;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final border = accent ?? DshColors.line(context);
    final lineStyle = TextStyle(
      fontFamily: DshTheme.mono,
      fontSize: 12,
      height: 1.0,
      letterSpacing: 0,
      color: border,
    );
    final titleStyle = TextStyle(
      fontFamily: DshTheme.mono,
      fontSize: 11.5,
      height: 1.0,
      letterSpacing: 0,
      fontWeight: FontWeight.w600,
      color: accent ?? DshColors.ink2(context),
    );
    final cw = tuiCharWidth(lineStyle);
    final titleTxt = title ?? '';
    // 顶/底边用「角 + Expanded 横线 + 角」三段拼：横线吃掉剩余空间，
    // 两角永远落在内容区的左右边缘上——比按字符列数硬算更稳（不差半列、不缺封口）。
    Widget topBar() => Row(
          children: [
            Text('╭─', style: lineStyle, maxLines: 1, softWrap: false),
            if (titleTxt.isNotEmpty)
              Text(' $titleTxt ', style: titleStyle, maxLines: 1, softWrap: false),
            Expanded(
              child: Text('─' * 400, style: lineStyle, maxLines: 1, softWrap: false, overflow: TextOverflow.clip),
            ),
            Text('╮', style: lineStyle, maxLines: 1, softWrap: false),
          ],
        );
    Widget bottomBar() => Row(
          children: [
            Text('╰', style: lineStyle, maxLines: 1, softWrap: false),
            Expanded(
              child: Text('─' * 400, style: lineStyle, maxLines: 1, softWrap: false, overflow: TextOverflow.clip),
            ),
            Text('╯', style: lineStyle, maxLines: 1, softWrap: false),
          ],
        );
    return Padding(
      padding: margin,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (trailing == null) topBar() else Stack(children: [topBar(), Positioned(right: 6, child: trailing!)]),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(width: 1, color: border),
                Expanded(
                  child: Container(
                    color: filled ? DshColors.panel(context) : Colors.transparent,
                    padding: padding.add(EdgeInsets.symmetric(horizontal: cw * 0.5)),
                    child: child,
                  ),
                ),
                Container(width: 1, color: border),
              ],
            ),
          ),
          bottomBar(),
        ],
      ),
    );
  }
}

/// 字符分隔行：`──────── 标签 ────────`。
class TuiRule extends StatelessWidget {
  const TuiRule({super.key, this.label, this.color, this.margin = const EdgeInsets.symmetric(vertical: 3)});

  final String? label;
  final Color? color;
  final EdgeInsets margin;

  @override
  Widget build(BuildContext context) {
    final c = color ?? DshColors.line(context);
    final style = TextStyle(fontFamily: DshTheme.mono, fontSize: 11, height: 1.0, letterSpacing: 0, color: c);
    final labelStyle = TextStyle(
      fontFamily: DshTheme.mono,
      fontSize: 10.5,
      height: 1.0,
      letterSpacing: 0,
      color: DshColors.muted(context),
    );
    final lbl = label ?? '';
    return Padding(
      padding: margin,
      child: Row(
        children: [
          Text('─' * 4, style: style, maxLines: 1, softWrap: false),
          if (lbl.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text(lbl, style: labelStyle, maxLines: 1),
            ),
          Expanded(
            child: Text('─' * 200, style: style, maxLines: 1, softWrap: false, overflow: TextOverflow.clip),
          ),
        ],
      ),
    );
  }
}

/// 单行状态栏（dsh-tui status bar 的手机版）：
/// `● 6d7b5a60 · v4-flash · full · running`，运行中把 ● 换成盲文 spinner。
class TuiStatusBar extends StatelessWidget {
  const TuiStatusBar({
    super.key,
    this.onBack,
    required this.sessionCode,
    required this.model,
    this.preset,
    required this.status,
    this.detail,
    this.actions = const [],
  });

  final VoidCallback? onBack;
  final String sessionCode;
  final String model;
  final String? preset;

  /// idle | running | waiting | offline
  final String status;
  final String? detail;
  final List<Widget> actions;

  Color _statusColor(BuildContext c) {
    switch (status) {
      case 'running':
        return DshColors.cyan(c);
      case 'waiting':
        return DshColors.warn(c);
      case 'offline':
        return DshColors.danger(c);
      default:
        return DshColors.ok(c);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dot = _statusColor(context);
    final muted = DshColors.muted(context);
    final ink = DshColors.ink(context);
    TextStyle st(Color c, {double size = 11.5, FontWeight w = FontWeight.w500}) => TextStyle(
          fontFamily: DshTheme.mono,
          fontSize: size,
          height: 1.25,
          letterSpacing: 0,
          fontWeight: w,
          color: c,
        );
    final sep = st(DshColors.line(context));
    return Container(
      padding: const EdgeInsets.fromLTRB(2, 2, 6, 2),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        border: Border(bottom: BorderSide(color: DshColors.line(context))),
      ),
      child: Row(
        children: [
          if (onBack != null)
            IconButton(
              icon: const Icon(Icons.arrow_back, size: 18),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 28),
              onPressed: onBack,
            ),
          if (status == 'running')
            Padding(padding: const EdgeInsets.only(right: 4), child: TuiSpinner(color: dot, size: 12))
          else
            Padding(padding: const EdgeInsets.only(right: 4), child: Text('●', style: st(dot, size: 10))),
          Expanded(
            child: Text.rich(
              TextSpan(children: [
                TextSpan(text: sessionCode, style: st(ink, w: FontWeight.w700)),
                TextSpan(text: ' · ', style: sep),
                TextSpan(text: model, style: st(DshColors.indigo(context))),
                if (preset != null && preset!.isNotEmpty) ...[
                  TextSpan(text: ' · ', style: sep),
                  TextSpan(text: preset!, style: st(muted)),
                ],
                if (detail != null && detail!.isNotEmpty) ...[
                  TextSpan(text: ' · ', style: sep),
                  TextSpan(text: detail!, style: st(dot)),
                ],
              ]),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          ...actions,
        ],
      ),
    );
  }
}

/// 统计行（dsh-tui stats line）：`turn 3 · step 12 · llm 42.1s · ctx 34%`。
class TuiStatsLine extends StatelessWidget {
  const TuiStatsLine({super.key, required this.parts, this.accent});

  final List<String> parts;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    if (parts.isEmpty) return const SizedBox.shrink();
    final style = TextStyle(
      fontFamily: DshTheme.mono,
      fontSize: 10.5,
      height: 1.3,
      letterSpacing: 0,
      color: accent ?? DshColors.muted(context),
    );
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(10, 3, 10, 3),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: DshColors.line(context))),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (var i = 0; i < parts.length; i++) ...[
              if (i > 0)
                Text('  ·  ', style: TextStyle(fontFamily: DshTheme.mono, fontSize: 10.5, color: DshColors.line(context))),
              Text(parts[i], style: style),
            ],
          ],
        ),
      ),
    );
  }
}

/// 终端键位：`[Enter] 发送`（TUI 按键分布落到手机上的触控等价物）。
class TuiKey extends StatelessWidget {
  const TuiKey({
    super.key,
    this.keyLabel,
    required this.label,
    this.icon,
    this.onTap,
    this.onLongPress,
    this.color,
    this.active = false,
  });

  final String? keyLabel;
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Color? color;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final c = color ?? DshColors.ink2(context);
    final enabled = onTap != null || onLongPress != null;
    final keyTxt = keyLabel == null ? '' : '[$keyLabel] ';
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      borderRadius: BorderRadius.circular(2),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
        decoration: BoxDecoration(
          color: active ? DshColors.brandSoft(context) : Colors.transparent,
          border: Border.all(color: enabled ? (active ? c : DshColors.line(context)) : DshColors.line(context)),
          borderRadius: BorderRadius.circular(2),
        ),
        child: Text.rich(
          TextSpan(children: [
            if (keyTxt.isNotEmpty)
              TextSpan(
                text: keyTxt,
                style: TextStyle(
                  fontFamily: DshTheme.mono,
                  fontSize: 10.5,
                  height: 1.2,
                  fontWeight: FontWeight.w700,
                  color: DshColors.ink3(context),
                ),
              ),
            TextSpan(
              text: label,
              style: TextStyle(
                fontFamily: DshTheme.mono,
                fontSize: 11,
                height: 1.2,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                color: enabled ? c : DshColors.ink3(context),
              ),
            ),
          ]),
          maxLines: 1,
        ),
      ),
    );
  }
}

/// 键位条：一排可横滑的终端键位。
class TuiKeyBar extends StatelessWidget {
  const TuiKeyBar({super.key, required this.keys, this.padding = const EdgeInsets.fromLTRB(8, 5, 8, 5)});

  final List<Widget> keys;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: DshColors.line(context)),
          bottom: BorderSide(color: DshColors.line(context)),
        ),
      ),
      padding: padding,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (var i = 0; i < keys.length; i++) ...[
              if (i > 0) const SizedBox(width: 5),
              keys[i],
            ],
          ],
        ),
      ),
    );
  }
}

/// 转录行：可选字符前缀（`✓` / `✗` / `✦` / `❯`）+ 内容。
class TuiLine extends StatelessWidget {
  const TuiLine({
    super.key,
    required this.child,
    this.prefix,
    this.prefixIcon,
    this.prefixColor,
    this.railColor,
    this.crossAxisAlignment = CrossAxisAlignment.start,
  });

  final Widget child;

  /// 字符前缀（TUI 风格优先用字符而非图标）。
  final String? prefix;
  final IconData? prefixIcon;
  final Color? prefixColor;
  final Color? railColor;
  final CrossAxisAlignment crossAxisAlignment;

  @override
  Widget build(BuildContext context) {
    final pc = prefixColor ?? DshColors.muted(context);
    return Row(
      crossAxisAlignment: crossAxisAlignment,
      children: [
        if (prefix != null)
          Padding(
            padding: const EdgeInsets.only(right: 5),
            child: Text(
              prefix!,
              style: TextStyle(
                fontFamily: DshTheme.mono,
                fontSize: 12,
                height: 1.35,
                color: pc,
                fontWeight: FontWeight.w700,
              ),
            ),
          )
        else if (prefixIcon != null)
          Padding(
            padding: const EdgeInsets.only(right: 6, top: 2),
            child: Icon(prefixIcon, size: 13, color: pc),
          ),
        if (railColor != null)
          Container(
            width: 2,
            margin: const EdgeInsets.only(right: 8, top: 2, bottom: 2),
            constraints: const BoxConstraints(minHeight: 14),
            color: railColor,
          ),
        Expanded(child: child),
      ],
    );
  }
}

/// 区块标题（青色单行 + 字符细线）：`▌ 标题 ────────`。
class TuiSectionHeader extends StatelessWidget {
  const TuiSectionHeader({super.key, required this.title, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Text(
            '▌',
            style: TextStyle(fontFamily: DshTheme.mono, fontSize: 11, height: 1.0, color: DshColors.cyan(context)),
          ),
          const SizedBox(width: 4),
          Text(
            title,
            style: TextStyle(
              fontFamily: DshTheme.mono,
              fontSize: 11.5,
              height: 1.2,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
              color: DshColors.cyan(context),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '─' * 200,
              style: TextStyle(fontFamily: DshTheme.mono, fontSize: 11, height: 1.0, color: DshColors.line(context)),
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.clip,
            ),
          ),
          if (trailing != null) Padding(padding: const EdgeInsets.only(left: 6), child: trailing!),
        ],
      ),
    );
  }
}

/// 用户输入回显行：`❯ 原文`（dsh-tui 的转录语法）。
class TuiPromptEcho extends StatelessWidget {
  const TuiPromptEcho({super.key, required this.text, this.images = const []});

  final String text;
  final List<Widget> images;

  @override
  Widget build(BuildContext context) {
    final promptStyle = TextStyle(
      fontFamily: DshTheme.mono,
      fontSize: 13,
      height: 1.5,
      fontWeight: FontWeight.w700,
      color: DshColors.cyan(context),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (images.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(kTuiPrompt, style: promptStyle),
                const SizedBox(width: 6),
                Expanded(child: Wrap(spacing: 6, runSpacing: 6, children: images)),
              ],
            ),
          ),
        if (text.isNotEmpty)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(kTuiPrompt, style: promptStyle),
              const SizedBox(width: 6),
              Expanded(
                child: SelectableText(
                  text,
                  style: TextStyle(
                    fontFamily: DshTheme.mono,
                    fontSize: 13,
                    height: 1.5,
                    fontWeight: FontWeight.w500,
                    color: DshColors.ink(context),
                  ),
                ),
              ),
            ],
          ),
      ],
    );
  }
}
