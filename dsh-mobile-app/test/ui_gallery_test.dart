// UI 走查画廊：把设计系统（令牌 + 基础组件）渲染成 golden PNG，
// 用于在没有真机/模拟器时肉眼核对官方风格。
//
// 生成/更新：flutter test --update-goldens test/ui_gallery_test.dart
// 产物：test/goldens/ui_gallery_light.png、ui_gallery_dark.png
//
// 测试环境默认字体（FlutterTest）把所有字形画成方块，所以这里显式加载
// 系统中的中文字体（等线 Deng），并按官方回退栈里的族名注册。
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dsh_mobile_app/dsh_kit.dart';
import 'package:dsh_mobile_app/theme.dart';

/// 把字体文件注册到若干族名下（测试环境没有系统字体回退）。
Future<void> _registerFont(String path, List<String> families) async {
  final bytes = File(path).readAsBytesSync();
  for (final family in families) {
    final loader = FontLoader(family)
      ..addFont(Future<ByteData>.value(ByteData.view(bytes.buffer)));
    await loader.load();
  }
}

/// 画布尺寸：手机宽度 × 足够高，一次拍完整个画廊。
const Size _canvas = Size(390, 1560);

/// 聊天版式分区画布。
const Size _chatCanvas = Size(390, 1080);

void main() {
  setUpAll(() async {
    const families = <String>[
      'Roboto',
      'Microsoft YaHei',
      'PingFang SC',
      'Deng',
    ];
    await _registerFont(r'C:\Windows\Fonts\Deng.ttf', families);
  });

  testWidgets('设计系统画廊 - 亮色', (tester) async {
    await tester.binding.setSurfaceSize(_canvas);
    await tester.pumpWidget(
      const _Gallery(brightness: Brightness.light, part: _Part.tokens),
    );
    // 画廊里含无限循环动画（DshDots / 脉冲状态点 / 加载环），
    // 所以固定推进若干帧取确定画面，不用 pumpAndSettle。
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    await expectLater(
      find.byType(_Gallery),
      matchesGoldenFile('goldens/ui_gallery_light.png'),
    );
  });

  testWidgets('设计系统画廊 - 暗色', (tester) async {
    await tester.binding.setSurfaceSize(_canvas);
    await tester.pumpWidget(
      const _Gallery(brightness: Brightness.dark, part: _Part.tokens),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    await expectLater(
      find.byType(_Gallery),
      matchesGoldenFile('goldens/ui_gallery_dark.png'),
    );
  });

  testWidgets('聊天版式画廊 - 亮色', (tester) async {
    await tester.binding.setSurfaceSize(_chatCanvas);
    await tester.pumpWidget(
      const _Gallery(brightness: Brightness.light, part: _Part.chat),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    await expectLater(
      find.byType(_Gallery),
      matchesGoldenFile('goldens/ui_gallery_chat_light.png'),
    );
  });

  testWidgets('聊天版式画廊 - 暗色', (tester) async {
    await tester.binding.setSurfaceSize(_chatCanvas);
    await tester.pumpWidget(
      const _Gallery(brightness: Brightness.dark, part: _Part.chat),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    await expectLater(
      find.byType(_Gallery),
      matchesGoldenFile('goldens/ui_gallery_chat_dark.png'),
    );
  });
}

/// 画廊分区：令牌/组件区 与 聊天版式区（分开出图，避免单图过长被裁切）。
enum _Part { tokens, chat }

class _Gallery extends StatelessWidget {
  const _Gallery({required this.brightness, required this.part});

  final Brightness brightness;
  final _Part part;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: brightness == Brightness.dark ? DshTheme.dark() : DshTheme.light(),
      home: _GalleryBody(part: part),
    );
  }
}

class _GalleryBody extends StatelessWidget {
  const _GalleryBody({required this.part});

  final _Part part;

  bool get _tokens => part == _Part.tokens;

  @override
  Widget build(BuildContext context) {
    final c = DshPalette.of(context);
    return Scaffold(
      backgroundColor: c.bg,
      appBar: DshAppBar(
        title: _tokens ? '设计令牌 · DSH 官方风格' : '对话 · DSH 官方风格',
        automaticallyImplyLeading: false,
        actions: [
          DshIconButton(icon: Icons.search, onTap: () {}),
          DshIconButton(icon: Icons.more_horiz, onTap: () {}),
          const SizedBox(width: DshSpace.sm),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_tokens) ...[
              // ---------- 令牌色板 ----------
            const DshSectionHeader('令牌色板'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: DshSpace.pageH),
              child: Wrap(
                spacing: DshSpace.sm,
                runSpacing: DshSpace.sm,
                children: [
                  for (final (name, color) in <(String, Color)>[
                    ('brand', c.brand),
                    ('link', c.link),
                    ('ok', c.ok),
                    ('warn', c.warn),
                    ('danger', c.danger),
                    ('idle', c.idle),
                    ('bubble', c.bubble),
                    ('module', c.module),
                    ('selector', c.selector),
                    ('tag', c.tag),
                    ('codeBlock', c.codeBlock),
                    ('sidebar', c.sidebar),
                  ])
                    _Swatch(label: name, color: color),
                ],
              ),
            ),

            // ---------- 字体阶梯 ----------
            const DshSectionHeader('字体阶梯'),
            DshCard(
              margin: const EdgeInsets.symmetric(horizontal: DshSpace.pageH),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('l20 · 页面大标题', style: DshType.l20.copyWith(color: c.ink)),
                  Text('m16 · 标题栏标题', style: DshType.m16.copyWith(color: c.ink)),
                  Text('s14 · 正文默认 14/22', style: DshType.s14.copyWith(color: c.ink)),
                  Text('sStrong14 · 正文强调',
                      style: DshType.sStrong14.copyWith(color: c.ink)),
                  Text('xs13 · 次要文字 13/20',
                      style: DshType.xs13.copyWith(color: c.ink2)),
                  Text('xxs12 · 元信息 12/18',
                      style: DshType.xxs12.copyWith(color: c.ink3)),
                  Text('xxxs11 · 角标 11/14',
                      style: DshType.xxxs11.copyWith(color: c.caption)),
                  const SizedBox(height: DshSpace.sm),
                  Text('Markdown 正文 14/24，中文行高充裕便于长文阅读。',
                      style: DshType.mdBase.copyWith(color: c.ink)),
                  Text('行内代码 inline_code_sample',
                      style: DshType.mdCode.copyWith(color: c.ink)),
                ],
              ),
            ),

            // ---------- 按钮 ----------
            const DshSectionHeader('按钮'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: DshSpace.pageH),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: DshSpace.sm,
                    runSpacing: DshSpace.sm,
                    children: [
                      DshButton(label: '主操作', onPressed: () {}),
                      DshButton(
                        label: '次操作',
                        variant: DshButtonVariant.outline,
                        onPressed: () {},
                      ),
                      DshButton(
                        label: '弱操作',
                        variant: DshButtonVariant.ghost,
                        onPressed: () {},
                      ),
                      DshButton(
                        label: '危险',
                        variant: DshButtonVariant.danger,
                        onPressed: () {},
                      ),
                      DshButton(
                        label: '业务蓝',
                        variant: DshButtonVariant.business,
                        onPressed: () {},
                      ),
                    ],
                  ),
                  const SizedBox(height: DshSpace.sm),
                  Wrap(
                    spacing: DshSpace.sm,
                    runSpacing: DshSpace.sm,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      DshButton(
                        label: '小号 H28',
                        size: DshButtonSize.sm,
                        onPressed: () {},
                      ),
                      DshButton(
                        label: '中号 H36',
                        icon: Icons.add,
                        onPressed: () {},
                      ),
                      DshButton(
                        label: '加载中',
                        loading: true,
                        onPressed: () {},
                      ),
                      DshButton(label: '禁用', onPressed: null),
                    ],
                  ),
                  const SizedBox(height: DshSpace.md),
                  Row(
                    children: [
                      DshIconButton(icon: Icons.bolt, onTap: () {}),
                      DshIconButton(icon: Icons.push_pin, selected: true, onTap: () {}),
                      DshIconButton(
                        icon: Icons.notifications_none,
                        badge: 12,
                        onTap: () {},
                      ),
                      const SizedBox(width: DshSpace.sm),
                      DshPill(label: 'deepseek-v4', icon: Icons.auto_awesome, onTap: () {}),
                      const SizedBox(width: DshSpace.sm),
                      DshPill(label: 'PTC', active: true, onTap: () {}),
                    ],
                  ),
                ],
              ),
            ),

            // ---------- 设置卡片与列表行 ----------
            const DshSectionHeader('设置卡片与列表行'),
            DshCardGroup(
              children: [
                DshTile(
                  leading: const Icon(Icons.tune),
                  title: '默认 Agent 预设',
                  subtitle: '作用于之后新建的会话',
                  chevron: true,
                  onTap: () {},
                ),
                DshTile(
                  leading: const Icon(Icons.shield_outlined),
                  title: '权限预设',
                  subtitle: '危险权限需二次确认',
                  trailing: DshTag(label: '标准', color: c.business),
                  onTap: () {},
                ),
                DshTile(
                  leading: const Icon(Icons.language),
                  title: '语言',
                  trailing: Text('简体中文', style: DshType.xs13.copyWith(color: c.ink3)),
                  chevron: true,
                  onTap: () {},
                ),
                DshTile(
                  leading: const Icon(Icons.dark_mode_outlined),
                  title: '深色模式',
                  trailing: DshSwitch(value: true, onChanged: (_) {}),
                ),
                DshTile(
                  leading: const Icon(Icons.delete_outline),
                  title: '清除本地缓存',
                  danger: true,
                  onTap: () {},
                ),
              ],
            ),

            // ---------- 标签、状态、进度 ----------
            const DshSectionHeader('标签 / 状态 / 进度'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: DshSpace.pageH),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: DshSpace.sm,
                    runSpacing: DshSpace.sm,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      DshTag(label: '已连接', color: c.ok, background: c.okSoft),
                      DshTag(label: '思考中', color: c.business),
                      DshTag(label: '等待审批', color: c.warnLabel, background: c.warnSoft),
                      DshTag(label: '失败', color: c.danger, background: c.dangerSoft),
                      DshTag(label: '归档', dense: true),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          DshStatusDot(color: c.ok),
                          const SizedBox(width: 6),
                          DshStatusDot(color: c.business, pulse: true),
                          const SizedBox(width: 6),
                          DshStatusDot(color: c.idle),
                        ],
                      ),
                      const DshDots(),
                    ],
                  ),
                  const SizedBox(height: DshSpace.md),
                  DshProgressBar(value: 0.42),
                  const SizedBox(height: DshSpace.sm),
                  DshProgressBar(value: 0.86, color: c.warn),
                  const SizedBox(height: DshSpace.lg),
                  DshSegmented(
                    items: const ['任务', '子代理', '目标'],
                    index: 1,
                    onChanged: (_) {},
                  ),
                  const SizedBox(height: DshSpace.lg),
                  const DshBanner(
                    message: '该操作不可撤销，请确认后继续。',
                    icon: Icons.warning_amber_rounded,
                    tone: DshBannerTone.warn,
                  ),
                  const SizedBox(height: DshSpace.sm),
                  const DshBanner(
                    message: '已连接到 192.168.1.8:3080',
                    icon: Icons.check_circle_outline,
                    tone: DshBannerTone.success,
                  ),
                ],
              ),
            ),

            ],

            // ---------- 消息气泡与工具卡 ----------
            if (!_tokens) ...[
            const DshSectionHeader('消息与工具卡'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: DshSpace.chatH),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(
                    alignment: Alignment.centerRight,
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 280),
                      padding: const EdgeInsets.symmetric(
                        horizontal: DshSpace.md,
                        vertical: DshSpace.sm + 2,
                      ),
                      decoration: BoxDecoration(
                        color: c.bubble,
                        borderRadius: BorderRadius.circular(DshRadius.lg),
                      ),
                      child: Text('把 README 的截图那段重写一下',
                          style: DshType.mdBase.copyWith(color: c.ink)),
                    ),
                  ),
                  const SizedBox(height: DshSpace.md),
                  Text(
                    '已按官方 DeepSeek Harness 的令牌体系重写：主按钮改为近黑填充，'
                    '卡片统一 R20 + 发丝描边，分隔线降到 0.5px。',
                    style: DshType.mdBase.copyWith(color: c.ink),
                  ),
                  const SizedBox(height: DshSpace.md),
                  DshCard(
                    radius: DshRadius.lg,
                    padding: const EdgeInsets.all(DshSpace.md),
                    child: Row(
                      children: [
                        DshStatusDot(color: c.ok),
                        const SizedBox(width: DshSpace.sm),
                        Expanded(
                          child: Text('edit · lib/theme.dart',
                              style: DshType.xxs12.copyWith(color: c.ink3)),
                        ),
                        Text('+128 −41', style: DshType.xxs12.copyWith(color: c.ok)),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // ---------- 输入区 ----------
            const DshSectionHeader('输入区（composer）'),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                DshSpace.chatH,
                0,
                DshSpace.chatH,
                DshSpace.xxl,
              ),
              child: Container(
                padding: const EdgeInsets.fromLTRB(
                  DshSpace.lg,
                  DshSpace.md,
                  DshSpace.sm,
                  DshSpace.sm,
                ),
                decoration: BoxDecoration(
                  color: c.input,
                  borderRadius: DshRadius.rPanel,
                  border: Border.fromBorderSide(DshStroke.side(c.line4)),
                  boxShadow: DshShadow.soft,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('给 agent 派个活…',
                        style: DshType.s14.copyWith(color: c.caption)),
                    const SizedBox(height: DshSpace.md),
                    Row(
                      children: [
                        DshPill(label: '标准', icon: Icons.tune, onTap: () {}),
                        const SizedBox(width: DshSpace.sm),
                        DshPill(label: 'v4.1', onTap: () {}),
                        const Spacer(),
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: c.brand,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(Icons.arrow_upward,
                              size: 18, color: c.onInk),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            // ---------- 空状态 ----------
            const DshSectionHeader('空状态'),
            const SizedBox(
              height: 200,
              child: DshEmpty(
                icon: Icons.forum_outlined,
                title: '还没有会话',
                message: '在电脑端 dsh 新建一个会话，这里会自动出现。',
              ),
            ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final c = DshPalette.of(context);
    return Column(
      children: [
        Container(
          width: 56,
          height: 40,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(DshRadius.sm),
            border: Border.fromBorderSide(DshStroke.side(c.line3)),
          ),
        ),
        const SizedBox(height: DshSpace.xs),
        Text(label, style: DshType.xxxs11.copyWith(color: c.ink3)),
      ],
    );
  }
}
