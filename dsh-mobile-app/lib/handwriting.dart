// v3.3.1（手写探针）：原生输入框通道。
//
// 华为「全局手写」只认真正的 Android 输入框；Flutter 的 TextField 是自绘的，系统只看到
// 一个隐藏的编辑代理，落笔不会被判定成「书写」。这一层用来验证另一半假设：
// 换成原生 EditText 之后，系统手写能不能接管。
import 'package:flutter/services.dart';

const MethodChannel _channel = MethodChannel('dsh/handwriting');

/// 打开原生输入框探针页；返回写进去的文字，取消返回 null。
Future<String?> openHandwritingProbe() async {
  try {
    return await _channel.invokeMethod<String>('openProbe');
  } on PlatformException catch (e) {
    if (e.code == 'cancelled') return null;
    rethrow;
  }
}
