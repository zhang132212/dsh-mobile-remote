# DSH Remote App（dsh-mobile-app）
> DeepSeek Harness 的移动端原生 App（**Android / iOS 15.0+**）**手机远程操作电脑上的 agent** —— 发消息派活、看进度、收通知、审批决策、管理会话。
与 `dsh-mobile-remote` 插件配套使用（本仓库同目录的插件），共享同一套 API 与 DeepSeek 配色设计。
## 功能

> 平台：**Android 7.0+ / iOS 15.0+**。iOS 平台差异（无系统悬浮球、后台不常驻、无 App 内自更新、文件保存到 App 文稿、本地网络权限）见仓库根 `docs/09-compatibility.md` §4。

- 📶 **扫码连接**：扫桌面 dsh 设置页「连接移动端设备」二维码，自动填入地址+口令；也支持手动输入
- 🏠 **首页**：欢迎语 + 最近会话 + 底部输入框（模型/权限胶囊）
- 💬 **对话页**：流式回复、Markdown 渲染（标题/列表/代码块/表格/引用/链接）、token 用量、**活动条**（思考中/工具执行中实时显示，可展开看思考内容）、微信式无限上翻（滑到顶部自动加载更早，无断页）
- 📋 **会话列表**：标题（会话 ID） 时间 + 工作目录，下拉刷新
- 🔔 **通知中心**：完成/失败/待回答三色图标、未读角标、点击跳会话、全部已读
- ⚙️ **设置**：余额实时查询、充值跳转、**默认 Agent 预设 / 默认权限预设修改**、深色模式三态切换、环境诊断（带时间戳）、重新配置连接
- ➕ **新建会话**：模式选择 + 工作目录选择（跨盘浏览、新建文件夹）
- 🎨 **DeepSeek 配色**：浅色/深色双主题（#426EFE / #0E1116），跟随系统或手动切换
## 构建

前置：Flutter SDK（3.47+） + Android SDK。
```powershell
cd dsh-mobile-app
flutter analyze        # 应为 No issues found
flutter build apk --release
# 产物：build\app\outputs\flutter-apk\app-release.apk
```

### 构建 iOS（需 macOS + Xcode）

前置：macOS + Xcode（部署目标 **iOS 15.0**）+ Flutter 3.47+。Windows/Linux 无法构建 iOS。

```bash
cd dsh-mobile-app
flutter pub get                               # 插件经 Swift Package Manager 集成，无需 pod install
flutter analyze
flutter build ios --release --no-codesign     # 验证构建（产物 build/ios/iphoneos/Runner.app）
flutter build ios --simulator --debug         # 模拟器版，用于冒烟
```

- **签名安装**：Xcode 打开 `ios/Runner.xcworkspace` → Signing & Capabilities 选自己的 Team（免费 Apple ID 可侧载，**7 天需重签**；公开分发走 TestFlight / App Store）。
- **工程形态**：Flutter 3.47 的 Swift Package Manager 集成 + UIScene 生命周期，**没有 Podfile**；bundle id `com.dsh.remote`。
- **权限文案**：`ios/Runner/Info.plist` 已含相机/相册/本地网络权限与 md/txt/docx/xlsx 文档类型、ATS 放行任意加载（用户可自填任意 DSH 地址）。
- **CI**：GitHub Actions macOS runner 自动跑 analyze / 测试 / 构建 / 模拟器冒烟，见 `docs/ios-ci.md`。
- **图标**：改 `assets/icon-1024.png` 后运行 `python tools/make_icon.py`（同时生成 iOS AppIcon 与 Android 图标）再构建。

**Release 签名（Android）**：正式分发须自建 keystore（`android/key.properties` 存在时自动使用；不存在则回退 debug 签名，仅自用）：

```powershell
keytool -genkeypair -v -keystore android/app/release.jks -keyalg RSA -keysize 2048 -validity 10950 -alias dsh
# 然后写 android/key.properties：
#   storePassword=<密码>
#   keyPassword=<密码>
#   keyAlias=dsh
#   storeFile=app/release.jks
```

> 首次构建需下载 Gradle 依赖（约 5-10 分钟）；如遇 Kotlin 增量缓存损坏，删除 `build` 与 `.dart_tool` 后重试（`android/gradle.properties` 已设 `kotlin.incremental=false`）。
> 更换图标：把 1024×1024 PNG 覆盖到 `assets/icon-1024.png`，运行 `python tools/make_icon.py` 后重新构建。
> **keystore 与 key.properties 已被 gitignore**：勿提交、勿丢失（丢失无法对已发布 APK 升级）。换签名 = 换应用，用户需卸载重装并重新扫码。
> 渲染后端为 Impeller（Vulkan→GLES 自动回退）；个别旧机型异常时把 `AndroidManifest.xml` 的 `EnableImpeller` 改为 `false` 出 Skia 版。详见仓库根 `docs/09-compatibility.md`。

## 兼容性

- Android 7.0+ 全品牌（实测：小米 17 Pro Max）；**iOS 15.0+**（Impeller 为唯一渲染后端；构建走 SPM/UIScene；平台差异见 docs/09 §4）。
- 功能/服务依赖与降级行为见仓库根 `docs/09-compatibility.md`。
## 安装使用

1. **Android**：把 `app-release.apk` 传到手机安装（允许"安装未知来源应用"）；**iOS**：经 TestFlight / App Store 安装，或按上面的「构建 iOS」自行签名安装。
2. 打开 App →「扫码连接」对准电脑屏幕上的二维码（dsh 设置 →「连接移动端设备」），或手动输入电脑地址（如 `http://192.168.1.100:3080`） 访问口令。
3. 连接成功进入首页，直接发消息派活。**iOS 首次连接请允许「本地网络」权限**（设置 → 隐私与安全性 → 本地网络）。
## 目录结构

```
lib/
  main.dart         入口：主题、抽屉导航、连接页、返回键处理
  platform_support.dart  平台能力判定（iOS 降级/文件通道封装）
  api.dart          API 客户端（插件 /m/api 全接口 + SSE 解析）
  store.dart        全局状态 + SSE 事件桥（重连退避、断线补拉）
  theme.dart        DeepSeek 设计令牌（配色/圆角/阴影）
  md.dart           Markdown 渲染（与网页端同款样式）
  scan_screen.dart  扫码连接页
  screens/          首页 / 对话 / 会话 / 通知 / 设置 / 弹层

tools/
  make_icon.py      图标生成脚本
assets/
  icon-1024.png     图标源图
```

## 安全说明

- 连接信息（地址+口令）仅保存在本机 SharedPreferences，不联网上传。
- 仅限局域网/可信内网使用；App 已放行明文 HTTP（`usesCleartextTraffic`），勿在公网使用。
- 二维码含访问口令，请勿截屏转发。
## 许可

MIT（与插件同仓库，见根目录 LICENSE）
