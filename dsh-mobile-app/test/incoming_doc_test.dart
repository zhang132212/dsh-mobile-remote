// 外部文档投递去重策略（cross-review F3 + C3）。
//
// 语义（与 T2 原生契约一致）：
//   · 原生带 deliveryId（openDocument 事件 arguments 与 getIncomingFile 返回 Map 的
//     同一份暂存文档 id 相同）→ 同 id 重复回调只处理一次；不同 id 正常打开；
//   · 无 deliveryId（Android 旧原生/未升级端）→ 回退「同名同大小 + 1s 短窗口」，
//     只挡「事件推送 + 首帧拉取」同一时刻的双路径重复；≥1s 的合法二次打开必须生效。
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:dsh_mobile_app/platform_support.dart';

void main() {
  group('IncomingDocDeduper · 有 deliveryId（原生 v4 契约）', () {
    Map<String, Object> docArgs(String id) => {
          'name': 'a.md',
          'bytes': Uint8List.fromList([1, 2, 3]),
          'deliveryId': id,
        };

    test('同一份文档的两条路径（同 deliveryId）只打开一次', () {
      final d = IncomingDocDeduper();
      expect(d.shouldAccept(docArgs('uuid-1')), isTrue);
      expect(d.shouldAccept(docArgs('uuid-1')), isFalse);
    });

    test('同一文件再次打开（新 deliveryId）必须生效，不受时间窗影响', () {
      final d = IncomingDocDeduper();
      final t0 = DateTime(2026, 10, 24, 1, 0, 0);
      expect(d.shouldAccept(docArgs('uuid-1'), now: t0), isTrue);
      expect(
        d.shouldAccept(docArgs('uuid-2'),
            now: t0.add(const Duration(milliseconds: 300))),
        isTrue,
      );
    });

    test('error 载荷也按 deliveryId 去重（{name, deliveryId, error}）', () {
      final d = IncomingDocDeduper();
      final err = <String, Object>{
        'name': 'big.xlsx',
        'deliveryId': 'uuid-e',
        'error': 'too-large',
      };
      expect(d.shouldAccept(err), isTrue);
      expect(d.shouldAccept(err), isFalse);
    });
  });

  group('IncomingDocDeduper · 无 deliveryId（Android 旧原生兜底）', () {
    Map<String, Object> docArgs({int size = 3}) => {
          'name': 'a.md',
          'bytes': Uint8List.fromList(List<int>.filled(size, 1)),
        };
    final t0 = DateTime(2026, 10, 24, 1, 0, 0);

    test('事件推送 + 首帧拉取（<1s 同 name+size）只处理一次', () {
      final d = IncomingDocDeduper();
      expect(d.shouldAccept(docArgs(), now: t0), isTrue);
      expect(
        d.shouldAccept(docArgs(), now: t0.add(const Duration(milliseconds: 500))),
        isFalse,
      );
    });

    test('间隔 ≥1s 的合法二次打开必须生效（不再有 5s 窗口）', () {
      final d = IncomingDocDeduper();
      expect(d.shouldAccept(docArgs(), now: t0), isTrue);
      expect(
        d.shouldAccept(docArgs(), now: t0.add(const Duration(seconds: 1))),
        isTrue,
        reason: '打开→返回→再打开同一文件是合法操作，不能超过 1s 仍被去重吞掉',
      );
    });

    test('1s 窗口内不同文件（name/size 不同）不受影响', () {
      final d = IncomingDocDeduper();
      expect(d.shouldAccept(docArgs(), now: t0), isTrue);
      expect(
        d.shouldAccept(docArgs(size: 4),
            now: t0.add(const Duration(milliseconds: 100))),
        isTrue,
      );
    });

    test('非 Map 参数拒绝（防御性）', () {
      final d = IncomingDocDeduper();
      expect(d.shouldAccept(null), isFalse);
      expect(d.shouldAccept('x'), isFalse);
    });
  });
}
