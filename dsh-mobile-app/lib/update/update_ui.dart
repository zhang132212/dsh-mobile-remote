// 更新 UI（v3.2.1）——「检查到 → 选择更新 → 自动安装」的用户侧流程。
//
// 两条入口：
//   · checkUpdateSilent   启动时静默检查（有新版才弹窗，且 6 小时内不重复打扰）
//   · checkUpdateInteractive  用户手动点「检查更新」：无论结果都给明确反馈
//
// 信任判断全部在 Updater 里（验签 + sha256），这里只负责呈现与引导；
// 安装前必须让用户看到「版本号 + 更新说明」，不静默安装。
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../l10n.dart';
import '../logger.dart';
import '../theme.dart';
import '../toast.dart';
import 'updater.dart';

/// 当前已安装的 versionCode（来自 pubspec 的 `+N`）。
Future<int> installedVersionCode() async {
  try {
    final info = await PackageInfo.fromPlatform();
    return int.tryParse(info.buildNumber) ?? 0;
  } catch (_) {
    return 0;
  }
}

Future<String> installedVersionName() async {
  try {
    final info = await PackageInfo.fromPlatform();
    return info.version;
  } catch (_) {
    return '?';
  }
}

/// 启动静默检查：只在**确实有新版本**时弹窗；任何失败都静默（不打扰使用）。
Future<void> checkUpdateSilent(BuildContext context) async {
  try {
    if (!await Updater.shouldCheck()) return;
    await Updater.markChecked();
    final code = await installedVersionCode();
    if (code <= 0) return;
    final info = await Updater().check(installedVersionCode: code);
    if (info == null) return;
    if (!context.mounted) return;
    await _promptUpdate(context, info);
  } catch (e) {
    // 静默路径：网络/验签失败都不弹窗，只留日志（手动检查时才把原因告诉用户）
    AppLog.instance.log('[update] 静默检查未完成: $e');
  }
}

/// 手动检查：把结果如实告诉用户（含失败原因）。
Future<void> checkUpdateInteractive(BuildContext context) async {
  final code = await installedVersionCode();
  if (!context.mounted) return;
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const Center(child: CircularProgressIndicator()),
  );
  UpdateInfo? info;
  Object? error;
  try {
    await Updater.markChecked();
    info = await Updater().check(installedVersionCode: code);
  } catch (e) {
    error = e;
  }
  if (!context.mounted) return;
  Navigator.of(context, rootNavigator: true).pop(); // 关掉 loading
  if (!context.mounted) return;

  if (error != null) {
    showToast(context, L10n.t('检查更新失败：$error', 'Update check failed: $error'));
    return;
  }
  if (info == null) {
    final cur = await installedVersionName();
    if (!context.mounted) return;
    showToast(context, L10n.t('已是最新版本（v$cur）', 'Already up to date (v$cur)'));
    return;
  }
  await _promptUpdate(context, info);
}

/// 「发现新版本」弹窗 → 下载（带进度）→ 交给系统安装器。
Future<void> _promptUpdate(BuildContext context, UpdateInfo info) async {
  final go = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(L10n.t('发现新版本 v${info.versionName}', 'New version v${info.versionName}')),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 320),
        child: SingleChildScrollView(
          child: Text(
            info.notes.trim().isEmpty
                ? L10n.t('（本次发布未填写更新说明）', '(no release notes)')
                : info.notes.trim(),
            style: const TextStyle(fontSize: 13, height: 1.5),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(c).pop(false),
          child: Text(L10n.t('稍后', 'Later')),
        ),
        FilledButton(
          onPressed: () => Navigator.of(c).pop(true),
          child: Text(L10n.t('立即更新', 'Update now')),
        ),
      ],
    ),
  );
  if (go != true || !context.mounted) return;

  // 下载 + 校验（进度弹窗，不可取消——中断会留下半成品）
  final progress = ValueNotifier<double?>(0);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => AlertDialog(
      title: Text(L10n.t('正在下载更新', 'Downloading update')),
      content: ValueListenableBuilder<double?>(
        valueListenable: progress,
        builder: (_, v, _) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LinearProgressIndicator(value: v),
            const SizedBox(height: 10),
            Text(
              v == null
                  ? L10n.t('已下载…', 'Downloading…')
                  : L10n.t('${(v * 100).toStringAsFixed(0)}%', '${(v * 100).toStringAsFixed(0)}%'),
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
    ),
  );

  Object? err;
  try {
    final apk = await Updater().download(info, onProgress: (p) => progress.value = p);
    if (!context.mounted) return;
    Navigator.of(context, rootNavigator: true).pop(); // 关进度
    if (!context.mounted) return;
    // 拉起系统安装器；同签名可覆盖安装，无需卸载
    final ok = await Updater.install(apk);
    if (!context.mounted) return;
    if (!ok) {
      showToast(
        context,
        L10n.t('请允许「安装未知来源应用」后重试', 'Please allow "install unknown apps" and retry'),
      );
    }
  } catch (e) {
    err = e;
    if (!context.mounted) return;
    Navigator.of(context, rootNavigator: true).pop();
    if (!context.mounted) return;
    showToast(context, L10n.t('更新失败：$e', 'Update failed: $e'));
  }
  if (err == null) {
    AppLog.instance.log('[update] 已发起安装：${info.fileName}');
  }
}

/// 设置页/首页可用的「检查更新」行。
class CheckUpdateTile extends StatelessWidget {
  const CheckUpdateTile({super.key});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(Icons.system_update_alt, color: DshColors.ink2(context)),
      title: Text(L10n.t('检查更新', 'Check for updates')),
      subtitle: FutureBuilder<String>(
        future: installedVersionName(),
        builder: (_, snap) => Text(
          L10n.t('当前版本 v${snap.data ?? '…'}', 'Current v${snap.data ?? '…'}'),
          style: const TextStyle(fontSize: 12),
        ),
      ),
      trailing: const Icon(Icons.chevron_right, size: 18),
      onTap: () => checkUpdateInteractive(context),
    );
  }
}
