# iOS CI 运行摘要（iOS job）

- 结论：✅ **success**
- 仓库：zhang132212/dsh-mobile-remote　分支：ios　commit：6b8c1c9746382bb31aae6e0e3d5af8601c4fd4cf
- run：40089108312（attempt 1）　触发：push
- runner：GitHub Actions 1000000222（macOS/ARM64）

## 步骤结果

| 步骤 | 结果 |
| --- | --- |
| checkout | ✅ success |
| env | ✅ success |
| ios-project | ✅ success |
| install-flutter | ✅ success |
| pub-get | ✅ success |
| analyze | ✅ success |
| test | ✅ success |
| build-device | ✅ success |
| build-sim | ✅ success |
| sim-smoke | ✅ success |
| integration-test | ✅ success |
| collect-artifacts | ✅ success |

## 性能 / 冒烟证据（模拟器 debug 构建）

| 指标 | 值 |
| --- | --- |
| 启动 PID | 14602 |
| simctl launch 调用耗时(ms) | 8108 |
| 启动到首帧(ms，约 1s 精度) | 19919 |
| 应用容器路径 | /Users/runner/Library/Developer/CoreSimulator/Devices/48B2DA2E-AF18-4E36-BB25-B25969A4EBCF/data/Containers/Bundle/Application/B9CE6209-1EA1-4CD1-ADC1-91183DB0DDD4/Runner.app |
| 模拟器版 Runner.app | 183M（192036864 bytes） |
| Runner 可执行文件 | 123136 bytes |
| 设备版 Runner.app |  24M（24936448 bytes） |
| 设备版 .app 归档 zip |  12M |
| Impeller 日志命中 | 1 |

说明：Flutter 3.47 在 iOS 上默认启用 Impeller（Metal）渲染；设备版为 release 构建，
模拟器版为 debug（JIT + 调试开销），启动耗时仅用于冒烟观察，不代表真机 release 性能。

## 失败 / 未完成步骤

（无）

## 端到端冒烟（integration_test）

✅ **integration-test: success** —— 模拟器上真机形态端到端冒烟已跑通（不是允许失败放行）。

## 证据文件

- smoke.png：模拟器启动后截图
- Runner-device-release.app.zip：设备版 .app 归档
- test-failures.txt：失败行抽取（0 行）
- build.log：全量日志
- artifact-manifest.txt：产物清单（大小 / bundle id / sha256 / 架构）

## 取回方式（无需 GitHub API token）

    git fetch origin ci-artifacts
    mkdir -p ci-artifacts-out && git archive FETCH_HEAD | tar -x -C ci-artifacts-out
