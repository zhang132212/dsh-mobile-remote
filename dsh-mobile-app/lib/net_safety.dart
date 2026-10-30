// 明文 HTTP 是否出了局域网。
// 和电脑端 lib/public-entrance.js 的 isPrivateLanHost 同一套口径：
// 回环、RFC1918、链路本地、CGNAT（Tailscale 100.64/10）、
// .local / .lan / .home / .internal / .localhost / .home.arpa。
// 这些地址上的 http 继续允许；其余 http 会在连接时警告。

const _privateDnsSuffixes = [
  '.local',
  '.lan',
  '.home',
  '.internal',
  '.localhost',
  '.home.arpa',
];

/// 已在本次进程里确认过的明文公网 origin（scheme://host[:port]）。
/// 连接页点了「仍要连接」之后，主界面不再对同一个地址重复弹窗。
final Set<String> acknowledgedInsecurePublicHttp = {};

/// 主机名是不是局域网 / 回环 / 虚拟组网常见段。不含 scheme。
bool isPrivateLanHost(String host) {
  var h = host.trim().toLowerCase();
  if (h.startsWith('[') && h.endsWith(']')) {
    h = h.substring(1, h.length - 1);
  }
  final zone = h.indexOf('%');
  if (zone >= 0) h = h.substring(0, zone);
  if (h.endsWith('.')) h = h.substring(0, h.length - 1);
  if (h.isEmpty) return false;
  if (h == 'localhost' || h == '::1') return true;
  for (final suffix in _privateDnsSuffixes) {
    if (h.endsWith(suffix)) return true;
  }
  if (h.contains(':')) return _isPrivateIpv6(h);
  return _isPrivateIpv4(h);
}

bool _isPrivateIpv4(String host) {
  final parts = host.split('.');
  if (parts.length != 4) return false;
  final octets = <int>[];
  for (final part in parts) {
    final n = int.tryParse(part);
    if (n == null || n < 0 || n > 255 || part != '$n') return false;
    octets.add(n);
  }
  final a = octets[0];
  final b = octets[1];
  if (a == 10 || a == 127 || a == 0) return true;
  if (a == 192 && b == 168) return true;
  if (a == 172 && b >= 16 && b <= 31) return true;
  if (a == 169 && b == 254) return true;
  if (a == 100 && b >= 64 && b <= 127) return true;
  return false;
}

bool _isPrivateIpv6(String host) {
  if (host == '::1') return true;
  final first = host.split(':').first;
  if (first.isEmpty) return false;
  final n = int.tryParse(first, radix: 16);
  if (n == null) return false;
  if (n >= 0xfc00 && n <= 0xfdff) return true;
  if (n >= 0xfe80 && n <= 0xfebf) return true;
  return false;
}

/// `http://` 且主机不是局域网。https、无 scheme、坏地址都返回 false（不拦截）。
bool isInsecurePublicHttp(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return false;
  final uri = Uri.tryParse(text);
  if (uri == null || !uri.hasScheme) return false;
  if (uri.scheme.toLowerCase() != 'http') return false;
  if (uri.host.isEmpty) return false;
  return !isPrivateLanHost(uri.host);
}

/// 忽略路径，只按 scheme://host[:port] 记「这个地址用户已经看过警告」。
String? insecurePublicHttpKey(String raw) {
  final uri = Uri.tryParse(raw.trim());
  if (uri == null || uri.host.isEmpty) return null;
  final port = uri.hasPort ? ':${uri.port}' : '';
  return '${uri.scheme.toLowerCase()}://${uri.host}$port';
}

void acknowledgeInsecurePublicHttp(String raw) {
  final key = insecurePublicHttpKey(raw);
  if (key != null) acknowledgedInsecurePublicHttp.add(key);
}

bool insecurePublicHttpAcknowledged(String raw) {
  final key = insecurePublicHttpKey(raw);
  return key != null && acknowledgedInsecurePublicHttp.contains(key);
}
