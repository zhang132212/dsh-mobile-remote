# ci-artifacts —— CI 运行产物（自动生成，勿手改）

本分支由 .github/workflows/ios.yml 的 report job 在每次 CI 运行后强制覆盖（孤儿提交），
只存放日志 / 截图 / 产物清单 / .app 归档，不含源码；不要合并回业务分支。

- 最近运行：run 40109432810 attempt 1
- 结论：success
- commit：5e25e2128b0caa06c450322f17a137e13389e2c5　分支：ci/ipa
- runner：ios=macOS、android=ubuntu

目录结构：

    ios/       iOS job 证据（build.log / smoke.png / summary.md / artifact-manifest.txt / sizes.txt / smoke.txt）
    android/   Android job 证据（build.log / summary.md / artifact-manifest.txt / sizes.txt）
    summary.md 本次运行总摘要
    run.json   机器可读运行信息

取回命令：

    git fetch origin ci-artifacts
    git archive FETCH_HEAD | tar -x -C <目录>

详细说明见仓库 docs/ios-ci.md。
