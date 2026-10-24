# Android 回归构建（非阻塞）

- 结论：✅ success
- flutter build apk --release：success
- APK 大小：77M
- 说明：仓库无 key.properties，release 构建回退 debug 签名（见 android/app/build.gradle.kts）；
  本 job 只验证 Dart 侧改动没有破坏 Android 构建，失败不阻塞 iOS 结论。
