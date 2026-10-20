// v3.2.14：思维链分步可见 + 轮次失败原因可见。
import 'dart:convert';

import 'package:dsh_mobile_app/api.dart';
import 'package:dsh_mobile_app/models.dart';
import 'package:dsh_mobile_app/screens/chat_screen.dart';
import 'package:dsh_mobile_app/store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _Backend {
  _Backend({required this.historyEvents});
  final List<Map<String, dynamic>> historyEvents;

  late final Api api = Api(client: MockClient(_handle))
    ..baseUrl = 'http://reasoning.test'
    ..path = '/m'
    ..token = ''
    ..timelineCapabilities = const TimelineCapabilities(
      version: 1,
      live: false,
      history: true,
      detail: false,
      unknownEvents: false,
      callCorrelation: true,
    );

  Future<http.Response> _handle(http.Request req) async {
    Map<String, dynamic> body;
    if (req.url.path == '/m/api/history') {
      body = req.url.queryParameters.containsKey('after')
          ? {'ok': true, 'events': <Object>[], 'hasMore': false}
          : {'ok': true, 'events': historyEvents, 'hasMore': false};
    } else if (req.url.path == '/m/api/queue') {
      body = {'ok': true, 'rows': <Object>[]};
    } else if (req.url.path == '/m/api/todos') {
      body = {'ok': true, 'todos': <Object>[]};
    } else {
      body = {'ok': true};
    }
    return http.Response(
      jsonEncode(body),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  }
}

Map<String, dynamic> _assistant({
  required int seq,
  required String text,
  required String reasoning,
}) =>
    {
      'seq': seq,
      'type': 'assistant/message',
      'data': {
        'turn': 1,
        'step': seq,
        'messageId': 'm$seq',
        'text': text,
        'reasoning': reasoning,
        'reasoningChars': reasoning.length,
      },
    };

Future<void> _pump(WidgetTester tester, _Backend backend, AppStore store) async {
  await tester.pumpWidget(
    MaterialApp(
      home: ChatScreen(
        store: store,
        apiClient: backend.api,
        onTitleChanged: () {},
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pump(const Duration(milliseconds: 350));
}

void main() {
  testWidgets('中间步骤只有思维链时也能看到（不再只在轮次末尾出现一波）', (tester) async {
    final backend = _Backend(historyEvents: [
      {
        'seq': 1,
        'type': 'user/message',
        'data': {'text': '帮我查一下', 'messageId': 'u1'},
      },
      _assistant(seq: 2, text: '', reasoning: 'STEP-ONE-THINK'),
      {
        'seq': 3,
        'type': 'tool/call',
        'data': {'turn': 1, 'step': 1, 'callId': 'c1', 'name': 'pwsh', 'arguments': '{}'},
      },
      {
        'seq': 4,
        'type': 'tool/result',
        'data': {'turn': 1, 'step': 1, 'callId': 'c1', 'name': 'pwsh', 'isError': false, 'text': 'ok'},
      },
      _assistant(seq: 5, text: '最终回答', reasoning: 'STEP-TWO-THINK'),
      {
        'seq': 6,
        'type': 'turn/end',
        'data': {'turn': 1, 'reason': {'kind': 'completed'}},
      },
    ]);
    final store = AppStore()
      ..sessionId = 's-reason'
      ..reasoningDefaultExpanded = true;

    await _pump(tester, backend, store);

    expect(find.textContaining('STEP-ONE-THINK'), findsOneWidget);
    expect(find.textContaining('STEP-TWO-THINK'), findsOneWidget);
    expect(find.textContaining('思维链'), findsNWidgets(2));
    expect(find.text('最终回答'), findsWidgets);
  });

  testWidgets('轮次失败原因以醒目卡片落进时间线', (tester) async {
    final backend = _Backend(historyEvents: [
      {
        'seq': 1,
        'type': 'user/message',
        'data': {'text': '你好', 'messageId': 'u1'},
      },
      {
        'seq': 2,
        'type': 'turn/end',
        'data': {
          'turn': 1,
          'reason': {
            'kind': 'error',
            'error': {'message': '402: Insufficient account funds (TEST)', 'code': 'PI_AI_ERROR'},
          },
        },
      },
    ]);
    final store = AppStore()..sessionId = 's-err';

    await _pump(tester, backend, store);

    expect(find.textContaining('Insufficient account funds'), findsOneWidget);
    expect(find.textContaining('本轮执行失败'), findsOneWidget);
  });
}
