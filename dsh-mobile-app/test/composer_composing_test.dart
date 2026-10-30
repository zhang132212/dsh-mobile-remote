// v3.3.1（手写适配）：composer 的「预上屏」判定与落字。
//
// 手写笔、语音、拼音未选字，输入法都会给出一段 composing 区间——这段时间里的文本
// 是**还没确认**的。这里锁住两条约定：
//   1) 预上屏期间不存草稿（否则半截字下次进会话又被恢复出来）；
//   2) 发送/清空前先落字（否则手写 IME 可能把刚才那句再推回空输入框）。
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dsh_mobile_app/screens/chat_screen.dart';

void main() {
  test('空值与光标型 composing 都不算预上屏', () {
    expect(isImeComposing(TextEditingValue.empty), isFalse);

    // 某些输入法把 composing 标成 start == end（只是光标位置），那不是"正在写字"
    const cursorOnly = TextEditingValue(
      text: '你好',
      selection: TextSelection.collapsed(offset: 2),
      composing: TextRange(start: 2, end: 2),
    );
    expect(isImeComposing(cursorOnly), isFalse);
  });

  test('正在写的字算预上屏', () {
    const writing = TextEditingValue(
      text: '你好世界',
      selection: TextSelection.collapsed(offset: 4),
      composing: TextRange(start: 2, end: 4),
    );
    expect(isImeComposing(writing), isTrue);
  });

  test('落字：composing 清空，文本与光标不动', () {
    const writing = TextEditingValue(
      text: '你好世界',
      selection: TextSelection.collapsed(offset: 4),
      composing: TextRange(start: 2, end: 4),
    );
    final committed = commitComposing(writing);
    expect(committed.text, '你好世界');
    expect(committed.selection, const TextSelection.collapsed(offset: 4));
    expect(committed.composing, TextRange.empty);
    expect(isImeComposing(committed), isFalse);
  });

  test('没有预上屏时落字是恒等变换', () {
    const plain = TextEditingValue(
      text: 'abc',
      selection: TextSelection.collapsed(offset: 3),
    );
    expect(commitComposing(plain), plain);
  });
}
