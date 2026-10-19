// DSH UI 基础组件库 —— 官方 DeepSeek Harness Web 客户端组件的 Flutter 版。
//
// 对应官方 `packages/client/ui-primitives`（Button / IconButton / Card / Menu /
// SegmentedControl / Tag）与 `ui-settings`（设置卡片与行）的视觉规格。
// 页面一律复用这里的控件，不再各自手写圆角/配色/高度。
import 'package:flutter/material.dart';

import 'l10n.dart';
import 'theme.dart';

/// 页面脚手架：统一底色，可选官方样式标题栏。
class DshPage extends StatelessWidget {
  const DshPage({
    super.key,
    required this.child,
    this.title,
    this.leading,
    this.actions,
    this.appBar,
    this.bottomBar,
    this.padding,
    this.showDivider = true,
    this.resizeToAvoidBottomInset = true,
  });

  final Widget child;
  final String? title;
  final Widget? leading;
  final List<Widget>? actions;
  final PreferredSizeWidget? appBar;
  final Widget? bottomBar;
  final EdgeInsetsGeometry? padding;
  final bool showDivider;
  final bool resizeToAvoidBottomInset;

  @override
  Widget build(BuildContext context) {
    final c = DshPalette.of(context);
    return Scaffold(
      backgroundColor: c.bg,
      resizeToAvoidBottomInset: resizeToAvoidBottomInset,
      appBar: appBar ??
          (title == null
              ? null
              : DshAppBar(
                  title: title!,
                  leading: leading,
                  actions: actions,
                  showDivider: showDivider,
                )),
      bottomNavigationBar: bottomBar,
      body: padding == null ? child : Padding(padding: padding!, child: child),
    );
  }
}

/// 官方标题栏：透明底、无阴影、底部发丝分隔线，标题 16/24 · 500。
class DshAppBar extends StatelessWidget implements PreferredSizeWidget {
  const DshAppBar({
    super.key,
    this.title,
    this.titleWidget,
    this.leading,
    this.actions,
    this.bottom,
    this.showDivider = true,
    this.height = 52,
    this.automaticallyImplyLeading = true,
    this.centerTitle = false,
  }) : assert(title != null || titleWidget != null, '标题或标题组件二选一');

  final String? title;

  /// 自定义标题内容（如「状态点 + 文字」）；设置后优先于 [title]。
  final Widget? titleWidget;
  final Widget? leading;
  final List<Widget>? actions;
  final PreferredSizeWidget? bottom;
  final bool showDivider;
  final double height;
  final bool automaticallyImplyLeading;
  final bool centerTitle;

  @override
  Size get preferredSize => Size.fromHeight(
        height +
            (bottom?.preferredSize.height ??
                (showDivider ? DshStroke.hairline : 0)),
      );

  @override
  Widget build(BuildContext context) {
    final c = DshPalette.of(context);
    final canPop = Navigator.of(context).canPop();
    final autoLeading = automaticallyImplyLeading && canPop;
    final leadingWidget = leading ??
        (autoLeading
            ? DshIconButton(
                icon: Icons.arrow_back_ios_new,
                iconSize: 18,
                onTap: () => Navigator.of(context).maybePop(),
              )
            : null);

    // 不用 Material 的 AppBar：它内部的 Column(mainAxisAlignment.spaceBetween)
    // 在高度无界处（嵌进可滚动区域/自定义弹层）会抛 RenderFlex 约束错误。
    // 这里用固定高度的 SizedBox 自绘，作为 Scaffold.appBar 时行为一致。
    return Material(
      color: c.bg,
      child: SizedBox(
        height: preferredSize.height,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: height,
              child: Row(
                children: [
                  if (leadingWidget != null)
                    SizedBox(
                      width: 52,
                      child: Center(child: leadingWidget),
                    )
                  else
                    const SizedBox(width: DshSpace.pageH),
                  Expanded(
                    child: Align(
                      alignment: centerTitle
                          ? Alignment.center
                          : Alignment.centerLeft,
                      child: titleWidget ??
                          Text(
                            title!,
                            style: DshType.m16.copyWith(color: c.ink),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                    ),
                  ),
                  ...?actions,
                  const SizedBox(width: DshSpace.sm),
                ],
              ),
            ),
            ?bottom,
            if (bottom == null && showDivider)
              Container(height: DshStroke.hairline, color: c.line2),
          ],
        ),
      ),
    );
  }
}

/// 区块标题（设置分组、列表分组）：13/20 · 500 · tertiary。
class DshSectionHeader extends StatelessWidget {
  const DshSectionHeader(
    this.title, {
    super.key,
    this.trailing,
    this.padding = const EdgeInsets.fromLTRB(
      DshSpace.pageH,
      DshSpace.lg,
      DshSpace.pageH,
      DshSpace.sm,
    ),
  });

  final String title;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final c = DshPalette.of(context);
    return Padding(
      padding: padding,
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: DshType.xsStrong13.copyWith(color: c.ink3),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// 侧栏/抽屉导航行：官方导航项几何（R12、H40、图标 20 `ink2`、选中 `navActive`）。
class DshNavItem extends StatelessWidget {
  const DshNavItem({
    super.key,
    required this.label,
    this.icon,
    this.leading,
    this.trailing,
    this.onTap,
    this.selected = false,
    this.iconSize = 20,
  });

  final String label;
  final IconData? icon;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool selected;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final c = DshPalette.of(context);
    final fg = selected ? c.ink : c.ink2;
    return Material(
      color: selected ? c.navActive : Colors.transparent,
      borderRadius: BorderRadius.circular(DshRadius.md),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(DshRadius.md),
        splashFactory: NoSplash.splashFactory,
        highlightColor: c.hover,
        hoverColor: selected ? c.navActive : c.hover,
        child: Container(
          constraints: const BoxConstraints(minHeight: DshSpace.controlLg - 4),
          padding: const EdgeInsets.symmetric(
            horizontal: DshSpace.md,
            vertical: DshSpace.sm,
          ),
          child: Row(
            children: [
              if (leading != null)
                leading!
              else if (icon != null)
                Icon(icon, size: iconSize, color: fg),
              if (leading != null || icon != null) const SizedBox(width: DshSpace.md),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: (selected ? DshType.sStrong14 : DshType.s14)
                      .copyWith(color: fg),
                ),
              ),
              ?trailing,
            ],
          ),
        ),
      ),
    );
  }
}

/// Toast 面：官方 `--dsw-alias-toast-bg` + 发丝边 + `prominent` 阴影。
///
/// 仅负责外观；定位与进出场由调用方（SnackBar / 自绘横幅）决定。
class DshToast extends StatelessWidget {
  const DshToast({
    super.key,
    required this.message,
    this.icon,
    this.trailing,
    this.onTap,
    this.maxWidth = 520,
  });

  final String message;
  final IconData? icon;
  final Widget? trailing;
  final VoidCallback? onTap;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final c = DshPalette.of(context);
    final body = Container(
      constraints: BoxConstraints(maxWidth: maxWidth),
      padding: const EdgeInsets.symmetric(
        horizontal: DshSpace.md,
        vertical: 10,
      ),
      decoration: BoxDecoration(
        color: c.toast,
        borderRadius: BorderRadius.circular(DshRadius.md),
        border: Border.fromBorderSide(DshStroke.side(c.line3)),
        boxShadow: DshShadow.prominent,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 16, color: c.onToast),
            const SizedBox(width: DshSpace.sm),
          ],
          Flexible(
            child: Text(
              message,
              style: DshType.xs13.copyWith(color: c.onToast),
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: DshSpace.md),
            trailing!,
          ],
        ],
      ),
    );
    if (onTap == null) return body;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(DshRadius.md),
        splashFactory: NoSplash.splashFactory,
        child: body,
      ),
    );
  }
}

/// 设置卡片：R20 + 0.5px 发丝描边 + layer-2 填充（docs/ui-radius.md 规范）。
class DshCard extends StatelessWidget {
  const DshCard({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.padding = const EdgeInsets.all(DshSpace.lg),
    this.margin = EdgeInsets.zero,
    this.selected = false,
    this.fill,
    this.stroke,
    this.side,
    this.radius = DshRadius.xl,
    this.shadows = DshShadow.none,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final bool selected;
  final Color? fill;
  final Color? stroke;

  /// 直接指定描边（状态色用 1px：`DshStroke.state(c.danger)`）。
  final BorderSide? side;
  final double radius;
  final List<BoxShadow> shadows;

  @override
  Widget build(BuildContext context) {
    final c = DshPalette.of(context);
    final br = BorderRadius.circular(radius);
    final body = DecoratedBox(
      decoration: BoxDecoration(
        color: fill ?? c.layer2,
        borderRadius: br,
        border: Border.fromBorderSide(
          side ?? DshStroke.side(stroke ?? (selected ? c.ink3 : c.line4)),
        ),
        boxShadow: shadows,
      ),
      child: Padding(padding: padding, child: child),
    );
    if (onTap == null && onLongPress == null) {
      return Padding(padding: margin, child: body);
    }
    return Padding(
      padding: margin,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          borderRadius: br,
          splashFactory: NoSplash.splashFactory,
          highlightColor: Colors.transparent,
          child: body,
        ),
      ),
    );
  }
}

/// 列表行：官方 H≥52 单行 / H≥64 双行几何，圆角 R12 的整行 hover 底。
class DshTile extends StatelessWidget {
  const DshTile({
    super.key,
    this.title,
    this.titleWidget,
    this.subtitle,
    this.subtitleWidget,
    this.leading,
    this.trailing,
    this.onTap,
    this.onLongPress,
    this.selected = false,
    this.dense = false,
    this.danger = false,
    this.padding,
    this.borderRadius = DshRadius.md,
    this.chevron = false,
    this.maxTitleLines = 1,
    this.background,
    this.trailingText,
  });

  final String? title;
  final Widget? titleWidget;
  final String? subtitle;
  final Widget? subtitleWidget;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool selected;
  final bool dense;
  final bool danger;
  final EdgeInsetsGeometry? padding;
  final double borderRadius;
  final bool chevron;
  final int maxTitleLines;

  /// 覆盖整行底色（多选态用 `navAccent`）。
  final Color? background;

  /// 右侧值文本（`xs13` · `ink3`），与 `trailing` 二选一。
  final String? trailingText;

  @override
  Widget build(BuildContext context) {
    final c = DshPalette.of(context);
    final titleColor = danger ? c.danger : c.ink;
    final hasSub = subtitle != null || subtitleWidget != null;

    final row = Padding(
      padding: padding ??
          EdgeInsets.symmetric(
            horizontal: DshSpace.md,
            vertical: dense ? DshSpace.sm : DshSpace.md,
          ),
      child: Row(
        crossAxisAlignment:
            hasSub ? CrossAxisAlignment.start : CrossAxisAlignment.center,
        children: [
          if (leading != null) ...[
            IconTheme.merge(
              data: IconThemeData(color: danger ? c.danger : c.ink2, size: 20),
              child: leading!,
            ),
            const SizedBox(width: DshSpace.md),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                DefaultTextStyle.merge(
                  style: DshType.s14.copyWith(color: titleColor),
                  child: titleWidget ??
                      Text(
                        title ?? '',
                        maxLines: maxTitleLines,
                        overflow: TextOverflow.ellipsis,
                        style: DshType.s14.copyWith(color: titleColor),
                      ),
                ),
                if (hasSub) ...[
                  const SizedBox(height: DshSpace.xxs),
                  subtitleWidget ??
                      Text(
                        subtitle!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: DshType.xs13.copyWith(color: c.ink3),
                      ),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: DshSpace.sm),
            trailing!,
          ],
          if (trailingText != null) ...[
            const SizedBox(width: DshSpace.sm),
            Text(
              trailingText!,
              style: DshType.xs13.copyWith(color: c.ink3),
            ),
          ],
          if (chevron) ...[
            const SizedBox(width: DshSpace.xs),
            Icon(Icons.chevron_right, size: 18, color: c.caption),
          ],
        ],
      ),
    );

    final content = ConstrainedBox(
      constraints: BoxConstraints(
        minHeight: dense
            ? DshSpace.controlLg
            : (hasSub ? DshSpace.rowMinTwoLine : DshSpace.rowMin),
      ),
      child: row,
    );

    final bg = background ?? (selected ? c.navActive : Colors.transparent);
    if (onTap == null && onLongPress == null) {
      return DecoratedBox(
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(borderRadius),
        ),
        child: content,
      );
    }
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(borderRadius),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(borderRadius),
        splashFactory: NoSplash.splashFactory,
        highlightColor: c.hover,
        hoverColor: c.hover,
        child: content,
      ),
    );
  }
}

/// 按钮变体（官方 Button 的 Flutter 版）。
enum DshButtonVariant {
  /// 主操作：浅色近黑 / 深色近白填充。
  primary,

  /// 次操作：白底 + 发丝描边。
  outline,

  /// 弱操作：无底，hover 才出现叠加。
  ghost,

  /// 危险操作：红字（ghost 语义）或红浅底（`danger`）。
  danger,

  /// 强破坏确认：红底白字（「我理解风险，继续」这类）。
  dangerSolid,

  /// 业务蓝填充（发送、确认类）。
  business,
}

/// 按钮尺寸（官方 sm=H28/R8、md=H36/R12）。
enum DshButtonSize { sm, md, lg }

/// 官方规格按钮。
class DshButton extends StatelessWidget {
  const DshButton({
    super.key,
    this.label,
    this.icon,
    this.onPressed,
    this.variant = DshButtonVariant.primary,
    this.size = DshButtonSize.md,
    this.expanded = false,
    this.loading = false,
    this.trailingIcon,
  });

  final String? label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final DshButtonVariant variant;
  final DshButtonSize size;
  final bool expanded;
  final bool loading;
  final IconData? trailingIcon;

  double get _height => switch (size) {
        DshButtonSize.sm => DshSpace.controlSm,
        DshButtonSize.md => DshSpace.controlMd,
        DshButtonSize.lg => DshSpace.controlLg,
      };

  double get _radius => switch (size) {
        DshButtonSize.sm => DshRadius.sm,
        DshButtonSize.md => DshRadius.md,
        DshButtonSize.lg => DshRadius.md,
      };

  TextStyle _textStyle(DshPalette c) => switch (size) {
        DshButtonSize.sm => DshType.xsStrong13.copyWith(color: _fg(c)),
        DshButtonSize.md => DshType.sStrong14.copyWith(color: _fg(c)),
        DshButtonSize.lg => DshType.baseStrong16.copyWith(color: _fg(c)),
      };

  Color _fg(DshPalette c) => switch (variant) {
        DshButtonVariant.primary => c.onInk,
        DshButtonVariant.business => c.onInk,
        DshButtonVariant.outline => c.ink,
        DshButtonVariant.ghost => c.ink2,
        DshButtonVariant.danger => c.danger,
        DshButtonVariant.dangerSolid => Colors.white,
      };

  Color _bg(DshPalette c) => switch (variant) {
        DshButtonVariant.primary => c.brand,
        DshButtonVariant.business => c.business,
        DshButtonVariant.outline => c.layer1,
        DshButtonVariant.ghost => Colors.transparent,
        DshButtonVariant.danger => c.dangerSoft,
        DshButtonVariant.dangerSolid => c.danger,
      };

  Color _bgPressed(DshPalette c) => switch (variant) {
        DshButtonVariant.primary => c.brandHover,
        DshButtonVariant.business => c.link,
        DshButtonVariant.outline => c.hoverSolid,
        DshButtonVariant.ghost => c.hover,
        DshButtonVariant.danger => c.danger,
        DshButtonVariant.dangerSolid => c.danger.withValues(alpha: 0.85),
      };

  @override
  Widget build(BuildContext context) {
    final c = DshPalette.of(context);
    final enabled = onPressed != null && !loading;
    final fg = enabled ? _fg(c) : c.caption;
    final iconSize = size == DshButtonSize.sm ? 14.0 : 16.0;

    final child = Row(
      mainAxisSize: expanded ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (loading) ...[
          SizedBox(
            width: iconSize,
            height: iconSize,
            child: CircularProgressIndicator(
              strokeWidth: 1.5,
              color: fg,
            ),
          ),
          if (label != null) const SizedBox(width: DshSpace.sm),
        ] else if (icon != null) ...[
          Icon(icon, size: iconSize, color: fg),
          if (label != null) const SizedBox(width: DshSpace.sm),
        ],
        if (label != null)
          Flexible(
            child: Text(
              label!,
              style: _textStyle(c).copyWith(color: fg),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        if (trailingIcon != null) ...[
          if (label != null) const SizedBox(width: DshSpace.xs),
          Icon(trailingIcon, size: iconSize, color: fg),
        ],
      ],
    );

    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: Material(
        color: enabled ? _bg(c) : c.hoverSolid,
        borderRadius: BorderRadius.circular(_radius),
        child: InkWell(
          onTap: enabled ? onPressed : null,
          borderRadius: BorderRadius.circular(_radius),
          splashFactory: NoSplash.splashFactory,
          highlightColor: enabled ? _bgPressed(c).withValues(alpha: 0.9) : null,
          hoverColor: enabled ? _bgPressed(c).withValues(alpha: 0.9) : null,
          child: Container(
            height: _height,
            padding: EdgeInsets.symmetric(
              horizontal: size == DshButtonSize.sm ? DshSpace.sm : DshSpace.md,
            ),
            decoration: variant == DshButtonVariant.outline
                ? BoxDecoration(
                    borderRadius: BorderRadius.circular(_radius),
                    border: Border.fromBorderSide(DshStroke.side(c.line4)),
                  )
                : null,
            // 不用 Container.alignment：它会让按钮撑满可用宽度（Align 展开
            // 松约束）；宽度交给 Row 的 mainAxisSize 决定。
            child: child,
          ),
        ),
      ),
    );
  }
}

/// 圆形填充按钮：官方 composer 发送键（36 圆 + `brand` 填充 + `onInk` 图标）。
///
/// `loading` 时为禁用填充 + 细环；`enabled: false` 用 `line4` 表示不可发送。
class DshCircleButton extends StatelessWidget {
  const DshCircleButton({
    super.key,
    required this.icon,
    this.onTap,
    this.size = DshSpace.controlMd,
    this.iconSize = 18,
    this.enabled = true,
    this.loading = false,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final double size;
  final double iconSize;
  final bool enabled;
  final bool loading;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final c = DshPalette.of(context);
    final active = enabled && onTap != null && !loading;
    final bg = active ? c.brand : c.line4;
    final fg = active ? c.onInk : c.caption;

    final button = Material(
      color: bg,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: active ? onTap : null,
        customBorder: const CircleBorder(),
        splashFactory: NoSplash.splashFactory,
        highlightColor: c.brandHover,
        child: SizedBox(
          width: size,
          height: size,
          child: Center(
            child: loading
                ? SizedBox(
                    width: iconSize,
                    height: iconSize,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.6,
                      color: fg,
                    ),
                  )
                : Icon(icon, size: iconSize, color: fg),
          ),
        ),
      ),
    );
    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}

/// 图标按钮：官方紧凑控件 H32/R8，选中态用 nav 底。
class DshIconButton extends StatelessWidget {
  const DshIconButton({
    super.key,
    required this.icon,
    this.onTap,
    this.tooltip,
    this.size = DshSpace.controlMd,
    this.iconSize = 20,
    this.selected = false,
    this.color,
    this.badge,
    this.badgeColor,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final String? tooltip;
  final double size;
  final double iconSize;
  final bool selected;
  final Color? color;
  final int? badge;
  final Color? badgeColor;

  @override
  Widget build(BuildContext context) {
    final c = DshPalette.of(context);
    final fg = color ?? (selected ? c.ink : c.ink2);
    Widget button = Material(
      color: selected ? c.navActive : Colors.transparent,
      borderRadius: BorderRadius.circular(DshRadius.sm),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(DshRadius.sm),
        splashFactory: NoSplash.splashFactory,
        highlightColor: c.hover,
        hoverColor: c.hover,
        child: SizedBox(
          width: size,
          height: size,
          child: Center(child: Icon(icon, size: iconSize, color: fg)),
        ),
      ),
    );

    if (badge != null && badge! > 0) {
      button = Stack(
        clipBehavior: Clip.none,
        children: [
          button,
          Positioned(
            right: 2,
            top: 2,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              constraints: const BoxConstraints(minWidth: 14),
              height: 14,
              decoration: BoxDecoration(
                color: badgeColor ?? c.danger,
                borderRadius: BorderRadius.circular(DshRadius.pill),
                border: Border.all(color: c.bg, width: 1.5),
              ),
              alignment: Alignment.center,
              child: Text(
                badge! > 99 ? '99+' : '$badge',
                style: DshType.xxxsStrong11.copyWith(
                  color: Colors.white,
                  height: 1,
                ),
              ),
            ),
          ),
        ],
      );
    }

    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}

/// 标签/胶囊：官方 markdown tag 底 + 11–12px 文字。
class DshTag extends StatelessWidget {
  const DshTag({
    super.key,
    required this.label,
    this.icon,
    this.color,
    this.background,
    this.border = false,
    this.dense = false,
  });

  final String label;
  final IconData? icon;
  final Color? color;
  final Color? background;
  final bool border;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final c = DshPalette.of(context);
    final fg = color ?? c.ink2;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 6 : DshSpace.sm,
        vertical: dense ? 2 : DshSpace.xs,
      ),
      decoration: BoxDecoration(
        color: background ?? c.tag,
        borderRadius: BorderRadius.circular(DshRadius.sm),
        border: border
            ? Border.fromBorderSide(DshStroke.side(color ?? c.line4))
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: dense ? 11 : 12, color: fg),
            const SizedBox(width: DshSpace.xs),
          ],
          Text(
            label,
            style: (dense ? DshType.xxxsStrong11 : DshType.xxsStrong12)
                .copyWith(color: fg),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

/// 胶囊选择器（模型选择、模式切换）：999px + selector 底。
class DshPill extends StatelessWidget {
  const DshPill({
    super.key,
    required this.label,
    this.icon,
    this.onTap,
    this.active = false,
    this.trailing,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final bool active;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = DshPalette.of(context);
    return Material(
      color: active ? c.brand : c.selector,
      borderRadius: BorderRadius.circular(DshRadius.pill),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(DshRadius.pill),
        splashFactory: NoSplash.splashFactory,
        highlightColor: c.hover,
        child: Container(
          height: DshSpace.controlSm,
          padding: const EdgeInsets.symmetric(horizontal: DshSpace.md),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 14, color: active ? c.onInk : c.ink2),
                const SizedBox(width: 6),
              ],
              Flexible(
                child: Text(
                  label,
                  style: DshType.xsStrong13.copyWith(
                    color: active ? c.onInk : c.ink2,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: DshSpace.xs),
                trailing!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 状态圆点：官方 50% 圆 + 状态色。
///
/// 脉冲环画在自身盒子之外（`clipBehavior: none`），因此 `pulse: true` 时
/// 组件占位仍是 [size]×[size]，放进 Row/leading 不会挤开相邻文字。
class DshStatusDot extends StatelessWidget {
  const DshStatusDot({
    super.key,
    required this.color,
    this.size = 8,
    this.pulse = false,
  });

  final Color color;
  final double size;
  final bool pulse;

  @override
  Widget build(BuildContext context) {
    final dot = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
    if (!pulse) return dot;
    return SizedBox(
      width: size,
      height: size,
      child: _Pulse(color: color, child: dot),
    );
  }
}

class _Pulse extends StatefulWidget {
  const _Pulse({required this.child, required this.color});

  final Widget child;
  final Color color;

  @override
  State<_Pulse> createState() => _PulseState();
}

class _PulseState extends State<_Pulse> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, child) {
        final t = _ctrl.value;
        return Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            // 脉冲环允许溢出自身盒子：用 Positioned 脱开布局，避免撑大占位。
            Positioned(
              child: Container(
                width: 8 + 12 * t,
                height: 8 + 12 * t,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.color.withValues(alpha: 0.32 * (1 - t)),
                ),
              ),
            ),
            child!,
          ],
        );
      },
      child: widget.child,
    );
  }
}

/// 分隔线：官方 0.5px 发丝。
class DshDivider extends StatelessWidget {
  const DshDivider({super.key, this.indent = 0, this.endIndent = 0});

  final double indent;
  final double endIndent;

  @override
  Widget build(BuildContext context) {
    final c = DshPalette.of(context);
    return Padding(
      padding: EdgeInsets.only(left: indent, right: endIndent),
      child: Container(height: DshStroke.hairline, color: c.line2),
    );
  }
}

/// 分段控件：官方外框 R12 + 4px 内衬 + R8 段（SegmentedControl）。
class DshSegmented extends StatelessWidget {
  const DshSegmented({
    super.key,
    required this.items,
    required this.index,
    required this.onChanged,
  });

  final List<String> items;
  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = DshPalette.of(context);
    return Container(
      padding: const EdgeInsets.all(DshSpace.xs),
      decoration: BoxDecoration(
        color: c.module,
        borderRadius: BorderRadius.circular(DshRadius.md),
      ),
      child: Row(
        children: [
          for (var i = 0; i < items.length; i++)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onChanged(i),
                child: AnimatedContainer(
                  duration: DshMotion.fast,
                  curve: DshMotion.standard,
                  height: DshSpace.controlSm + 2,
                  decoration: BoxDecoration(
                    color: i == index ? c.layer1 : Colors.transparent,
                    borderRadius: BorderRadius.circular(DshRadius.sm),
                    boxShadow: i == index ? DshShadow.lv1 : null,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    items[i],
                    style: (i == index ? DshType.xsStrong13 : DshType.xs13)
                        .copyWith(color: i == index ? c.ink : c.ink3),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 底部弹层容器：R28 顶角 + 拖拽把手 + 可选标题和动作区。
class DshSheet extends StatelessWidget {
  const DshSheet({
    super.key,
    this.title,
    this.titleAction,
    required this.child,
    this.actions,
    this.scrollable = true,
    this.maxHeight,
    this.padding = const EdgeInsets.fromLTRB(
      DshSpace.xl,
      DshSpace.sm,
      DshSpace.xl,
      DshSpace.xl,
    ),
  });

  final String? title;

  /// 标题右侧动作槽（如「上级」「全选」）。
  final Widget? titleAction;
  final Widget child;
  final Widget? actions;
  final bool scrollable;

  /// 弹层最大高度（不传则按内容自适应）。
  final double? maxHeight;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final c = DshPalette.of(context);
    final body = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: DshSpace.sm, bottom: DshSpace.md),
          child: Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: c.line4,
                borderRadius: BorderRadius.circular(DshRadius.pill),
              ),
            ),
          ),
        ),
        if (title != null || titleAction != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              DshSpace.xl,
              0,
              DshSpace.lg,
              DshSpace.md,
            ),
            child: Row(
              children: [
                if (title != null)
                  Expanded(
                    child: Text(
                      title!,
                      style: DshType.m16.copyWith(color: c.ink),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  )
                else
                  const Spacer(),
                ?titleAction,
              ],
            ),
          ),
        Flexible(
          child: scrollable
              ? SingleChildScrollView(padding: padding, child: child)
              : Padding(padding: padding, child: child),
        ),
        if (actions != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              DshSpace.xl,
              DshSpace.md,
              DshSpace.xl,
              DshSpace.sm,
            ),
            child: actions!,
          ),
      ],
    );

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: maxHeight ?? double.infinity,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: c.layer1,
          borderRadius: DshRadius.sheet,
          border: Border.fromBorderSide(DshStroke.side(c.line4)),
        ),
        // 内置键盘避让：弹层里有输入框时自动顶起，调用方不需要自己包 Padding。
        child: Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: SafeArea(top: false, child: body),
        ),
      ),
    );
  }
}

/// 弹出官方底部弹层（统一 R28 面 + 遮罩）。
Future<T?> showDshSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = true,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: isScrollControlled,
    backgroundColor: Colors.transparent,
    barrierColor: DshPalette.of(context).mask,
    elevation: 0,
    builder: builder,
  );
}

/// 空状态：图标 + 标题 + 说明 + 可选动作。
class DshEmpty extends StatelessWidget {
  const DshEmpty({
    super.key,
    this.icon = Icons.inbox_outlined,
    required this.title,
    this.message,
    this.action,
    this.compact = false,
  });

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final c = DshPalette.of(context);
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: DshSpace.xxxl,
          vertical: compact ? DshSpace.xxl : DshSpace.xxxl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: c.module,
                borderRadius: BorderRadius.circular(DshRadius.xl),
              ),
              child: Icon(icon, size: 26, color: c.caption),
            ),
            const SizedBox(height: DshSpace.lg),
            Text(
              title,
              textAlign: TextAlign.center,
              style: DshType.sStrong14.copyWith(color: c.ink2),
            ),
            if (message != null) ...[
              const SizedBox(height: DshSpace.sm),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: DshType.xs13.copyWith(color: c.ink3),
              ),
            ],
            if (action != null) ...[
              const SizedBox(height: DshSpace.xl),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

/// 提示条：状态色保持 1px 实边（官方规则），浅底承载文案。
class DshBanner extends StatelessWidget {
  const DshBanner({
    super.key,
    required this.message,
    this.icon,
    this.tone = DshBannerTone.info,
    this.trailing,
    this.onTap,
  });

  final String message;
  final IconData? icon;
  final DshBannerTone tone;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = DshPalette.of(context);
    final (fg, bg) = switch (tone) {
      DshBannerTone.info => (c.business, c.bubble),
      DshBannerTone.warn => (c.warnLabel, c.warnSoft),
      DshBannerTone.danger => (c.danger, c.dangerSoft),
      DshBannerTone.success => (c.ok, c.okSoft),
    };

    final content = Container(
      padding: const EdgeInsets.symmetric(
        horizontal: DshSpace.md,
        vertical: DshSpace.sm + 2,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(DshRadius.md),
      ),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 16, color: fg),
            const SizedBox(width: DshSpace.sm),
          ],
          Expanded(
            child: Text(
              message,
              style: DshType.xs13.copyWith(color: fg),
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: DshSpace.sm),
            trailing!,
          ],
        ],
      ),
    );

    if (onTap == null) return content;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(DshRadius.md),
        splashFactory: NoSplash.splashFactory,
        child: content,
      ),
    );
  }
}

/// [DshBanner] 的语气。
enum DshBannerTone { info, warn, danger, success }

/// 细进度条：4px 轨道 + 状态色填充（用量页、上下文占用）。
///
/// 自身撑满可用宽度（松约束下也成立），调用方不需要再包 SizedBox。
class DshProgressBar extends StatelessWidget {
  const DshProgressBar({
    super.key,
    required this.value,
    this.color,
    this.height = 4,
    this.track,
  });

  final double value;
  final Color? color;
  final double height;
  final Color? track;

  @override
  Widget build(BuildContext context) {
    final c = DshPalette.of(context);
    // LayoutBuilder：先拿到父级给的宽度，再按宽度定死轨道，避免
    // FractionallySizedBox 反过来决定自身宽度（松约束下会缩成一小截）。
    return LayoutBuilder(
      builder: (context, constraints) {
        final width =
            constraints.maxWidth.isFinite ? constraints.maxWidth : 120.0;
        return SizedBox(
          width: width,
          height: height,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(DshRadius.pill),
            child: Stack(
              children: [
                Positioned.fill(
                  child: ColoredBox(color: track ?? c.line2),
                ),
                Positioned.fill(
                  child: FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: value.clamp(0.0, 1.0),
                    child: ColoredBox(color: color ?? c.brand),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// 三点脉冲：思考中/运行中的官方活动指示。
class DshDots extends StatefulWidget {
  const DshDots({super.key, this.color, this.size = 4, this.count = 3});

  final Color? color;
  final double size;
  final int count;

  @override
  State<DshDots> createState() => _DshDotsState();
}

class _DshDotsState extends State<DshDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = DshPalette.of(context);
    final color = widget.color ?? c.ink3;
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < widget.count; i++) ...[
              if (i > 0) SizedBox(width: widget.size),
              Opacity(
                opacity: 0.3 +
                    0.7 *
                        (1 -
                            ((_ctrl.value - i / widget.count) % 1.0 - 0.5)
                                .abs() *
                                2)
                            .clamp(0.0, 1.0),
                child: Container(
                  width: widget.size,
                  height: widget.size,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

/// 分组卡片容器：把若干 [DshTile] 收进一张 R20 设置卡片，行间用发丝分隔。
class DshCardGroup extends StatelessWidget {
  const DshCardGroup({
    super.key,
    required this.children,
    this.margin = const EdgeInsets.symmetric(horizontal: DshSpace.pageH),
    this.padding = const EdgeInsets.symmetric(vertical: DshSpace.xs),
  });

  final List<Widget> children;
  final EdgeInsetsGeometry margin;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      rows.add(children[i]);
      if (i != children.length - 1) {
        rows.add(DshDivider(indent: DshSpace.md, endIndent: DshSpace.md));
      }
    }
    return DshCard(
      margin: margin,
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: rows,
      ),
    );
  }
}

/// 全屏加载：官方只有细环，不铺满色块。
class DshLoading extends StatelessWidget {
  const DshLoading({super.key, this.label});

  final String? label;

  @override
  Widget build(BuildContext context) {
    final c = DshPalette.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 1.6,
              color: c.ink3,
            ),
          ),
          if (label != null) ...[
            const SizedBox(height: DshSpace.md),
            Text(label!, style: DshType.xs13.copyWith(color: c.ink3)),
          ],
        ],
      ),
    );
  }
}

/// 页面级错误状态（保留重试入口）。
class DshError extends StatelessWidget {
  const DshError({
    super.key,
    required this.message,
    this.onRetry,
    this.retryLabel,
  });

  final String message;
  final VoidCallback? onRetry;
  final String? retryLabel;

  @override
  Widget build(BuildContext context) {
    final c = DshPalette.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(DshSpace.xxxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 28, color: c.danger),
            const SizedBox(height: DshSpace.md),
            Text(
              message,
              textAlign: TextAlign.center,
              style: DshType.xs13.copyWith(color: c.ink2),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: DshSpace.lg),
              DshButton(
                label: retryLabel ?? L10n.t('重试', 'Retry'),
                variant: DshButtonVariant.outline,
                size: DshButtonSize.sm,
                onPressed: onRetry,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
