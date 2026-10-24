# iOS CI 运行摘要

- 结论：✅ **success**（iOS 通过；Android 回归结果见下）
- 仓库：zhang132212/dsh-mobile-remote　分支：ci/ipa
- commit：5e25e2128b0caa06c450322f17a137e13389e2c5
- run：40109432810（attempt 1）　触发：push
- 运行链接：https://github.com/zhang132212/dsh-mobile-remote/actions/runs/40109432810
- Flutter：3.47.7 stable（Dart 3.13.5）

## iOS（主结论）

- job 结果：success
- 证据结论：success

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
| integration-test | ❌ failure |
| collect-artifacts | ✅ success |

允许失败（不影响结论）：

- ios/integration-test（失败但按允许列表放行，不影响结论）

## 端到端冒烟（integration_test）

❌ **integration-test: failure** —— 当前在 ALLOW_FAIL_STEPS 里放行（不影响结论），但说明端到端冒烟没跑通，需人工确认。

## 性能 / 冒烟证据（模拟器 debug 构建）

| 指标 | 值 |
| --- | --- |
| 启动 PID | 37765 |
| simctl launch 调用耗时(ms) | 262867 |
| 启动到首帧(ms，约 1s 精度) | 278766 |
| 应用容器路径 | /Users/runner/Library/Developer/CoreSimulator/Devices/48B2DA2E-AF18-4E36-BB25-B25969A4EBCF/data/Containers/Bundle/Application/1533B9DE-8C7D-46E9-A409-149EF63A384D/Runner.app |
| 模拟器版 Runner.app | 183M（191692800 bytes） |
| 设备版 Runner.app |  24M（24670208 bytes） |
| 设备版 .app 归档 zip |  12M |
| Impeller 日志命中 | 1 |

说明：Flutter 3.47 在 iOS 上默认启用 Impeller（Metal）渲染；设备版为 release 构建，
模拟器版为 debug 构建（JIT + 调试开销），启动耗时只用于冒烟观察，不代表真机 release 性能。

## Android 回归（非阻塞）

- job 结果：success
- 证据结论：success
- release APK：77M（80378542 bytes）
- 说明：验证 Dart 侧改动没有破坏 Android 构建；失败不阻塞 iOS 结论。

## 产物目录

- ios/：build.log（全量日志）、smoke.png（模拟器截图）、summary.md、artifact-manifest.txt、
  sizes.txt、smoke.txt、test-failures.txt/tar.gz（若有失败）、Runner-device-release.app.zip（设备版 .app 归档）
- android/：build.log、summary.md、artifact-manifest.txt、sizes.txt
- run.json：机器可读运行信息（状态 / 各步骤 / 产物清单）

## 取回方式（无需 GitHub API token）

    git fetch origin ci-artifacts
    mkdir -p ci-artifacts-out && git archive FETCH_HEAD | tar -x -C ci-artifacts-out

或直接读单个文件（raw.githubusercontent.com 会缓存，约 5 分钟）：

    https://raw.githubusercontent.com/zhang132212/dsh-mobile-remote/ci-artifacts/summary.md
