// issue #13 回归：eventsRaw() 的「取消窗口」客户端连接释放语义。
//
// 判据（cross-review 后修正）：旧版数服务端 HttpServer.connectionsInfo()，但 FakeSse
// 从不 close 自己的 response —— 客户端 force close 只发 FIN（半关闭），Darwin 的
// HttpServer 仍会把这个 socket 计为 active，于是 macOS 上「真修复也红」（v2/v3 实测
// active=1 idle=0 closing=0），而 Windows 立刻归零。判据本身在 Darwin 上不可靠。
//
// 现在改成 **raw ServerSocket** 手写 HTTP/1.1 chunked 响应，并用「服务端 read 到 EOF」
//（客户端确实关闭了 socket）作为判据：read 结束即 closed++，不依赖 HttpServer 的半关闭
// 记账。EOF 语义 Windows/macOS 一致，且正对应用户可感的「连接被释放」。
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:dsh_mobile_app/api.dart';

class FakeSse {
  FakeSse._(this.server);

  final ServerSocket server;
  int responses = 0; // accept 到的 SSE 请求数
  int closed = 0; // 服务端 read 到 EOF（客户端已关闭）的连接数
  final List<Socket> _sockets = [];
  final List<Timer> _timers = [];

  int get port => server.port;
  int get activeConnections => _sockets.length - closed;

  static Future<FakeSse> start({required Duration beforeRespond}) async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final self = FakeSse._(server);
    server.listen((socket) {
      self.responses++;
      self._sockets.add(socket);
      self._serve(socket, beforeRespond);
    });
    return self;
  }

  Future<void> _serve(Socket socket, Duration beforeRespond) async {
    var clientGone = false;
    socket.listen(
      (_) {}, // 消费客户端请求字节
      onDone: () {
        if (!clientGone) {
          clientGone = true;
          closed++;
        }
      },
      onError: (_) {
        if (!clientGone) {
          clientGone = true;
          closed++;
        }
      },
      cancelOnError: true,
    );
    socket.done.catchError((_) {});
    await Future<void>.delayed(beforeRespond); // 慢响应窗口（真机：握手/Tailscale 隧道建立）
    if (clientGone) return; // 客户端已关闭：不再写
    try {
      socket.add(utf8.encode(
        'HTTP/1.1 200 OK\r\n'
        'Content-Type: text/event-stream; charset=utf-8\r\n'
        'Cache-Control: no-cache\r\n'
        'Transfer-Encoding: chunked\r\n'
        '\r\n',
      ));
      _writeChunk(socket, 'data: {"type":"hello","capabilities":{}}\n\n');
      await socket.flush();
      _timers.add(Timer.periodic(const Duration(milliseconds: 250), (_) {
        if (clientGone) return;
        try {
          _writeChunk(socket, ': ping\n\n');
          socket.flush().catchError((_) {});
        } catch (_) {}
      }));
    } catch (_) {
      // 客户端在写响应前关闭：忽略
    }
  }

  /// 写一个 HTTP/1.1 chunk（长度按 UTF-8 字节数）。
  void _writeChunk(Socket socket, String payload) {
    final bytes = utf8.encode(payload);
    socket.add(utf8.encode('${bytes.length.toRadixString(16)}\r\n'));
    socket.add(bytes);
    socket.add(utf8.encode('\r\n'));
  }

  Future<void> stop() async {
    for (final t in _timers) {
      t.cancel();
    }
    for (final s in _sockets) {
      try {
        s.destroy();
      } catch (_) {}
    }
    await server.close();
  }
}

/// 先等「服务端确实 accept 了 [atLeast] 个请求」，避免还没连上就判过。
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

/// 轮询等待「客户端已关闭 [atLeast] 条连接」（服务端 read 到 EOF）。
///
/// 为什么不用 HttpServer.connectionsInfo().total：Darwin 上客户端 FIN 是半关闭，
/// 服务端不 close response 就会继续把连接记为 active（与客户端是否释放无关）。
Future<void> waitForClientCloses(
  FakeSse s,
  int atLeast, {
  Duration timeout = const Duration(seconds: 15),
  required String reason,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (s.closed >= atLeast) return;
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  fail(
    '$reason：等待 ${timeout.inSeconds}s 后仅 ${s.closed}/$atLeast 条连接被客户端关闭'
    '（responses=${s.responses} active=${s.activeConnections}）——'
    'active 长期非 0 说明客户端没有真正释放 socket',
  );
}

Api mkApi(FakeSse s) => Api()
  ..baseUrl = 'http://127.0.0.1:${s.port}'
  ..token = '';

void main() {
  test('对照：响应到达后取消（正常路径）→ 客户端关闭连接', () async {
    final s = await FakeSse.start(beforeRespond: Duration.zero);
    addTearDown(s.stop);
    final sub = mkApi(s).eventsRaw().listen((_) {}, onError: (_) {});
    await Future<void>.delayed(const Duration(milliseconds: 600));
    await sub.cancel();
    await waitForClientCloses(s, 1, reason: '正常取消必须释放连接');
    // ignore: avoid_print
    print('对照: responses=${s.responses} closed=${s.closed}');
  }, timeout: Timeout(const Duration(seconds: 90)));

  test('取消窗口：响应到达前取消 → 客户端必须关闭连接（不留半开 socket）', () async {
    final s = await FakeSse.start(beforeRespond: const Duration(milliseconds: 900));
    addTearDown(s.stop);
    final sub = mkApi(s).eventsRaw().listen((_) {}, onError: (_) {});
    await Future<void>.delayed(const Duration(milliseconds: 150));
    await sub.cancel();
    await waitForResponses(s, 1); // 确认请求已到达服务端（否则「没连上」不能算通过）
    await waitForClientCloses(s, 1, reason: '取消窗口内客户端也必须关闭连接');
    // ignore: avoid_print
    print('取消窗口: responses=${s.responses} closed=${s.closed}');
  }, timeout: Timeout(const Duration(seconds: 90)));

  test('窗口内连续重建 3 次 → 3 条连接全部被客户端关闭', () async {
    final s = await FakeSse.start(beforeRespond: const Duration(milliseconds: 700));
    addTearDown(s.stop);
    final a = mkApi(s);
    for (var i = 0; i < 3; i++) {
      final sub = a.eventsRaw().listen((_) {}, onError: (_) {});
      await Future<void>.delayed(const Duration(milliseconds: 120));
      await sub.cancel();
    }
    await waitForResponses(s, 3); // 3 次请求都已到达服务端
    await waitForClientCloses(s, 3, reason: '每次窗口内重建都不该留下半个 socket');
    // ignore: avoid_print
    print('重连 x3: responses=${s.responses} closed=${s.closed}');
  }, timeout: Timeout(const Duration(seconds: 90)));
}
