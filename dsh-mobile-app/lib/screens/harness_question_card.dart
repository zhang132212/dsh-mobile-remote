import 'package:flutter/material.dart';
import '../l10n.dart';
import '../models.dart';
import '../theme.dart';

/// Mobile adaptation of the official Harness QuestionComposer.
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
    final questions = widget.request.questions;
    final q = questions.isEmpty ? null : questions[_page];
    final ink2 = DshColors.ink2(context);
    final line = DshColors.line(context);
    final media = MediaQuery.of(context);
    final height = ((media.size.height - media.viewInsets.bottom) * 0.55).clamp(180.0, 520.0);
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      constraints: BoxConstraints(maxHeight: height),
      decoration: BoxDecoration(
        color: DshColors.surface(context),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: line),
        boxShadow: const [BoxShadow(color: Color(0x0A000000), blurRadius: 12, offset: Offset(0, 3))],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 8, 0),
            child: Row(children: [
              Expanded(child: Text(q?.header ?? L10n.t('需要你决定', 'Your input needed'),
                style: TextStyle(fontSize: 11, height: 1.45, color: ink2))),
              IconButton(
                tooltip: L10n.t('取消', 'Cancel'),
                onPressed: _submitting ? null : widget.onCancel,
                icon: const Icon(Icons.close, size: 18),
              ),
            ]),
          ),
          Flexible(
            child: SingleChildScrollView(
              key: ValueKey('question-page-$_page'),
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                if (q != null) ...[
                  Text(q.question, style: const TextStyle(fontSize: 16, height: 1.375, fontWeight: FontWeight.w500)),
                  if (q.detail?.isNotEmpty == true) ...[
                    const SizedBox(height: 8),
                    Text(q.detail!, style: TextStyle(fontSize: 13, height: 1.5, color: ink2)),
                  ],
                  const SizedBox(height: 12),
                  for (final o in q.options)
                    _OptionTile(label: o.label, description: o.description, multi: q.multiSelect,
                      selected: _selected[q.id]!.contains(o.label),
                      onTap: () { if (!_submitting) _toggle(q, o.label); }),
                  const SizedBox(height: 10),
                  TextField(
                    enabled: !_submitting,
                    controller: _ctrls[q.id],
                    onChanged: (v) => _onCustom(q, v),
                    minLines: 1,
                    maxLines: 3,
                    style: const TextStyle(fontSize: 14),
                    decoration: InputDecoration(
                      hintText: q.multiSelect ? L10n.t('补充说明（可选）…', 'Add details (optional)…')
                        : L10n.t('或输入其他答案…', 'Or type another answer…'),
                      isDense: true,
                    ),
                  ),
                ] else Text(L10n.t('问题内容为空，请取消后重试', 'No questions received. Cancel and retry.')),
                if (_hint != null) Padding(padding: const EdgeInsets.only(top: 8),
                  child: Text(_hint!, style: TextStyle(fontSize: 12, color: DshColors.danger(context)))),
                const SizedBox(height: 8),
              ]),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 16, 10),
            child: Row(children: [
              if (questions.length > 1) ...[
                IconButton(tooltip: L10n.t('上一题', 'Previous question'),
                  onPressed: _submitting || _page == 0 ? null : () => setState(() { _page--; _hint = null; }),
                  icon: const Icon(Icons.chevron_left, size: 20)),
                Text('${_page + 1} / ${questions.length}', style: TextStyle(fontSize: 12, color: ink2)),
              ],
              const Spacer(),
              TextButton(onPressed: _submitting ? null : widget.onCancel, child: Text(L10n.t('取消', 'Cancel'))),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _submitting || q == null ? null : _page < questions.length - 1
                  ? () => setState(() { _page++; _hint = null; }) : _submit,
                child: Text(_submitting ? L10n.t('提交中…', 'Submitting…') : _page < questions.length - 1
                  ? L10n.t('下一题', 'Next') : L10n.t('提交', 'Submit')),
              ),
            ]),
          ),
        ],
      ),
    );
  }
}

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
    final brand = DshColors.brand(context);
    final ink3 = DshColors.ink3(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              multi
                  ? (selected ? Icons.check_box : Icons.check_box_outline_blank)
                  : (selected ? Icons.radio_button_checked : Icons.radio_button_unchecked),
              size: 18,
              color: brand,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(fontSize: 13.5, fontWeight: selected ? FontWeight.w600 : FontWeight.w500),
                  ),
                  if (description != null && description!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 1),
                      child: Text(description!, style: TextStyle(fontSize: 11.5, color: ink3, height: 1.35)),
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

