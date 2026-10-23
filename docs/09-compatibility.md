# 09 兼容性说明（Compatibility）

> 版本：v3.2.0（用量与额度；机制基线 0.1.2-rc.1） · 面向：开源使用者 / 二次开发 / 多设备部署

本文回答两个问题：**App 在哪些手机上能跑**，以及**插件在什么样的 Harness 上能跑**。

---

## 1. 版本要求

| 组件 | 要求 |
|---|---|
| 桌面端 DSH（Harness） | **v3.1.2/v3.1.3 机制基线：`0.1.2-rc.1` 服务包 = DSH Desktop v2.0.5**（approval/request 瀑布 answerer + `$events` 远程事件双端审批 + RPC 网关，见 §2）；旧基线 `0.1.1-rc.2` = v2.0.2 起适配（本文件 §2 同时保留两代机制说明，`apiProxy` 帧桥为旧内核路径） |
| dsh-mobile-remote 插件 | **v3.0.0 基线；v3.2.0+ 才提供用量与额度**；`/m/api/diagnostics` 可自检 |
| 手机 App（Android / iOS） | v3.0.0 基线（用量与额度需 v3.2.0+；使用同一 Release 的配套插件；App 与插件版本号独立）；不同版本可用但"谁旧谁吃亏"，详见 README「版本与兼容」；**Android 7.0+、64 位机型 / iOS 15.0+** |
| 字段级兼容（v3.1.0 候选） | `reasoning`/`title` 为纯增量字段：新插件+旧 App 无影响（忽略新字段）；新 App+旧插件自动回退（不渲染折叠块 / 悬浮球标题兜底短码）——任意组合均可使用 |
| 字段级兼容（v3.1.1） | `/m/api/directories` 根视图新增 `sep`（服务端路径分隔符）；新插件+旧 App 忽略该字段即可（旧 App 在 WSL 上仍按 `\` 拼接，由服务端`normalizeServerPath` 归一化兜底，浏览/建夹/建会话均可用）；新 App+旧插件缺少 `sep` 时按根视图推断分隔符——任意组合均可使用 |
| 用量与额度（v3.2） | 新插件+新 App 通过 `/m/api/account-usage` 显示 DeepSeek/Codex/OpenCode Go；旧 App 忽略新端点。新 App+旧插件进入该入口会显示“电脑端插件版本过旧”，不影响其它功能；升级插件后无需重新配置凭据 |
| 悬浮球面板用量与额度（v3.2） | 新 App+新插件：面板展开时按需展示三来源区块（金额行文字 + 配额行细条/颜色），整块可点进详情页。新 App+旧插件：区块整体降级为原有单行余额（点击仍=去充值），其余面板功能不受影响；旧 App 忽略新端点。无新增服务端契约 |
| Flutter 构建环境 | Flutter 3.47+（Dart SDK ^3.13；本工程验证版本 3.47.7） |

**快速自检**：手机 App → 设置 → 环境诊断。`services` 一节列出每个内核服务是否存在；**v3.1.3+ 看 `checks.approvalMode`**（生效策略）与 **`checks.remoteEvents`**（`true` = `$events` 双端呈现通道就绪，`false` = both 降级 mobile 或配置即 mobile/desktop）；`notes` 首行说明当前审批策略实际语义。旧内核（0.1.1-rc.2 及更早）宿主才会出现 `services.apiProxy` / `checks.respondBridge` / `checks.frameBridge` / `checks.pendingFrames`（帧桥 era 探测项，v3.1.3 起仅帧桥激活时输出）——**0.1.2-rc.1+ 宿主看不到这些键属正常**。

---

## 2. 内核耦合点与降级行为

插件与 Harness 的耦合分三档：**硬依赖**（缺失 = 对应功能不可用）、**软依赖**（缺失 = 功能降级）、**可选**（缺失 = 自动禁用该功能）。插件对每个依赖都做了存在性探测，**任何一项缺失都不会让插件崩溃或影响其他功能**。

### 2.1 服务（`ctx.get` / `ctx.inject`）

| 服务 | 用途 | 档位 | 缺失时行为 |
|---|---|---|---|
| `webServer` | 挂载 `/m/api`、`/m/events`、`/m/qr.png` 路由 | 硬依赖（插件存在的意义） | v2.4 起守卫：纯 headless 形态下插件静默无操作，不崩进程 |
| `sessions` | 会话列表/touch/创建/停止 | 硬依赖（内核核心） | 移动端会话功能不可用 |
| `agents` | 会话创建、状态 | 硬依赖（内核核心） | 同上 |
| `workspaceRegistry` | 工作区列表、会话归档（与 PC 端同一份状态） | 软依赖 | 归档/工作区筛选不可用；App 回退为 cwd 前缀分组（旧版兼容路径） |
| `messageFeedback` | 消息 👍/👎（与 PC 端同一份） | 软依赖 | 反馈菜单隐藏/报错 |
| `approval` | 权限策略读取（`setPolicy` 仅当存在时调用） | 可选 | 跳过策略写入 |
| `credentials` | DeepSeek 余额查询 | 可选 | 回退环境变量 `DEEPSEEK_API_KEY`；都没有则余额不可用 |
| `apiProxy`（0.1.1-rc.2 及更早） | 问询/审批帧桥 + 应答回写（旧内核通道） | 可选（v2.3+ 新功能） | 旧内核下手机不弹问询/审批卡（PC 端不受影响）；`/m/api/respond` 返回 503。v3.1.3 起该键与 `respondBridge`/`frameBridge`/`pendingFrames` 仅在帧桥激活时输出——0.1.2-rc.1+ 宿主缺失属正常 |
| `userQuestions` | （间接）问询链路 | 可选 | 无弹窗（同上） |
| `approval/request`·`user-questions/request` 瀑布（0.1.2-rc.1+） | Agent 作用域 Cordis 瀑布，插件 answerer 应答（0.1.2 移除了 apiProxy 后的新机制） | 软依赖 | 无瀑布宿主（旧内核）由 apiProxy 帧桥接管；手机弹窗功能不受影响 |
| `typertGateway` `$events` 远程事件（0.1.2-rc.1+，`both` 模式） | 插件进程内 $events 客户端：瀑布经内核转发到网关后与桌面 GUI 同收事件副本、先答生效（issue #9 双端呈现） | 可选（v3.1.3） | `approvalMode: both` 自动降级为 mobile（手机在线独占），日志与诊断 notes 说明 |

> ⚠ **approvalMode（v3.1.3，issue #9）语义**：`both`（默认）= 桌面 GUI 与手机同时弹卡、任一端先答即生效、另一端自动收卡（对齐 v3.1.1 帧桥体验；仅 0.1.2-rc.1+ 网关可用，旧宿主自动降级 mobile）；`mobile` = 手机在线独占应答（v3.1.2 行为），离线交桌面 GUI；`desktop` = 一律交桌面 GUI（手机不弹卡）。手机在场时待办 120s 无应答 fail-close（`unavailable` / 问询跳过），与 v3.1.2 一致。配置于 `cordis.patch.yml` → mobile-remote 行 `config.approvalMode`，重启生效。
>
> ⚠ **apiProxy 属私有协议**（旧内核通道）：`events.mux` 与 `respond` 的消息格式是 PC 端 GUI 的内部通道，**无版本稳定承诺**。插件以 `ctx.inject(["apiProxy"])` 获取并做函数存在性探测；若未来 Harness 重构该接口，桥会干净降级（不影响其他功能），随插件版本更新恢复。这是本插件对内核唯一的"越界"耦合，集中在 `lib/index.js` 的「问询/审批帧桥」一段（0.1.2-rc.1+ 内核无 apiProxy，该段静默不生效，改走瀑布 answerer + $events 双端呈现）。

### 2.2 事件与 RPC

| 内核接口 | 用途 | 风险与降级 |
|---|---|---|
| `ctx.on("session/event")` | 消息流/通知聚合/上下文窗口/Conversation timeline | 事件形态随版本演进；未知类型进入通用事件卡，能力缺失时 App 回退摘要模式 |
| `sessionQuery.readEvent`（可选） | Tool activity 与未知 Visible event 的按需无损详情 | 不存在时回退快照；旧历史详情明确显示不可用，不猜测重建 |
| `ctx.on("agent/status")` | 状态点（绿/橙） | 同上 |
| `session.models` RPC | 模型目录（App 模型选择器） | 失败 → 目录为空，App 隐藏模型胶囊 |
| `settings.update`（`agent-presets` / `permission` 命名空间） | 默认预设修改 | 与 PC 端同一写入通道；命名空间变更会导致设置失败（App 报错提示） |
| `session.fork` | 消息分支 | 内核接口变化 → fork 失败提示 |
| `agent.followup` / `session.cancel` | 发消息/停止 | 同上 |

> ⚠ **子代理通知判定需要 `session.header.origin`（DSH ≥ 0.1.1-rc.2）**：通知聚合对子代理会话（`origin === "subagent"`）抑制完成/失败通知（与内核自身通知一致）。旧内核 header 无 `origin` 字段时，子代理完成/失败通知会被放行（不影响功能正确性，仅通知噪音）；fork 出的独立会话（无 origin）照常通知。
>
> ⚠ **v3.1.0 候选新增字段（纯增量，无协议破坏）**：`assistant/message` 摘要的 `reasoning`（思维链正文，仅非空时下发，≤20000 字符）与 `/m/api/bootstrap` 的 `agents[*].title` / `sessions[*].title`（会话标题，空则兜底短码）。旧版 App 按 key 取值、忽略未知字段；旧版插件缺少这些字段时新版 App 自动回退（不渲染折叠块 / 悬浮球显示 id 短码）。两端任意组合均可正常使用。

> ⚠ **Issue #1 时间线能力协商（纯增量）：** `/bootstrap` 与 SSE `hello` 的 `capabilities.eventTimeline` 声明 `detail`、`unknownEvents`、`callCorrelation` 等能力。新版 App 只在 `capabilities.eventTimeline.detail` 且事件摘要带 `detail.available` 时请求 `/event-detail`；能力是端点级声明，单事件仍可能因旧日志/离线而不可用。旧插件没有声明时继续使用已有摘要/历史路径，并把详情显示为不可用，不按插件版本号猜测能力。
>
> ⚠ **当前界面降级与 dormant-session 依赖：** seeded session 若只能读取当前 surface，`/event-detail` 返回 `degraded: true` 与 `detailMode: "current-surface"`，新版 App 展示不完整提示；无法读取时使用稳定错误码和重试，不显示原始异常。休眠会话的完整读取依赖 issue #7 的独立修复，本分支不复制该实现。
>
> ⚠ **`/bootstrap` 的 `agents[*].sessionId`（纯增量）**：`agentId` 与 `sessionId` 不是同一标识（`session:` 前缀、子代理场景），新版 App 按 session 维护运行状态，需要 bootstrap 一并下发映射，否则冷启动/重连后要等 `agent/status` 变化帧才知道会话在跑（发送键会短暂显示为「发送」而非「停止」）。旧插件不发该字段时 App 回退按 `agentId == sessionId` 取值。`agents[*].title` 的兜底短码也改由 sessionId 派生（旧插件缺字段时不影响）。

### 2.3 高度自定义化的 Harness

- **自定义权限预设/模型/Agent 预设**：App 全部从内核动态读取（catalog、session-config），不内置白名单；未知预设名显示为「…」（后续版本可拉取预设清单美化）。
- **第三方插件动作**：`ctx.mobileActions.register(...)` 注册后自动出现在 App 动作区（v0.1 契约：仅 text 字段）。
- **自定义问答 provider / 自动审批策略**：若用户的 Harness 已经接管人类问询（如自动答题插件、审批策略改为自动放行），内核**不会产生** `question/requested` / `approval/requested` 帧——手机不弹窗是**正确行为**，不是 bug。
- **多 profile**：插件按 profile 安装（`<profile>/node_modules/dsh-mobile-remote`），每个 profile 独立配置口令/连接。

---

## 3. Android 多品牌适配

App 为 Flutter 原生 APK（`com.dsh.remote`），渲染后端为 **Impeller（Vulkan，自动回退 OpenGLES）**。

| 维度 | 状态 | 说明 |
|---|---|---|
| 渲染 | ✅ 已验证（小米 17 Pro Max） | Flutter 引擎在无 Vulkan 机型自动回退 GLES；再老机型回退 Skia。历史风险点：部分旧 Mali GPU 的 Impeller 花屏（2024 年问题，现版本基本修复） |
| 系统版本 | Android 7.0+ | minSdk 跟随引擎默认 |
| 明文 HTTP | ✅ | `usesCleartextTraffic=true` 已配置（Android 9+） |
| 扫码 | ✅ | mobile_scanner（CameraX）全品牌通用 |
| 后台存活 | 部分依赖系统 | 国产 ROM 杀后台会断 SSE；App 有指数退避重连 + 回前台自动探测。系统级提醒走推送桥（ntfy/Bark/Server酱），不依赖 App 存活 |
| 深色/字体缩放 | ✅ | Flutter 主题自适应 |

**建议发布前实测**（借 1~2 台其他品牌即可）：① 长时间流式回复渲染；② 上翻深历史（Impeller 表现）；③ 熄屏后回前台自动重连。

**如遇渲染异常**：把 `dsh-mobile-app/android/app/src/main/AndroidManifest.xml` 中 `EnableImpeller` 改为 `false` 出一个 Skia 版验证；App 代码无需改动（列表结构两种后端都验证过）。

## 4. iOS（iOS 15.0+）

App 与 Android 共用同一套 Dart 代码与插件（`dsh-mobile-app/`），iOS 端只补平台差异层。**最低 iOS 15.0**（Flutter 3.47 工程模板与 image_picker_ios 的硬性要求），bundle id `com.dsh.remote`，显示名 `DSH Remote`。iOS 工程由 npm 无依赖的 Swift Package Manager 集成（**无 Podfile / 无需 CocoaPods**），使用 Flutter 3.47 的 **UIScene 生命周期**（`SceneDelegate` + `UIApplicationSceneManifest`，Xcode 27/iOS 27 SDK 起 Apple 强制要求）。

| 维度 | 状态 | 说明 |
|---|---|---|
| 渲染 | ✅ Impeller（Metal） | iOS 上 Impeller 是**唯一**渲染引擎（不能切 Skia）；启动日志可见 `Using the Impeller rendering backend (Metal)` |
| 系统版本 | iOS 15.0+ | 覆盖 iPhone 6s 及之后机型（Apple 支持范围）；模拟器验证为 iOS 26.2 / iPhone SE (3rd) |
| 明文 HTTP | ✅ 仅限可信内网 | Flutter 走 dart:io socket，ATS 不拦截；真正门槛是「本地网络」权限（见下行）。ATS 配置为**放行任意加载**（理由：用户可自填任意 DSH 地址，含局域网/组网/自建 http）；`NSLocalNetworkUsageDescription` 单独保留 |
| 本地网络权限 | ⚠️ 需用户允许 | iOS 14+ 首次连接局域网会弹系统授权；**拒绝或不理时首次请求会失败一次**——App 会自动退避重试，允许后即恢复；仍失败时到「设置 → 隐私与安全性 → 本地网络」放行 DSH Remote |
| 扫码连接 | ✅ | mobile_scanner（AVFoundation）；首次需相机权限；也可从相册识别二维码（需相册权限）。模拟器无摄像头，相机链路需真机 |
| 系统悬浮球 | ❌ 平台不支持 | iOS 无跨 App 悬浮窗 API。App 隐藏悬浮球入口并在设置页说明；后台提醒由 **Bark 推送**承担（与 Android 同一套推送配置，不依赖 App 存活） |
| 后台常驻 / 后台 SSE | ❌ 平台不支持 | iOS 退后台后 App 会被挂起，无法像 Android 前台服务那样保持长连接。iOS 只保证**前台**实时流式；回前台自动重连并补拉。提醒走推送桥 |
| App 内自更新 | ❌ 平台不支持 | iOS 不能安装 IPA。更新入口在 iOS 隐藏，版本升级只能经 **TestFlight / App Store**（或自行签名重装） |
| 文件保存 | ✅ 语义不同 | 保存到 App「文稿」目录（`Documents/DSH-Remote/`），设置 `UIFileSharingEnabled` 后可在「文件」App → 我的 iPhone → DSH Remote 查看；用户主动保存/导出时弹系统分享面板（UIActivityViewController）。iOS 没有系统「下载」目录 |
| 文件选择 | ✅ | 系统文档选择器（UIDocumentPickerViewController），取消返回 null |
| 外部文档打开 | ✅ | `CFBundleDocumentTypes` 声明 md/txt/docx/xlsx，可从「文件」App/其他 App「用 DSH Remote 打开」（冷启动/热启动均支持） |
| 系统通知 | ⚠️ 走推送桥 | App 内通知中心照旧；锁屏/后台提醒依赖 Bark / ntfy / Server酱（不依赖 App 存活） |
| 深色 / 字体缩放 | ✅ | Flutter 主题跟随系统 |
| 签名与分发 | ⚠️ 需 Apple 账号 | 自用：Mac + Xcode + 免费 Apple ID 侧载（**7 天重签**）；公开分发：TestFlight / App Store（需付费开发者账号） |

**平台差异（不可实现项，显式降级，不是 bug）**：

- **系统悬浮球**：Android 的透明悬浮球依赖 `SYSTEM_ALERT_WINDOW` + 前台服务，iOS 没有对应能力。iOS 端不显示悬浮球入口，设置页给出说明；"人不在电脑前"的提醒由**推送桥**（Bark 等）承担。
- **后台常驻**：iOS App 退到后台会被挂起，无法保持 SSE。iOS 端只保证**前台**实时；切回前台自动重连并补拉。
- **App 内自更新**：iOS 不允许 App 自行下载安装 IPA；更新走 TestFlight / App Store。
- **本地网络权限**：iOS 14+ 首次访问局域网需要用户授权（弹窗文案来自 `NSLocalNetworkUsageDescription`）。拒绝后局域网请求全部失败，需引导用户去系统设置放行。

**构建**（macOS + Xcode，Windows/Linux 无法构建 iOS）：

```bash
cd dsh-mobile-app
flutter pub get                               # 插件走 Swift Package Manager，无需 pod install
flutter analyze
flutter build ios --release --no-codesign     # 验证构建；产物 build/ios/iphoneos/Runner.app
flutter build ios --simulator --debug         # 模拟器版，用于冒烟
```

- iOS 工程：Swift Package Manager（`ios/Flutter/ephemeral/Packages/FlutterGeneratedPluginSwiftPackage` + Xcode 工程内的 local package 引用），**没有 Podfile**；
- Info.plist 权限/配置：`NSCameraUsageDescription`、`NSPhotoLibraryUsageDescription`、`NSLocalNetworkUsageDescription`、`NSAppTransportSecurity`（`NSAllowsArbitraryLoads=true`）、`CFBundleDocumentTypes`（md/txt/docx/xlsx）、`UIFileSharingEnabled`、`LSSupportsOpeningDocumentsInPlace`；
- 签名安装：Xcode 打开 `ios/Runner.xcworkspace` → Signing & Capabilities 选自己的 Team；
- CI（GitHub Actions macOS runner）：analyze / 全量测试 / release 构建 / 模拟器冒烟/集成测试，证据与取回方式见 [docs/ios-ci.md](ios-ci.md)。

**未覆盖 / 需真机验证**：相机扫码真机链路、真机局域网/组网直连、iPad 布局、真机启动耗时与滚动帧率（本期无 iPhone 真机，CI 为 macOS 模拟器；证据口径见交接报告，**不承诺**帧率/毫秒级性能数字）。

## 5. 已知问题清单（发布时如实告知）

| # | 问题 | 影响 | 状态/缓解 |
|---|---|---|---|
| 1 | 问询/审批桥依赖 apiProxy 私有协议 | 未来内核大版本可能断桥 | 干净降级 + 插件版本跟进；诊断可查 |
| 2 | 自定义权限预设名在 App 显示「…」 | 纯展示 | 后续拉取预设清单 |
| 3 | 国产 ROM 杀后台导致通知延迟（App 内角标） | 通知不及时 | 推送桥不受影响；App 重连后补拉 |
| 4 | Impeller 在极老 GPU 的潜在渲染问题（未实测） | 少数旧机可能花屏 | manifest 一行回退 Skia |
| 5 | 大体积消息（数万字符）首次滚动定位 | 仅首屏定位，无功能损失 | 列表已按段加载（50 条/页） |
| 6 | 明文 HTTP 通信 | 仅限可信内网 | 设计如此（docs/04-security.md）；公网必须虚拟组网（蒲公英推荐）/ TLS 反代（docs/06 §5/§6b） |
| 7 | 通知记录删除后，同会话同类事件会再生成新通知 | 符合预期（删除≠静音） | 已文档化 |
| 8 | GIF 发送后显示静态 | 与 PC 端一致（内核附件规范化取首帧重编码）| 动态链路已就绪（Flutter 原生支持），待内核保留动画附件 |
| 9 | 思维链块仅标题行（图标+字数+箭头）可点击切换，正文为可选中文本（点正文不切换，属设计） | 轻微认知成本 | 已文档化；折叠状态 v3.1.0 起按消息持久化（滚动/重进/重启保持） |
| 10 | 旧版 App（≤v3.0.0）在 WSL/类 Unix 服务端浏览目录会拼出 `/\home` 形态的路径 | 旧 App 在 WSL 端目录浏览受限 | **v3.1.1 已修复**（服务端 `normalizeServerPath` 归一化）；新版 App 按服务端 `sep` 拼接，任意组合可用 |
| 11 | 与 dsh-web 移动端远程（`@linxin666/dsh-remote-web-ui`）同装冲突 | 两者抢 `/m` 路由前缀（对方写死不可配），可能异常/崩溃 | 本插件 `path` 改 `/mr` 等非 `/m` 单段即可共存（App 自动适配，无需重装）；详见 FAQ |
| 12 | 手机在线时桌面端不弹审批/问询框（v3.1.2，issue #9） | 桌面用户无法在 PC 审批/应答（只能手机答或 120s fail-close） | **v3.1.3 修复**：默认 `approvalMode: both` 双端同卡、先答生效（0.1.2-rc.1+）；旧宿主/历史版本可用 `approvalMode: mobile \| desktop` 明确策略 |
| 13 | `approvalMode: both` 依赖内核 `$events` 通道 | 旧宿主（0.1.1-rc.2 及更早）无法双端同卡 | 自动降级 mobile 并写日志；诊断 `notes` 可查 |
| 14 | iOS 无系统悬浮球（平台限制） | 无法从其他 App 上直接弹面板；后台提醒只能靠推送桥 | 已显式降级：iOS 隐藏入口 + 设置页说明；Bark 推送不受影响（§4） |
| 15 | iOS App 退后台会被挂起，SSE 断开 | 后台期间收不到实时流；回前台自动重连补拉 | 设计如此（iOS 无后台常驻）；提醒走推送桥（§4） |
| 16 | iOS 无 App 内自更新 | 无法像 Android 一样 App 内升级 | 升级走 TestFlight / App Store；更新入口在 iOS 隐藏（§4） |
| 17 | iOS 首次局域网连接可能失败一次 | 本地网络权限弹窗未决/被拒时系统可能先拒绝一次 | App 自动退避重试；仍失败则引导到系统设置放行（§4） |

## 6. 内置常量与"写死"数据速查

**零敏感写死**：口令、密钥、推送凭据全部在用户配置（`cordis.patch.yml`）或手机本地，代码与仓库中无任何密钥硬编码。

| 类别 | 内容 | 说明 |
|---|---|---|
| 设计令牌（有意） | 品牌色 `#426EFE` / 深色 `#0E1116` 等（App `theme.dart`）、`com.dsh.remote`、QR 协议 `DSHREMOTE\|地址\|口令`、`EnableImpeller=true` | 产品设计/通信契约，勿随意改 |
| 内核耦合词（有意） | 系统消息过滤词 `Current runtime context` / `This snapshot supersedes` / `background job `（App `chat_screen.dart`）、apiProxy 协议字段名 | 与内核/PC 端保持一致的隐藏规则 |
| 插件可配置项 | `path` / `authToken` / `cookieName` / `sessionTtlMs` / `rechargeUrl` / `maxConnections` / `pushUrls` / `pushCooldownMs` / `pushContent` / `rateLimit` / `trustedHosts` / `doneGraceMs`（v2.8.0）/ `lanBridge`（v3.0.0：`{enabled, port, host}`，默认关）/ `approvalMode`（v3.1.3：`both` 默认 \| `mobile` \| `desktop`） | schema 默认值，改配置即可 |
| 插件内置常量 | 通知上限 100、catalog 缓存 15s、SSE 心跳 25s、SSE 超时 15s、登录限流默认 10 次/60s（`rateLimit` 可配）、状态文件 `~/.dsh/mobile-remote/` | 合理默认，无需配置 |
| App 内置常量 | HTTP 超时 15/20s（余额 25s）、连接/探测超时 8s、地址表上限 8、重试退避 1s→15s、看门狗 15s 检查 / 心跳 75s（3 周期）、日志保留 15 天/256KB、聊天初始窗口 50 条、历史分段 30 条、上下文圆环阈值 70%/90%、思维链折叠手动状态键 `dsh_mr_reasoning_overrides`（按会话持久化，每会话软上限 100 条） | 合理默认；修改点集中在各文件顶部常量 |
| 已消除的写死 | 充值链接（原 App 硬编码 `platform.deepseek.com/top_up`） | v2.4.2 起走 `catalog.rechargeUrl`（插件配置为准） |

## 7. 发布签名

- Release APK 需正式 keystore：`dsh-mobile-app/android/app/dsh-release.jks` + `android/key.properties`（**均已 gitignore，切勿提交**）。
- 干净克隆无 key.properties 时自动回退 debug 签名（仅自用可安装；商店/公开分发必须自建 keystore）。
- 自建方法见 `dsh-mobile-app/README.md`「构建」一节。
- ⚠ 更换签名 = 新应用：用户需卸载重装并重新扫码。
- **iOS**：需要 Mac + Xcode + Apple 开发者账号——自用可用免费账号侧载（**7 天重签**），公开分发走 **TestFlight / App Store**（需付费开发者账号）。CI 只做 `flutter build ios --release --no-codesign` 的**未签名**构建验证；签名/上传在本地 Xcode 完成。iOS 没有 Android 那种"换 keystore = 换应用"的等价物，商店版本升级由 Apple 统一签名。

## 8. iOS 上架前加固清单（非移植阻塞项）

> 来源：iOS 移植期间的交叉审查（安全/性能）。以下均为**非移植阻塞项**——不影响 iOS 版可用性、不阻塞测试与交付；建议在**公开上架 / 长期维护**前处理，自用与 TestFlight 可先跑。

| # | 发现 | 影响 | 建议 | 阻塞性 |
|---|---|---|---|---|
| S1 | 连接目标校验偏弱：二维码内容只做前缀校验；首个探测请求即携带访问口令 | 恶意二维码可把口令发给任意主机；首个探测请求即带凭据 | 连接前弹「确认连接到此地址」；校验 URL scheme（仅 http/https）；探测阶段不带 token | 上架前建议 |
| S2 | 访问口令明文存 `NSUserDefaults`（SharedPreferences） | 越狱/备份场景可被读取 | 改用 Keychain 存储口令 | 上架前建议 |
| S3 | 日志文件写在 Documents 且开启 `UIFileSharingEnabled` | 日志（含连接地址等）对「文件」App/分享可见 | 移到 `Library/Caches`，仅导出时分享 | 上架前建议 |
| S4 | 下载无体积上限 | 大文件下载在 iOS 上可能 OOM 被杀 | 增加上限与提示（与 Android 端额度对齐） | 上架前建议 |
| S5 | docx/xlsx 解压无大小/条目上限 | 恶意压缩包（zip bomb）可打爆内存 | 解压前限制压缩比/条目数/总字节 | 上架前建议 |
| P1 | 文档解析在主 isolate | 超大 docx/xlsx 解析时 UI 冻结 | 解析移到 isolate（compute） | 非阻塞 |
| P2 | 流式回复每个 chunk 全量重新解析 Markdown | 长回复流式时 CPU 占用偏高 | 增量/分片解析或节流 | 非阻塞 |
| P3 | 本地网络权限被拒后的引导文案偏 Android 措辞 | iOS 用户可能找不到设置入口 | iOS 文案改为「设置 → 隐私与安全性 → 本地网络」 | 非阻塞（建议随下个版本修） |

**补充说明**：ATS 采用 `NSAllowsArbitraryLoads=true`（用户可配置任意 DSH 地址，含局域网/组网/自建 http）。注意 iOS 10+ 若同时声明 `NSAllowsLocalNetworking` 等细粒度键，系统会**忽略** `NSAllowsArbitraryLoads`、只放行本地网络，因此工程中**只保留** `NSAllowsArbitraryLoads`；本地网络隐私权限由 `NSLocalNetworkUsageDescription` 单独声明。公开上架时需在审核备注中说明明文 HTTP 的用途（仅连用户自建服务）。
