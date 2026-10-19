// 内核问询卡（question/requested）——官方 Harness QuestionComposer 的手机版。
//
// v3.3.0（官方风格）：整卡用 DshCard（R20 + 发丝边，不再自绘投影）承载，
// 标题 sStrong14·ink、说明 xs13·ink3；选项行换 DshTile（选中态 navActive 底）
// 配左侧 DshStatusDot；按钮全部走 DshButton；自定义输入交给主题 inputDecorationTheme。
import 'package:flutter/material.dart';
import '../dsh_kit.dart';
import '../l10n.dart';
import '../models.dart';
import '../theme.dart';

/// 官方 Harness QuestionComposer 的手机端适配：逐题作答 + 自定义输入。
class HarnessQuestionCard extends StatefulWidget {
  final QuestionRequest request;
  final VoidCallback onCancel;
  final Future<void> Function(List<Map<String, dynamic>> answers) onSubmitted;
  // v3.1.6（app-audit ①5）：支持 key——聊天页按 rpcId 传 ValueKey，换问询时强制新建 State
  const HarnessQuestionCard({super.key, required this.request, required this.onCancel, required this.onSubmitted});

  @override
  State<HarnessQuestionCard> createState() => HarnessQuestionCardState();
}

class HarnessQuestionCardState extends State<HarnessQuestionCard> {
  final Map<String, Set<String>> _selected = {}; // questionId -> 选项 label 集合
  final Map<String, String> _custom = {}; // questionId -> 自定义输入
  final Map<String, TextEditingController> _ctrls = {};
  bool _submitting = false;
  int _page = 0;
  String? _hint; // 校验提示

  @override
  void initState() {
    super.initState();
    for (final q in widget.request.questions) {
      _selected[q.id] = {};
      _custom[q.id] = '';
      _ctrls[q.id] = TextEditingController();
    }
  }

  @override
  void dispose() {
    for (final c in _ctrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _toggle(AskQuestion q, String label) {
    setState(() {
      final sel = _selected[q.id]!;
      if (q.multiSelect) {
        if (!sel.add(label)) sel.remove(label);
      } else {
        if (sel.contains(label)) {
          sel.clear();
        } else {
          sel
            ..clear()
            ..add(label);
        }
      }
      // 单选语义：选了选项就清掉自定义输入（内核要求二选一）
      if (!q.multiSelect && sel.isNotEmpty) {
        _custom[q.id] = '';
        _ctrls[q.id]!.clear();
      }
      _hint = null;
    });
  }

  void _onCustom(AskQuestion q, String v) {
    setState(() {
      _custom[q.id] = v;
      // 单选语义：输入了自定义答案就清掉选项
      if (!q.multiSelect && v.trim().isNotEmpty) _selected[q.id]!.clear();
      _hint = null;
    });
  }

  Future<void> _submit() async {
    final answers = <Map<String, dynamic>>[];
    for (final q in widget.request.questions) {
      final sel = _selected[q.id] ?? const <String>{};
      final custom = (_custom[q.id] ?? '').trim();
      if (custom.isEmpty && sel.isEmpty) {
        setState(() {
          _page = widget.request.questions.indexOf(q);
          _hint = L10n.t('请选择选项，或输入其他答案', 'Choose an option or type another answer');
        });
        return;
      }
      answers.add({
        'id': q.id,
        'selected': q.multiSelect || custom.isEmpty ? sel.toList() : const <String>[],
        if (custom.isNotEmpty) 'custom': custom,
      });
    }
    setState(() => _submitting = true);
    try {
      await widget.onSubmitted(answers);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = DshPalette.of(context);
    final questions = widget.request.questions;
    final q = questions.isEmpty ? null : questions[_page];
    final media = MediaQuery.of(context);
    final height = ((media.size.height - media.viewInsets.bottom) * 0.55).clamp(180.0, 520.0);
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: height),
      // 官方卡片：R20 + layer2 填充 + 0.5px 发丝边，不叠投影
      child: DshCard(
        margin: const EdgeInsets.fromLTRB(DshSpace.md, 0, DshSpace.md, DshSpace.sm),
        padding: EdgeInsets.zero,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 标题行：问询 header（sStrong14 · ink）+ 取消
            Padding(
              padding: const EdgeInsets.fromLTRB(
                DshSpace.xl,
                DshSpace.md,
                DshSpace.sm,
                0,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      q?.header ?? L10n.t('需要你决定', 'Your input needed'),
                      style: DshType.sStrong14.copyWith(color: c.ink),
                    ),
                  ),
                  DshIconButton(
                    icon: Icons.close,
                    iconSize: 18,
                    tooltip: L10n.t('取消', 'Cancel'),
                    onTap: _submitting ? null : widget.onCancel,
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                key: ValueKey('question-page-$_page'),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (q != null) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          DshSpace.xl,
                          DshSpace.xs,
                          DshSpace.xl,
                          0,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              q.question,
                              style: DshType.baseStrong16.copyWith(color: c.ink),
                            ),
                            if (q.detail?.isNotEmpty == true) ...[
                              const SizedBox(height: DshSpace.sm),
                              Text(
                                q.detail!,
                                style: DshType.xs13.copyWith(color: c.ink3),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: DshSpace.sm),
                      // 选项行整行铺满卡片，选中态用 navActive 底（DshTile 自带）
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: DshSpace.sm),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (final o in q.options)
                              _OptionTile(
                                label: o.label,
                                description: o.description,
                                multi: q.multiSelect,
                                selected: _selected[q.id]!.contains(o.label),
                                onTap: () {
                                  if (!_submitting) _toggle(q, o.label);
                                },
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: DshSpace.md),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: DshSpace.xl),
                        child: TextField(
                          enabled: !_submitting,
                          controller: _ctrls[q.id],
                          onChanged: (v) => _onCustom(q, v),
                          minLines: 1,
                          maxLines: 3,
                          style: DshType.s14.copyWith(color: c.ink),
                          // 边框/内衬/焦点态一律取主题 inputDecorationTheme
                          decoration: InputDecoration(
                            hintText: q.multiSelect
                                ? L10n.t('补充说明（可选）…', 'Add details (optional)…')
                                : L10n.t('或输入其他答案…', 'Or type another answer…'),
                            isDense: true,
                          ),
                        ),
                      ),
                    ] else
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: DshSpace.xl),
                        child: Text(
                          L10n.t('问题内容为空，请取消后重试', 'No questions received. Cancel and retry.'),
                          style: DshType.s14.copyWith(color: c.ink2),
                        ),
                      ),
                    if (_hint != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          DshSpace.xl,
                          DshSpace.md,
                          DshSpace.xl,
                          0,
                        ),
                        child: Text(
                          _hint!,
                          style: DshType.xs13.copyWith(color: c.danger),
                        ),
                      ),
                    const SizedBox(height: DshSpace.md),
                  ],
                ),
              ),
            ),
            const DshDivider(),
            // 底栏：翻页 + 取消/下一步（primary）
            Padding(
              padding: const EdgeInsets.fromLTRB(
                DshSpace.md,
                DshSpace.sm,
                DshSpace.md,
                DshSpace.md,
              ),
              child: Row(
                children: [
                  if (questions.length > 1) ...[
                    DshIconButton(
                      icon: Icons.chevron_left,
                      tooltip: L10n.t('上一题', 'Previous question'),
                      onTap: _submitting || _page == 0
                          ? null
                          : () => setState(() {
                                _page--;
                                _hint = null;
                              }),
                    ),
                    const SizedBox(width: DshSpace.xs),
                    Text(
                      '${_page + 1} / ${questions.length}',
                      style: DshType.xxs12.copyWith(color: c.ink3),
                    ),
                  ],
                  const Spacer(),
                  DshButton(
                    label: L10n.t('取消', 'Cancel'),
                    variant: DshButtonVariant.outline,
                    onPressed: _submitting ? null : widget.onCancel,
                  ),
                  const SizedBox(width: DshSpace.sm),
                  DshButton(
                    label: _submitting
                        ? L10n.t('提交中…', 'Submitting…')
                        : _page < questions.length - 1
                            ? L10n.t('下一题', 'Next')
                            : L10n.t('提交', 'Submit'),
                    variant: DshButtonVariant.primary,
                    loading: _submitting,
                    onPressed: _submitting || q == null
                        ? null
                        : _page < questions.length - 1
                            ? () => setState(() {
                                  _page++;
                                  _hint = null;
                                })
                            : _submit,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 单个选项行：DshTile（选中 navActive 底）+ 左侧状态圆点；多选额外给一个勾选框提示。
class _OptionTile extends StatelessWidget {
  final String label;
  final String? description;
  final bool multi;
  final bool selected;
  final VoidCallback onTap;
  const _OptionTile({
    required this.label,
    this.description,
    required this.multi,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = DshPalette.of(context);
    final desc = description;
    return DshTile(
      selected: selected,
      leading: DshStatusDot(color: selected ? c.business : c.idle),
      titleWidget: Text(
        label,
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        style: (selected ? DshType.sStrong14 : DshType.s14).copyWith(color: c.ink),
      ),
      subtitle: (desc != null && desc.isNotEmpty) ? desc : null,
      trailing: multi
          ? Icon(
              selected ? Icons.check_box : Icons.check_box_outline_blank,
              size: 18,
              color: selected ? c.ink : c.ink3,
            )
          : null,
      onTap: onTap,
    );
  }
}
