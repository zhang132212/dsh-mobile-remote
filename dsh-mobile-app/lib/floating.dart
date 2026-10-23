// 悬浮球（v2.7）：原生 overlay 服务桥接。
// 小球常驻系统上层（App 被杀仍工作），自己连 SSE 收事件；
// App 侧负责开关、权限引导、余额联动、面板页。
//
// iOS 移植（T3）：iOS 不提供跨 App 的系统级悬浮窗（Android 的
// SYSTEM_ALERT_WINDOW / TYPE_APPLICATION_OVERLAY 没有等价物），所以这套能力在
// iOS 上**显式降级**而不是静默坏掉：
//   · [isSupported] = false —— 设置页据此隐藏开关、改成"iOS 不支持"说明，
//     不会出现"开关打开但其实没有服务"的假象；
//   · 查询类返回安全值（isRunning / canDrawOverlay = false）；
//   · 动作类全部 no-op，且**不触碰 MethodChannel**（iOS 侧没有 dsh/floating 通道，
//     调用会抛 MissingPluginException）；
//   · [unsupportedHint] 统一降级文案（iOS 后台提醒改走已有的 Bark 推送）。
import 'package:flutter/services.dart';

import 'l10n.dart';
import 'platform_support.dart';

class Floating {
  static const _channel = MethodChannel('dsh/floating');

  /// 当前平台是否支持系统悬浮球（iOS 不支持）。
  ///
  /// 设置页/引导弹层用它决定展示开关还是降级说明；调用方不要自己判 Platform。
  static bool get isSupported => DshPlatform.supportsSystemFloatingBubble;

  /// iOS 降级说明（设置页与引导弹窗共用同一文案，避免两处说法不一致）。
  static String get unsupportedHint => L10n.t(
        'iOS 不支持系统悬浮球；后台提醒请配置 Bark 推送',
        'System floating bubble is unavailable on iOS; use Bark push for background alerts',
      );

  static Future<void> start() async {
    if (!isSupported) return;
    await _channel.invokeMethod<void>('start');
  }

  static Future<void> stop() async {
    if (!isSupported) return;
    await _channel.invokeMethod<void>('stop');
  }

  static Future<bool> isRunning() async {
    if (!isSupported) return false;
    return (await _channel.invokeMethod<bool>('isRunning')) ?? false;
  }

  /// 是否已授权悬浮窗权限。
  static Future<bool> canDrawOverlay() async {
    if (!isSupported) return false;
    return (await _channel.invokeMethod<bool>('canDrawOverlay')) ?? false;
  }

  /// 跳转系统悬浮窗权限设置页。
  static Future<void> openOverlaySettings() async {
    if (!isSupported) return;
    await _channel.invokeMethod<void>('openOverlaySettings');
  }

  /// 余额刷新后同步给悬浮球（低余额时亮起 + 气泡）。value 为裸数字字符串（如 "10.50"），
  /// 币种固定 CNY（App 侧取值已 CNY 优先，原生 onBalance 也按此解析）。
  static Future<void> notifyBalance(double total) async {
    if (!isSupported) return;
    await _channel.invokeMethod<void>(
      'notifyBalance',
      {'value': total.toStringAsFixed(2)},
    );
  }

  /// 余额预警配置同步给悬浮球（开关 + 阈值；悬浮球的报警判定完全以此为准，
  /// 开关关闭 → 悬浮球不因余额报警/亮起，仅常驻显示余额数值）。
  static Future<void> setBalanceAlert(bool enabled, double threshold) async {
    if (!isSupported) return;
    await _channel.invokeMethod<void>('setBalanceAlert', {
      'enabled': enabled,
      'threshold': threshold.toStringAsFixed(2),
    });
  }

  /// 冷启动暂存的面板动作（一次性消费）：返回 `charge` | `notifs` | `session:<id>` | null。
  /// v2.7.2 review：原生侧投递后仍保留 pending 直到被消费，Dart 首帧后主动拉取，
  /// 解决"Dart handler 注册晚于投递"导致动作丢失。
  static Future<String?> consumeOpenPanel() async {
    if (!isSupported) return null;
    return _channel.invokeMethod<String>('consumeOpenPanel');
  }
}
