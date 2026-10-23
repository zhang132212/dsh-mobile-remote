# iOS CI（GitHub Actions macOS）

> 维护：T4（ci-macos）。最后更新：2026-10-23。
> 工作流文件：`.github/workflows/ios.yml`　脚本目录：`tools/ios-ci/`
> 任务板：task-3（T4 GitHub Actions macOS CI）。

本文件描述 iOS 移植在 **GitHub Actions macOS runner** 上的构建 / 测试 / 模拟器冒烟闭环：
怎么触发、跑什么、产物在哪、怎么取、本地怎么等价复现、失败怎么排查。

---

## 1. 这套 CI 验证什么

| 目标 | 对应步骤 | 是否阻塞结论 |
|---|---|---|
| Dart 代码能编译、无静态问题 | `flutter pub get` + `flutter analyze` | 是 |
| 全量单测 / Widget 测试通过（含 golden） | `flutter test --reporter expanded` | 是 |
| **真机构建**能出包（Swift + SPM + Flutter 引擎） | `flutter build ios --release --no-codesign` | 是 |
| 模拟器构建 + 安装 + 启动 + 首帧渲染正常 | `flutter build ios --simulator --debug` + `sim-smoke.sh` | 是 |
| 集成测试（App 冒烟） | `flutter test integration_test -d <模拟器 UDID>` | **暂不阻塞**（见 §5.3） |
| Android 端没有被 iOS 改动带坏 | `flutter build apk --release`（ubuntu job） | 否（只记录） |
| 证据归档 | `report` job 回传 ci-artifacts 分支 | 否（回传失败只报警告，不影响结论，§6.5） |

---

## 2. 触发方式

- **自动**：push 到 `ios/port` 分支（任何文件）。
- **手动**：Actions 页面 -> iOS CI -> Run workflow（`workflow_dispatch`），可选参数：

| 输入 | 默认 | 说明 |
|---|---|---|
| `runner` | `macos-15` | macOS runner 标签；备选 `macos-14` / `macos-26` |
| `xcode_app` | 空 | 指定 `/Applications/Xcode_16.4.app` 之类的绝对路径；空 = runner 默认 Xcode |
| `allow_test_failures` | `false` | 排障用：`flutter test` 失败仍判成功（**不要**用它冒充绿） |
| `skip_android` | `false` | 排障用：跳过 Android 回归 job |

**并发策略**：同一分支同一时刻只保留一轮（`concurrency: cancel-in-progress`）。
新 push 会取消正在跑的那一轮——所以**连续 push 等于互相取消**；要迭代时请一次改完再 push，
或等一轮结束。手工重跑（Re-run）不会取消自己。

---

## 3. Runner 与工具链版本

| 项 | 值 | 依据 / 备注 |
|---|---|---|
| iOS runner | `macos-15`（arm64） | GitHub runner 镜像；默认 Xcode 16.4 |
| Android runner | `ubuntu-latest` | Android SDK 预装；用 setup-java 固定 **JDK 21**（工程用 AGP 9.1.0 / Gradle 9.5.0，JDK 21 更稳） |
| Xcode | 16.4（macos-15 默认） | Flutter 3.47.7 要求 **Xcode >= 15**、推荐 16（`flutter_tools/lib/src/macos/xcode.dart` 里 `xcodeRequiredVersion = 15`、`xcodeRecommendedVersion = 16`）。macos-15 同时提供 Xcode 26.x，可用 `xcode_app` 输入切换 |
| Flutter | **3.47.7 stable（Dart 3.13.5）** | 与本地 SDK 一致；用 `subosito/flutter-action@v2` 安装（`cache: true`） |
| 版本号定义处 | 工作流 `env.FLUTTER_VERSION` / `with.flutter-version` / 本文件 | 三处要一起改 |

> 注意：macOS 14 镜像已进入废弃流程（2026-11-02 起不再支持），**默认用 macos-15**；
> Xcode 26.x 尚无项目实测记录，切换前先用 `workflow_dispatch` 的 `xcode_app` 试跑。

---

## 4. 流水线结构（3 个 job）

```
ios（macOS）      —— 主结论：analyze / test / 设备版构建 / 模拟器构建 / 冒烟 / 集成测试
android（ubuntu） —— 回归：flutter build apk --release（非阻塞）
report（ubuntu）  —— needs: [ios, android]：下载两边证据 -> summary/run.json -> 推 ci-artifacts 分支
```

各 job 关键步骤（详细见 .github/workflows/ios.yml）：

**ios job**：Checkout -> 规范化脚本换行 -> 环境信息 -> iOS 工程检查 -> 安装 Flutter ->
`flutter pub get` -> `flutter analyze` -> `flutter test` -> 构建设备版（release, no-codesign）->
构建模拟器版（debug, --simulator）-> 模拟器冒烟（boot/install/launch/首帧/截图/存活）-> 集成测试 ->
收集产物 -> 汇总 `status.txt/summary.md` -> 上传 ios-evidence artifact。

**android job**：Checkout -> 规范化脚本换行 -> JDK 21 -> 记录工具链版本 -> 安装 Flutter -> 缓存 Gradle -> `flutter pub get` ->
`flutter build apk --release --no-pub` -> 收集 APK 证据 -> 上传 android-evidence artifact。
仓库没有 `android/key.properties`，release 构建会回退 debug 签名（`android/app/build.gradle.kts` 里已处理），
因此干净克隆也能构建；本 job 只验证"没被改坏"，不产出正式分发包。

> 已知问题（v2 首跑实测，已修）：Android job 里 `flutter pub get` 会以 releaseMode=false 生成
> `GeneratedPluginRegistrant.java`（含 dev 依赖 integration_test），而 `flutter build apk --release --no-pub`
> 不会以 releaseMode=true 重新注入插件 → release 编译报 `package dev.flutter.plugins.integration_test does not exist`。
> 修法（双保险）：① **build 不带 `--no-pub`**，让构建自己以 release 模式重新生成 registrant（过滤 dev 依赖）；
> ② 构建前仍临时摘掉 integration_test dev 依赖（`lib/` 不允许 import dev 依赖，语义等价），构建后立即恢复。
> 详见 workflow 的 build_apk 步骤。

**report job**：Checkout -> 下载 ios-evidence/android-evidence -> `assemble-report.sh`（汇总 summary.md / run.json /
status.txt / README.md）-> `publish-artifacts.sh`（孤儿提交 force push 到 ci-artifacts）-> 门禁
（iOS 红则整体红；Android 失败只记录）。

---

## 5. 失败语义

### 5.1 iOS 主结论
`ios` job 里 `analyze / test / build-device / build-sim / smoke` 任一步失败 ->
`verdict.sh` 写入 `status.txt=failure` -> 最终 `report` 门禁 exit 1 -> workflow 红。

### 5.2 Android 非阻塞
`android` job 失败不会改变 iOS 结论，也不会让 workflow 因它变红（job 级 `continue-on-error`）；
但会在 `ci-artifacts/summary.md` 的 Android 段落标红，需要人工跟进。

### 5.3 允许失败列表（ALLOW_FAIL_STEPS）
`verdict.sh` 支持 `ALLOW_FAIL_STEPS`（空格分隔的步骤名）：
列在其中的步骤失败只记录、不判红。**当前默认放行 `integration-test`**，因为集成测试刚接入、
可能受模拟器环境波动影响；等它连续稳定若干轮后，把 workflow 里 `ios.verdict` 的
`ALLOW_FAIL_STEPS` 改成空字符串即可转为阻塞。
另外 `allow_test_failures` 手工输入等价于把 `test` 加进允许列表。

---

## 6. 证据与产物（ci-artifacts 分支）

每次运行结束，`report` job 用 **GITHUB_TOKEN**（`permissions: contents: write`）把产物
以**孤儿提交 + force push** 推到 `ci-artifacts` 分支。**只保留最近一次**运行的证据，
**不进入业务分支**，失败也照常回传（`if: always()`）。

### 6.1 分支结构

```
ci-artifacts/
├── README.md               # 本分支说明 + 最近一次 run 信息
├── summary.md              # 本次运行总摘要（结论 / 步骤表 / 性能证据 / Android / 取回方式）
├── run.json                # 机器可读：status / jobs / steps / smoke / sizes / artifacts
├── ios/
│   ├── build.log           # 全量日志（所有步骤 tee 到同一个文件，含步骤分隔标记）
│   ├── smoke.png           # 模拟器启动后截图（首帧证据）
│   ├── smoke.txt           # PID / 启动耗时 / 首帧耗时 / 容器路径 / 包体积 / Impeller 命中
│   ├── sizes.txt           # 设备版/模拟器版 Runner.app 体积、归档 zip 体积
│   ├── artifact-manifest.txt  # bundle id / 版本 / sha256 / 架构 / Frameworks / 文件数
│   ├── summary.md          # iOS job 级摘要
│   ├── steps.txt / status.txt / failed-steps.txt / allowed-steps.txt
│   ├── env.txt             # macOS / Xcode / 模拟器 / CocoaPods 版本
│   ├── sim-devices.txt     # runner 上可用模拟器清单
│   ├── ios-project-report.txt  # bundle id / deployment target / Info.plist 权限 / 图标
│   ├── test-failures.txt   # 从日志抽取的失败行（有失败时）
│   ├── test-failures.tar.gz# golden 失败图（master/test/diff，有失败时）
│   ├── sim-log-tail.txt / launchctl-list.txt / *.ips  # 冒烟崩溃诊断（有崩溃时）
│   └── Runner-device-release.app.zip  # 设备版 .app 归档（DoD 要求）
└── android/
    ├── build.log
    ├── artifact-manifest.txt  # APK 路径 / 大小 / sha256
    ├── sizes.txt
    └── summary.md
```

### 6.2 取回方式（**不需要 GitHub API token**）

```sh
# 在仓库工作树的任意分支上执行（只读操作）
git fetch origin ci-artifacts
mkdir -p ci-artifacts-out
git archive FETCH_HEAD | tar -x -C ci-artifacts-out
# 之后看 ci-artifacts-out/ios/build.log、smoke.png 等
```

**兜底通道**：ios job 另有一个 `兜底回传` 步骤，会把 iOS 证据（< 8MB 的小文件，
显式排除 `*.zip` 归档，避免设备版 .app 重复推送）直推到 `ci-artifacts-ios` 分支。
正常情况下用不到；若 `report` job 出问题（artifact 传递失败等），仍可从该分支拿到
`build.log` / `smoke.png` 等关键证据。

> 若只想看某个文本文件，也可以直接读 raw：
> `https://raw.githubusercontent.com/<owner>/<repo>/ci-artifacts/summary.md`
> （raw 的 branch 路径有 CDN 缓存，约 5 分钟；要点最新的可用 commit sha 路径。）

### 6.3 查询运行状态（免鉴权、有限流）

public 仓库的 Actions 元数据可以匿名读，限额 **60 次/小时/IP**，轮询间隔建议 >= 45 秒：

```sh
# 最近几次运行
curl -s "https://api.github.com/repos/<owner>/<repo>/actions/runs?per_page=5"
# 某次运行的 job/step 状态（无需日志即可判断哪一步失败）
curl -s "https://api.github.com/repos/<owner>/<repo>/actions/runs/<run_id>/jobs"
```

> 日志下载（`/actions/runs/<id>/logs`）和 artifact 下载接口**需要鉴权**，
> 本项目的设计刻意不依赖它们（见 §6.4）。
> 由于并发策略会取消旧轮，**取证据时以 `run.json` 里的 `run_id` 为准**，不要假设分支内容就是页面上最近一轮。

### 6.4 网络与代理说明（本机环境）

- 本机（Windows）访问 api.github.com / raw.githubusercontent.com 经 HTTP 代理不稳定；
  实测可用方式：`ssh ssh1 "curl -s https://api.github.com/..."`（ssh1 有直连外网）。
- CI runner 上无此问题（runner 直连 GitHub）。

### 6.5 门禁与"证据回传"是解耦的

- workflow 的结论只由 **iOS 证据结论（status.txt）+ iOS job 结果**决定；
- **证据回传失败不会让整轮变红**，只在 gate 步骤打 `::warning::` 并在 Step Summary 里提示。
  回传到底成没成功，请以 `ci-artifacts` 分支是否更新（`git ls-remote origin ci-artifacts`）为准。
- 理由：回传依赖 token 权限 / 网络 / 体积限制，属于"基础设施问题"；把它和"代码/构建是否 OK"
  绑在一起会出现"全绿却红、且 failed-steps 为空"的误导现象。

---

## 7. 本地等价复现

> 本机是 Windows，**不能**编译 iOS；以下用于 macOS 机器（或 T5 的 macOS VM）复现，
> 也是"CI 红了怎么在本地查"的标准流程。

### 7.1 一次性准备

```sh
# Flutter 3.47.7 stable（与 CI 一致）
git clone https://github.com/flutter/flutter.git -b stable --depth 1
export PATH="$(pwd)/flutter/bin:$PATH"
flutter --version   # 期望 3.47.7 / Dart 3.13.5

xcode-select -p                 # 期望是一个 >= 16 的 Xcode
xcodebuild -version
xcrun simctl list devices available | grep iPhone | head
```

### 7.2 复现 iOS job

```sh
cd dsh-mobile-app

# 1) 依赖（注意 lockfile 里的 hosted 源；CI 会自动把镜像 URL 改成 pub.dev）
grep -n "pub.flutter-io.cn" pubspec.lock
sed -i '' 's#https://pub.flutter-io.cn#https://pub.dev#g' pubspec.lock   # macOS 用 -i ''
flutter pub get

# 2) 静态分析 + 全量测试（golden 在非 Windows 平台会按测试内逻辑跳过）
flutter analyze --no-pub
flutter test --no-pub --reporter expanded

# 3) 真机构建（不需要签名）
flutter build ios --release --no-codesign
ls -lh build/ios/iphoneos/Runner.app

# 4) 模拟器构建（设备版 .app 不能装模拟器，必须用 --simulator）
flutter build ios --simulator --debug
ls -lh build/ios/iphonesimulator/Runner.app
```

### 7.3 手工模拟器验证（与 sim-smoke.sh 等价）

```sh
UDID="$(xcrun simctl list devices available | grep -m1 -oE '[0-9A-F-]{36}')"
xcrun simctl boot "$UDID"
xcrun simctl bootstatus "$UDID" -b
xcrun simctl install "$UDID" build/ios/iphonesimulator/Runner.app

APP=build/ios/iphonesimulator/Runner.app
BUNDLE_ID="$(plutil -extract CFBundleIdentifier raw -o - "$APP/Info.plist")"   # 期望 com.dsh.remote
xcrun simctl launch --terminate-running-process "$UDID" "$BUNDLE_ID"         # 输出里带 PID
sleep 10
xcrun simctl io "$UDID" screenshot smoke.png
xcrun simctl spawn "$UDID" launchctl list | grep "UIKitApplication:$BUNDLE_ID"  # 有输出=进程存活
xcrun simctl get_app_container "$UDID" "$BUNDLE_ID" app                      # 应用容器路径
xcrun simctl spawn "$UDID" log show --last 2m --style compact | grep -i impeller | head
xcrun simctl terminate "$UDID" "$BUNDLE_ID"
xcrun simctl shutdown "$UDID"
```

### 7.4 直接跑 CI 脚本（macOS 上）

```sh
export APP_DIR=dsh-mobile-app
export CI_OUT="$PWD/ci-out"
export BUILD_LOG="$CI_OUT/build.log"
mkdir -p "$CI_OUT"
bash tools/ios-ci/check-env.sh
bash tools/ios-ci/pub-get.sh
bash tools/ios-ci/sim-smoke.sh           # 需要先 flutter build ios --simulator --debug
bash tools/ios-ci/collect-artifacts.sh
OUT_CHECKOUT=success OUT_ENV=success OUT_IOS_PROJECT=success OUT_INSTALL=success \
OUT_PUB=success OUT_ANALYZE=success OUT_TEST=success OUT_BUILD_DEVICE=success \
OUT_BUILD_SIM=success OUT_SMOKE=success OUT_INTEGRATION=skipped OUT_COLLECT=success \
bash tools/ios-ci/verdict.sh
```

脚本用 **macOS 自带 bash 3.2** 兼容写法（无数组 / mapfile / 大写展开等 bash4 语法），
本地用 bash 直接执行即可。

---

## 8. 平台差异与 golden 测试

- golden 基准图（`test/goldens/`）是**在 Windows 上生成和维护**的。
- 测试代码已做跨平台处理（Lead 修复，2026-10-23）：
  - `ui_gallery_test.dart` / `ui_pages_gallery_test.dart` 在**非 Windows 平台自动 skip** golden 用例；
  - Material 图标字体按 `FLUTTER_ROOT` 动态解析（不再硬编码 Windows 路径）。
- 因此 macOS CI 上 **`flutter test` 应全量通过**，不需要在 CI 里排除 golden 测试；
  如果 macOS 上出现 golden 失败，先看 `test-failures.tar.gz` 里的 diff 图，**不要**直接
  `--update-goldens` 覆盖基准图（会把 Windows 侧基准带偏）。
- 其它平台差异：iOS 无系统级悬浮球、无 App 内自更新（走 App Store/TestFlight）——这些属于
  Dart 侧降级逻辑，与 CI 无关，见 `docs/09-compatibility.md`。

---

## 9. 常见失败排查

| 现象（step 名） | 可能原因 | 处理 |
|---|---|---|
| 安装 Flutter 3.47.7 失败 | subosito/flutter-action 下载 storage.googleapis 失败；或版本号写错 | Re-run；确认 releases_macos.json 里有该版本（3.47.7 有 arm64/x64） |
| 环境信息 / xcodebuild 报错 | runner 默认 Xcode 版本变化；或磁盘满 | 看 build.log 的 `xcodebuild -version`；用 `xcode_app` 指定；macos-15 镜像信息见 runner-images 仓库 |
| flutter pub get 失败 | 网络 / lockfile 的镜像 URL 不可达；pub.dev 限流 | CI 会先把 lockfile 的 pub.flutter-io.cn 改写为 pub.dev；仍失败看 build.log 的 TLS/SocketException |
| flutter analyze 失败 | 代码有 warning/error（跨平台分支未覆盖） | 本地 `flutter analyze --no-pub` 复现 |
| flutter test 失败 | 某个测试依赖平台能力 / golden 差异 | 看 `test-failures.txt` 与 `test-failures.tar.gz`；本地同平台复现 |
| build-device 失败 | Swift/SwiftPM 编译错误、插件平台通道实现、部署目标不一致 | 看 build.log 里 `error:` 行；对照 `ios/Runner/AppDelegate.swift`、`ios/Flutter/ephemeral/Packages/...` |
| build-sim 失败 | 同上（debug 模拟器变体）；或 Xcode 不支持该模拟器架构 | 同 build-device；确认 `--simulator` 产物路径 `build/ios/iphonesimulator/Runner.app` |
| 冒烟 install 失败 | App 不是 simulator 版；设备/运行时不可用 | 冒烟只用 `--simulator` 产物；看 `sim-devices.txt` |
| 冒烟"进程不在 launchctl 列表" | 启动即崩溃（Swift 通道注册/插件缺失/SDK 版本） | 看 `sim-log-tail.txt`、`launchctl-list.txt`、`*.ips`、`smoke-fail.png`；本地按 §7.3 复现 |
| integration-test 失败 | 测试环境波动 / UI 断言与当前页面不一致 | 当前在 `ALLOW_FAIL_STEPS` 里放行；连续稳定后改为阻塞 |
| 回传 ci-artifacts 失败（gate 只 warning，不判红） | 仓库 Settings -> Actions -> General -> Workflow permissions 不是 **Read and write**；或 token 权限被限制 | 让 Lead 改仓库设置；临时可用 `ci-artifacts-ios` 兜底分支或 Actions 页面日志 |
| report job 下载 evidence 失败 | 前一个 job 的 upload-artifact 失败/名字不匹配 | 看 report job 日志；artifact 名固定为 `ios-evidence` / `android-evidence` |
| 运行长时间 pending | macOS runner 排队（public 仓库免费额度） | 等；不要重复 push（会取消排队中的旧 run） |
| 运行超过 100 分钟被取消 | job timeout（ios 100 / android 45 / report 20 分钟） | 看卡在哪一步；必要时调高 timeout 或拆 job |

---

## 10. 安全与隐私

- 仓库是 **public**：ci-artifacts 分支上的日志/截图/产物清单**所有人可见**。
  不要把 token、密钥、内网地址写进测试输出；新增脚本时不要在日志里 `set -x` 打印环境变量。
- `GITHUB_TOKEN` 只在 report job 的 push 步骤使用：以 `http.extraheader` 传 basic auth，
  不写进 remote URL、不落盘到业务仓库；日志里由 Actions 自动打码。
- 单文件推送上限 60MB（`ARTIFACT_MAX_BYTES`），避免撞 GitHub 100MB 硬上限；
  超大文件会被跳过并在日志里标注。
- 产物只进 ci-artifacts 分支（孤儿提交 + force push），**绝不提交到 ios/port / main**。

---

## 11. 维护指南（改 workflow / 脚本时）

1. **三处版本号同步**：`env.FLUTTER_VERSION`、`with.flutter-version`、本文件表格。
2. **脚本保持 bash 3.2 兼容**（macOS `/bin/bash` 是 3.2）：不要用关联数组、`mapfile`、
   大写展开语法、`<<<` 之外的 bash4 特性；空数组展开要加默认值。
   特别注意：**`read -d`（NUL 分隔读）是 bash 4+ 才有**，macOS 自带 3.2 会报 `invalid option`——
   需要遍历带空格文件名时用 `find -print | while IFS= read -r`（不要用 `-print0 -d ''`，v3 首跑就踩过：
   兜底发布脚本因此在 macOS 上静默 0 文件、分支没更新）。
3. **脚本必须 LF**：`tools/ios-ci/.gitattributes` 已声明 `*.sh text eol=lf`；
   workflow 第一步也会 `sed` 兜底换行。用 `git config core.autocrlf` 时别绕过。
4. **新增步骤要登记结果**：在 workflow 里给 step 设 `id`，把 `steps.<id>.outcome`
   通过环境变量传给 `verdict.sh`（`OUT_*`），并在 `verdict.sh` 里 `record_step`，
   否则 summary/run.json 看不到它。
5. **job 依赖**：`report` 依赖 `ios` 与 `android` 的 artifact 名称；改名字要两边一起改。
6. **本地校验**（Windows 也能做）：
   ```sh
   python -c "import yaml,io; yaml.safe_load(io.open('.github/workflows/ios.yml', encoding='utf-8'))"
   for f in tools/ios-ci/*.sh; do bash -n "$f"; done    # Git Bash 可用
   ```
7. **本地校验 YAML 只是语法**；表达式（`steps.*` / `needs.*` / `inputs`）语义建议用
   actionlint（`https://github.com/rhysd/actionlint`）或先 workflow_dispatch 试跑。

---

## 12. 当前状态与后续

### 12.1 首轮完整实测（2026-10-23，run 39981868876 / commit 13643a7，v1 workflow）

环境：**macOS 15.7.9 / Xcode 16.4 (16F6) / Flutter 3.47.7 / CocoaPods 1.17.0（未使用，走 SPM）**。

| 结果 | 实测数据 |
|---|---|
| flutter analyze | ✅ 约 19s |
| flutter test（全量） | ❌ 304 passed / 12 skipped / **3 failed**（全部是 `test/sse_cancel_window_test.dart` 的"残留连接"断言；同一文件在更早一轮 macOS 上是绿的 → 时序 flaky，T3 改为轮询等待中） |
| build-device（release, no-codesign） | ✅ **2m39s**，Runner.app **23MB**，bundle id **com.dsh.remote**，3.2.10 (33)，arm64；Frameworks = App / Flutter / **objective_c**（native assets 正常）；插件 bundle 齐全 |
| build-sim（debug, --simulator） | ✅ 约 2m26s，Runner.app **183MB**（universal x86_64+arm64） |
| sim-smoke | ✅ 首次 boot 1m47s → install → launch **PID 22022** → 12s 后进程存活 → 截图 **62,924 bytes**（连接页完整渲染：标题/扫码连接/电脑地址/访问口令/连接，中文字体正常） |
| 回传 ci-artifacts | ✅（该轮 status=failure 也照常回传，验证"失败也回传"） |
| 整轮耗时 | 约 **14m51s**（iOS job） |

结论：**Swift 编译、SPM（无 Podfile）、native assets（objective_c）、模拟器安装/启动/渲染全部通过**。

### 12.2 v3 实测（2026-10-23，run 39990093033 / commit 93840ce，三 job 全链路）

| 结果 | 实测数据 |
|---|---|
| **integration-test** | ✅ **success（首次真跑通，不是 allow-fail）**：Xcode build 136s + 用例 17s，`All tests passed!`；日志里用真实 UDID 启动（不再是 `-d iPhone`） |
| **Android release APK** | ✅ **success，APK 77MB**（80,378,542 bytes，sha256 `7a5b086c…432e7a`）；修复了 dev 依赖 `integration_test` 混入 release registrant 的问题（build 去掉 `--no-pub` + 构建前临时摘除 dev 依赖） |
| build-device | ✅ 24MB（24,670,208 bytes，arm64） |
| build-sim | ✅ 183MB（191,660,032 bytes） |
| sim-smoke | ✅ PID 26441，launch 调用 3181ms，**首帧 10280ms**，Impeller Metal 日志命中 1，截图 63,712 bytes |
| flutter test | ❌ 仍 3 条 `sse_cancel_window`：`active=1 idle=0 closing=0 responses=1`（重建用例 `active=3`）。已确认客户端 `IOClient.close()` 内部是 `HttpClient.close(force:true)`（package:http 1.6.0 源码），所以更像 FakeSse 服务端没清理/度量口径问题，T3 修测试度量或平台化处理中 |
| report / 回传 | ✅ ci-artifacts 已更新（run.json status=failure 仅因 test）；⚠️ 兜底分支 ci-artifacts-ios 本轮**没更新**——原因是发布脚本用了 bash4 的 `read -d`，macOS 3.2 不支持 → 已改为 `find -print | read -r`，并把兜底步骤移到 upload 之前，确保失败日志也进证据 |

### 12.3 交叉审查修复（v2 首批，v3 已生效）

- 门禁与证据回传解绑（F1）、integration_test UDID 读取修正并删除 name 兜底（F2）、
  artifact 布局自动探测 + 显式断言（F4）、iOS 工程检查改为诚实硬门禁（F5）、Android 改 JDK 21 并记录工具链版本（F6）、
  兜底分支排除 zip（F7）、发布脚本支持带空格文件名（F8）、Impeller 日志只取一次（F9）。
- v4 补充：Android build **不带 `--no-pub`**（release 模式重新注入，过滤 dev 依赖）+ ATS 检查措辞（只保留 `NSAllowsArbitraryLoads`，无 `NSAllowsLocalNetworking` 属设计）。

### 12.4 待办

- SSE 三条用例：等 T3 选定「服务端度量修正 / 平台条件处理」方案后转绿；
- test 全绿 + integration-test 稳定 2 轮后，把 integration-test 移出 `ALLOW_FAIL_STEPS` 转为阻塞；
- 兜底分支 ci-artifacts-ios 在下一轮确认恢复更新；
- 视需要给设备版/模拟器版构建加 SPM 缓存（当前设备版约 2-3 分钟，可接受）；
- 如需在 macOS 上维护 golden 基准，再引入按平台命名的 golden（`goldens/<platform>/`），当前不需要。
