# 10 · UI 设计系统（官方 DSH 风格）

> 适用：`dsh-mobile-app/`（Flutter 原生 App）。本文说明 App 的视觉层如何与**官方 DeepSeek Harness Web 客户端**保持同源，以及改样式时的规矩。
>
> 迁移前的视觉是「Claude 式布局 + 自定义配色」；现在整套换成官方令牌体系。

## 1. 令牌来源

数值不凭感觉定，全部取自官方源码 `packages/client/ui-theme/src/styles/`：

| 官方文件 | 内容 | App 侧对应 |
|---|---|---|
| `design-platform.css` | 静态调色板 + 语义 alias（`--dsw-alias-*`、`--dsw-static-*`、`--dsw-specific-*`） | `lib/theme.dart` 的 `DshPalette` |
| `gradient-shadow-text.css` | 字体阶梯、阴影 `--dsw-shadow-lv*`、高度 `--dsw-elevation-*` | `DshType` / `DshShadow` |
| `base.css` | 圆角阶梯 `--dsw-radius-*`、字体族、动效曲线与时长 | `DshRadius` / `DshSpace` / `DshMotion` |
| `docs/ui-radius.md` | 圆角选档规范（按组件角色 + 高度） | `DshRadius` 的档位注释 |
| `docs/web-styling.md` | 样式归属：只用语义令牌、发丝描边 0.5px、浮层只用高度不叠边框 | 本文第 3 节 |

## 2. 三层结构

```
lib/theme.dart      令牌层：DshPalette / DshType / DshRadius / DshSpace / DshShadow / DshStroke / DshMotion / DshSwitch
lib/dsh_kit.dart    基础组件层：DshPage / DshAppBar / DshTile / DshCard / DshCardGroup / DshButton / DshIconButton /
                    DshTag / DshPill / DshNavItem / DshStatusDot / DshDivider / DshSegmented / DshSheet / showDshSheet /
                    DshToast / DshEmpty / DshBanner / DshProgressBar / DshDots / DshLoading / DshError
lib/screens/**      页面层：只消费上面两层，不写死颜色/字号/圆角
```

`lib/theme.dart` 里还保留了一层**静态兼容垫片** `DshColors.ink3(context)` 形式，供尚未迁移到 `DshPalette.of(context)` 的旧调用点使用；新代码统一写：

```dart
final c = DshPalette.of(context);   // 一次解析，多次读取
Text('标题', style: DshType.s14.copyWith(color: c.ink));
```

## 3. 硬性规矩

1. **不写死颜色**：禁止 `Color(0x...)`（`theme.dart` / `dsh_kit.dart` 除外）。
2. **不写死字号**：一律 `DshType` 阶梯（14/22、13/20、12/18、11/14 …）。
3. **不写死圆角**：一律 `DshRadius` 档位（4/8/12/16/20/28，40px 图标方块用特例档 `tile = 10`）。
4. **发丝描边 0.5px**：`DshStroke.hairline` / `DshStroke.side()`；状态色描边保持 1px（`DshStroke.state()`）。
5. **卡片靠填充 + 描边分层，不加投影**；浮层/输入框才用 `DshShadow.panel/prominent/soft`，且配 `border: 0` 语义（别既描边又投影）。
6. **主按钮不是蓝色**：`brand` 浅色下是 `#0F1115`（近黑）、深色下是 `#F9FAFB`（近白），文字用 `onInk`。蓝色只用于链接与业务强调（`link` / `business`）。
7. **间距 4 的倍数**：`DshSpace`，页面左右 16、聊天内容 12。
8. **文案走 i18n**：用户可见文字一律 `L10n.t('中文', 'English')`。

完整令牌表与官方版式特征见 `dsh-mobile-app/UI_STYLE_GUIDE.md`。

## 4. 视觉走查（golden 画廊）

没有真机/模拟器也能核对样式：两个测试文件用真实组件渲染 golden，产物在 `test/goldens/`（同步一份到 `docs/screenshots/ui-*.png`）。

```powershell
cd dsh-mobile-app
flutter test --update-goldens test/ui_gallery_test.dart test/ui_pages_gallery_test.dart
```

| 产物 | 内容 |
|---|---|
| `ui_gallery_light.png` / `ui_gallery_dark.png` | 令牌色板、字体阶梯、按钮、设置卡片与列表行、标签/状态/进度 |
| `ui_gallery_chat_light.png` / `ui_gallery_chat_dark.png` | 消息气泡、工具卡、输入区（composer）、空状态 |
| `page_home_*.png` | 首页（欢迎语、连接状态、最近会话、入口按钮） |
| `page_sessions_*.png` | 会话列表（工作区胶囊筛选、活跃/归档分段、会话行） |
| `page_notifications_*.png` | 通知中心（状态图标、未读点、多选态） |
| `page_settings_*.png` | 设置页（分组标题 + 设置卡片 + 列表行 + 开关） |

每个页面都出浅色与深色两张。测试环境默认字体把所有字形画成方块，用例里显式加载了系统中文字体（等线）；换机器若缺该字体，把 `_registerFont` 的路径改成机器上存在的中文 TTF 即可。Material 图标在 golden 里显示为方框属测试环境正常现象（真机由 `uses-material-design: true` 提供图标字体）。

页面级 golden 用假后端（`MockClient`）喂固定数据，只依赖页面自身的渲染路径；若某个页面在无网络下确实驱动不起来，用例会跳过它而不是放宽生产代码。

## 5. 二次开发

- **加页面**：`DshPage` + `DshAppBar` 起头，正文用 `DshSectionHeader` + `DshCardGroup` + `DshTile`，不要自己写卡片圆角与行高。
- **加控件**：先查 `lib/dsh_kit.dart` 有没有；确实需要一个通用新控件时加到 kit 里，而不是在页面里复制一份。
- **加令牌**：先在官方 `design-platform.css` 里找到对应语义变量，再在 `DshPalette` 补一个 getter（浅/深两套值都要），别在页面里 `copyWith` 凑近似色。
- **桌面端模块**：`lib/client.js`（设置页「连接移动端设备」）同样只消费 `--dsw-alias-*` 官方令牌，规矩与本文一致。
