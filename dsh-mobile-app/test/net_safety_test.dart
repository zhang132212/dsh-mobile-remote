import 'package:dsh_mobile_app/net_safety.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(acknowledgedInsecurePublicHttp.clear);

  test('局域网与虚拟组网的 http 不算公网明文', () {
    const ok = [
      'http://127.0.0.1:3080',
      'http://localhost:3080/m',
      'http://192.168.1.20:3080',
      'http://10.1.2.3:3080/m',
      'http://172.16.5.5:3080',
      'http://172.31.255.255',
      'http://169.254.1.1:3080',
      'http://100.64.0.7:3080',
      'http://100.127.0.1:3080',
      'http://my-pc.local:3080',
      'http://nas.lan',
      'http://box.home.arpa:3080',
      'http://[::1]:3080',
      'http://[fc00::1]:3080',
      'http://[fe80::1]:3080',
      'https://vps.example:443',
      'https://8.8.8.8',
    ];
    for (final url in ok) {
      expect(isInsecurePublicHttp(url), isFalse, reason: url);
    }
  });

  test('公网 IP 和域名的 http 要警告', () {
    const bad = [
      'http://8.8.8.8:8080',
      'http://1.2.3.4/m',
      'http://100.63.0.1:3080',
      'http://100.128.0.1:3080',
      'http://172.15.0.1',
      'http://172.32.0.1',
      'http://11.0.0.1',
      'http://vps.example:8080/m',
      'http://xxx.natfrp.com',
      'HTTP://VPS.Example:8080',
      'http://[2001:db8::1]:3080',
    ];
    for (final url in bad) {
      expect(isInsecurePublicHttp(url), isTrue, reason: url);
    }
  });

  test('没有 scheme 或不是 URL 时不拦截', () {
    expect(isInsecurePublicHttp(''), isFalse);
    expect(isInsecurePublicHttp('192.168.1.5:3080'), isFalse);
    expect(isInsecurePublicHttp('not a url'), isFalse);
  });

  test('确认过的 origin 忽略路径差异', () {
    acknowledgeInsecurePublicHttp('http://vps.example:8080/m');
    expect(insecurePublicHttpAcknowledged('http://vps.example:8080'), isTrue);
    expect(insecurePublicHttpAcknowledged('http://other.example:8080'), isFalse);
  });
}
