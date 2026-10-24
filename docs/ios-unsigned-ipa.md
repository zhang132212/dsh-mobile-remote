# iOS 未签名 IPA（自动构建）与自签安装

> 每次推送到 `ios/port` 分支（或手动触发 iOS CI），GitHub Actions 会在 macOS runner 上执行
> `flutter build ios --release --no-codesign`，把 `Runner.app` 打包成
> `DSH-Remote-unsigned.ipa`，上传到 Actions artifact，并同步更新公开 Release：

## 下载

- **Release（推荐，免登录）**：
  https://github.com/zhang132212/dsh-mobile-remote/releases/download/ios-unsigned/DSH-Remote-unsigned.ipa
- **Actions artifact**：仓库 → Actions → iOS CI 最近一次运行 → `ios-unsigned-ipa`（需登录 GitHub）

## 为什么是「未签名」

iOS 不允许安装未签名 App。这个 IPA 里的二进制是未签名的，必须用你自己的 Apple ID 重新签名后才能装进 iPhone。
免费 Apple ID 签名的 App **7 天有效**，到期需要重签/续签。

## 安装方法 A：Sideloadly（Windows / macOS）

1. 电脑安装 [Sideloadly](https://sideloadly.io/)（Windows 需先装 iTunes 或 Apple 设备驱动）；
2. iPhone 用数据线连接电脑并在手机上点「信任」；
3. 打开 Sideloadly，把 `DSH-Remote-unsigned.ipa` 拖进去；
4. Apple 账号栏填入你的 Apple ID（会用于签名，不会上传到别处）；
5. 点 Start，等待签名 + 安装完成；
6. iPhone 上：设置 → 通用 → VPN 与设备管理 → 信任你的开发者证书；
7. iOS 16+ 还需：设置 → 隐私与安全性 → 开发者模式 → 打开并重启。

## 安装方法 B：AltStore（Windows / macOS，可自动 7 天续签）

1. 电脑安装 [AltServer](https://altstore.io/)；
2. iPhone 连电脑，AltServer 菜单 → Install AltStore → 选择你的 iPhone，输入 Apple ID；
3. iPhone 上打开 AltStore → My Apps → 左上角 + → 选择下载好的 IPA；
4. 首次安装后到 设置 → 通用 → VPN 与设备管理 信任证书；
5. 保持电脑与手机同一 Wi-Fi 并运行 AltServer，AltStore 会每 7 天自动续签。

## 方法 C：TrollStore（仅部分 iOS 版本）

iOS 14.0–16.6.1 等特定版本可装 TrollStore，直接永久安装未签名 IPA，无需续签；版本不支持则用 A/B。

## 常见问题

| 现象 | 处理 |
|---|---|
| Sideloadly 报 `Unable to sign` | 换用最新 Sideloadly；确认 Apple ID 密码正确（部分账号需 App 专用密码） |
| 安装后闪退/无法打开 | 到 设置 → 通用 → VPN 与设备管理 信任证书；iOS 16+ 确认开发者模式已开 |
| 7 天后打不开 | 免费签名过期：用 Sideloadly 重新安装，或 AltStore 自动续签 |
| 下载 404 | CI 还没跑完或还没推送构建；到仓库 Actions 页确认最近一次 iOS CI 成功 |

## 相关

- 连接服务器方式见 `docs/` 与服务器侧文档：https://111.228.59.79/m
