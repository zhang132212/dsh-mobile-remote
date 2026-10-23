// issue #13 回归：eventsRaw() 的「取消窗口」连接释放语义。
//
// 三条用例守护：
//   1) 正常路径：响应到达后取消 → 连接必须释放；
//   2) 取消窗口：响应到达前取消（resume/switchBase/disposeBridge 的动作）
//      → 晚到响应必须被消费并释放（api.dart eventsRaw 的 cancelled 守卫）；
//   3) 窗口内连续重建 3 次 → 不得残留半开 socket。
//
// 断言方式：cancel 后**轮询等待**服务端连接数归零（真实时间，超时才失败），
// 不用固定 sleep —— macOS CI（Xcode 16.4 runner）上 FIN/事件循环回收慢于 Windows，
// 固定 2~3s 等待会假阳性（run 39981868876 曾 3 连红，而前一轮同文件全绿）。
// 超时失败信息带 active/idle/closing 计数，便于区分「只是慢」与「真泄漏」。
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:dsh_mobile_app/api.dart';

class FakeSse {
  FakeSse._(this.server);
  final HttpServer server;
  int responses = 0;
  final List<Timer> _timers = [];

  static Future<FakeSse> start({required Duration beforeRespond}) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final self = FakeSse._(server);
    server.listen((req) async {
      self.responses++;
      await Future<void>.delayed(beforeRespond); // 慢响应窗口（真机：握手/Tailscale 隧道建立）
      final res = req.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType('text', 'event-stream')
        ..bufferOutput = false; // 必须！默认 true 时帧根本不上线
      res.done.catchError((_) {});
      void write(String s) {
        try {
          res.add(utf8.encode(s));
          res.flush().catchError((_) {});
        } catch (_) {}
      }

      write('data: {"type":"hello","capabilities":{}}\n\n');
      self._timers
          .add(Timer.periodic(const Duration(milliseconds: 250), (_) => write(': ping\n\n')));
    });
    return self;
  }

  int get openConnections => server.connectionsInfo().total;

  Future<void> stop() async {
    for (final t in _timers) {
      t.cancel();
    }
    await server.close(force: true);
  }
}

/// 先等「服务端确实收到了 [atLeast] 个请求」，避免请求还没发出就轮询到 0 的假通过。
Future<void> waitForResponses(
  FakeSse s,
  int atLeast, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (s.responses >= atLeast) return;
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  fail('等待服务端收到 $atLeast 个请求超时（实际 responses=${s.responses}）');
}

/// 轮询等待「服务端连接全部回收」，直到 [FakeSse.openConnections] == 0 或超时。
///
/// 旧实现是固定 `Future.delayed(2~3s)` 后直接断言 0：Windows 上够用，但 macOS CI
/// （Xcode 16.4 runner）事件循环 / FIN 回收更慢，固定等待会假阳性（CI 首跑 3 连红）。
/// 这里用真实时间轮询（非 fake async），超时才失败，并带上最后一次连接统计，
/// 便于区分「只是慢」与「真泄漏」。
Future<void> waitNoResidualConnections(
  FakeSse s, {
  // macOS runner 上 FIN/事件循环回收明显慢于 Windows：给到 15s 仍失败才是真泄漏。
  Duration timeout = const Duration(seconds: 15),
  required String reason,
}) async {
  final deadline = DateTime.now().add(timeout);
  var info = s.server.connectionsInfo();
  while (DateTime.now().isBefore(deadline)) {
    info = s.server.connectionsInfo();
    if (info.total == 0) return;
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  fail(
    '$reason：等待 ${timeout.inSeconds}s 后仍有 ${info.total} 条连接未释放'
    '（active=${info.active} idle=${info.idle} closing=${info.closing} '
    'responses=${s.responses}）——若持续非 0 则是真泄漏，不是慢',
  );
}

Api mkApi(FakeSse s) => Api()
  ..baseUrl = 'http://127.0.0.1:${s.server.port}'
  ..token = '';

void main() {
  test('对照：响应到达后取消（正常路径）→ 连接释放', () async {
    final s = await FakeSse.start(beforeRespond: Duration.zero);
    addTearDown(s.stop);
    final sub = mkApi(s).eventsRaw().listen((_) {}, onError: (_) {});
    await Future<void>.delayed(const Duration(milliseconds: 600));
    await sub.cancel();
    await waitNoResidualConnections(s, reason: '正常取消必须释放连接');
    // ignore: avoid_print
    print('对照: responses=${s.responses} 残留连接=${s.openConnections}');
  });

  test('取消窗口：响应到达前取消（resume/switchBase/disposeBridge 的动作）', () async {
    final s = await FakeSse.start(beforeRespond: const Duration(milliseconds: 900));
    addTearDown(s.stop);
    final sub = mkApi(s).eventsRaw().listen((_) {}, onError: (_) {});
    await Future<void>.delayed(const Duration(milliseconds: 150));
    await sub.cancel(); // bodySub 仍为 null → onCancel 什么也没做，等晚到响应落地
    await waitForResponses(s, 1); // 先确认请求已到达服务端（否则可能「还没发就连 0」假通过）
    await waitNoResidualConnections(s,
        reason: '晚到的响应必须被消费并释放（api.dart eventsRaw 的已取消守卫）');
    // ignore: avoid_print
    print('取消窗口: responses=${s.responses} 残留连接=${s.openConnections}');
  });

  test('窗口内连续重建 3 次 → 泄漏连接线性累积', () async {
    final s = await FakeSse.start(beforeRespond: const Duration(milliseconds: 700));
    addTearDown(s.stop);
    final a = mkApi(s);
    for (var i = 0; i < 3; i++) {
      final sub = a.eventsRaw().listen((_) {}, onError: (_) {});
      await Future<void>.delayed(const Duration(milliseconds: 120));
      await sub.cancel();
    }
    // 3 条窗口内连接都要回收（同样用真实时间轮询，等 FIN 落地而不是固定等待）。
    await waitForResponses(s, 3); // 3 次请求都已到达服务端，再等连接归零
    await waitNoResidualConnections(s, reason: '每次窗口内重建都不该留下半个 socket');
    // ignore: avoid_print
    print('重连 x3: responses=${s.responses} 残留连接=${s.openConnections}');
  });
}
