// 文档链接（v3.2.1）——让聊天里的超链接能**就地打开文档**，不跳出对话。
//
// 两种形态：
//   ① `dsh-doc:<路径>`            走 harness 的 /api/files 读电脑工作区里的文件
//   ② `http(s)://…/xxx.md|docx|…` 直接下载后在本 App 内渲染
//
// 为什么自定义 scheme 而不用 `file://`：
//   · file:// 在 Android 上会被 FileUriExposed / 存储权限拦住（实测过）；
//   · 放行 file:// 等于开了「读本机任意文件」的口子，而 dsh-doc: 是我们自己的语义，
//     只由助手/harness 产出，攻击面小得多。
//   · 非文档的普通 http(s) 链接**行为不变**（照旧交给系统浏览器），避免误伤。
import 'model.dart';

/// 文档链接的自定义 scheme。
const String kDocScheme = 'dsh-doc:';

/// 一个可就地打开的文档链接目标。
class DocLinkTarget {
  /// 文件名（含扩展名）——用于判定格式与抽屉标题。
  final String name;

  /// harness 工作区里的绝对路径（`dsh-doc:` 形态）。
  final String? localPath;

  /// 直链（http(s) 且扩展名可读）。
  final String? httpUrl;

  const DocLinkTarget({required this.name, this.localPath, this.httpUrl});
}

/// 该 URL 是否是文档链接；不是则返回 null（调用方按普通链接处理）。
DocLinkTarget? parseDocLink(String raw) {
  final s = raw.trim();
  if (s.isEmpty) return null;

  // ① dsh-doc:<路径>
  if (s.toLowerCase().startsWith(kDocScheme)) {
    var p = s.substring(kDocScheme.length);
    // 容忍 `dsh-doc://` 多写的两斜杠（但 `dsh-doc:C:/x` 里的 `C:/` 必须保住）
    if (p.startsWith('//')) p = p.substring(2);
    // 允许链接里写百分号转义（空格、中文等）
    try {
      p = Uri.decodeFull(p);
    } catch (_) {/* 转义不合法就按原样用 */}
    p = p.trim();
    if (p.isEmpty) return null;
    final base = p.split(RegExp(r'[\\/]')).last;
    return DocLinkTarget(name: base.isEmpty ? 'document' : base, localPath: p);
  }

  // ② http(s) 且扩展名可读
  Uri uri;
  try {
    uri = Uri.parse(s);
  } catch (_) {
    return null;
  }
  if (uri.scheme != 'http' && uri.scheme != 'https') return null;
  if (!isReadableFormat(uri.path)) return null;
  final base = uri.path.split('/').last;
  return DocLinkTarget(name: base.isEmpty ? 'document' : base, httpUrl: s);
}

/// 把工作区绝对路径拼成 `dsh-doc:` 链接（助手写消息时用；也供测试用）。
String docLinkFor(String absolutePath) =>
    '$kDocScheme${Uri.encodeFull(absolutePath)}';
