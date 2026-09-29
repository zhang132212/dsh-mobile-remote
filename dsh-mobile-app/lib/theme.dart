// Design tokens adapted from official Harness ui-theme/design-platform.css.
import 'package:flutter/material.dart';

/// 设计令牌：配色/圆角/阴影，浅色深色两套。
class DshTheme {
  DshTheme._();

  // 浅色
  static const bg = Color(0xFFFFFFFF);
  static const surface = Color(0xFFFFFFFF);
  static const ink = Color(0xFF0F1115);
  static const ink2 = Color(0xFF61666B);
  static const ink3 = Color(0xFF81858C);
  static const line = Color(0x1A000000);
  static const brand = Color(0xFF0F1115);
  static const brandSoft = Color(0x0A0F1115); // neutral selection tint
  static const ok = Color(0xFF3BA55D);
  static const warn = Color(0xFFD9730D);
  static const danger = Color(0xFFD44C47);

  // 深色
  static const bgDark = Color(0xFF151517);
  static const surfaceDark = Color(0xFF2C2C2E);
  static const inkDark = Color(0xFFF9FAFB);
  static const ink2Dark = Color(0xFF8B949E);
  static const ink3Dark = Color(0xFF5C6470);
  static const lineDark = Color(0x24FFFFFF);
  static const brandDark = Color(0xFFF9FAFB);
  static const brandSoftDark = Color(0x14FFFFFF); // neutral selection tint
  static const okDark = Color(0xFF4CB86F);
  static const warnDark = Color(0xFFD9A94A); // 深色下略降亮度（v3.0.0 review）
  static const dangerDark = Color(0xFFE0655F);

  // 圆角（v2.7 统一：卡片 14 / 输入框 10 / 胶囊全圆）
  static const radiusLg = 20.0; // 弹层/底部弹窗顶部
  static const radiusMd = 14.0; // 卡片
  static const radiusSm = 10.0; // 输入框/次级元素

  // 轻量阴影：卡片靠"浅底+细边框+极轻投影"分层，不用重阴影（v2.7 弱化）
  static const shadow = [
    BoxShadow(color: Color(0x0A1F2329), blurRadius: 10, offset: Offset(0, 2)),
  ];
  static const shadowDark = [
    BoxShadow(color: Color(0x33000000), blurRadius: 10, offset: Offset(0, 2)),
  ];

  static ThemeData light() => _base(Brightness.light);
  static ThemeData dark() => _base(Brightness.dark);

  static ThemeData _base(Brightness b) {
    final dark = b == Brightness.dark;
    final scheme = ColorScheme.fromSeed(
      seedColor: dark ? brandDark : brand,
      brightness: b,
      surface: dark ? surfaceDark : surface,
    );
    return ThemeData(
      useMaterial3: true,
      brightness: b,
      colorScheme: scheme.copyWith(
        primary: dark ? brandDark : brand,
        onPrimary: dark ? ink : Colors.white,
        secondary: dark ? brandDark : brand,
        surface: dark ? surfaceDark : surface,
        error: dark ? dangerDark : danger,
      ),
      scaffoldBackgroundColor: dark ? bgDark : bg,
      fontFamilyFallback: const ['PingFang SC', 'Microsoft YaHei', 'sans-serif'],
      // v2.7：统一页面转场——轻量 iOS 味（新页全宽滑入 + 轻微淡入，旧页静止不重绘，流畅）
      pageTransitionsTheme: const PageTransitionsTheme(builders: {
        TargetPlatform.android: _IosLightTransitionsBuilder(),
        TargetPlatform.iOS: _IosLightTransitionsBuilder(),
      }),
      appBarTheme: AppBarTheme(
        backgroundColor: dark ? bgDark : bg,
        foregroundColor: dark ? inkDark : ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
      ),
      dividerTheme: DividerThemeData(color: dark ? lineDark : line, thickness: 1),
      cardTheme: CardThemeData(
        color: dark ? surfaceDark : surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusMd)),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: dark ? inkDark : ink,
        contentTextStyle: TextStyle(color: dark ? bgDark : bg, fontSize: 13),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: dark ? brandDark : brand,
          foregroundColor: dark ? ink : Colors.white,
          shape: const StadiumBorder(),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: dark ? surfaceDark : surface,
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
          borderSide: BorderSide(color: dark ? brandDark : brand, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
    );
  }
}

/// 轻量 iOS 味转场：新页全宽滑入 + 轻微淡入；旧页静止（不参与动画 → 零重绘，流畅）。
class _IosLightTransitionsBuilder extends PageTransitionsBuilder {
  const _IosLightTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    return FadeTransition(
      opacity: Tween<double>(begin: 0.7, end: 1.0).animate(curved),
      child: SlideTransition(
        position: Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero).animate(curved),
        child: child,
      ),
    );
  }
}

/// 会话内的语义色（对齐网页端 var(--ok/warn/danger/brand)）。
class DshColors {
  const DshColors._();
  static Color ok(BuildContext c) => Theme.of(c).brightness == Brightness.dark ? DshTheme.okDark : DshTheme.ok;
  // v3.0.0 review：warn 无暗色变体（深色下偏亮）——补 DshTheme.warnDark 分支
  static Color warn(BuildContext c) => Theme.of(c).brightness == Brightness.dark ? DshTheme.warnDark : DshTheme.warn;
  static Color danger(BuildContext c) => Theme.of(c).brightness == Brightness.dark ? DshTheme.dangerDark : DshTheme.danger;
  static Color bubble(BuildContext c) => Theme.of(c).brightness == Brightness.dark ? const Color(0xFF2C2C2E) : const Color(0xFFEDF3FE);
  static Color brand(BuildContext c) => Theme.of(c).colorScheme.primary;
  static Color brandSoft(BuildContext c) => Theme.of(c).brightness == Brightness.dark ? DshTheme.brandSoftDark : DshTheme.brandSoft;
  static Color ink2(BuildContext c) => Theme.of(c).brightness == Brightness.dark ? DshTheme.ink2Dark : DshTheme.ink2;
  static Color ink3(BuildContext c) => Theme.of(c).brightness == Brightness.dark ? DshTheme.ink3Dark : DshTheme.ink3;
  static Color line(BuildContext c) => Theme.of(c).brightness == Brightness.dark ? DshTheme.lineDark : DshTheme.line;
  static Color surface(BuildContext c) => Theme.of(c).brightness == Brightness.dark ? DshTheme.surfaceDark : DshTheme.surface;
  static Color ink(BuildContext c) => Theme.of(c).brightness == Brightness.dark ? DshTheme.inkDark : DshTheme.ink;
}

/// 设置项专用开关：小尺寸胶囊（44×28）+ 品牌蓝/浅灰白色调。
/// Phase 0 收敛：原三处设置开关各自手写同一套 SizedBox+FittedBox+Switch。
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
          // Follow official neutral actions with contrasting foreground in both themes.
          activeTrackColor: DshColors.brand(context),
          activeThumbColor: Theme.of(context).colorScheme.onPrimary,
          inactiveTrackColor:
              Theme.of(context).brightness == Brightness.dark ? const Color(0xFF3C424A) : const Color(0x1A000000),
          inactiveThumbColor:
              Theme.of(context).brightness == Brightness.dark ? const Color(0xFF9AA3AF) : Colors.white,
          onChanged: onChanged,
        ),
      ),
    );
  }
}
