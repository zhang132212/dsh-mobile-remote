# DSH 官方风格 UI 规范（App 端）

本文件是 `dsh-mobile-app` 重构的**唯一样式契约**。所有页面按此改写，不再各自定义配色/圆角/字号。

数值来源：官方 DeepSeek Harness Web 客户端 `dsh-0.2.1-src/packages/client/ui-theme/src/styles/`
（`design-platform.css` 调色板、`gradient-shadow-text.css` 字体与阴影、`base.css` 圆角与动效），
配套规范 `dsh-0.2.1-src/docs/ui-radius.md`、`docs/web-styling.md`。

## 0. 铁律

1. **只改视觉，不改行为。** 公共类的名字、构造函数签名、参数名、回调语义一律保持原样；只重写 `build` 内部的呈现层。跨文件引用的 widget 不要改签名。
2. **不写死颜色。** 禁止 `Color(0x...)`（纯白/纯黑文字叠在状态色上等极少数场景除外）。一律走 `lib/theme.dart` 的令牌。
3. **不写死字号。** 用 `DshType` 阶梯。
4. **不写死圆角。** 用 `DshRadius` 阶梯。
5. **只动自己被分配的文件**（见任务说明）。不要碰 `theme.dart`、`dsh_kit.dart`；缺令牌时用现有令牌组合，并在交付说明里提出。
6. **文案走 i18n**：用户可见文字用 `L10n.t('中文', 'English')`。
7. **注释用中文**，风格与文件既有注释一致。
8. 完成后必须 `flutter analyze` 自己的文件且 **0 error**。

## 1. 取令牌

```dart
import '../theme.dart';   // 令牌
import '../dsh_kit.dart'; // 基础组件

// 页面里解析一次，后续复用
final c = DshPalette.of(context);
...
color: c.ink2,
```

旧写法 `DshColors.ink3(context)` 仍然可用（静态兼容层），新代码优先 `DshPalette.of`。

## 2. 颜色令牌（`DshPalette` / `DshColors`）

| 令牌 | 官方变量 | 用途 |
|---|---|---|
| `bg` | `--dsw-alias-bg-base` | 页面底色 |
| `layer1/2/3` | `--dsw-alias-bg-layer-1/2/3` | 卡片、浮层填充（L2 = 设置卡片默认） |
| `sidebar` | `--dsw-specific-sidebar-fill` | 侧栏/会话列表底 |
| `module` | `--dsw-alias-bg-module-platform` | 次级区块、分段控件槽底 |
| `docPreview` | `--dsw-alias-bg-document-preview` | 文档阅读底 |
| `skeleton` | `--dsw-alias-bg-skeleton` | 骨架屏 |
| `mask` | `--dsw-alias-bg-mask-1` | 模态遮罩 |
| `ink` / `ink2` / `ink3` | `label-primary/secondary/tertiary` | 主/次/三级文字 |
| `caption` / `dimmed` | `label-caption` / `label-dimmed` | 说明、占位 |
| `onInk` | `label-primary-foreground` | 主色填充上的文字 |
| `line1/2/3/4` | `border-l1..l4` | 描边（l2 常规分隔、l4 卡片/输入框） |
| `brand` / `brandHover` | `brand-primary` / `button-primary-hover` | **主按钮填充：浅色近黑、深色近白** |
| `brandSoft` | — | 品牌淡染底 |
| `link` / `business` | `link` / `state-business-primary` | 链接、业务蓝（唯一允许的蓝） |
| `ok` / `warn` / `warnLabel` / `danger` | `state-success/warn/error-*` | 状态色 |
| `okSoft` / `warnSoft` / `dangerSoft` | `state-*-tertiary` | 状态浅底 |
| `idle` | `state-idle-primary` | 未激活 |
| `hover` / `active` / `hoverSolid` | `interactive-bg-hover/active/hover-solid` | 交互叠加 |
| `navActive` / `navHover` / `navAccent` | `sidebar-nav-item-*` | 导航/列表选中态 |
| `input` | `specific-input-major` | 输入框主面 |
| `selector` | `specific-selector` | 胶囊选择器底 |
| `bubble` / `bubbleStrong` | `specific-bubble(-highlight)` | 用户气泡 |
| `codeBlock` / `codeBanner` / `inlineCode` | `markdown-code-block(-banner)` / `inline-code` | 代码 |
| `tag` | `markdown-tag` | 标签底 |
| `toast` / `onToast` / `tooltip` | `toast-*` / `tooltip-bg` | 浮层深底 |
| `floating` | `button-floating-fill` | 浮动按钮底 |
| `scrollbar` | `scrollbar-bg-l2` | 滚动条 |
| `diffAdded` / `diffDeleted` | `file-diff-*-bg` | diff |

**主按钮不是蓝色**：`brand` 浅色下是 `#0F1115`（近黑），深色下是 `#F9FAFB`（近白），文字用 `onInk`。
蓝色只用于链接、业务强调（`business`/`link`）。

## 3. 圆角（`DshRadius`，按角色选档）

| 角色 | 取值 |
|---|---|
| 行内代码、键帽、小细节 | `xs` = 4 |
| 紧凑控件（小按钮 H28、菜单项） | `sm` = 8 |
| 40px 图标/首字母方块（官方组件特例） | `tile` = 10 |
| 标准控件/单行单元格（按钮、输入框、导航行） | `md` = 12 |
| 多行单元格、嵌套表单组、代码块/diff | `lg` = 16 |
| 独立卡片（设置卡、消息气泡、引导卡） | `xl` = 20 |
| 主容器面（输入框面板、对话框、浮动面板） | `panel` = 28 |
| 胶囊/圆 | `pill` = 999 / `BoxShape.circle` |

预置 `BorderRadius`：`DshRadius.rXs/rSm/rMd/rLg/rXl/rPanel/rPill/sheet/menu/menuItem`。
不要因为卡片高就升级到 `panel`；多行单元格用 `lg`。

## 4. 字体（`DshType`）

| 令牌 | 规格 | 用途 |
|---|---|---|
| `xl24` | 24/32 · 600 | 页面主标题 |
| `l20` | 20/28 · 500 | 大标题 |
| `m16` | 16/28 · 500 | 标题栏、弹层标题 |
| `base16` / `baseStrong16` | 16/24 · 400 / 500 | 大正文 |
| `s14` / `sStrong14` | 14/22 · 400 / 500 | **正文默认** |
| `xs13` / `xsStrong13` | 13/20 · 400 / 500 | 次要文字、分组标题 |
| `xxs12` / `xxsStrong12` | 12/18 · 400 / 500 | 标签、元信息 |
| `xxxs11` / `xxxsStrong11` | 11/14 · 400 / 500 | 角标、极小字 |
| `mdH1..mdH4` | 21/30·700，19/28·700，18/26·700，14/24·600 | Markdown 标题 |
| `mdBase` / `mdBaseStrong` | 14/24 · 400 / 600 | Markdown 正文 |
| `mdTable` / `mdTableHead` | 13/22 · 400 / 500 | Markdown 表格 |
| `mdSmall` / `mdSmallStrong` | 12/20 · 400 / 600 | Markdown 小字 |
| `mdCode` / `mdCodeBlock` / `mdCodeSmall` | 12/19、11/19、11/16 · mono | 代码 |

取色写法：`DshType.s14.copyWith(color: c.ink2)`。

## 5. 描边与阴影

- **发丝线统一 0.5px**：`DshStroke.hairline` / `DshStroke.side(color)` / `DshStroke.divider(color)`。分隔线用 `line2`，卡片/输入框边框用 `line4`。
- **状态色描边保持 1px**：`DshStroke.state(color)`。
- **不要给普通卡片加投影**：卡片靠「填充 + 发丝描边」分层（`DshCard` 默认无阴影）。
- **浮层/输入框才用高度**：`DshShadow.soft`（输入框）、`panel`（浮层）、`prominent`（菜单/弹窗）；配 `border: 0` 时用发丝边，别既描边又投影。
- 其他：`lv1`（分段控件选中）、`lv2`、`lv3`（大弹窗）。

## 6. 间距（`DshSpace`）

`xxs 2 / xs 4 / sm 8 / md 12 / lg 16 / xl 20 / xxl 24 / xxxl 32`，
页面左右 `pageH = 16`，聊天内容左右 `chatH = 12`，
行高 `rowMin 52` / `rowMinTwoLine 64`，控件高 `controlSm 28 / controlMd 36 / controlLg 44`。
一律用 4 的倍数，不要出现 5/7/9/13/15 这类值。

## 7. 动效（`DshMotion`）

曲线 `DshMotion.standard`（cubic-bezier(0.4,0,0.2,1)），时长 `fast 100ms / normal 200ms / slow 300ms`。
用 `AnimatedContainer` / `AnimatedOpacity` / `AnimatedSwitcher` 表达状态过渡，不要自定义其他曲线。

## 8. 基础组件（`lib/dsh_kit.dart`，优先复用）

| 组件 | 说明 |
|---|---|
| `DshPage` | 页面脚手架（统一底色 + 可选标题栏/底栏） |
| `DshAppBar` | 官方标题栏：透明底、无阴影、底部发丝线、标题 16/24·500；`titleWidget` 可放「状态点 + 文字」 |
| `DshSectionHeader` | 分组标题（13/20·500·`ink3`），可带右侧动作 |
| `DshCard` | 设置卡片：R20 + 0.5px `line4` 描边 + `layer2` 填充，可 `onTap`/`selected` |
| `DshCardGroup` | 把多个 `DshTile` 收进一张卡片，行间自动发丝分隔 |
| `DshTile` | 列表行：H≥52/≥64、R12 hover/选中底、`leading`/`title`/`subtitle`/`trailing`/`trailingText`/`chevron`；`dense` 降到 H44；`background` 可覆盖整行底色（多选态用 `navAccent`） |
| `DshNavItem` | 侧栏/抽屉导航行：R12、图标 20 `ink2`、选中 `navActive` |
| `DshButton` | 官方按钮：`variant` primary/outline/ghost/danger/business，`size` sm(H28,R8)/md(H36,R12)/lg |
| `DshIconButton` | H32/R8 图标按钮，支持 `selected`、`badge`、`tooltip` |
| `DshTag` | 标签/胶囊（`tag` 底 + 11–12px） |
| `DshPill` | 胶囊选择器（999px + `selector` 底，`active` 为主色填充） |
| `DshStatusDot` | 状态圆点（可选 `pulse`） |
| `DshDivider` | 0.5px 发丝分隔线 |
| `DshSegmented` | 分段控件（外框 R12 + 4px 内衬 + R8 段） |
| `DshSheet` + `showDshSheet` | 底部弹层（R28 顶角 + 拖拽把手 + 标题/动作区 + **内置键盘避让**，调用方不要再自己加 viewInsets） |
| `DshToast` | Toast 面（`toast` 底 + `onToast` 字 + 发丝边 + `prominent` 阴影），定位与进出场由调用方决定 |
| `DshEmpty` | 空状态 |
| `DshBanner` | 提示条（`DshBannerTone.info/warn/danger/success`） |
| `DshProgressBar` | 4px 细进度条，**自身撑满可用宽度**，无需外包 SizedBox |
| `DshDots` | 三点脉冲（思考中/运行中） |
| `DshLoading` / `DshError` | 加载中 / 错误重试 |

## 9. 官方版式特征（写页面时照着做）

- **页面底色 `bg`**；成组内容放 `module` 或 `DshCard`；会话列表/侧栏类列表放 `sidebar`。
- **标题栏**：52 高、无阴影、底部 0.5px `line2`；标题 `m16`；右侧动作图标 20px、`ink2`。
- **分组**：`DshSectionHeader`（13/20·500·`ink3`）+ `DshCardGroup`，卡片之间 `lg` 间距。
- **列表行**：左图标 20px `ink2`，标题 `s14` `ink`，副标题 `xs13` `ink3`，右侧箭头 `chevron_right` 18px `caption`。
- **主按钮**近黑/近白，圆角 `md`；**次按钮**白底 + 发丝描边；**弱按钮**无底 hover 才出现 `hover` 叠色。
- **输入框**：`input` 面 + R28 + `DshShadow.soft` + 发丝边；发送键圆形 36 用 `brand` 填充。
- **弹层**：`showDshSheet` + `DshSheet`，遮罩 `mask`。
- **空状态**：`DshEmpty`（56 圆角方块图标底 + 标题 + 说明 + 可选按钮）。
- **状态色**：成功 `ok`、警告 `warn`、错误 `danger`、进行中 `business`；浅底用 `*Soft`。
- 中文正文行高偏大（官方 14/24），不要把行高压到 1.2。
