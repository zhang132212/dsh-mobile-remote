// 文档抽屉（v3.2.1）——把文档读在**底部抽屉**里，而不是新开一整页。
//
// 用户要的手感：聊天里点助手发的链接 → 就地开始读 → 划下去立刻回到对话，
// **对话全程不关闭**。所以这里用 modal bottom sheet（对话在下面仍然存活），
// 而不是 Navigator.push 一整页把聊天盖掉。
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../api.dart';
import '../screens/doc_viewer_screen.dart';
import '../theme.dart';
import 'link.dart';

/// 在底部抽屉里打开文档；返回的 Future 在抽屉关闭时完成。
Future<void> showDocSheet(
  BuildContext context, {
  required String name,
  String? localPath,
  String? httpUrl,
  Uint8List? bytes,
  Api? api,
  double heightFactor = 0.86,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: DshColors.surface(context),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (c) => FractionallySizedBox(
      heightFactor: heightFactor,
      child: DocViewerScreen(
        name: name,
        bytes: bytes,
        remotePath: localPath,
        httpUrl: httpUrl,
        api: api,
        embedded: true,
      ),
    ),
  );
}

/// 便捷入口：给一个（可能）文档链接的 URL，是文档链接就在抽屉里打开。
/// 返回 true 表示已按文档处理（调用方不必再走浏览器）。
Future<bool> showDocLinkSheet(BuildContext context, String url, {Api? api}) async {
  final t = parseDocLink(url);
  if (t == null) return false;
  await showDocSheet(
    context,
    name: t.name,
    localPath: t.localPath,
    httpUrl: t.httpUrl,
    api: api,
  );
  return true;
}
