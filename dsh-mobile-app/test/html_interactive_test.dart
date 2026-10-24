// HTML 交互模式参数构造测试（v3.2.13）。
import 'package:flutter_test/flutter_test.dart';

import 'package:dsh_mobile_app/docs/html_interactive.dart';

void main() {
  group('buildInteractiveHtmlArgs', () {
    test('本地 HTML：带正文 + 目录，不带 url', () {
      final args = buildInteractiveHtmlArgs(
        html: '<h1>x</h1>',
        baseDir: r'D:\docs',
        title: '演示',
        apiBase: 'http://114.66.28.120:8080/m',
        token: 'tk',
      );
      expect(args['html'], '<h1>x</h1>');
      expect(args['baseDir'], r'D:\docs');
      expect(args['title'], '演示');
      expect(args.containsKey('url'), isFalse);
      expect(args['apiBase'], 'http://114.66.28.120:8080/m');
      expect(args['token'], 'tk');
    });

    test('网络 HTML：只带 url（本地正文不传）', () {
      final args = buildInteractiveHtmlArgs(
        url: 'https://example.com/page.html',
        apiBase: 'http://x:8080/m',
        token: 'tk',
      );
      expect(args['url'], 'https://example.com/page.html');
      expect(args.containsKey('html'), isFalse);
      expect(args.containsKey('baseDir'), isFalse);
    });

    test('空字符串不塞进参数（原生侧按「不存在」处理）', () {
      final args = buildInteractiveHtmlArgs(
        url: '',
        html: '<p>x</p>',
        title: '',
        baseDir: '',
        apiBase: 'http://x:8080/m',
        token: '',
      );
      expect(args.containsKey('url'), isFalse);
      expect(args.containsKey('title'), isFalse);
      expect(args.containsKey('baseDir'), isFalse);
      expect(args['html'], '<p>x</p>');
    });
  });
}
