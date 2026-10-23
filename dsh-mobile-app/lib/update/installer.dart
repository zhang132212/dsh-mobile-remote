// M1：APK 安装——经原生通道触发系统安装器（FileProvider content URI + 未知来源引导）。
//
// iOS 移植（T3）：iOS 不允许 App 内下载并安装可执行包（App Store 审核政策，也没有
// 安装器 API）。入口在 UI 层（设置页）隐藏，这里再兜一层：直接返回
// [ApkInstallResult.unsupportedPlatform]，不触碰 dsh/update 通道（iOS 侧未实现）。
import 'dart:io';

import 'package:flutter/services.dart';

import '../platform_support.dart';

/// 发起安装的结果（调用方据此给用户不同提示）。
enum ApkInstallResult {
  /// 已拉起系统安装器（安装结果由用户在系统界面决定）。
  started,

  /// 需先在系统设置允许「安装未知来源应用」后重试。
  needsPermission,

  /// 当前平台不支持 App 内更新（iOS：必须走 App Store / TestFlight）。
  unsupportedPlatform,
}

class ApkInstaller {
  static const MethodChannel _ch = MethodChannel('dsh/update');

  /// 触发系统安装器。
  static Future<ApkInstallResult> install(File apk) async {
    if (!DshPlatform.supportsInAppApkUpdate) {
      return ApkInstallResult.unsupportedPlatform;
    }
    final ok = await _ch.invokeMethod<bool>('installApk', {'path': apk.path});
    return ok == true
        ? ApkInstallResult.started
        : ApkInstallResult.needsPermission;
  }
}
