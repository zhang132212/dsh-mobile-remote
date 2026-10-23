// 外部文档投递去重策略（cross-review F3）。
//
// 旧实现按「name:字节长度 + 5 秒时间窗」去重，会把「打开文档 → 返回 → 马上再打开同一文件」
// 静默吞掉（用户完全没反应、无提示）。现改为「同一次投递」语义：同一次投递的去重交给原生
// docDelivered（事件推送与首帧拉取不会双报），Dart 侧只在原生可选携带的相同 deliveryId
// 重复回调时忽略。本文件钉住该行为，防止时间窗被重新引入。
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:dsh_mobile_app/platform_support.dart';

void main() {
  group('IncomingDocDeduper · 同一次投递语义', () {
    Map<String, Object> docArgs({String? deliveryId}) => {
          'name': 'a.md',
          'bytes': Uint8List.fromList([1, 2, 3]),
          'deliveryId': ?deliveryId,
        };

    test('同一份文档间隔 1s 连续投递两次：第二次也必须被接受（不再有 5s 时间窗）', () async {
      final deduper = IncomingDocDeduper();
      final args = docArgs();
      expect(deduper.shouldAccept(args), isTrue);
      await Future<void>.delayed(const Duration(seconds: 1));
      expect(deduper.shouldAccept(args), isTrue,
          reason: '打开→返回→再打开同一文件是合法操作，不能被去重吞掉');
    }, timeout: Timeout(const Duration(seconds: 30)));

    test('同一次投递的重复回调（相同 deliveryId）只处理一次', () {
      final deduper = IncomingDocDeduper();
      final args = docArgs(deliveryId: 'delivery-1');
      expect(deduper.shouldAccept(args), isTrue);
      expect(deduper.shouldAccept(args), isFalse);
    });

    test('不同 deliveryId 的两次投递都应处理（即使文件完全相同）', () {
      final deduper = IncomingDocDeduper();
      expect(deduper.shouldAccept(docArgs(deliveryId: 'd-1')), isTrue);
      expect(deduper.shouldAccept(docArgs(deliveryId: 'd-2')), isTrue);
    });

    test('无 deliveryId（当前原生契约）一律放行', () {
      final deduper = IncomingDocDeduper();
      expect(deduper.shouldAccept(docArgs()), isTrue);
      expect(deduper.shouldAccept(docArgs()), isTrue);
    });

    test('非 Map 参数拒绝（防御性）', () {
      final deduper = IncomingDocDeduper();
      expect(deduper.shouldAccept(null), isFalse);
      expect(deduper.shouldAccept('x'), isFalse);
    });
  });
}
