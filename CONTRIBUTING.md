# 贡献指南

欢迎任何形式的贡献：提 issue、修 bug、加功能、补文档、二次开发。

## 参与方式

- **报告问题**：GitHub Issues —— 说明环境（dsh 版本 / 平台）、操作步骤、现象；移动端问题附截图更佳
- **提交代码**：Fork → 分支 → PR；小改动直接 PR，大功能先开 issue 讨论
- **文档**：README / docs/ 的任何改进都欢迎
- **二次开发**：见 `docs/08-扩展开发指南.md` —— 欢迎基于本项目做自己的定制并回馈上游

## 开发环境

- **插件**：Node.js 18+；在 `~/.dsh/profiles/<desktop|web>` 以 `file:` 依赖引入（见 docs/06-install-run.md；桌面版移动端用 LAN 桥）
- **App**：Flutter 3.47+ + Android SDK；`flutter analyze` 必须零问题

## 代码约定

- 插件：ESM，遵循现有 `lib/index.js` 的风格；新端点必须在 `docs/03-api.md` 补文档
- 原型：`prototype/app-prototype.html`（设计参考，零构建，改完直接刷新浏览器看效果）
- App：`flutter analyze` 零 warning；UI 使用 `theme.dart` 设计令牌，不硬编码颜色
- 提交信息：中文或英文均可，一句话说明改动（如 `fix: SSE 解析死循环`）
- 兼容边界：改动涉及内核服务依赖时，对照 `docs/09-compatibility.md` 的降级约定

## 测试要求

- 插件改动：跑 `tools/e2e-check.mjs`（需 `DSH_MOBILE_TOKEN` 环境变量）
- App 改动：`flutter analyze` + 真机冒烟（发消息/收通知/新建会话）
- 新端点：在 `docs/05-test-cases.md` 补用例

## 安全底线

- 任何新端点默认走统一鉴权；敏感数据（口令/二维码）只允许 loopback 读取
- 不引入公网暴露；见 `docs/04-security.md`

## 发布新版本（维护者清单）

**分离版本原则**：App 的 `pubspec.yaml` 与插件的 `package.json` 独立版本；仅为有发布改动的一端 bump。Release/git tag 标识配套代码，当前 tag 跟随 App 版本。`v3.2.2` 对应 App `3.2.2+25` 与插件 `3.1.5-eun.1`；Release 说明须写明两端版本，不能按数字相等判断兼容。文档修正无需 bump 产品版本。

**main 分支完整性约定**：main **永远保持完整可发布状态**——每次合并前必须完成：涉及发布的端已 bump 版本、功能改动已更新 CHANGELOG、`flutter analyze`/`node --check` 通过；不推半成品。main 是维护分支，可以包含发布后的改动；安装正式版应锁定 Release tag。已发布的代码必须同步回 main。破坏性/实验性改动走分支或 PR，不进 main。

**插件改动（电脑端）**：改 `lib/index.js` → `node --check` → 同步安装目录并重启实测 → `package.json` 版本号（独立于 App）→ CHANGELOG 条目。

**App 改动（手机端）**：改代码 → `flutter analyze` + `flutter test` → `flutter build apk --release` + 真机实测 → `pubspec.yaml` 版本号（形如 `2.5.2+1`）。

**共同步骤**：
1. 文档同步（API/行为变化时更新 docs/03 等）
2. `git commit`（一句话说明改动）+ `git push origin main`
3. `git tag -a vX.Y.Z -m "..."` + `git push origin main --tags`
4. **本地归档**：运行 `dsh-mobile-app\tools\package-release.ps1` → 生成 APK 与插件包（两端版本号独立；以实际产物名为准），插件包名采用插件自己的版本号，不从 App/tag 版本推断
5. GitHub 网页创建 **Release**：选新 tag → 标题 `DSH Remote vX.Y.Z` → 说明写清本次改动 → **同时上传上面两个附件**
6. 大更新在 DSH 社区发帖；CHANGELOG 保持完整历史

**版本保留原则**：
- **旧版 Release 永远保留不删**——它们是版本历史，用户可自行选择下载任一版本回退；每次只**新增**一条 Release（选新 tag），新版本自动成为 Latest
- 发布时更新有改动的一端版本号，并在 CHANGELOG/Release 说明列出 App 与插件的配套版本
- 同一签名覆盖安装，用户升级无痛；换 keystore 除外（= 换应用）

> 提醒：v3.2.1 起 App 支持应用内更新，更新源为 `zhang132212/dsh-mobile-remote`；更早版本需手动下载 APK。重要修复在 Release 说明里写醒目；**不要更换签名 keystore**（同签名覆盖安装保留连接信息）。
