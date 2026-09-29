// 更新信任链测试（v3.2.1）——**跨语言验证**：Node 侧签名 → Dart 侧验签。
//
// 为什么必须有这层：manifest 的签名与验签分别在两套实现里（发布工具用 Node 的
// node:crypto，App 用 Dart 的 package:cryptography），两边对 JCS 规范化、base64url、
// Ed25519 的细节理解只要差一点，线上表现就是「App 永远说更新不可信」——而单侧单测
// 完全发现不了。所以这里用**真实发布工具产出的签名**做夹具，钉死两边一致。
//
// 夹具 = test/fixtures/signed_manifest.json（由 tools/publish-manifest.mjs 生成）。
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:dsh_mobile_app/update/jcs.dart';
import 'package:dsh_mobile_app/update/update_manifest.dart';
import 'package:dsh_mobile_app/update/trusted_keys.dart';

String fixture([String name = 'signed_manifest.json']) =>
    File('test/fixtures/$name').readAsStringSync();

void main() {
  group('跨语言：Node 签名 ↔ Dart 验签', () {
    test('夹具能被内置公钥验签通过', () async {
      final (manifest, keyId) = await parseAndVerifyManifest(fixture());
      expect(keyId, 'dsh-release-eun');
      expect(manifest.schemaVersion, 1);
      expect(manifest.sequence, greaterThanOrEqualTo(1));
      expect(manifest.channel, 'stable');
      expect(manifest.app.versionCode, isNotNull);
      expect(manifest.app.versionCode!, greaterThan(0));
      expect(manifest.app.sha256.length, 64);
      expect(manifest.app.sizeBytes, greaterThan(0));
    });

    test('公钥表里必须有对应 keyId（否则更新永远不可信）', () async {
      final (_, keyId) = await parseAndVerifyManifest(fixture());
      expect(trustedReleaseKeys.containsKey(keyId), isTrue);
    });
  });

  group('拒绝被篡改的清单（信任根不能有缝）', () {
    test('改动任一已签字段 → 验签失败', () async {
      final doc = jsonDecode(fixture()) as Map<String, dynamic>;
      // 把 versionCode 改大（攻击者最想干的事：让你装他的包）
      (doc['artifacts'] as Map)['app']['versionCode'] =
          ((doc['artifacts'] as Map)['app']['versionCode'] as int) + 1;
      await expectLater(
        parseAndVerifyManifest(jsonEncode(doc)),
        throwsA(isA<UpdateManifestException>()),
      );
    });

    test('替换 sha256 → 验签失败（下载物校验不会被打穿）', () async {
      final doc = jsonDecode(fixture()) as Map<String, dynamic>;
      (doc['artifacts'] as Map)['app']['sha256'] = 'f' * 64;
      await expectLater(
        parseAndVerifyManifest(jsonEncode(doc)),
        throwsA(isA<UpdateManifestException>()),
      );
    });

    test('未知字段 → 拒绝（不放过任何未签名语义）', () async {
      final doc = jsonDecode(fixture()) as Map<String, dynamic>;
      doc['evilExtra'] = 'x';
      await expectLater(
        parseAndVerifyManifest(jsonEncode(doc)),
        throwsA(isA<UpdateManifestException>()),
      );
    });

    test('重复键 → 拒绝', () async {
      final raw = fixture().replaceFirst('"sequence":', '"sequence":1,"sequence":');
      await expectLater(
        parseAndVerifyManifest(raw),
        throwsA(isA<UpdateManifestException>()),
      );
    });

    test('掐掉 signatures → 拒绝', () async {
      final doc = jsonDecode(fixture()) as Map<String, dynamic>;
      doc.remove('signatures');
      await expectLater(
        parseAndVerifyManifest(jsonEncode(doc)),
        throwsA(isA<UpdateManifestException>()),
      );
    });

    test('换成不受信的 keyId → 拒绝（不能自己签一个就装）', () async {
      final doc = jsonDecode(fixture()) as Map<String, dynamic>;
      (doc['signatures'] as List)[0]['keyId'] = 'attacker-key';
      await expectLater(
        parseAndVerifyManifest(jsonEncode(doc)),
        throwsA(isA<UpdateManifestException>()),
      );
    });

    test('schemaVersion 非 1 → 拒绝', () async {
      final doc = jsonDecode(fixture()) as Map<String, dynamic>;
      doc['schemaVersion'] = 2;
      await expectLater(
        parseAndVerifyManifest(jsonEncode(doc)),
        throwsA(isA<UpdateManifestException>()),
      );
    });
  });

  group('payloadDigest 稳定性（重放防护的基准）', () {
    test('同一份清单两次计算一致', () async {
      final a = await payloadDigestOf(fixture());
      final b = await payloadDigestOf(fixture());
      expect(a, b);
      expect(a.length, 64);
    });

    test('内容变了 digest 就变', () async {
      final doc = jsonDecode(fixture()) as Map<String, dynamic>;
      doc['sequence'] = (doc['sequence'] as int) + 1;
      final a = await payloadDigestOf(fixture());
      final b = await payloadDigestOf(jsonEncode(doc));
      expect(a, isNot(b));
    });
  });

  group('JCS 规范化', () {
    test('键序无关：重排顶层键不改变 canonical 结果', () {
      final a = jcs({'b': 1, 'a': 2, 'c': {'z': 1, 'y': 2}});
      final b = jcs({'c': {'y': 2, 'z': 1}, 'a': 2, 'b': 1});
      expect(a, b);
    });

    test('输出与 RFC 8785 示例一致（键按 UTF-16 码元升序、无多余空白）', () {
      expect(jcs({'a': 1, 'b': 'x'}), '{"a":1,"b":"x"}');
      expect(jcs([1, 2, 3]), '[1,2,3]');
      expect(jcs(null), 'null');
      expect(jcs(true), 'true');
    });
  });
}
