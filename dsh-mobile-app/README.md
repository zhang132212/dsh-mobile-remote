# DSH Remote App（dsh-mobile-app）

> DeepSeek Harness 的移动端**原生 App**（**Android 7.0+ / iOS 15.0+**）：手机远程操作电脑上的 agent —— 发消息派活、看进度、收通知、审批决策、管理会话。
> 与同仓库的 `dsh-mobile-remote` 插件配套使用，共享同一套 `/m/api` 协议与 DeepSeek 设计令牌。

## 平台与差异

| 项 | Android 7.0+ | iOS 15.0+ |
|---|---|---|
| 渲染 | Impeller（Vulkan → GLES 自动回退；可切 Skia） | Impeller（Metal，唯一后端） |
| 悬浮球 / 后台常驻 | ✅ 悬浮窗 + 前台服务 | ❌ 平台不支持；入口隐藏 + 设置页说明（后台提醒用 Bark 推送） |
| App 内更新 | ✅ 验签 APK 安装 | ❌ 走 TestFlight / App Store |
| 文件保存 | 系统「下载」目录 | App「文稿」目录（文件 App 可见）+ 分享面板 |
| 文件选择 / 外部文档打开 | 系统选择器 / 分享 intent | UIDocumentPickerViewController + `CFBundleDocumentTypes` |
| 构建/分发 | Gradle + 自建 keystore | Xcode + SPM（无 Podfile）；免费账号侧载 7 天重签 |

> 完整平台差异与验证证据见仓库根 [docs/09-compatibility.md](../docs/09-compatibility.md) §4 与 [docs/ios-ci.md](../docs/ios-ci.md)。

## 功能

**连接**

- 📶 **扫码连接**：扫桌面 dsh 设置页「连接移动端设备」二维码，自动填入地址+口令；也支持手动输入；
- 🌐 **多地址自动切换**：收集局域网 / 组网 / `publicUrls` 候选地址，按可达性自动切换；下拉刷新重新收集。

**对话**

- 💬 **流式回复 + Markdown**（标题/列表/代码块/表格/引用/链接）、token 用量、**微信式无限上翻**；
- 👀 **活动条 + 思考面板**：思考中 / 工具执行中实时状态，可展开看思考内容；普通/调试双模式；
- 🖼️ **图片**：拍照/选图上传、聊天图片渲染与全屏预览；
- 💾 **消息操作**：复制、👍/👎 反馈（可取消）、fork 分支、斜杠命令菜单；
- ❓ **问询 / 审批卡**：agent 需要你拍板或授权时弹卡片（与 PC 端同一待办，任一端回答两端同步消失）；
- 🛠️ **会话工具弹层**：任务（后台任务，可取消）/ 子代理（查看+中断）/ 目标（查看、创建、暂停、继续、完成）。

**会话与配置**

- 🏠 **首页**：欢迎语 + 最近会话 + 底部输入框（模型/权限胶囊）；
- 📋 **会话列表**：标题、时间、工作目录，按工作区分组，下拉刷新，归档同源；
- ➕ **新建会话**：Agent 模式选择 + 工作目录跨盘浏览 / 新建文件夹；
- ⚙️ **设置**：余额与用量（DeepSeek / Codex / OpenCode Go）、充值跳转、默认 Agent/权限预设、模型提供商（37 个 dormant 提供商可配）、语言（中/英，即时生效）、深色模式三态、环境诊断、重新配置连接；
- 🔔 **通知中心**：完成/失败/待回答、未读角标、点击跳会话、单删/批量/清空；
- 📄 **文档阅读器**：浏览电脑文件并渲染 **md / txt / docx / xlsx**；公式渲染（KaTeX 字体）与 Word 原生 OMML 导出；外部文件「用 DSH Remote 打开」；
- 🫧 **悬浮球（Android）**：透明鲸鱼常驻桌面，空闲灰 / 有任务·通知·余额低亮蓝+红点；迷你面板（运行中会话/通知/打开 App/去充值）；
- 🔄 **应用内更新（Android）**：Ed25519 签名 manifest 验签 + sha256 校验后安装。

## 构建

前置：**Flutter 3.47+**（开发验证 3.47.7 / Dart 3.13.5）。

### Android

前置：Flutter SDK + Android SDK。

```powershell
cd dsh-mobile-app
flutter analyze        # 应为 No issues found
flutter test
flutter build apk --release
# 产物：build\app\outputs\flutter-apk\app-release.apk
```

**Release 签名**（正式分发必做；无 `key.properties` 时回退 debug 签名，仅自用）：

```powershell
keytool -genkeypair -v -keystore android/app/release.jks -keyalg RSA -keysize 2048 -validity 10950 -alias dsh
# 然后写 android/key.properties：
#   storePassword=<密码>
#   keyPassword=<密码>
#   keyAlias=dsh
#   storeFile=app/release.jks
flutter build apk --release
```

> keystore 与 `key.properties` 已 gitignore：勿提交、勿丢失（丢失无法对已发布 APK 升级）；换签名 = 换应用，用户需卸载重装并重新扫码。

### iOS（需 macOS + Xcode）

前置：macOS + Xcode（部署目标 **iOS 15.0**）。Windows/Linux 无法构建 iOS。

```bash
cd dsh-mobile-app
flutter pub get                               # 插件经 Swift Package Manager 集成，无需 pod install
flutter analyze
flutter test
flutter build ios --release --no-codesign     # 验证构建；产物 build/ios/iphoneos/Runner.app
flutter build ios --simulator --debug         # 模拟器版（冒烟/集成测试用）
```

- **签名安装**：Xcode 打开 `ios/Runner.xcworkspace` → Runner target → Signing & Capabilities 选自己的 Team；免费 Apple ID 可侧载（**7 天需重签**），公开分发走 TestFlight / App Store。
- **工程形态**：Flutter 3.47 默认 **Swift Package Manager（无 Podfile）** + **UIScene** 生命周期；bundle id `com.dsh.remote`，显示名 `DSH Remote`；
- **权限/配置**：`ios/Runner/Info.plist` 已含相机/相册/本地网络权限文案、md/txt/docx/xlsx 文档类型、文件共享、ATS 放行任意加载（用户可自填任意 DSH 地址）；
- **本地网络权限**：iOS 14+ 首次连接局域网会弹系统授权，**必须允许**；拒绝后首次请求会失败一次，App 会自动重试一次并显示「设置 → 隐私与安全性 → 本地网络」引导 + 「重试」按钮。

### 图标

- 改 `assets/icon-1024.png` → 运行 `python tools/make_icon.py` 生成 Android 各密度图标；
- iOS：运行 `python tool/ios/generate_app_icons.py` 生成 AppIcon（15 尺寸，无 alpha）+ LaunchImage。

### 测试与 CI

```bash
# 单元 / Widget / golden（Windows/macOS 均可）
flutter analyze && flutter test

# iOS 模拟器端到端冒烟（需 macOS + 已 boot 的模拟器）
flutter test integration_test -d <device-id>
```

> golden 基准图在 Windows 生成；非 Windows 平台自动跳过 golden 对比（iOS 视觉证据走模拟器截图）。
> CI：仓库根 [.github/workflows/ios.yml](../.github/workflows/ios.yml) 在 macOS runner 跑 analyze / 全量测试 / iOS 构建 / 模拟器冒烟 / integration_test / Android APK 回归，证据回传 `ci-artifacts` 分支；说明见 [docs/ios-ci.md](../docs/ios-ci.md)。

## 安装使用

1. **Android**：安装 `app-release.apk`（允许「安装未知来源应用」）；**iOS**：经 TestFlight / App Store，或按上面「构建 iOS」自行签名安装。
2. 打开 App →「扫码连接」对准电脑屏幕上的二维码（桌面 dsh 设置 →「连接移动端设备」），或手动输入电脑地址（如 `http://192.168.1.100:3080/m`）+ 访问口令。
3. 连接成功进入首页，直接发消息派活。

> 手机与电脑需在同一局域网，或处于同一虚拟组网（蒲公英 / Tailscale 等）。iOS 首次连接务必允许「本地网络」权限。

## 目录结构

```
lib/
  main.dart            入口：主题 / 抽屉导航 / 连接页 / 外部文档入口
  api.dart             API 客户端（插件 /m/api 全接口 + SSE 解析）
  store.dart           全局状态 + SSE 事件桥（重连退避 / 断线补拉）
  platform_support.dart 平台能力判定 + 文件通道封装（iOS 降级）
  theme.dart           DeepSeek 设计令牌（与官方 Web 客户端同源）
  md.dart / timeline.dart / dsh_kit.dart   Markdown、时间线、基础组件库
  scan_screen.dart     扫码连接页
  floating.dart        Android 悬浮球桥
  screens/             首页 / 对话 / 会话 / 通知 / 设置 / 文档 / 用量 / 提供商 / 弹层
  docs/                文档阅读器（md / docx / xlsx / 渲染 / 导出）
  math/                公式解析与 OMML 导出
  update/              Android 应用内更新（验签 / 下载 / 安装）
  l10n.dart / fmt.dart / logger.dart / models.dart / toast.dart / tui.dart  工具与本地化
test/                  单元 / Widget / golden 测试
integration_test/      iOS 模拟器端到端冒烟
tools/make_icon.py     Android 图标生成
tool/ios/generate_app_icons.py  iOS AppIcon / LaunchImage 生成
assets/                图标与 logo 源图
```

## 安全说明

- 连接信息（地址 + 口令）仅保存在本机 SharedPreferences，不联网上传；
- 仅限局域网 / 可信内网使用；App 放行明文 HTTP（Android `usesCleartextTraffic` / iOS ATS 任意加载），勿在公网使用；
- 二维码含访问口令，请勿截屏转发；
- iOS 上架前的加固建议（Keychain、日志位置、体积上限等）见 [docs/09-compatibility.md](../docs/09-compatibility.md) §8。

## 许可

MIT（与插件同仓库，见根目录 [LICENSE](../LICENSE)）。
