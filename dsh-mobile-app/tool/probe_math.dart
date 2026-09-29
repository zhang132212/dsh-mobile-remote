// 二分定位：那条 851 字符回答里，到底是哪个片段触发无限循环/无界分配。
// 纯 Dart（只用 tex.dart，不碰 Flutter），逐个片段跑，先打印再执行 ——
// 一旦挂住，最后打印的那条就是元凶。
//
// 跑法： dart run tool/probe_math.dart
import 'dart:io';

import 'package:dsh_mobile_app/math/tex.dart';

void probe(String label, String text) {
  stdoutWriteln('>>> [$label] len=${text.length}');
  final sw = Stopwatch()..start();
  try {
    final segs = findMathSegments(text);
    stdoutWriteln('    段数=${segs.length}  用时=${sw.elapsedMilliseconds}ms');
    for (final s in segs.take(3)) {
      stdoutWriteln('      · ${s.tex.length} 字符: ${s.tex.substring(0, s.tex.length > 60 ? 60 : s.tex.length)}');
    }
  } catch (e) {
    stdoutWriteln('    抛异常: $e');
  }
}

// 顶层输出收口（不用 print —— 会让 flutter analyze 报 avoid_print）
void stdoutWriteln(String s) => stdout.writeln(s);

void main() {
  const single = r'''/"x^5+1"/''';
  const factorization =
      r'''/"x^5+1=(x+1)\left(x^2+\alpha x+1\right)\left(x^2-\beta x+1\right),\qquad \alpha=\frac{\sqrt5-1}{2},\ \beta=\frac{\sqrt5+1}{2}"/''';
  const coeffs =
      r'''/"A=\frac15,\ B=\frac{\alpha}{5},\ C=\frac25,\ D=-\frac{\beta}{5},\ E=\frac25"/''';
  const mainIntegral =
      r'''/"\int\frac{dx}{x^5+1}=\frac15\ln|x+1|+\frac{\alpha}{10}\ln\!\left(x^2+\alpha x+1\right)-\frac{\beta}{10}\ln\!\left(x^2-\beta x+1\right)+\frac{\sqrt{4-\alpha^2}}5\arctan\frac{2x+\alpha}{\sqrt{4-\alpha^2}}+\frac{\sqrt{4-\beta^2}}5\arctan\frac{2x-\beta}{\sqrt{4-\beta^2}}+C"/''';

  probe('1 简单', single);
  probe('2 因式分解', factorization);
  probe('3 系数', coeffs);
  probe('4a 绝对值条 ln|x+1|', r'''/"/\ln|x+1|"/''');
  probe('4b 负细空 \\!', r'''/"/a\!b"/''');
  probe('4c left-right + 负细空', r'''/"/\ln\!\left(x^2+\alpha x+1\right)"/''');
  probe('4d arctan+frac+sqrt', r'''/"/\arctan\frac{2x+\alpha}{\sqrt{4-\alpha^2}}"/''');
  probe('4e frac 分母单字符', r'''/"/\frac{\sqrt{4-\alpha^2}}5"/''');
  probe('4f 小误差', r'''/"8.7\times10^{-11}"/''');
  probe('4g 定积分', r'''/"/\int_0^1\frac{dx}{1+x^5}=0.8883135727\ldots"/''');
  probe('5 完整主公式', mainIntegral);
  stdoutWriteln('=== 全部片段跑完，没有挂 ===');
}
