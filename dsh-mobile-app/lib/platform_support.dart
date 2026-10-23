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
///   saveToDownloads {name, bytes, share?} → 原生返回**展示用位置串**
///     （iOS 为相对 App 文稿的 "DSH-Remote/文件名"；Android 为下载目录展示串；
///     都不是完整沙盒路径——那会出现在 toast 里）；
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
      // cross-review F6：Android 取消文件选择走 error('cancelled')（MainActivity.kt），
      // 契约语义应等同「用户取消」→ 返回 null，而不是弹「文件操作失败：cancelled」。
      if (e.code == 'cancelled') return null;
      throw FileBridgeException(_describePlatformError(e));
    }
  }

  /// 把原生错误码翻译成用户能看懂的话（cross-review F5）。
  ///
  /// 当前 T2（2026-10-24）在用码：
  ///   · read-failed  picker 选中的文件读取失败/为空
  ///   · save-failed  saveToDownloads 写盘失败
  ///   · pick-failed  presenter 不可用 / document picker 弹不出来（原 no-view 已废弃）
  ///   · busy         已有文件选择器在弹
  ///   · too-large    文件超过 24MB（与原生 kMaxDocBytes 一致）
  /// 兼容保留：no-view（旧构建）、bad-args（历史码）——同样翻成中文，
  /// 确保任何版本都不会把英文 code 直接冒到用户面前；未知码兜底带上原生 message/code。
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
      'bad-args' => L10n.t('文件参数异常', 'Invalid file arguments'),
      'busy' => L10n.t(
          '正在选择文件，请稍候',
          'A file picker is already open, please wait',
        ),
      'no-view' => L10n.t(
          '当前界面暂不可用，请稍后重试',
          'The current screen is unavailable, please try again later',
        ),
      'too-large' => L10n.t(
          '文件过大（上限 24MB）',
          'File is too large (24MB limit)',
        ),
      _ => L10n.t(
          '文件操作失败：${detail.isEmpty ? e.code : detail}',
          'File operation failed: ${detail.isEmpty ? e.code : detail}',
        ),
    };
  }
}

/// 外部文档「同一次投递」去重（cross-review F3 + C3）。
///
/// 原生（T2，v4 起）给每份新收到的外部文档生成 UUID `deliveryId`，并同时挂在
/// **openDocument 事件 arguments** 与 **getIncomingFile 返回 Map** 顶层——同一份
/// 暂存文档两条路径的 id 相同。因此：
///   · 有 deliveryId → 按 id 精确去重（同一次投递只开一次；不同 id 正常打开，
///     用户连续打开两个同名文件不会被误吞）；
///   · 无 deliveryId（Android 旧原生 / 未升级端）→ 回退「同名同大小 + 1s 短窗口」，
///     只挡「事件推送 + 首帧拉取」这种同一时刻的双路径重复（恢复删掉的 5s 窗口防护，
///     但窗口缩短到 1s，避免再次吞掉合法的二次打开）。
class IncomingDocDeduper {
  String? _lastAcceptedDeliveryId;
  String? _lastSignature;
  DateTime _lastAcceptedAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// 返回 true = 应处理本次投递；false = 同一次投递的重复回调（或参数非法）。
  /// [now] 仅测试用：注入时间，避免用例依赖真实时钟。
  bool shouldAccept(dynamic args, {DateTime? now}) {
    if (args is! Map) return false;
    final id = args['deliveryId'];
    if (id is String && id.isNotEmpty) {
      if (id == _lastAcceptedDeliveryId) return false;
      _lastAcceptedDeliveryId = id;
      return true;
    }
    // 无 deliveryId：短窗口兜底（事件推送与首帧拉取几乎同时到达）。
    final name = args['name'];
    if (name is! String || name.isEmpty) return true; // 缺字段交给主流程判定
    final bytes = args['bytes'];
    final size = bytes is List ? bytes.length : -1;
    final signature = '$name:$size';
    final ts = now ?? DateTime.now();
    final duplicate = signature == _lastSignature &&
        ts.difference(_lastAcceptedAt) < const Duration(seconds: 1);
    if (!duplicate) {
      _lastSignature = signature;
      _lastAcceptedAt = ts;
    }
    return !duplicate;
  }
}
