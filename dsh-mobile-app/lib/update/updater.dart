// 应用内更新（v3.2.1）——GitHub 源，复用 wip-autoupdate 分支已定的信任模型。
//
// 信任根 = **Ed25519 签名的 manifest**（`update.json` 作为 Release 资产发布）：
//   · manifest 用 RFC 8785（JCS）规范化后验签，公钥集内置在 trusted_keys.dart；
//   · 验签不通过 → 拒绝一切更新动作（不降级成"先装了再说"）；
//   · sequence + payloadDigest 做重放/回滚防护；
//   · APK 下载边下边算 sha256，与 manifest 里的值比对，不符就删临时文件。
//
// 设计取舍（相对 wip-autoupdate 的完整版）：
//   本文件只实现 **GitHub 官方源**（PRD §2 F1 的默认源）。电脑源 / 插件联动更新
//   （F4/F5/F6）依赖电脑端插件新增 /update-* 端点，属 P1，先不搬——但 manifest 的
//   解析与验签、字段校验、重放规则全部沿用原实现，将来接电脑源只需再加一个 candidate。
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../logger.dart';
import 'installer.dart';
import 'update_manifest.dart';

/// 发布仓库（公开）：manifest 与 APK 都是它的 Release 资产。
const String kUpdateRepo = 'zhang132212/dsh-mobile-remote';

/// Release 里承载签名 manifest 的资产名。
const String kManifestAssetName = 'update.json';

/// 已安装版本 info 的持久化键（重放防护用）。
const String _kSeqKey = 'update_seq';
const String _kDigestKey = 'update_digest';
const String _kLastCheckKey = 'update_last_check_ms';

/// 一次「有新版本」的检查结果。
class UpdateInfo {
  final int versionCode;
  final String versionName;
  final String fileName;
  final int sizeBytes;
  final String sha256;
  final String apkUrl;
  final String releaseUrl;
  final String notes;
  final int sequence;
  final String payloadDigest;

  const UpdateInfo({
    required this.versionCode,
    required this.versionName,
    required this.fileName,
    required this.sizeBytes,
    required this.sha256,
    required this.apkUrl,
    required this.releaseUrl,
    required this.notes,
    required this.sequence,
    required this.payloadDigest,
  });
}

/// 检查/下载/安装。无状态，可反复调用。
class Updater {
  /// 距离上次检查不足 [minInterval] 时跳过（启动静默检查用，避免每次开 App 都打网络）。
  static Future<bool> shouldCheck({
    Duration minInterval = const Duration(hours: 6),
  }) async {
    final sp = await SharedPreferences.getInstance();
    final last = sp.getInt(_kLastCheckKey) ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    return now - last >= minInterval.inMilliseconds;
  }

  static Future<void> markChecked() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setInt(_kLastCheckKey, DateTime.now().millisecondsSinceEpoch);
  }

  /// 检查更新。返回 null = 已是最新；抛异常 = 检查失败（网络/验签/字段非法）。
  Future<UpdateInfo?> check({required int installedVersionCode}) async {
    final release = await _fetchLatestRelease();
    final manifestText = await _fetchManifestText(release);

    // ① 验签 + 字段校验（失败即拒绝，绝不降级）
    final (manifest, keyId) = await parseAndVerifyManifest(manifestText);
    AppLog.instance.log('[update] manifest 验签通过 keyId=$keyId seq=${manifest.sequence}');

    // ② 重放 / 回滚防护
    final digest = await payloadDigestOf(manifestText);
    final sp = await SharedPreferences.getInstance();
    final seenSeq = sp.getInt(_kSeqKey);
    final seenDigest = sp.getString(_kDigestKey);
    if (seenSeq != null && manifest.sequence < seenSeq) {
      throw StateError('manifest sequence 回退（${manifest.sequence} < $seenSeq），已拒绝');
    }
    if (seenSeq != null && manifest.sequence == seenSeq && seenDigest != digest) {
      throw StateError('同 sequence 但内容不同（疑似被篡改），已拒绝');
    }
    await sp.setInt(_kSeqKey, manifest.sequence);
    await sp.setString(_kDigestKey, digest);

    // ③ 版本比较：只用 manifest 里的整数 versionCode（不从文件名推导）
    final app = manifest.app;
    final remoteCode = app.versionCode;
    if (remoteCode == null) throw StateError('manifest 缺少 app.versionCode');
    if (remoteCode <= installedVersionCode) return null; // 已是最新

    // ④ 找 APK 资产（按 manifest 的 fileName 匹配）
    final apkUrl = _assetUrl(release, app.fileName);
    if (apkUrl == null) {
      throw StateError('Release 里找不到资产 ${app.fileName}');
    }

    return UpdateInfo(
      versionCode: remoteCode,
      versionName: app.versionName,
      fileName: app.fileName,
      sizeBytes: app.sizeBytes,
      sha256: app.sha256.toLowerCase(),
      apkUrl: apkUrl,
      releaseUrl: (release['html_url'] as String?) ?? '',
      notes: (release['body'] as String?) ?? '',
      sequence: manifest.sequence,
      payloadDigest: digest,
    );
  }

  /// 流式下载 APK 到 `<cacheDir>/updates/`，边下边算 sha256，校验通过才落最终文件名。
  /// [onProgress] 回调 0..1（总大小未知时为 null）。
  Future<File> download(UpdateInfo info, {void Function(double? progress)? onProgress}) async {
    final cacheDir = await getTemporaryDirectory();
    final dir = Directory('${cacheDir.path}${Platform.pathSeparator}updates');
    if (!dir.existsSync()) dir.createSync(recursive: true);

    final finalPath = '${dir.path}${Platform.pathSeparator}${info.fileName}';
    final partFile = File('$finalPath.part');
    if (partFile.existsSync()) partFile.deleteSync();

    final client = http.Client();
    try {
      final req = http.Request('GET', Uri.parse(info.apkUrl))
        ..headers['User-Agent'] = 'DSH-Remote-Updater';
      final res = await client.send(req).timeout(const Duration(seconds: 60));
      if (res.statusCode != 200) {
        throw StateError('下载失败 HTTP ${res.statusCode}');
      }
      final total = res.contentLength ?? (info.sizeBytes > 0 ? info.sizeBytes : null);
      final sink = partFile.openWrite();
      final digestSink = _Sha256Capture();
      var received = 0;
      try {
        await for (final chunk in res.stream) {
          sink.add(chunk);
          digestSink.add(chunk);
          received += chunk.length;
          onProgress?.call(total == null || total <= 0 ? null : received / total);
        }
      } finally {
        await sink.flush();
        await sink.close();
      }
      digestSink.finish();
      final got = digestSink.digest.toLowerCase();
      if (got != info.sha256) {
        // 校验失败：删掉半成品，绝不安装
        if (partFile.existsSync()) partFile.deleteSync();
        throw StateError('APK 校验失败（sha256 不符）\n期望 ${info.sha256}\n实际 $got');
      }
      // 原子改名
      final target = File(finalPath);
      if (target.existsSync()) target.deleteSync();
      partFile.renameSync(finalPath);
      AppLog.instance.log('[update] APK 下载完成并校验通过：$finalPath');
      return target;
    } finally {
      client.close();
    }
  }

  /// 触发系统安装器（用户确认后系统安装；同签名可**覆盖安装，无需卸载**）。
  static Future<bool> install(File apk) => ApkInstaller.install(apk);

  // ── GitHub ──

  Future<Map<String, dynamic>> _fetchLatestRelease() async {
    final uri = Uri.parse('https://api.github.com/repos/$kUpdateRepo/releases/latest');
    final res = await http.get(uri, headers: const {
      'Accept': 'application/vnd.github+json',
      'User-Agent': 'DSH-Remote-Updater',
    }).timeout(const Duration(seconds: 30));
    if (res.statusCode == 404) throw StateError('仓库暂无 Release');
    if (res.statusCode != 200) throw StateError('查询 Release 失败 HTTP ${res.statusCode}');
    final doc = jsonDecode(utf8.decode(res.bodyBytes));
    if (doc is! Map<String, dynamic>) throw StateError('Release 返回格式异常');
    return doc;
  }

  Future<String> _fetchManifestText(Map<String, dynamic> release) async {
    final url = _assetUrl(release, kManifestAssetName);
    if (url == null) {
      throw StateError('该 Release 未附带签名清单 $kManifestAssetName');
    }
    final res = await http.get(Uri.parse(url), headers: const {
      'Accept': 'application/octet-stream',
      'User-Agent': 'DSH-Remote-Updater',
    }).timeout(const Duration(seconds: 30));
    if (res.statusCode != 200) throw StateError('下载清单失败 HTTP ${res.statusCode}');
    return utf8.decode(res.bodyBytes);
  }

  static String? _assetUrl(Map<String, dynamic> release, String name) {
    final assets = release['assets'];
    if (assets is! List) return null;
    for (final a in assets) {
      if (a is Map && a['name'] == name) {
        final u = a['browser_download_url'];
        if (u is String && u.isNotEmpty) return u;
      }
    }
    return null;
  }
}

/// 增量 sha256（边下边算，避免把 76MB 全读进内存）。
///
/// 用 `sha256.startChunkedConversion` + 一个只存结果的 Sink 实现，
/// 不额外引入 package:convert（AccumulatorSink 在那边）。
class _Sha256Capture {
  final _out = _DigestSink();
  late final ByteConversionSink _input = sha256.startChunkedConversion(_out);

  void add(List<int> data) => _input.add(data);

  void finish() => _input.close();

  String get digest => _out.value?.toString() ?? '';
}

class _DigestSink implements Sink<Digest> {
  Digest? value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}
