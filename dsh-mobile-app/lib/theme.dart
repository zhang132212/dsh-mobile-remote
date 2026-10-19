// DSH 设计令牌层 —— 与官方 DeepSeek Harness Web 客户端同源。
//
// 数值直接取自官方 `packages/client/ui-theme/src/styles/`：
//   design-platform.css  静态调色板 + 语义 alias（--dsw-alias-*）
//   gradient-shadow-text.css  字体阶梯、阴影/高度（--dsw-font-*、--dsw-shadow-*）
//   base.css  圆角阶梯（--dsw-radius-*）、字体族、动效曲线
// 参考文档：docs/ui-radius.md（圆角规范）、docs/web-styling.md（样式归属）。
//
// 约定：页面只消费 [DshColors] / [DshType] / [DshRadius] / [DshSpace] /
// [DshShadow] 这些语义令牌，不再写死颜色或字号。
import 'package:flutter/material.dart';

/// 语义色令牌：按当前亮/暗主题解析。
///
/// 命名与官方 `--dsw-alias-*` 一一对应，括号内是官方变量名。
class DshPalette {
  const DshPalette._(this._dark);

  final bool _dark;

  /// 从 context 解析（页面统一入口）。
  factory DshPalette.of(BuildContext context) =>
      DshPalette._(Theme.of(context).brightness == Brightness.dark);

  /// 当前是否暗色。
  bool get isDark => _dark;

  // ---------- 背景层 ----------

  /// 页面底色（--dsw-alias-bg-base）
  Color get bg => _dark ? const Color(0xFF151517) : const Color(0xFFFFFFFF);

  /// 卡片/浮层填充 L1（--dsw-alias-bg-layer-1）
  Color get layer1 => _dark ? const Color(0xFF232324) : const Color(0xFFFFFFFF);

  /// 卡片/浮层填充 L2 = 设置卡片默认填充（--dsw-alias-bg-layer-2）
  Color get layer2 => _dark ? const Color(0xFF2C2C2E) : const Color(0xFFFFFFFF);

  /// 卡片/浮层填充 L3（--dsw-alias-bg-layer-3）
  Color get layer3 => _dark ? const Color(0xFF353638) : const Color(0xFFFFFFFF);

  /// 侧栏/会话列表底色（--dsw-specific-sidebar-fill）
  Color get sidebar => _dark ? const Color(0xFF1B1B1C) : const Color(0xFFF9FAFB);

  /// 模块/次级区块填充（--dsw-alias-bg-module-platform）
  Color get module => _dark ? const Color(0xFF353638) : const Color(0xFFF5F6F7);

  /// 文档预览底色（--dsw-alias-bg-document-preview）
  Color get docPreview => _dark ? const Color(0xFF151517) : const Color(0xFFEBEEF2);

  /// 骨架屏（--dsw-alias-bg-skeleton）
  Color get skeleton =>
      _dark ? const Color(0x14FFFFFF) : const Color(0x0A000000);

  /// 模态遮罩（--dsw-alias-bg-mask-1）
  Color get mask => _dark ? const Color(0x80000000) : const Color(0x3D000000);

  // ---------- 文字 ----------

  /// 主文字（--dsw-alias-label-primary）
  Color get ink => _dark ? const Color(0xFFF9FAFB) : const Color(0xFF0F1115);

  /// 次级文字（--dsw-alias-label-secondary）
  Color get ink2 => _dark ? const Color(0xFFCFD3D6) : const Color(0xFF61666B);

  /// 三级文字（--dsw-alias-label-tertiary）
  Color get ink3 => _dark ? const Color(0xFFADB2B8) : const Color(0xFF81858C);

  /// 说明文字（--dsw-alias-label-caption）
  Color get caption => _dark ? const Color(0xFF81858C) : const Color(0xFFADB2B8);

  /// 极淡文字/占位（--dsw-alias-label-dimmed）
  Color get dimmed => _dark ? const Color(0xFF43454A) : const Color(0xFFE1E5EE);

  /// 反色主文字（--dsw-alias-label-primary-foreground）
  Color get onInk => _dark ? const Color(0xFF0F1115) : const Color(0xFFFFFFFF);

  // ---------- 描边 ----------

  /// 极淡分隔（--dsw-alias-border-l1）
  Color get line1 => _dark ? const Color(0x0FFFFFFF) : const Color(0x0A000000);

  /// 常规分隔线（--dsw-alias-border-l2）
  Color get line2 => _dark ? const Color(0x1FFFFFFF) : const Color(0x1A000000);

  /// 稍强描边（--dsw-alias-border-l3）
  Color get line3 => _dark ? const Color(0x29FFFFFF) : const Color(0x1F000000);

  /// 卡片/输入框描边（--dsw-alias-border-l4）
  Color get line4 => _dark ? const Color(0x33FFFFFF) : const Color(0x29000000);

  // ---------- 品牌与状态 ----------

  /// 主操作填充（--dsw-alias-brand-primary：浅色近黑，深色近白）
  Color get brand => _dark ? const Color(0xFFF9FAFB) : const Color(0xFF0F1115);

  /// 主操作 hover（--dsw-alias-button-primary-hover）
  Color get brandHover => _dark ? const Color(0xFFEBEEF2) : const Color(0xFF43454A);

  /// 品牌文字色（--dsw-alias-brand-text）
  Color get brandText => _dark ? const Color(0xFFF9FAFB) : const Color(0xFF0F1115);

  /// 品牌浅底（选中态淡染）
  Color get brandSoft =>
      _dark ? const Color(0x14FFFFFF) : const Color(0x0A0F1115);

  /// 链接/业务蓝（--dsw-alias-link）
  Color get link => _dark ? const Color(0xFF7AAAFF) : const Color(0xFF4176E6);

  /// 业务主色（--dsw-alias-state-business-primary）
  Color get business =>
      _dark ? const Color(0xFF7AAAFF) : const Color(0xFF4176E6);

  /// 成功（--dsw-alias-state-success-primary）
  Color get ok => const Color(0xFF22C55E);

  /// 警告（--dsw-alias-state-warn-primary）
  Color get warn =>
      _dark ? const Color(0xFFF7AD31) : const Color(0xFFF59E0B);

  /// 警告文字（--dsw-alias-state-warn-label）
  Color get warnLabel => const Color(0xFFDD8629);

  /// 错误（--dsw-alias-state-error-primary）
  Color get danger =>
      _dark ? const Color(0xFFF25A5A) : const Color(0xFFEC1313);

  /// 空闲/未激活（--dsw-alias-state-idle-primary）
  Color get idle => _dark ? const Color(0xFF545557) : const Color(0xFFD4D4D4);

  /// 成功浅底（--dsw-alias-state-success-tertiary）
  Color get okSoft => _dark ? const Color(0xFF233C2C) : const Color(0xFFE6FAED);

  /// 错误浅底
  Color get dangerSoft =>
      _dark ? const Color(0xFF3C1F1B) : const Color(0xFFFEF2F2);

  /// 警告浅底（--dsw-alias-state-warn-tertiary）
  Color get warnSoft => _dark ? const Color(0xFF27241F) : const Color(0xFFFEF5E7);

  // ---------- 交互态 ----------

  /// hover 叠加（--dsw-alias-interactive-bg-hover）
  Color get hover =>
      _dark ? const Color(0x14FFFFFF) : const Color(0x0F263148);

  /// 按下/选中叠加（--dsw-alias-interactive-bg-active）
  Color get active =>
      _dark ? const Color(0x24FFFFFF) : const Color(0x1A263148);

  /// 实底 hover（--dsw-alias-interactive-bg-hover-solid）
  Color get hoverSolid =>
      _dark ? const Color(0xFF353638) : const Color(0xFFF1F3F5);

  /// 导航项选中底（--dsw-specific-sidebar-nav-item-active）
  Color get navActive =>
      _dark ? const Color(0xFF43454A) : const Color(0xFFEBEEF2);

  /// 导航项 hover 底（--dsw-specific-sidebar-nav-item-hover）
  Color get navHover =>
      _dark ? const Color(0xFF2C2C2E) : const Color(0xFFF1F3F5);

  /// 导航项选中强调底（--dsw-specific-sidebar-nav-item-active-accent）
  Color get navAccent =>
      _dark ? const Color(0xFF353638) : const Color(0xFFE4EDFD);

  // ---------- 组件面 ----------

  /// 输入框主面（--dsw-specific-input-major）
  Color get input => _dark ? const Color(0xFF2C2C2E) : const Color(0xFFFFFFFF);

  /// 选择器胶囊底（--dsw-specific-selector）
  Color get selector => _dark ? const Color(0xFF353638) : const Color(0xFFF5F6F7);

  /// 用户气泡（--dsw-specific-bubble）
  Color get bubble => _dark ? const Color(0xFF2C2C2E) : const Color(0xFFEDF3FE);

  /// 用户气泡强调（--dsw-specific-bubble-highlight）
  Color get bubbleStrong =>
      _dark ? const Color(0xFF43454A) : const Color(0xFFD3E2FF);

  /// 代码块底（--dsw-alias-markdown-code-block）
  Color get codeBlock =>
      _dark ? const Color(0xFF1B1B1C) : const Color(0xFFF9FAFB);

  /// 代码块标题条（--dsw-alias-markdown-code-block-banner）
  Color get codeBanner =>
      _dark ? const Color(0xFF2C2C2E) : const Color(0xFFF9FAFB);

  /// 行内代码底（--dsw-alias-markdown-inline-code）
  Color get inlineCode =>
      _dark ? const Color(0xFF292929) : const Color(0xFFFAFAFA);

  /// 标签底（--dsw-alias-markdown-tag）
  Color get tag => _dark ? const Color(0xFF2C2C2E) : const Color(0xFFF1F3F5);

  /// Toast 底（--dsw-alias-toast-bg）
  Color get toast => _dark ? const Color(0xFF43454A) : const Color(0xFF353638);

  /// Toast 文字（--dsw-alias-toast-label）
  Color get onToast => const Color(0xFFFFFFFF);

  /// Tooltip/浮层深底（--dsw-alias-tooltip-bg）
  Color get tooltip => _dark ? const Color(0xFF43454A) : const Color(0xFF2C2C2E);

  /// 浮动按钮底（--dsw-alias-button-floating-fill）
  Color get floating =>
      _dark ? const Color(0xFF2C2C2E) : const Color(0xFFFFFFFF);

  /// 滚动条（--dsw-alias-scrollbar-bg-l2）
  Color get scrollbar =>
      _dark ? const Color(0xFF545557) : const Color(0xFFE5E5E5);

  // ---------- TUI 终端皮肤遗留令牌 ----------
  //
  // 这几个只服务于 `lib/tui.dart`（发行线 v3.2.5 那套 dsh-tui 皮肤控件库）。
  // 默认界面已改用官方 Web 令牌，保留取值只为让那套控件仍能编译、日后若要接成
  // 独立入口时不必再找回色值。数值沿用发行线定义，未做改动。

  /// Electric Cyan —— 区块标题 / 流式（tui.dart）
  Color get cyan => _dark ? const Color(0xFF38BDF8) : const Color(0xFF0284C7);

  /// Slate Indigo —— 徽章（tui.dart）
  Color get indigo => _dark ? const Color(0xFF818CF8) : const Color(0xFF4F46E5);

  /// 弱化文字（tui.dart）
  Color get muted => _dark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

  /// 终端面板底（tui.dart）
  Color get panel =>
      _dark ? const Color(0xFF0E121A) : const Color(0xFFF7F9FB);

  /// 代码 diff 新增底（--dsw-alias-file-diff-added-bg）
  Color get diffAdded =>
      _dark ? const Color(0xFF1F3124) : const Color(0xFFE6F4E7);

  /// 代码 diff 删除底（--dsw-alias-file-diff-deleted-bg）
  Color get diffDeleted =>
      _dark ? const Color(0xFF3C1F1B) : const Color(0xFFFCE6E2);

  // ---------- 兼容旧调用点的别名 ----------

  /// 页面底色。
  Color get surface => bg;

  /// 卡片填充。
  Color get card => layer2;
}

/// 圆角阶梯（base.css `--dsw-radius-*`）。
///
/// 选档规则见 docs/ui-radius.md：按组件角色 + 高度选，不按内容长度选。
class DshRadius {
  const DshRadius._();

  /// 小细节：行内代码、键帽（H<20）
  static const double xs = 4;

  /// 紧凑控件：小按钮、紧凑菜单项（H20–28）
  static const double sm = 8;

  /// 组件特例：40px 图标/首字母方块（官方 ui-radius.md 明确列出的例外档）
  static const double tile = 10;

  /// 标准控件/单行单元格：按钮、输入框、导航行（H32–40）
  static const double md = 12;

  /// 大控件/成组内容：多行单元格、嵌套表单组
  static const double lg = 16;

  /// 独立内容卡片：设置卡片、消息气泡、引导卡
  static const double xl = 20;

  /// 主容器面：输入框、对话框、浮动面板
  static const double panel = 28;

  /// 胶囊（配 [BorderRadius.all] 外的 StadiumBorder 使用）
  static const double pill = 999;

  static const BorderRadius rXs = BorderRadius.all(Radius.circular(xs));
  static const BorderRadius rSm = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius rTile = BorderRadius.all(Radius.circular(tile));
  static const BorderRadius rMd = BorderRadius.all(Radius.circular(md));
  static const BorderRadius rLg = BorderRadius.all(Radius.circular(lg));
  static const BorderRadius rXl = BorderRadius.all(Radius.circular(xl));
  static const BorderRadius rPanel = BorderRadius.all(Radius.circular(panel));
  static const BorderRadius rPill = BorderRadius.all(Radius.circular(pill));

  /// 底部弹层：只圆上方两角（R28）。
  static const BorderRadius sheet = BorderRadius.vertical(
    top: Radius.circular(panel),
  );

  /// 菜单外框 R16 + 4px 内衬 → 菜单项 R12。
  static const BorderRadius menu = BorderRadius.all(Radius.circular(lg));
  static const BorderRadius menuItem = BorderRadius.all(Radius.circular(md));

  // ---------- 兼容旧调用点 ----------
  static const double radiusLg = xl;
  static const double radiusMd = md;
  static const double radiusSm = sm;
}

/// 间距阶梯：4 的倍数。
class DshSpace {
  const DshSpace._();

  static const double xxs = 2;
  static const double xs = 4;
  static const double sm = 8;

  /// 官方气泡内衬 12/10、活动条 10/8 里的 10 档（紧凑纵向内衬）。
  static const double tight = 10;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double xxxl = 32;

  /// 页面左右安全边距（官方侧栏内衬同为 12）。
  static const double pageH = 16;

  /// 手机端聊天内容左右边距。
  static const double chatH = 12;

  /// 列表行最小高度（H52 折叠 / H64 双行）。
  static const double rowMin = 52;
  static const double rowMinTwoLine = 64;

  /// 控件高度。
  static const double controlSm = 28;
  static const double controlMd = 36;
  static const double controlLg = 44;
}

/// 字体阶梯与文本样式（gradient-shadow-text.css）。
///
/// 所有字号都配好行高，避免页面各自调 height。
class DshType {
  const DshType._();

  /// 文本族：官方 `--dsh-font-family-text-default`。
  static const List<String> textFallback = <String>[
    'PingFang SC',
    'Hiragino Sans GB',
    'Microsoft YaHei',
    'Noto Sans CJK SC',
    'Roboto',
    'Helvetica Neue',
    'Helvetica',
    'Arial',
    'sans-serif',
  ];

  /// 代码族：官方 `--dsh-font-family-code-default`。
  static const List<String> monoFallback = <String>[
    'JetBrains Mono',
    'SF Mono',
    'Fira Code',
    'Consolas',
    'Liberation Mono',
    'Menlo',
    'Courier New',
    'monospace',
  ];

  // ---------- 界面阶梯 ----------

  /// 24/32 · 600（--dsw-font-xl-24）
  static const TextStyle xl24 = TextStyle(
    fontSize: 24,
    height: 32 / 24,
    fontWeight: FontWeight.w600,
  );

  /// 20/28 · 500（--dsw-font-l-20）
  static const TextStyle l20 = TextStyle(
    fontSize: 20,
    height: 28 / 20,
    fontWeight: FontWeight.w500,
  );

  /// 16/28 · 500（--dsw-font-m-18）
  static const TextStyle m16 = TextStyle(
    fontSize: 16,
    height: 28 / 16,
    fontWeight: FontWeight.w500,
  );

  /// 16/24 · 400（--dsw-font-base-16）
  static const TextStyle base16 = TextStyle(fontSize: 16, height: 24 / 16);

  /// 16/24 · 500（--dsw-font-base-strong-16）
  static const TextStyle baseStrong16 = TextStyle(
    fontSize: 16,
    height: 24 / 16,
    fontWeight: FontWeight.w500,
  );

  /// 14/22 · 400（--dsw-font-s-14）
  static const TextStyle s14 = TextStyle(fontSize: 14, height: 22 / 14);

  /// 14/22 · 500（--dsw-font-s-strong-14）
  static const TextStyle sStrong14 = TextStyle(
    fontSize: 14,
    height: 22 / 14,
    fontWeight: FontWeight.w500,
  );

  /// 13/20 · 400（--dsw-font-xs-13）
  static const TextStyle xs13 = TextStyle(fontSize: 13, height: 20 / 13);

  /// 13/20 · 500（--dsw-font-xs-strong-13）
  static const TextStyle xsStrong13 = TextStyle(
    fontSize: 13,
    height: 20 / 13,
    fontWeight: FontWeight.w500,
  );

  /// 12/18 · 400（--dsw-font-xxs-12）
  static const TextStyle xxs12 = TextStyle(fontSize: 12, height: 18 / 12);

  /// 12/18 · 500（--dsw-font-xxs-strong-12）
  static const TextStyle xxsStrong12 = TextStyle(
    fontSize: 12,
    height: 18 / 12,
    fontWeight: FontWeight.w500,
  );

  /// 11/14 · 400（--dsw-font-xxxs-11）
  static const TextStyle xxxs11 = TextStyle(fontSize: 11, height: 14 / 11);

  /// 11/14 · 500（--dsw-font-xxxs-strong-11）
  static const TextStyle xxxsStrong11 = TextStyle(
    fontSize: 11,
    height: 14 / 11,
    fontWeight: FontWeight.w500,
  );

  // ---------- Markdown 阶梯 ----------

  /// Markdown H1：21/30 · 700
  static const TextStyle mdH1 = TextStyle(
    fontSize: 21,
    height: 30 / 21,
    fontWeight: FontWeight.w700,
  );

  /// Markdown H2：19/28 · 700
  static const TextStyle mdH2 = TextStyle(
    fontSize: 19,
    height: 28 / 19,
    fontWeight: FontWeight.w700,
  );

  /// Markdown H3：18/26 · 700
  static const TextStyle mdH3 = TextStyle(
    fontSize: 18,
    height: 26 / 18,
    fontWeight: FontWeight.w700,
  );

  /// Markdown H4：14/24 · 600
  static const TextStyle mdH4 = TextStyle(
    fontSize: 14,
    height: 24 / 14,
    fontWeight: FontWeight.w600,
  );

  /// Markdown 正文：14/24 · 400
  static const TextStyle mdBase = TextStyle(fontSize: 14, height: 24 / 14);

  /// Markdown 正文加粗：14/24 · 600
  static const TextStyle mdBaseStrong = TextStyle(
    fontSize: 14,
    height: 24 / 14,
    fontWeight: FontWeight.w600,
  );

  /// Markdown 表格：13/22 · 400
  static const TextStyle mdTable = TextStyle(fontSize: 13, height: 22 / 13);

  /// Markdown 表格表头：13/22 · 500
  static const TextStyle mdTableHead = TextStyle(
    fontSize: 13,
    height: 22 / 13,
    fontWeight: FontWeight.w500,
  );

  /// Markdown 小字：12/20 · 400
  static const TextStyle mdSmall = TextStyle(fontSize: 12, height: 20 / 12);

  /// Markdown 小字加粗：12/20 · 600
  static const TextStyle mdSmallStrong = TextStyle(
    fontSize: 12,
    height: 20 / 12,
    fontWeight: FontWeight.w600,
  );

  /// 行内代码：12/19 · mono
  static TextStyle get mdCode => const TextStyle(
        fontSize: 12,
        height: 19 / 12,
        fontFamilyFallback: monoFallback,
      );

  /// 代码块：11/19 · mono
  static TextStyle get mdCodeBlock => const TextStyle(
        fontSize: 11,
        height: 19 / 11,
        fontFamilyFallback: monoFallback,
      );

  /// 紧凑代码：11/16 · mono
  static TextStyle get mdCodeSmall => const TextStyle(
        fontSize: 11,
        height: 16 / 11,
        fontFamilyFallback: monoFallback,
      );
}

/// 阴影/高度（gradient-shadow-text.css `--dsw-elevation-*`、`--dsw-shadow-lv*`）。
///
/// 官方约定：浮层用「0.5px 发丝描边 + 极淡柔光」，不再叠中性实边。
/// Flutter 侧把发丝描边交给 [DshStroke.hairline]，柔光交给这些 BoxShadow。
class DshShadow {
  const DshShadow._();

  /// 普通卡片（无投影，只靠填充与描边分层）。
  static const List<BoxShadow> none = <BoxShadow>[];

  /// --dsw-shadow-lv1
  static const List<BoxShadow> lv1 = <BoxShadow>[
    BoxShadow(color: Color(0x0D000000), blurRadius: 4, offset: Offset(0, 2)),
  ];

  /// --dsw-shadow-lv2
  static const List<BoxShadow> lv2 = <BoxShadow>[
    BoxShadow(color: Color(0x0A000000), blurRadius: 12, offset: Offset(0, 4)),
    BoxShadow(color: Color(0x0A000000), blurRadius: 8, offset: Offset(0, 2)),
  ];

  /// --dsw-shadow-lv3
  static const List<BoxShadow> lv3 = <BoxShadow>[
    BoxShadow(color: Color(0x33000000), blurRadius: 1),
    BoxShadow(color: Color(0x05000000), blurRadius: 4),
    BoxShadow(color: Color(0x14000000), blurRadius: 32, offset: Offset(0, 12)),
  ];

  /// --dsw-elevation-panel：面板/浮层
  static const List<BoxShadow> panel = <BoxShadow>[
    BoxShadow(color: Color(0x08000000), blurRadius: 8, offset: Offset(0, 3)),
    BoxShadow(color: Color(0x05000000), blurRadius: 16),
  ];

  /// --dsw-elevation-prominent：菜单/弹窗
  static const List<BoxShadow> prominent = <BoxShadow>[
    BoxShadow(color: Color(0x0A000000), blurRadius: 8, offset: Offset(0, 3)),
    BoxShadow(color: Color(0x0D000000), blurRadius: 20),
  ];

  /// --dsw-elevation-soft：输入框
  static const List<BoxShadow> soft = <BoxShadow>[
    BoxShadow(color: Color(0x08000000), blurRadius: 16, offset: Offset(0, 4)),
    BoxShadow(color: Color(0x08000000), blurRadius: 24),
  ];

  // ---------- 兼容旧调用点 ----------
  static const List<BoxShadow> shadow = lv1;
  static const List<BoxShadow> shadowDark = lv1;
}

/// 发丝描边宽度：官方面型描边统一 0.5px（渲染为一个设备像素）。
class DshStroke {
  const DshStroke._();

  static const double hairline = 0.5;

  /// 卡片/输入框发丝边。
  static BorderSide side(Color color) =>
      BorderSide(color: color, width: hairline);

  /// 中性分隔线（列表行分隔、区块分隔）。
  static BorderSide divider(Color color) =>
      BorderSide(color: color, width: hairline);

  /// 状态色描边保持 1px。
  static BorderSide state(Color color) => BorderSide(color: color, width: 1);
}

/// 动效曲线与时长（base.css `--ds-ease-in-out` / `--ds-transition-duration*`）。
class DshMotion {
  const DshMotion._();

  /// cubic-bezier(0.4, 0, 0.2, 1)
  static const Curve standard = Cubic(0.4, 0, 0.2, 1);

  static const Duration fast = Duration(milliseconds: 100);
  static const Duration normal = Duration(milliseconds: 200);
  static const Duration slow = Duration(milliseconds: 300);
}

/// 全局主题装配：把令牌灌进 Material 3 的各组件主题。
class DshTheme {
  const DshTheme._();

  // ---------- 旧静态调色板（保留兼容；新代码用 DshColors/DshPalette） ----------
  static const bg = Color(0xFFFFFFFF);
  static const surface = Color(0xFFFFFFFF);
  static const ink = Color(0xFF0F1115);
  static const ink2 = Color(0xFF61666B);
  static const ink3 = Color(0xFF81858C);
  static const line = Color(0x1A000000);
  static const brand = Color(0xFF0F1115);
  static const brandSoft = Color(0x0A0F1115);
  static const ok = Color(0xFF22C55E);
  static const warn = Color(0xFFF59E0B);
  static const danger = Color(0xFFEC1313);
  static const bgDark = Color(0xFF151517);
  static const surfaceDark = Color(0xFF2C2C2E);
  static const inkDark = Color(0xFFF9FAFB);
  static const ink2Dark = Color(0xFFCFD3D6);
  static const ink3Dark = Color(0xFFADB2B8);
  static const lineDark = Color(0x1FFFFFFF);
  static const brandDark = Color(0xFFF9FAFB);
  static const brandSoftDark = Color(0x14FFFFFF);
  static const okDark = Color(0xFF22C55E);
  static const warnDark = Color(0xFFF7AD31);
  static const dangerDark = Color(0xFFF25A5A);

  // ---------- 旧几何别名 ----------
  static const double radiusLg = DshRadius.xl;
  static const double radiusMd = DshRadius.md;
  static const double radiusSm = DshRadius.sm;
  static const List<BoxShadow> shadow = DshShadow.lv1;
  static const List<BoxShadow> shadowDark = DshShadow.lv1;

  /// 等宽字体族名（`lib/tui.dart` 用；官方 Web 侧等宽走 [DshType.monoFallback]）。
  static const String mono = 'monospace';

  /// 亮色主题。
  static ThemeData light() => _base(Brightness.light);

  /// 暗色主题。
  static ThemeData dark() => _base(Brightness.dark);

  static ThemeData _base(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final c = DshPalette._(dark);

    final scheme = ColorScheme.fromSeed(
      seedColor: c.brand,
      brightness: brightness,
    ).copyWith(
      primary: c.brand,
      onPrimary: c.onInk,
      secondary: c.business,
      onSecondary: c.onInk,
      surface: c.bg,
      onSurface: c.ink,
      error: c.danger,
      onError: c.onInk,
      outline: c.line4,
      outlineVariant: c.line2,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: c.bg,
      canvasColor: c.bg,
      fontFamilyFallback: DshType.textFallback,
      splashFactory: InkSparkle.splashFactory,
      // 官方曲线：pages 用轻量滑入 + 淡入。
      pageTransitionsTheme: const PageTransitionsTheme(builders: {
        TargetPlatform.android: _DshTransitionsBuilder(),
        TargetPlatform.iOS: _DshTransitionsBuilder(),
      }),
      appBarTheme: AppBarTheme(
        backgroundColor: c.bg,
        surfaceTintColor: Colors.transparent,
        foregroundColor: c.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: DshType.m16.copyWith(color: c.ink),
        toolbarTextStyle: DshType.s14.copyWith(color: c.ink2),
      ),
      dividerTheme: DividerThemeData(
        color: c.line2,
        thickness: DshStroke.hairline,
        space: DshStroke.hairline,
      ),
      cardTheme: CardThemeData(
        color: c.layer2,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: const RoundedRectangleBorder(borderRadius: DshRadius.rXl),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: c.layer1,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: DshRadius.rPanel,
          side: DshStroke.side(c.line4),
        ),
        titleTextStyle: DshType.m16.copyWith(color: c.ink),
        contentTextStyle: DshType.s14.copyWith(color: c.ink2),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: c.toast,
        contentTextStyle: DshType.s14.copyWith(color: c.onToast),
        elevation: 0,
        shape: const RoundedRectangleBorder(borderRadius: DshRadius.rMd),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: c.layer1,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: c.layer1,
        elevation: 0,
        modalElevation: 0,
        shape: const RoundedRectangleBorder(borderRadius: DshRadius.sheet),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: c.layer1,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: DshRadius.rLg,
          side: DshStroke.side(c.line4),
        ),
        textStyle: DshType.s14.copyWith(color: c.ink),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return dark ? c.layer3 : c.navActive;
            }
            if (states.contains(WidgetState.pressed) ||
                states.contains(WidgetState.hovered)) {
              return c.brandHover;
            }
            return c.brand;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) return c.caption;
            return c.onInk;
          }),
          overlayColor: const WidgetStatePropertyAll(Colors.transparent),
          elevation: const WidgetStatePropertyAll(0),
          minimumSize: const WidgetStatePropertyAll(Size(0, DshSpace.controlMd)),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: DshSpace.lg),
          ),
          shape: const WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: DshRadius.rMd),
          ),
          textStyle: WidgetStatePropertyAll(DshType.sStrong14.copyWith(color: c.onInk)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStatePropertyAll(c.ink),
          overlayColor: WidgetStatePropertyAll(c.hover),
          minimumSize: const WidgetStatePropertyAll(Size(0, DshSpace.controlMd)),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: DshSpace.md),
          ),
          shape: const WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: DshRadius.rMd),
          ),
          textStyle: WidgetStatePropertyAll(DshType.sStrong14.copyWith(color: c.ink)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStatePropertyAll(c.ink),
          side: WidgetStatePropertyAll(DshStroke.side(c.line4)),
          backgroundColor: WidgetStatePropertyAll(c.layer1),
          overlayColor: WidgetStatePropertyAll(c.hover),
          elevation: const WidgetStatePropertyAll(0),
          minimumSize: const WidgetStatePropertyAll(Size(0, DshSpace.controlMd)),
          shape: const WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: DshRadius.rMd),
          ),
          textStyle: WidgetStatePropertyAll(DshType.sStrong14.copyWith(color: c.ink)),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStatePropertyAll(c.ink2),
          overlayColor: WidgetStatePropertyAll(c.hover),
          shape: const WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: DshRadius.rSm),
          ),
        ),
      ),
      iconTheme: IconThemeData(color: c.ink2, size: 20),
      listTileTheme: ListTileThemeData(
        iconColor: c.ink2,
        textColor: c.ink,
        contentPadding: const EdgeInsets.symmetric(horizontal: DshSpace.lg),
        minVerticalPadding: DshSpace.md,
        shape: const RoundedRectangleBorder(borderRadius: DshRadius.rMd),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected) ? c.onInk : c.layer1),
        trackColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected) ? c.brand : c.line4),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected) ? c.brand : Colors.transparent),
        checkColor: WidgetStatePropertyAll(c.onInk),
        side: DshStroke.side(c.line4),
        shape: const RoundedRectangleBorder(borderRadius: DshRadius.rXs),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected) ? c.brand : c.line4),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: c.brand,
        inactiveTrackColor: c.line4,
        thumbColor: c.layer1,
        overlayColor: c.hover,
        trackHeight: 4,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: c.ink3,
        linearTrackColor: c.line2,
        circularTrackColor: Colors.transparent,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.layer1,
        hintStyle: DshType.s14.copyWith(color: c.caption),
        labelStyle: DshType.s14.copyWith(color: c.ink2),
        floatingLabelStyle: DshType.xs13.copyWith(color: c.ink3),
        errorStyle: DshType.xs13.copyWith(color: c.danger),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: DshSpace.md,
          vertical: DshSpace.md,
        ),
        border: OutlineInputBorder(
          borderRadius: DshRadius.rMd,
          borderSide: DshStroke.side(c.line4),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: DshRadius.rMd,
          borderSide: DshStroke.side(c.line4),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: DshRadius.rMd,
          borderSide: DshStroke.side(c.line2),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: DshRadius.rMd,
          borderSide: BorderSide(color: c.ink3, width: 1),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: DshRadius.rMd,
          borderSide: DshStroke.state(c.danger),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: DshRadius.rMd,
          borderSide: DshStroke.state(c.danger),
        ),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: c.ink,
        unselectedLabelColor: c.ink3,
        labelStyle: DshType.xsStrong13.copyWith(color: c.ink),
        unselectedLabelStyle: DshType.xs13.copyWith(color: c.ink3),
        indicatorColor: c.brand,
        indicatorSize: TabBarIndicatorSize.label,
        dividerColor: c.line2,
        overlayColor: WidgetStatePropertyAll(c.hover),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: c.tooltip,
          borderRadius: DshRadius.rSm,
        ),
        textStyle: DshType.xxs12.copyWith(color: c.onToast),
        padding: const EdgeInsets.symmetric(
          horizontal: DshSpace.sm,
          vertical: DshSpace.xs,
        ),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thickness: const WidgetStatePropertyAll(5),
        radius: const Radius.circular(DshRadius.pill),
        thumbColor: WidgetStatePropertyAll(c.scrollbar),
        trackColor: const WidgetStatePropertyAll(Colors.transparent),
        trackBorderColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: c.business,
        selectionColor: c.bubbleStrong,
        selectionHandleColor: c.business,
      ),
      textTheme: TextTheme(
        displaySmall: DshType.xl24.copyWith(color: c.ink),
        headlineSmall: DshType.l20.copyWith(color: c.ink),
        titleLarge: DshType.m16.copyWith(color: c.ink),
        titleMedium: DshType.baseStrong16.copyWith(color: c.ink),
        titleSmall: DshType.sStrong14.copyWith(color: c.ink),
        bodyLarge: DshType.base16.copyWith(color: c.ink),
        bodyMedium: DshType.s14.copyWith(color: c.ink),
        bodySmall: DshType.xs13.copyWith(color: c.ink2),
        labelLarge: DshType.sStrong14.copyWith(color: c.ink),
        labelMedium: DshType.xsStrong13.copyWith(color: c.ink2),
        labelSmall: DshType.xxsStrong12.copyWith(color: c.ink3),
      ),
    );
  }
}

/// 官方味转场：新页全宽滑入 + 轻微淡入，旧页不参与动画（零重绘）。
class _DshTransitionsBuilder extends PageTransitionsBuilder {
  const _DshTransitionsBuilder();

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
        position: Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero)
            .animate(curved),
        child: child,
      ),
    );
  }
}

/// 兼容旧调用点：设置项开关（官方 Switch 尺寸 + 令牌配色）。
class DshSwitch extends StatelessWidget {
  const DshSwitch({super.key, required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = DshPalette.of(context);
    return SizedBox(
      width: 44,
      height: 28,
      child: FittedBox(
        fit: BoxFit.contain,
        child: Switch(
          value: value,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          activeTrackColor: c.brand,
          activeThumbColor: c.onInk,
          inactiveTrackColor: c.line4,
          inactiveThumbColor: c.layer1,
          onChanged: onChanged,
        ),
      ),
    );
  }
}

/// 静态便捷入口：`DshColors.ink3(context)`。
///
/// 新代码建议用 `final c = DshPalette.of(context)`（一次解析，多次读取），
/// 旧调用点继续可用，迁移可以逐个页面进行。
class DshColors {
  const DshColors._();

  /// 取当前主题的完整调色板。
  static DshPalette of(BuildContext context) => DshPalette.of(context);

  // ---------- 背景层 ----------
  static Color bg(BuildContext c) => DshPalette.of(c).bg;
  static Color layer1(BuildContext c) => DshPalette.of(c).layer1;
  static Color layer2(BuildContext c) => DshPalette.of(c).layer2;
  static Color layer3(BuildContext c) => DshPalette.of(c).layer3;
  static Color sidebar(BuildContext c) => DshPalette.of(c).sidebar;
  static Color module(BuildContext c) => DshPalette.of(c).module;
  static Color docPreview(BuildContext c) => DshPalette.of(c).docPreview;
  static Color skeleton(BuildContext c) => DshPalette.of(c).skeleton;
  static Color mask(BuildContext c) => DshPalette.of(c).mask;

  // ---------- 文字 ----------
  static Color ink(BuildContext c) => DshPalette.of(c).ink;
  static Color ink2(BuildContext c) => DshPalette.of(c).ink2;
  static Color ink3(BuildContext c) => DshPalette.of(c).ink3;
  static Color caption(BuildContext c) => DshPalette.of(c).caption;
  static Color dimmed(BuildContext c) => DshPalette.of(c).dimmed;
  static Color onInk(BuildContext c) => DshPalette.of(c).onInk;

  // ---------- 描边 ----------
  static Color line(BuildContext c) => DshPalette.of(c).line2;
  static Color line1(BuildContext c) => DshPalette.of(c).line1;
  static Color line2(BuildContext c) => DshPalette.of(c).line2;
  static Color line3(BuildContext c) => DshPalette.of(c).line3;
  static Color line4(BuildContext c) => DshPalette.of(c).line4;

  // ---------- 品牌与状态 ----------
  static Color brand(BuildContext c) => DshPalette.of(c).brand;
  static Color brandHover(BuildContext c) => DshPalette.of(c).brandHover;
  static Color brandText(BuildContext c) => DshPalette.of(c).brandText;
  static Color brandSoft(BuildContext c) => DshPalette.of(c).brandSoft;
  static Color link(BuildContext c) => DshPalette.of(c).link;
  static Color business(BuildContext c) => DshPalette.of(c).business;
  static Color ok(BuildContext c) => DshPalette.of(c).ok;
  static Color warn(BuildContext c) => DshPalette.of(c).warn;
  static Color warnLabel(BuildContext c) => DshPalette.of(c).warnLabel;
  static Color danger(BuildContext c) => DshPalette.of(c).danger;
  static Color idle(BuildContext c) => DshPalette.of(c).idle;
  static Color okSoft(BuildContext c) => DshPalette.of(c).okSoft;
  static Color dangerSoft(BuildContext c) => DshPalette.of(c).dangerSoft;
  static Color warnSoft(BuildContext c) => DshPalette.of(c).warnSoft;

  // ---------- 交互态 ----------
  static Color hover(BuildContext c) => DshPalette.of(c).hover;
  static Color active(BuildContext c) => DshPalette.of(c).active;
  static Color hoverSolid(BuildContext c) => DshPalette.of(c).hoverSolid;
  static Color navActive(BuildContext c) => DshPalette.of(c).navActive;
  static Color navHover(BuildContext c) => DshPalette.of(c).navHover;
  static Color navAccent(BuildContext c) => DshPalette.of(c).navAccent;

  // ---------- 组件面 ----------
  static Color input(BuildContext c) => DshPalette.of(c).input;
  static Color selector(BuildContext c) => DshPalette.of(c).selector;
  static Color bubble(BuildContext c) => DshPalette.of(c).bubble;
  static Color bubbleStrong(BuildContext c) => DshPalette.of(c).bubbleStrong;
  static Color codeBlock(BuildContext c) => DshPalette.of(c).codeBlock;
  static Color codeBanner(BuildContext c) => DshPalette.of(c).codeBanner;
  static Color inlineCode(BuildContext c) => DshPalette.of(c).inlineCode;
  static Color tag(BuildContext c) => DshPalette.of(c).tag;
  static Color toast(BuildContext c) => DshPalette.of(c).toast;
  static Color onToast(BuildContext c) => DshPalette.of(c).onToast;
  static Color tooltip(BuildContext c) => DshPalette.of(c).tooltip;
  static Color floating(BuildContext c) => DshPalette.of(c).floating;
  static Color scrollbar(BuildContext c) => DshPalette.of(c).scrollbar;
  static Color diffAdded(BuildContext c) => DshPalette.of(c).diffAdded;
  static Color diffDeleted(BuildContext c) => DshPalette.of(c).diffDeleted;

  // ---------- 旧别名 ----------
  static Color surface(BuildContext c) => DshPalette.of(c).surface;
  static Color card(BuildContext c) => DshPalette.of(c).card;

  // ---------- TUI 终端皮肤遗留令牌（只服务 lib/tui.dart） ----------
  static Color cyan(BuildContext c) => DshPalette.of(c).cyan;
  static Color indigo(BuildContext c) => DshPalette.of(c).indigo;
  static Color muted(BuildContext c) => DshPalette.of(c).muted;
  static Color panel(BuildContext c) => DshPalette.of(c).panel;
}
