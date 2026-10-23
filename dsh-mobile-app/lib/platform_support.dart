// 平台能力判定 + 原生文件通道封装（iOS 移植 T3，2026-10）。
//
// 为什么单独抽这一层：
//   · Android 独有的系统能力（系统悬浮球 / APK 覆盖安装）在 iOS 不存在，必须显式
//     降级——不能"调了再说"（iOS 侧根本没有对应 MethodChannel，会抛
//     MissingPluginException），否则 UI 会出现"开关打开但实际没有服务"的假象；
//   · Flutter 的 `Platform` 是 dart:io 的编译期判断，单测无法 mock；这里集中提供
//     [DshPlatform.isIOS] 与仅测试可写的 override，让单测能覆盖 iOS 分支；
//   · dsh/files 在 Android/iOS 两端都有实现，但保存位置语义不同（Android「下载」
//     目录 vs iOS App 文稿），成功文案与异常兜底也统一收在 [FileBridge]，
//     避免散落在各页面各写一份。
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'l10n.dart';

/// 运行平台能力判定（生产代码只读；单测用 [debugOverrideIsIOS] 注入 iOS 分支）。
class DshPlatform {
  DshPlatform._();

  /// 仅测试用：强制按 iOS / 非 iOS 运行。生产代码不要写它。
  @visibleForTesting
  static bool? debugOverrideIsIOS;

  /// 当前是否运行在 iOS 上。
  static bool get isIOS => debugOverrideIsIOS ?? Platform.isIOS;

  /// 是否支持 Android 式的系统级悬浮球（iOS 不提供跨 App 悬浮窗能力）。
  static bool get supportsSystemFloatingBubble => !isIOS;

  /// 是否支持 App 内下载 APK 并覆盖安装（iOS 只能走 App Store / TestFlight）。
  static bool get supportsInAppApkUpdate => !isIOS;
}

/// `dsh/files` 通道异常：`message` 已是用户可读文案，页面 catch 后直接 toast 即可，
/// 不会再让 MissingPluginException / PlatformException 的原始字符串漏给用户。
class FileBridgeException implements Exception {
  const FileBridgeException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// `dsh/files` 通道封装（Android: MainActivity / iOS: AppDelegate 同名通道）。
///
/// 方法：
///   saveToDownloads {name, bytes} → 原生返回**展示用位置串**（如 "App 文稿/DSH-Remote/x.docx"，
///     不是完整沙盒路径——那会出现在 toast 里）；
///   pickFile → {name, bytes} | null（用户取消）；
///   getIncomingFile → {name, bytes} | null（冷启动暂存的外部文档）；
///   clearIncomingFile → 清理暂存。
class FileBridge {
  FileBridge._();

  static const MethodChannel channel = MethodChannel('dsh/files');

  /// 保存字节到手机：Android 写「下载/DSH-Remote」；iOS 写 App 文稿（「文件」App 可见）。
  ///
  /// [share]：iOS 专有。用户**主动**保存/导出（导出 docx、另存原件、下载文件）时传 true，
  /// 原生保存后弹出系统分享面板（UIActivityViewController）；Android 忽略该参数。
  static Future<String?> saveToDownloads({
    required String name,
    required Uint8List bytes,
    bool share = false,
  }) =>
      _guard(() => channel.invokeMethod<String>('saveToDownloads', {
            'name': name,
            'bytes': bytes,
            // 只在 iOS + 用户主动动作时透传；Android 端参数保持原样。
            if (share && DshPlatform.isIOS) 'share': true,
          }));

  /// 选择本地文件上传；取消返回 null。
  static Future<Map<String, dynamic>?> pickFile() =>
      _guard(() => channel.invokeMapMethod<String, dynamic>('pickFile'));

  /// 冷启动暂存的外部文档；无则 null。
  static Future<Map<String, dynamic>?> getIncomingFile() =>
      _guard(() => channel.invokeMapMethod<String, dynamic>('getIncomingFile'));

  /// 清掉原生暂存的外部文档（不影响已打开页面的内容）。
  static Future<void> clearIncomingFile() async {
    await _guard(() => channel.invokeMethod<void>('clearIncomingFile'));
  }

  /// 保存成功后的用户提示。
  ///
  /// iOS 没有系统「下载」目录：文件落在 App 文稿，必须说清去哪里找（「文件」App）。
  /// 原生返回的位置串是「DSH-Remote/文件名」这种**相对 App 文稿**的短串（T2 契约），
  /// 因此这里拼上「已保存到 App 文稿：」，避免出现「App 文稿/...」被重复前缀。
  static String savedMessage(String? where) {
    final trimmed = where?.trim() ?? '';
    final loc = trimmed.isEmpty ? '' : '：$trimmed';
    return DshPlatform.isIOS
        ? L10n.t(
            '已保存到 App 文稿$loc（可在「文件」App 查看）',
            'Saved to the app documents folder$loc (open it in the Files app)',
          )
        : L10n.t('已保存到手机$loc', 'Saved on phone$loc');
  }

  static Future<T?> _guard<T>(Future<T?> Function() call) async {
    try {
      return await call();
    } on MissingPluginException {
      throw FileBridgeException(L10n.t(
        '当前版本不支持该文件操作，请更新 App 后重试',
        'This file operation is not supported by the current build; please update the app',
      ));
    } on PlatformException catch (e) {
      throw FileBridgeException(_describePlatformError(e));
    }
  }

  /// 把原生错误码翻译成用户能看懂的话（T2 约定：pickFile 读取失败 = `read-failed`；
  /// 保存失败 = `save-failed`）。未知码兜底带上原生 message/code，避免丢排障信息。
  static String _describePlatformError(PlatformException e) {
    final detail = (e.message ?? '').trim();
    return switch (e.code) {
      'read-failed' => L10n.t(
          '读取文件失败（可能无权限或文件已失效）',
          'Failed to read the file (permission denied or unavailable)',
        ),
      'save-failed' => L10n.t(
          '保存文件失败（请检查可用存储空间）',
          'Failed to save the file (check free storage)',
        ),
      'pick-failed' => L10n.t(
          '打开文件选择器失败',
          'Failed to open the file picker',
        ),
      _ => L10n.t(
          '文件操作失败：${detail.isEmpty ? e.code : detail}',
          'File operation failed: ${detail.isEmpty ? e.code : detail}',
        ),
    };
  }
}
