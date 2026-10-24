# iOS CI 运行摘要（iOS job）

- 结论：✅ **success**
- 备注：以下步骤失败但按允许列表放行（不影响结论）：integration-test
- 仓库：zhang132212/dsh-mobile-remote　分支：ci/ipa　commit：5e25e2128b0caa06c450322f17a137e13389e2c5
- run：40109432810（attempt 1）　触发：push
- runner：GitHub Actions 1000000224（macOS/ARM64）

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
| integration-test | ❌ failure |
| collect-artifacts | ✅ success |

## 性能 / 冒烟证据（模拟器 debug 构建）

| 指标 | 值 |
| --- | --- |
| 启动 PID | 37765 |
| simctl launch 调用耗时(ms) | 262867 |
| 启动到首帧(ms，约 1s 精度) | 278766 |
| 应用容器路径 | /Users/runner/Library/Developer/CoreSimulator/Devices/48B2DA2E-AF18-4E36-BB25-B25969A4EBCF/data/Containers/Bundle/Application/1533B9DE-8C7D-46E9-A409-149EF63A384D/Runner.app |
| 模拟器版 Runner.app | 183M（191692800 bytes） |
| Runner 可执行文件 | 123136 bytes |
| 设备版 Runner.app |  24M（24670208 bytes） |
| 设备版 .app 归档 zip |  12M |
| Impeller 日志命中 | 1 |

说明：Flutter 3.47 在 iOS 上默认启用 Impeller（Metal）渲染；设备版为 release 构建，
模拟器版为 debug（JIT + 调试开销），启动耗时仅用于冒烟观察，不代表真机 release 性能。

## 失败 / 未完成步骤

（无）

> ⚠️ **以下步骤失败但被允许列表放行，不能当成绿**：integration-test —— 例如 integration-test 失败说明端到端冒烟没跑通，需人工确认。

- integration-test

## 端到端冒烟（integration_test）

❌ **integration-test: failure** —— 当前在 ALLOW_FAIL_STEPS 里放行（不影响结论），但这说明端到端冒烟没跑通，需人工确认。

## flutter test 失败行（摘自全量日志，前 15 行）

    00:00 +0 -1: loading /Users/runner/work/dsh-mobile-remote/dsh-mobile-remote/dsh-mobile-app/integration_test/app_smoke_test.dart [E]
    00:00 +0 -1: Some tests failed.

## 证据文件

- smoke.png：模拟器启动后截图
- Runner-device-release.app.zip：设备版 .app 归档
- test-failures.txt：失败行抽取（2 行）
- build.log：全量日志
- artifact-manifest.txt：产物清单（大小 / bundle id / sha256 / 架构）

## 取回方式（无需 GitHub API token）

    git fetch origin ci-artifacts
    mkdir -p ci-artifacts-out && git archive FETCH_HEAD | tar -x -C ci-artifacts-out
