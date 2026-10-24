// HTML 交互模式（v3.2.13）——把 HTML 交给 Android 原生 WebView 执行。
//
// 静态阅读页只做「读」；用户真正要的是 HTML 里 JS 设计的按钮点得动，
// 这只能交给真浏览器引擎。这里用 Android 系统自带的 WebView（原生 Activity 承载），
// 不引第三方 WebView 包、不跳外部浏览器：
//   · http(s) 文档：直接交给 WebView 加载，完整网页能力；
//   · 电脑工作区的本地 HTML：原生侧按文档目录拦截相对资源（JS / CSS / 图片），
//     经电脑端 /m/api/files 拉取——所以依赖脚本的按钮也能工作。
import 'package:flutter/services.dart';

import '../api.dart';

const MethodChannel _webViewChannel = MethodChannel('dsh/webview');

/// 构造传给原生 WebView 的参数（纯函数，便于单测）。
Map<String, Object?> buildInteractiveHtmlArgs({
  String? url,
  String? html,
  String? title,
  String? baseDir,
  required String apiBase,
  required String token,
}) {
  final args = <String, Object?>{'apiBase': apiBase, 'token': token};
  final u = url;
  if (u != null && u.isNotEmpty) args['url'] = u;
  final h = html;
  if (h != null) args['html'] = h;
  final t = title;
  if (t != null && t.isNotEmpty) args['title'] = t;
  final d = baseDir;
  if (d != null && d.isNotEmpty) args['baseDir'] = d;
  return args;
}

/// 用原生 WebView 打开可交互 HTML；返回是否成功拉起。
///
/// [url] 与 [html] 二选一：网络文档传 [url]；本地 HTML 传正文 [html] 并给 [baseDir]
/// （电脑上的目录，原生侧用它解析页面里的相对 JS / CSS / 图片）。
Future<bool> openInteractiveHtml({
  String? url,
  String? html,
  String? title,
  String? baseDir,
}) async {
  final args = buildInteractiveHtmlArgs(
    url: url,
    html: html,
    title: title,
    baseDir: baseDir,
    apiBase: '${api.baseUrl}${api.path}',
    token: api.token,
  );
  final ok = await _webViewChannel.invokeMethod<bool>('openHtml', args);
  return ok == true;
}
