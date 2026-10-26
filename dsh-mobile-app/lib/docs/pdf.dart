// PDF 阅读（v3.2.16）——原生渲染出图，Dart 只做分页、缓存与手势。
//
// 为什么走原生：Android 自带 `android.graphics.pdf.PdfRenderer`（API 21+），
// iOS 有 PDFKit；两者都是系统能力，不需要再引一个第三方 PDF 包。
// 与 docx/xlsx「自研解析」不同，PDF 是排版好的页面流，按页渲染成位图才是正解，
// 也不需要把整份 PDF 的字体/对象模型搬到 Dart 侧。
//
// 通道契约（与 MainActivity.kt / 未来的 iOS 实现一一对应）：
//   open  {bytes}                        → {pages, width, height}（首页尺寸，单位 pt）
//   render{index, width, quality?}       → ByteArray（JPEG）
//   close {}                             → true
//
// 约定：所有方法都可能抛 [PdfUnsupported]（平台没实现）或 [PlatformException]（文件坏）。
import 'package:flutter/services.dart';

/// 一份已打开的 PDF 的基本信息。
class PdfInfo {
  /// 总页数（至少 1）
  final int pages;

  /// 首页宽度（pt，72dpi 下的页面单位）
  final int width;

  /// 首页高度（pt）
  final int height;

  const PdfInfo({required this.pages, required this.width, required this.height});

  /// 首页宽高比，用来在渲染前先把占位撑开，避免滚动时跳来跳去。
  double get aspect => height <= 0 || width <= 0 ? 1.414 : width / height;

  static PdfInfo fromMap(Map<Object?, Object?> m) => PdfInfo(
        pages: (m['pages'] as num?)?.toInt() ?? 1,
        width: (m['width'] as num?)?.toInt() ?? 595,
        height: (m['height'] as num?)?.toInt() ?? 842,
      );
}

/// 平台不支持 PDF（例如尚未接入 PDFKit 的 iOS 构建）。
class PdfUnsupported implements Exception {
  final String message;
  const PdfUnsupported(this.message);
  @override
  String toString() => message;
}

/// 一次 PDF 阅读会话：原生侧每份文档一个 PdfRenderer，
/// 用 [id] 区分——这样「抽屉里一份 + 全屏再开一份」不会互相把对方关掉。
class PdfSession {
  final int id;
  final PdfInfo info;

  const PdfSession({required this.id, required this.info});
}

/// 原生 PDF 渲染桥。
class PdfBridge {
  static const MethodChannel _channel = MethodChannel('dsh/pdf');

  /// 打开一份 PDF：原生侧落临时文件并持有 PdfRenderer，返回会话 id 与首页尺寸。
  static Future<PdfSession> open(Uint8List bytes) async {
    try {
      final res = await _channel.invokeMethod<Map<Object?, Object?>>('open', {'bytes': bytes});
      if (res == null) throw const PdfUnsupported('PDF 打开失败：原生未返回信息');
      return PdfSession(
        id: (res['id'] as num?)?.toInt() ?? 0,
        info: PdfInfo.fromMap(res),
      );
    } on MissingPluginException {
      throw const PdfUnsupported('当前平台暂不支持 PDF 阅读（Android 已支持）');
    }
  }

  /// 渲染 [sessionId] 的第 [index] 页为 JPEG。宽度由调用方按屏幕像素给，高度按页面比例算。
  static Future<Uint8List?> render({
    required int sessionId,
    required int index,
    required int width,
    int quality = 88,
  }) async {
    try {
      return await _channel.invokeMethod<Uint8List>(
        'render',
        {'id': sessionId, 'index': index, 'width': width, 'quality': quality},
      );
    } on MissingPluginException {
      throw const PdfUnsupported('当前平台暂不支持 PDF 阅读（Android 已支持）');
    }
  }

  /// 关闭某个会话（退出阅读页时调用），只释放这一份的句柄与渲染器。
  static Future<void> close(int sessionId) async {
    try {
      await _channel.invokeMethod<bool>('close', {'id': sessionId});
    } catch (_) {
      // 关闭失败不影响用户；原生侧有上限淘汰兜底
    }
  }
}
