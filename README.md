# DSH Remote — 插件

**把 DeepSeek Harness 开放给手机端的服务端插件。** 挂在 dsh 的 `webServer` 上，对外提供 `/m/api/*` + SSE：会话、消息、审批与问询、通知、改动审阅、用量、文档与文件。

- 插件版本：`3.1.5-eun.1`
- 配套 App：Android 在 [`main`](https://github.com/zhang132212/dsh-mobile-remote/tree/main)，iOS 在 [`ios`](https://github.com/zhang132212/dsh-mobile-remote/tree/ios)
- 本分支（`plugin`）**只放插件源码**，不带 Flutter 工程；由 `main` 导出，请勿在此直接开发

```
手机 App ──HTTP/SSE──► dsh 进程（本插件 /m）──► dsh 内核
                                              会话 · agent · 模型 · 审批 · 工作区
```

会话数据不落手机：App 是视图，插件是转发层，内核是唯一事实源。

---

## 安装

```powershell
# 方式一：按分支装（只要插件源码，不拉 Flutter 工程）
dsh plugin add github:zhang132212/dsh-mobile-remote#plugin

# 方式二：按 tag 装（App 与插件配套的发布版本）
dsh plugin add github:zhang132212/dsh-mobile-remote#v3.2.15

# 方式三：本地目录
dsh plugin add file:C:\path\to\dsh-mobile-remote
```

装完在 `cordis.patch.yml` 启用：

```yaml
- insert:
    - id: mobile-remote
      name: dsh-mobile-remote
      config:
        authToken: "<至少 16 位随机串>"
        lanBridge:
          enabled: true        # 桌面版必开：desktop 的 webserver 只听回环
          port: 3080
          host: 0.0.0.0
```

重启后：桌面版「设置 → 连接移动端设备」出现二维码；命令行 `dsh web` 默认已监听 `0.0.0.0:3080`，`lanBridge` 可不开。

> 桌面版 webserver 强制回环，手机连不进来；LAN 桥是插件在进程内另起的监听，**只转发 `${path}` 前缀的移动端面**（不转发内核网关，也不转发二维码数据）。

---

## 配置

| 字段 | 默认 | 说明 |
|---|---|---|
| `path` | `/m` | 挂载前缀，单段、以 `/` 开头。与别的插件抢前缀时改 `/mr` 之类，App 自动适配 |
| `authToken` | 空 | 访问口令。空 = 关闭认证；建议 ≥16 位随机串，每台电脑不同 |
| `cookieName` | `dsh_mobile_token` | 认证 cookie 名 |
| `sessionTtlMs` | 30 天 | 登录有效期 |
| `maxConnections` | `16` | SSE 连接数上限 |
| `trustedHosts` | `[]` | 额外放行的 Host（穿透 / 中继场景，不带端口） |
| `publicUrls` | `[]` | 写进二维码的公网 / 穿透入口（多设备、外网） |
| `pushUrls` | `[]` | 推送通道：`serverchan` / `ntfy` / `bark` / `generic`，可多个 |
| `pushCooldownMs` | `60000` | 同会话同类通知的最小间隔 |
| `doneGraceMs` | `15000` | agent 转 idle 后需稳定多久才算"真结束" |
| `pushContent` | `minimal` | `minimal` 只推事件类型 + 会话短码；`standard` 才含标题与详情 |
| `rateLimit` | `{10, 60000, 60000}` | 登录失败限流（超限 429） |
| `lanBridge` | `{false, 3080, 0.0.0.0}` | 桌面版必开；未设口令时拒绝启动 |
| `approvalMode` | `both` | `both` 双端同卡 / `mobile` 手机独占 / `desktop` 只走桌面 |
| `rechargeUrl` | DeepSeek 充值页 | 「去充值」跳转地址 |

---

## 端点

认证：`authToken` 校验后发 cookie；除 `/qr-config`（仅回环）外，全部走同一守卫。

| 组 | 端点 |
|---|---|
| 连接 | `bootstrap` `qr-config` `diagnostics` |
| 会话 | `sessions` `sessions/{archive,unarchive,touch,stop,fork}` `session-config` `workspaces` `directories` `catalog` |
| 消息 | `send` `send-receipt` `messages` `queue` `history` `event-detail` `events`(SSE) `respond` `feedback` |
| 时间线 | `jobs` `jobs/kill` `subagents` `subagents/interrupt` `goal` `todos` |
| 改动审阅 | `changes/summary` `changes/diff`（依赖宿主 `@deepseek-ai/dsh-workspace-changes`） |
| Git 只读 | `git/{capabilities,repository,branches,worktree,preview,graph,commit}` |
| 配置 | `llm-providers` `llm-providers/probe` `defaults` `actions` `commands` |
| 账户 | `account-usage` `balance` `usage` |
| 通知 | `notifications` `notifications/{read,delete}` `push-test` |
| 文件 | `files` `files/upload` `attachment` |

能力协商：`bootstrap` 的 `capabilities` 声明宿主实际具备什么（事件时间线、改动摘要……），App 据此显示或隐藏入口，不发无效请求。

---

## 安全模型

**信任边界**：假定手机与电脑之间的网络可信（家庭 WiFi、虚拟组网、加密隧道）；不提供端到端加密，也不加固公网暴露面。

已实现：

- 口令即凭据，登录失败按窗口限流；二维码含口令，等同凭据
- `/qr-config` 仅回环可读；LAN 桥只转发移动端面
- 非 GET 跨站防护：`Sec-Fetch-Site` 或来源主机不在允许集 → 403
- 事件白名单：系统提示词、LLM 请求快照、压缩摘要等内部记录不下发；详情只对允许类型返回
- 错误脱敏：不回传主机路径与内核原始异常
- 上传 ≤ 64 MB、文件名黑名单、目标会话不可解析直接 404
- fail-closed：认证、审批、问询超时倾向"不动作"

自担：强口令、网络隔离、不把 3080 裸露到公网、换口令后重启（旧二维码作废）。

---

## 兼容性

| 项 | 要求 |
|---|---|
| DSH | 机制基线 `0.1.2-rc.1`（Desktop v2.0.5）：双端审批走 `$events` + 瀑布 answerer；更旧内核走帧桥；headless 形态静默不动作 |
| Node | 20+（开发机 24.x 验证） |
| 宿主插件 | `@deepseek-ai/dsh-workspace-changes`（改动审阅，缺失自动隐藏） |

版本差不会崩：协议只加字段，新插件 + 旧 App / 新 App + 旧插件都能用；破坏性变更不做。发布物带 `update.json` 签名清单，供 Android App 的「检查更新」校验版本与 sha256。

---

## 开发

```powershell
node --check lib/index.js
node --test                                  # 回归用例（无 dsh profile 的用例会显式 skip）
node tools/timeline-contract-check.mjs       # 时间线契约
node tools/account-usage-check.mjs           # 用量归一化
node tools/e2e-check.mjs                     # 端到端冒烟
```

目录：

```
lib/index.js                      路由、认证、SSE 事件桥、时间线摘要、推送、审批
lib/client.js                     桌面设置页「连接移动端设备」
lib/account-usage.js              余额 / 配额聚合
lib/update-crypto.js              更新清单签名校验
lib/git-read-service.js           Git 只读工作台（按会话授权）
lib/git-read-bundled-provider.js  内置 git 命令 provider
test/ tools/                      回归与服务端验证脚本
docs/                             API / 安全 / 架构 / 兼容性文档
```

---

## 文档

| 文档 | 内容 |
|---|---|
| [docs/02-architecture.md](docs/02-architecture.md) | 架构、事件流、认证链路 |
| [docs/03-api.md](docs/03-api.md) | 全部端点与错误码 |
| [docs/04-security.md](docs/04-security.md) | 威胁模型与加固清单 |
| [docs/05-test-cases.md](docs/05-test-cases.md) | 验收用例 |
| [docs/06-install-run.md](docs/06-install-run.md) | 部署、穿透、签名与打包 |
| [docs/08-扩展开发指南.md](docs/08-扩展开发指南.md) | 动作区、自定义推送、二次开发 |
| [docs/09-compatibility.md](docs/09-compatibility.md) | 内核耦合点、降级行为 |
| [FAQ.md](FAQ.md) | 连接 / 审批 / 设备 / 安全速查 |

---

## 许可

MIT © 2026 Polaris。详见 [LICENSE](LICENSE)。
