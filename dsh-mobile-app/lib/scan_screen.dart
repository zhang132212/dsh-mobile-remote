// 扫码连接：扫描桌面端 dsh 设置页"连接移动端设备"二维码。
// 二维码内容格式：DSHREMOTE|<电脑地址>|<访问口令>
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'dsh_kit.dart';
import 'l10n.dart';
import 'theme.dart';
import 'toast.dart';

class ScanScreen extends StatefulWidget {
  final void Function(String base, String token) onScanned;
  const ScanScreen({super.key, required this.onScanned});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  final MobileScannerController _controller = MobileScannerController();
  bool _done = false;
  bool _picking = false; // 相册识别中（防重复触发）

  static final _pattern = RegExp(r'^DSHREMOTE\|(.+?)\|(.*)$');

  /// 取景框边长（遮罩窗口、发丝框、四角标记共用）。
  static const double _frame = 240;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_done) return;
    final code = capture.barcodes.firstOrNull?.rawValue;
    if (code == null) return;
    final m = _pattern.firstMatch(code);
    if (m == null) return; // 非本 App 二维码：忽略继续扫
    _done = true;
    widget.onScanned(m.group(1)!, m.group(2)!);
  }

  /// 手电筒开关（无闪光灯/相机未就绪时静默忽略）。
  Future<void> _toggleTorch() async {
    try {
      await _controller.toggleTorch();
    } catch (_) {/* 忽略：设备无闪光灯 */}
  }

  /// 相册选图识别：识别不到只弹轻提示，不打断相机预览。
  Future<void> _pickFromGallery() async {
    if (_picking) return;
    _picking = true;
    try {
      final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (picked == null || !mounted) return;
      final capture = await _controller.analyzeImage(picked.path);
      if (!mounted) return;
      if (capture == null) {
        showToast(context, L10n.t('图片里没有识别到二维码', 'No QR code found in the image'));
        return;
      }
      _onDetect(capture);
    } catch (_) {
      if (mounted) {
        showToast(context, L10n.t('图片识别失败', 'Could not read the image'));
      }
    } finally {
      _picking = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = DshPalette.of(context);
    return Scaffold(
      backgroundColor: c.bg,
      appBar: DshAppBar(title: L10n.t('扫码连接', 'Scan to Connect')),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            // v3.0.0 review：相机权限被拒/硬件异常时给出引导（黑屏兜底，不再无声失败）
            errorBuilder: (context, error) => _cameraError(context),
          ),
          // 取景覆盖层：窗外压暗 + R28 发丝取景框 + 主色四角标记（一次绘制，不加多余 widget）
          Positioned.fill(
            child: CustomPaint(
              painter: _ScanOverlayPainter(
                mask: c.mask,
                line: c.line4,
                brand: c.brand,
                window: _frame,
                radius: DshRadius.panel,
              ),
            ),
          ),
          // 底部提示 + 手电/相册入口（实底面板，保证提示文字在相机画面上可读）
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _bottomPanel(c),
          ),
        ],
      ),
    );
  }

  /// 相机不可用时的兜底界面（令牌配色，亮/暗都成立）。
  Widget _cameraError(BuildContext context) {
    final c = DshPalette.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(DshSpace.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.no_photography_outlined, size: 40, color: c.caption),
            const SizedBox(height: DshSpace.md),
            Text(
              L10n.t('无法启动相机（权限被拒或设备不支持）\n请在系统设置中允许相机权限后重试',
                  'Camera unavailable (permission denied or unsupported).\nAllow camera permission in system settings and try again'),
              textAlign: TextAlign.center,
              style: DshType.xs13.copyWith(color: c.ink2),
            ),
            const SizedBox(height: DshSpace.lg),
            DshButton(
              label: L10n.t('返回', 'Back'),
              variant: DshButtonVariant.outline,
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    );
  }

  /// 底部面板：提示文字 xs13/ink3 + 手电、相册图标按钮。
  Widget _bottomPanel(DshPalette c) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.bg,
        border: Border(top: DshStroke.side(c.line2)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            DshSpace.xl,
            DshSpace.lg,
            DshSpace.xl,
            DshSpace.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                L10n.t('对准电脑屏幕上 dsh 设置页的\n「连接移动端设备」二维码', 'Point at the "Connect mobile device" QR code\non the dsh settings page on your computer'),
                textAlign: TextAlign.center,
                style: DshType.xs13.copyWith(color: c.ink3),
              ),
              const SizedBox(height: DshSpace.md),
              ValueListenableBuilder<MobileScannerState>(
                valueListenable: _controller,
                builder: (context, state, _) {
                  final torchOn = state.torchState == TorchState.on;
                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      DshIconButton(
                        icon: torchOn ? Icons.flash_on : Icons.flash_off,
                        selected: torchOn,
                        tooltip: L10n.t('手电筒', 'Flashlight'),
                        onTap: _toggleTorch,
                      ),
                      const SizedBox(width: DshSpace.md),
                      DshIconButton(
                        icon: Icons.photo_library_outlined,
                        tooltip: L10n.t('从相册选择', 'Pick from gallery'),
                        onTap: _pickFromGallery,
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 取景覆盖层：窗外遮罩（mask）+ R28 发丝框（line4）+ 四角标记（brand）。
///
/// 四角标记沿圆角画一段弧，和取景框的圆角对齐，而不是直角 L 形——
/// 官方视觉里没有硬直角，圆角弧更贴合面板语言。
class _ScanOverlayPainter extends CustomPainter {
  const _ScanOverlayPainter({
    required this.mask,
    required this.line,
    required this.brand,
    required this.window,
    required this.radius,
  });

  final Color mask;
  final Color line;
  final Color brand;
  final double window;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2),
      width: window,
      height: window,
    );
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(radius));

    // 窗外压暗：大矩形挖掉取景窗口（evenOdd 填充）
    final scrim = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRRect(rrect);
    canvas.drawPath(scrim, Paint()..color = mask);

    // 取景框：0.5px 发丝描边
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = DshStroke.hairline
        ..color = line,
    );

    // 四角标记：主色 3px 圆头弧，半径与取景框圆角一致
    final corner = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..color = brand;
    final d = radius * 2;
    final half = math.pi / 2;
    // 左上（180°→270°）、右上（270°→360°）、右下（0°→90°）、左下（90°→180°）
    canvas.drawArc(Rect.fromLTWH(rect.left, rect.top, d, d), math.pi, half, false, corner);
    canvas.drawArc(Rect.fromLTWH(rect.right - d, rect.top, d, d), -half, half, false, corner);
    canvas.drawArc(Rect.fromLTWH(rect.right - d, rect.bottom - d, d, d), 0, half, false, corner);
    canvas.drawArc(Rect.fromLTWH(rect.left, rect.bottom - d, d, d), half, half, false, corner);
  }

  @override
  bool shouldRepaint(covariant _ScanOverlayPainter old) =>
      old.mask != mask ||
      old.line != line ||
      old.brand != brand ||
      old.window != window ||
      old.radius != radius;
}
