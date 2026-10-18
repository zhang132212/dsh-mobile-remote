// DSH Remote — TUI 终端皮肤设计令牌
//
// 对齐 @tomowang/dsh-tui 的 tui/theme.ts 调色板与视觉语言：无背景板分层
// （只用前景色 + 细边框）、圆角方框线、等宽字体、直角、无阴影。
// 令牌名（DshTheme / DshColors / DshSwitch）全部保持原样，仅替换数值并新增
// TUI 语义色——全项目 100+ 处引用不必改动。
import 'package:flutter/material.dart';

/// 设计令牌：配色/圆角/字体，浅色（终端白底）深色（终端黑底）两套。
class DshTheme {
  DshTheme._();

  // ── dsh-tui 终端调色板（theme.ts 同名 token）──
  static const primary = Color(0xFF4F6BFE); // DeepSeek Blue — 品牌 / 激活边框
  static const cyan = Color(0xFF38BDF8); // Electric Cyan — 区块标题 / 流式
  static const indigo = Color(0xFF818CF8); // Slate Indigo — 徽章
  static const violet = Color(0xFFA855F7); // Thought Violet — 推理内容
  static const mint = Color(0xFF34D399); // Mint Emerald — 成功
  static const amber = Color(0xFFFBBF24); // Amber Sun — 警告
  static const coral = Color(0xFFF87171); // Coral Red — 错误
  static const slate = Color(0xFF94A3B8); // Slate Gray — 弱化文字

  // 浅色＝终端白底（黑字 + 品牌蓝，户外可读）
  static const bg = Color(0xFFFFFFFF);
  static const surface = Color(0xFFFAFBFC);
  static const ink = Color(0xFF15181E);
  static const ink2 = Color(0xFF4A5568);
  static const ink3 = Color(0xFF8A94A3);
  static const line = Color(0xFFD7DDE5);
  static const brand = primary;
  static const brandSoft = Color(0x1A4F6BFE); // rgba(79,107,254,.10)
  static const ok = Color(0xFF12946A);
  static const warn = Color(0xFFB45309);
  static const danger = Color(0xFFD3382F);

  // 深色＝终端黑底
  static const bgDark = Color(0xFF0A0D12);
  static const surfaceDark = Color(0xFF11151C);
  static const inkDark = Color(0xFFD8DEE8);
  static const ink2Dark = slate;
  static const ink3Dark = Color(0xFF5B6577);
  static const lineDark = Color(0xFF232A36);
  static const brandDark = primary;
  static const brandSoftDark = Color(0x244F6BFE); // rgba(79,107,254,.14)
  static const okDark = mint;
  static const warnDark = amber;
  static const dangerDark = coral;

  // 语义色两套（浅底需压暗才够对比）
  static const cyanLight = Color(0xFF0284C7);
  static const cyanDark = cyan;
  static const violetLight = Color(0xFF7C3AED);
  static const violetDark = violet;
  static const indigoLight = Color(0xFF4F46E5);
  static const indigoDark = indigo;
  static const mutedLight = Color(0xFF64748B);
  static const mutedDark = slate;

  // 圆角：终端方框风（dsh-tui 的 ╭─╮ 只有 1px 弧，手机上留一点触感圆角）
  static const radiusLg = 6.0; // 弹层 / 底部弹窗
  static const radiusMd = 4.0; // 面板 / 卡片
  static const radiusSm = 2.0; // 输入框 / 次级元素

  // 无阴影：终端只用前景色 + 1px 边框分层
  static const shadow = <BoxShadow>[];
  static const shadowDark = <BoxShadow>[];

  // 等宽字体栈——TUI 观感的骨架；中文回落到系统 CJK
  static const mono = 'monospace';
  static const monoFallback = <String>[
    'JetBrains Mono',
    'Cascadia Mono',
    'Consolas',
    'Roboto Mono',
    'Menlo',
    'DejaVu Sans Mono',
  ];
  static const cjkFallback = <String>[
    'Noto Sans Mono CJK SC',
    'Source Han Mono SC',
    'PingFang SC',
    'Microsoft YaHei',
    'sans-serif',
  ];

  static ThemeData light() => _base(Brightness.light);
  static ThemeData dark() => _base(Brightness.dark);

  static ThemeData _base(Brightness b) {
    final dark = b == Brightness.dark;
    final scheme = ColorScheme.fromSeed(
      seedColor: primary,
      brightness: b,
      surface: dark ? surfaceDark : surface,
    );
    return ThemeData(
      useMaterial3: true,
      brightness: b,
      // 全 App 等宽（终端观感）
      fontFamily: mono,
      fontFamilyFallback: const [...monoFallback, ...cjkFallback],
      colorScheme: scheme.copyWith(
        primary: brand,
        onPrimary: Colors.white,
        secondary: dark ? cyan : cyanLight,
        surface: dark ? surfaceDark : surface,
        error: dark ? dangerDark : danger,
      ),
      scaffoldBackgroundColor: dark ? bgDark : bg,
      // 终端没有页面转场（TUI 是原地重绘）：只做极轻淡入，不做滑入位移
      pageTransitionsTheme: const PageTransitionsTheme(builders: {
        TargetPlatform.android: _TuiTransitionsBuilder(),
        TargetPlatform.iOS: _TuiTransitionsBuilder(),
      }),
      appBarTheme: AppBarTheme(
        backgroundColor: dark ? bgDark : bg,
        foregroundColor: dark ? inkDark : ink,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontFamily: mono,
          fontFamilyFallback: const [...monoFallback, ...cjkFallback],
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: dark ? inkDark : ink,
        ),
      ),
      dividerTheme: DividerThemeData(color: dark ? lineDark : line, thickness: 1, space: 1),
      cardTheme: CardThemeData(
        color: dark ? surfaceDark : surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          side: BorderSide(color: dark ? lineDark : line),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: dark ? surfaceDark : ink,
        contentTextStyle: TextStyle(
          color: dark ? inkDark : Colors.white,
          fontSize: 12.5,
          fontFamily: mono,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusSm),
          side: BorderSide(color: dark ? lineDark : line),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: brand,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusSm)),
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, fontFamily: mono),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: brand,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusSm)),
          textStyle: const TextStyle(fontSize: 12.5, fontFamily: mono),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: dark ? ink2Dark : ink2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusSm)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: dark ? surfaceDark : surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          side: BorderSide(color: dark ? lineDark : line),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: dark ? surfaceDark : surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(radiusLg)),
          side: BorderSide(color: dark ? lineDark : line),
        ),
      ),
      listTileTheme: ListTileThemeData(
        dense: true,
        iconColor: dark ? ink2Dark : ink2,
        textColor: dark ? inkDark : ink,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: dark ? surfaceDark : surface,
        isDense: true,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSm),
          borderSide: BorderSide(color: dark ? lineDark : line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSm),
          borderSide: BorderSide(color: dark ? lineDark : line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSm),
          borderSide: const BorderSide(color: primary, width: 1),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        hintStyle: TextStyle(color: dark ? ink3Dark : ink3, fontSize: 13),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: brand,
        thumbColor: brand,
        inactiveTrackColor: dark ? lineDark : line,
      ),
    );
  }
}

/// 终端式转场：无位移，只有极轻淡入（TUI 是原地重绘，不做页面滑入）。
class _TuiTransitionsBuilder extends PageTransitionsBuilder {
  const _TuiTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return FadeTransition(
      opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut).drive(Tween<double>(begin: 0.85, end: 1)),
      child: child,
    );
  }
}

/// 会话内的语义色（对齐 dsh-tui 的 theme.ts 前景令牌）。
class DshColors {
  const DshColors._();
  static bool _dark(BuildContext c) => Theme.of(c).brightness == Brightness.dark;
  static Color ok(BuildContext c) => _dark(c) ? DshTheme.okDark : DshTheme.ok;
  static Color warn(BuildContext c) => _dark(c) ? DshTheme.warnDark : DshTheme.warn;
  static Color danger(BuildContext c) => _dark(c) ? DshTheme.dangerDark : DshTheme.danger;

  /// 输入/消息面板底色——终端里同一块面板只比底色亮一档。
  static Color bubble(BuildContext c) => _dark(c) ? const Color(0xFF141A24) : const Color(0xFFF1F5FB);
  static Color brand(BuildContext c) => DshTheme.primary;
  static Color brandSoft(BuildContext c) => _dark(c) ? DshTheme.brandSoftDark : DshTheme.brandSoft;

  /// 电光青：区块标题 / 流式 / 用户提示符。
  static Color cyan(BuildContext c) => _dark(c) ? DshTheme.cyanDark : DshTheme.cyanLight;

  /// 思考紫：推理内容（独立于正文）。
  static Color violet(BuildContext c) => _dark(c) ? DshTheme.violetDark : DshTheme.violetLight;

  /// 靛蓝：徽章（provider / model / preset）。
  static Color indigo(BuildContext c) => _dark(c) ? DshTheme.indigoDark : DshTheme.indigoLight;

  /// 板岩灰：弱化文字（标签 / 提示 / 时间戳）。
  static Color muted(BuildContext c) => _dark(c) ? DshTheme.mutedDark : DshTheme.mutedLight;
  static Color ink2(BuildContext c) => _dark(c) ? DshTheme.ink2Dark : DshTheme.ink2;
  static Color ink3(BuildContext c) => _dark(c) ? DshTheme.ink3Dark : DshTheme.ink3;
  static Color line(BuildContext c) => _dark(c) ? DshTheme.lineDark : DshTheme.line;
  static Color surface(BuildContext c) => _dark(c) ? DshTheme.surfaceDark : DshTheme.surface;
  static Color ink(BuildContext c) => _dark(c) ? DshTheme.inkDark : DshTheme.ink;

  /// 极淡的"面板底"（TuiFrame 填充用）。
  static Color panel(BuildContext c) => _dark(c) ? const Color(0xFF0E121A) : const Color(0xFFF7F9FB);
}

/// 设置项专用开关：小尺寸胶囊（44×28）+ 品牌蓝/浅灰白色调。
class DshSwitch extends StatelessWidget {
  const DshSwitch({super.key, required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 44,
      height: 28,
      child: FittedBox(
        fit: BoxFit.contain,
        child: Switch(
          value: value,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          activeTrackColor: DshColors.brand(context),
          activeThumbColor: Colors.white,
          inactiveTrackColor:
              Theme.of(context).brightness == Brightness.dark ? const Color(0xFF2A3140) : const Color(0xFFD7DDE5),
          inactiveThumbColor:
              Theme.of(context).brightness == Brightness.dark ? const Color(0xFF8A94A3) : Colors.white,
          onChanged: onChanged,
        ),
      ),
    );
  }
}
