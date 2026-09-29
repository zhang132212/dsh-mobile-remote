// 数学模块测试（v3.2.0）：TeX 探测 / 解析 / OMML 导出 / OMML 回读。
// 重点覆盖用户给的实例公式（含 \boxed、\int、\frac 链、\varphi、\left..\right）。
import 'package:flutter_test/flutter_test.dart';
import 'package:xml/xml.dart';

import 'package:dsh_mobile_app/math/omml.dart';
import 'package:dsh_mobile_app/math/tex.dart';

/// 用户实例：一元五次分式的部分分式积分结果（$$..$$ 包裹）。
const String kUserExample = r'''$$\boxed{\;\int\frac{dx}{x^5+1}
=\frac15\ln|x+1|+\frac{\ln\left(x^2-\varphi x+1\right)}{10\varphi}
-\frac{\ln\left(x^2+\varphi^{-1}x-1\right)}{10\varphi^{-1}}
-\frac{\varphi^{-1}\sin\frac{2\pi}{5}}{5}\arctan\frac{x-\varphi/2}{\sin\frac{2\pi}{5}}
-\frac{\varphi\sin\frac{\pi}{5}\,}{5}\arctan\frac{x+\frac{1}{2\varphi^{-1}}}{\sin\frac{\pi}{5}}+C\;}$$''';

/// 去掉换行的紧凑版（OMML 往返用）
String get kUserExampleFlat =>
    kUserExample.replaceAll('\n', ' ').replaceAll(r'$$', '').replaceAll(r'\boxed{', r'\boxed{');

/// 取 `val` 属性：按 local 名扫（package:xml 把 m:val 存成前缀名，
/// 命名空间限定查找取不到——与 lib 里 _mVal 同一处理）。
String? mval(XmlElement? el) {
  if (el == null) return null;
  for (final a in el.attributes) {
    if (a.name.local == 'val') return a.value;
  }
  return null;
}

void main() {
  group('LaTeX 探测', () {
    test(r'$$...$$ 被识别为显示式', () {
      final segs = findMathSegments(kUserExample);
      expect(segs.length, 1);
      expect(segs.first.display, isTrue);
      expect(segs.first.tex.contains(r'\boxed'), isTrue);
      // 定界符要完整剥离
      expect(segs.first.tex.startsWith(r'$'), isFalse);
      expect(segs.first.tex.endsWith(r'$'), isFalse);
    });

    test(r'行内 $..$ 与 \(..\)、\[..\]', () {
      expect(findMathSegments(r'设 $x^2+1$ 为').length, 1);
      expect(findMathSegments(r'设 \(x^2+1\) 为').length, 1);
      expect(findMathSegments(r'\[a=b\]').first.display, isTrue);
    });

    test('货币串不误判为公式', () {
      expect(findMathSegments('价格 \$5 到 \$10 之间').isEmpty, isTrue);
      expect(findMathSegments('花费 \$100 与 \$200').isEmpty, isTrue);
    });

    test('纯文本无公式', () {
      expect(findMathSegments('这是一段普通的中文说明，没有公式。').isEmpty, isTrue);
      expect(containsMath('没有公式'), isFalse);
    });
  });

  group('TeX 解析', () {
    test(r'\int 被解析为大算符', () {
      final n = parseTex(r'\int f dx');
      // MRow 首元素应是 MBigOp（后续式子并入其 e）
      expect(n, isA<MRow>());
      final row = n as MRow;
      expect(row.items.first, isA<MBigOp>());
      expect((row.items.first as MBigOp).op, '∫');
    });

    test(r'\frac 与 \sqrt', () {
      final frac = parseTex(r'\frac{a}{b}');
      expect(frac, isA<MFrac>());
      final sqrt = parseTex(r'\sqrt[3]{x}');
      expect(sqrt, isA<MSqrt>());
      expect((sqrt as MSqrt).index, isNotNull);
      expect(parseTex(r'\sqrt{x}'), isA<MSqrt>());
    });

    test('上下标（含顺序颠倒）', () {
      final a = parseTex(r'x_i^2');
      expect(a, isA<MScript>());
      expect((a as MScript).sub, isNotNull);
      expect(a.sup, isNotNull);
      final b = parseTex(r'x^2_i');
      expect(b, isA<MScript>());
      expect((b as MScript).sub, isNotNull);
      expect(b.sup, isNotNull);
    });

    test(r'\varphi 与希腊字母', () {
      final n = parseTex(r'\varphi + \pi');
      expect(mathToPlain(n), contains('φ'));
      expect(mathToPlain(n), contains('π'));
    });

    test(r'\boxed 保留内容', () {
      final n = parseTex(r'\boxed{x+1}');
      expect(n, isA<MBoxed>());
      expect(mathToPlain(n), contains('x'));
    });

    test(r'\left( \right) 定界符', () {
      final n = parseTex(r'\left(x+1\right)');
      expect(n, isA<MDelim>());
      expect((n as MDelim).left, '(');
      expect(n.right, ')');
    });

    test('未知命令降级为文本而不是丢失', () {
      final n = parseTex(r'\unknowncmd{x}');
      expect(mathToPlain(n).contains('unknowncmd'), isTrue);
    });

    test('解析器对畸形输入不抛异常', () {
      for (final bad in [r'\frac{', r'}{', r'^', r'_', r'\left(', r'{a', r'\begin{matrix}']) {
        expect(() => parseTex(bad), returnsNormally, reason: bad);
      }
    });
  });

  group('OMML 导出（Word 原生公式）', () {
    test('产生合法的 m:oMath 结构', () {
      final xml = texToOmmlXml(r'\frac{a}{b}');
      final doc = XmlDocument.parse(xml);
      expect(doc.rootElement.name.local, 'oMath');
      expect(doc.rootElement.name.prefix, 'm');
      expect(xml.contains('<m:f>') || xml.contains('<m:f '), isTrue);
      expect(xml.contains('<m:num>'), isTrue);
      expect(xml.contains('<m:den>'), isTrue);
    });

    test(r'\int 映射为 nary，且被作用式进入 m:e', () {
      final el = texToOmmlElement(r'\int_a^b f dx');
      final nary = el.childElements.firstWhere((e) => e.name.local == 'nary');
      final pr = nary.childElements.firstWhere((e) => e.name.local == 'naryPr');
      final chr = pr.childElements.firstWhere((e) => e.name.local == 'chr');
      expect(mval(chr), '∫');
      // 上下限
      expect(nary.childElements.any((e) => e.name.local == 'sub'), isTrue);
      expect(nary.childElements.any((e) => e.name.local == 'sup'), isTrue);
      // 被作用式（f dx）必须在 e 里，而不是与算符并列
      final e = nary.childElements.firstWhere((x) => x.name.local == 'e');
      expect(e.innerText.replaceAll('\u2009', '').contains('f'), isTrue);
    });

    test(r'\boxed 映射为 borderBox（Word 里才会画出可见边框）', () {
      final el = texToOmmlElement(r'\boxed{x}');
      expect(el.childElements.any((x) => x.name.local == 'borderBox'), isTrue);
    });

    test(r'\sum 用 undOvr，\int 用 subSup', () {
      final sum = texToOmmlElement(r'\sum_{i=1}^{n} a_i');
      final sumPr = sum.childElements
          .firstWhere((e) => e.name.local == 'nary')
          .childElements
          .firstWhere((e) => e.name.local == 'naryPr');
      final limLoc = sumPr.childElements.firstWhere((e) => e.name.local == 'limLoc');
      expect(mval(limLoc), 'undOvr');

      final intEl = texToOmmlElement(r'\int_0^1 f');
      final intPr = intEl.childElements
          .firstWhere((e) => e.name.local == 'nary')
          .childElements
          .firstWhere((e) => e.name.local == 'naryPr');
      expect(mval(intPr.childElements.firstWhere((e) => e.name.local == 'limLoc')), 'subSup');
    });

    test('上下标映射 sSup / sSub / sSubSup', () {
      expect(texToOmmlXml(r'x^2').contains('<m:sSup>'), isTrue);
      expect(texToOmmlXml(r'x_2').contains('<m:sSub>'), isTrue);
      expect(texToOmmlXml(r'x_2^3').contains('<m:sSubSup>'), isTrue);
    });

    test('含 XML 特殊字符时正确转义', () {
      final xml = texToOmmlXml(r'a<b>c');
      final doc = XmlDocument.parse(xml); // 能解析即说明转义正确
      expect(doc.rootElement.innerText.contains('<'), isTrue);
    });

    test('用户实例公式可完整导出且包含所有关键结构', () {
      final tex = findMathSegments(kUserExample).first.tex;
      final xml = texToOmmlXml(tex);
      final doc = XmlDocument.parse(xml);
      expect(doc.rootElement.name.local, 'oMath');
      expect(xml.contains('borderBox'), isTrue, reason: r'\boxed 应生成边框公式');
      expect(xml.contains('<m:nary>'), isTrue, reason: r'\int 应生成 nary');
      expect(xml.contains('<m:f>'), isTrue, reason: r'\frac 应生成分式');
      expect(xml.contains('<m:rad>'), isFalse); // 本例无根式
      expect(xml.contains('φ'), isTrue, reason: r'\varphi 应转成 φ');
      expect(xml.contains('arctan'), isTrue, reason: '函数名应保留');
      // 显示的 m:oMathPara 版本
      final para = texToOmmlPara(tex);
      expect(para.name.local, 'oMathPara');
      expect(para.toXmlString().contains('oMath'), isTrue);
    });
  });

  group('OMML 回读（读 docx 里的公式）', () {
    test('导出的 OMML 能被读回为 TeX 并再次解析', () {
      const tex = r'\frac{a}{b} + x^2';
      final el = texToOmmlElement(tex);
      final back = ommlToTex(el);
      expect(back.contains(r'\frac'), isTrue);
      expect(back.contains('^'), isTrue);
      // 回读的 TeX 必须能被解析器接受
      expect(() => parseTex(back), returnsNormally);
    });

    test('用户实例公式：OMML → TeX → 再解析，关键符号不丢', () {
      final tex = findMathSegments(kUserExample).first.tex;
      final back = ommlToTex(texToOmmlElement(tex));
      expect(back.contains('φ'), isTrue);
      expect(back.contains('arctan'), isTrue);
      final plain = mathToPlain(parseTex(back));
      for (final must in ['φ', 'π', 'arctan', 'ln', 'C']) {
        expect(plain.contains(must), isTrue, reason: '回读后应保留 $must');
      }
    });

    test('根式往返', () {
      final back = ommlToTex(texToOmmlElement(r'\sqrt[3]{x}'));
      expect(back.contains(r'\sqrt'), isTrue);
      expect(back.contains('[3]'), isTrue);
    });

    test('矩阵往返', () {
      final back = ommlToTex(texToOmmlElement(r'\begin{pmatrix}a&b\\c&d\end{pmatrix}'));
      expect(back.contains('matrix'), isTrue);
      expect(back.contains('&'), isTrue);
    });
  });
}
