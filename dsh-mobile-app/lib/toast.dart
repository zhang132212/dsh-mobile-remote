// 全局轻提示：短滞留 + 悬浮样式，不遮挡底部输入区、不阻塞后续操作。
// 长消息自动延长（错误详情需要阅读时间），短提示 1.6 秒即消失。
// 视觉走官方 toast 语言：toast 深底 + onToast 文字 + R12 + 0.5px 发丝边，
// 底色与圆角由 theme.dart 的 snackBarTheme 统一，这里只补文字与内衬。
import 'package:flutter/material.dart';

import 'theme.dart';

void showToast(BuildContext context, String msg) {
  showToastAt(ScaffoldMessenger.of(context), msg);
}

/// 面向已持有 messenger 的调用点（弹层/异步回调后 context 可能已失效，用捕获的 messenger）。
void showToastAt(ScaffoldMessengerState msgr, String msg) {
  final ms = msg.length > 50 ? 3000 : 1600;
  // messenger 已卸载时无处可显示（且取不到主题），直接放弃
  if (!msgr.mounted) return;
  final c = DshPalette.of(msgr.context);
  msgr
    ..clearSnackBars()
    ..showSnackBar(SnackBar(
      content: Text(msg, style: DshType.xs13.copyWith(color: c.onToast)),
      duration: Duration(milliseconds: ms),
      behavior: SnackBarBehavior.floating,
      elevation: 0,
      // 官方 toast 内衬 12/10
      padding: const EdgeInsets.symmetric(
        horizontal: DshSpace.md,
        vertical: 10,
      ),
      // 悬浮提示外边距对齐页面左右安全边距
      margin: const EdgeInsets.fromLTRB(
        DshSpace.pageH,
        0,
        DshSpace.pageH,
        DshSpace.pageH,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: DshRadius.rMd,
        side: DshStroke.side(c.line3),
      ),
    ));
}
