// 手机端“用量与额度”详情页。
// 余额与配额按来源独立展示；配额窗口不相加，凭据永不下发到 App。
//
// 版式：DshPage + DshAppBar；来源卡片 DshCard（R20 + 发丝边 + layer2），
// 大数字 l20、标签 xs13，额度进度统一 DshProgressBar，明细用 DshTile。
import 'dart:async';

import 'package:flutter/material.dart';

import '../api.dart';
import '../dsh_kit.dart';
import '../l10n.dart';
import '../models.dart';
import '../store.dart';
import '../theme.dart';

class UsageScreen extends StatefulWidget {
  final AppStore store;
  final UsageSnapshot? initial;

  const UsageScreen({super.key, required this.store, this.initial});

  @override
  State<UsageScreen> createState() => _UsageScreenState();
}

class _UsageScreenState extends State<UsageScreen> {
  UsageSnapshot? _snapshot;
  String? _errorCode; // partial | outdated | failed
  bool _loading = false;
  Timer? _clock;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _snapshot = widget.initial;
    widget.store.addListener(_onStoreChanged);
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
    unawaited(_refresh());
  }

  @override
  void dispose() {
    _clock?.cancel();
    widget.store.removeListener(_onStoreChanged);
    super.dispose();
  }

  void _onStoreChanged() {
    if (mounted) setState(() {});
  }

  String? get _errorText => switch (_errorCode) {
        'partial' => L10n.t(
            '部分额度来源刷新失败，已隐藏不可用来源',
            'Some usage sources failed to refresh and were hidden',
          ),
        'outdated' => L10n.t(
            '电脑端插件版本过旧，请升级 dsh-mobile-remote 后重启桌面端',
            'The desktop plugin is outdated. Upgrade dsh-mobile-remote and restart the desktop app',
          ),
        'failed' => L10n.t('额度查询失败，请稍后重试', 'Usage query failed. Try again later'),
        _ => null,
      };

  Future<void> _refresh() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _errorCode = null;
    });
    try {
      final snapshot = await api.accountUsage(refresh: true);
      if (!mounted) return;
      setState(() {
        _snapshot = snapshot;
        _errorCode = snapshot.failedCount > 0 ? 'partial' : null;
      });
    } catch (e) {
      if (!mounted) return;
      final oldPlugin = e is ApiException && e.code == 'not-found';
      setState(() {
        // 保留已有快照，避免短暂网络失败导致页面闪成空状态。
        _snapshot ??= const UsageSnapshot(failedCount: 1);
        _errorCode = oldPlugin ? 'outdated' : 'failed';
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _snapshot;
    final c = DshPalette.of(context);
    return DshPage(
      title: L10n.t('用量与额度', 'Usage & Allowance'),
      actions: [
        if (_loading)
          const Padding(
            padding: EdgeInsets.only(right: DshSpace.md),
            child: Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          )
        else
          DshIconButton(
            icon: Icons.refresh,
            tooltip: L10n.t('刷新全部', 'Refresh all'),
            onTap: _refresh,
          ),
        const SizedBox(width: DshSpace.xs),
      ],
      child: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(
            DshSpace.pageH,
            DshSpace.md,
            DshSpace.pageH,
            DshSpace.xxl,
          ),
          children: [
            Text(
              L10n.t(
                '各提供方独立显示余额或配额；不同窗口与来源不会相加。',
                'Balances and quota windows are shown independently; windows and sources are never added together.',
              ),
              style: DshType.xs13.copyWith(color: c.ink3),
            ),
            if (_errorText != null && snapshot != null && snapshot.sources.isNotEmpty) ...[
              const SizedBox(height: DshSpace.md),
              DshBanner(
                message: _errorText!,
                icon: Icons.info_outline,
                tone: DshBannerTone.warn,
              ),
            ],
            const SizedBox(height: DshSpace.md),
            if (snapshot == null && _loading)
              Padding(
                padding: const EdgeInsets.only(top: DshSpace.xxxl * 2),
                child: DshLoading(label: L10n.t('查询中…', 'Loading…')),
              )
            else if (snapshot == null || snapshot.sources.isEmpty)
              _emptyState(snapshot)
            else ...[
              for (final source in snapshot.sources) _sourceCard(source),
              if (snapshot.fetchedAt != null) ...[
                const SizedBox(height: DshSpace.xs),
                Center(
                  child: Text(
                    '${L10n.t('最近更新：', 'Last updated: ')}${_formatDate(snapshot.fetchedAt!)}',
                    style: DshType.xs13.copyWith(color: c.ink3),
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  /// 空/失败：查询失败给 DshError（可重试），确实没有来源给 DshEmpty。
  Widget _emptyState(UsageSnapshot? snapshot) {
    final hasFailure = (snapshot?.failedCount ?? 0) > 0;
    if (hasFailure && _errorText != null) {
      return DshError(
        message: _errorText!,
        onRetry: _loading ? null : _refresh,
        retryLabel: L10n.t('重新查询', 'Try again'),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: DshSpace.xxxl),
      child: DshEmpty(
        icon: Icons.account_balance_wallet_outlined,
        title: hasFailure
            ? L10n.t('当前没有可用额度来源', 'No usage source is currently available')
            : L10n.t('暂无可用额度来源', 'No usage source is configured'),
        message: L10n.t(
          '请在电脑端「设置 → 模型」配置提供方；Codex 需要安装并登录 dsh-codex-connect。',
          'Configure providers in desktop Settings → Models. Codex requires dsh-codex-connect to be installed and signed in.',
        ),
        action: DshButton(
          label: L10n.t('重新查询', 'Try again'),
          icon: Icons.refresh,
          variant: DshButtonVariant.outline,
          onPressed: _loading ? null : _refresh,
        ),
      ),
    );
  }

  Widget _sourceCard(UsageSource source) {
    final c = DshPalette.of(context);
    final icon = switch (source.id) {
      'deepseek' => Icons.account_balance_wallet_outlined,
      'codex' => Icons.auto_awesome_outlined,
      'opencode-go' => Icons.code_outlined,
      _ => Icons.data_usage_outlined,
    };
    final account = source.account == null
        ? ''
        : [
            source.account!.displayName,
            source.account!.maskedEmail,
          ].whereType<String>().where((v) => v.trim().isNotEmpty).join(' · ');
    return DshCard(
      margin: const EdgeInsets.only(bottom: DshSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: c.ink2),
              const SizedBox(width: DshSpace.sm),
              Expanded(
                child: Text(
                  source.title,
                  style: DshType.sStrong14.copyWith(color: c.ink),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (!source.available)
                DshTag(
                  label: L10n.t('不可用', 'Unavailable'),
                  color: c.warn,
                  background: c.warnSoft,
                  dense: true,
                ),
            ],
          ),
          if (account.isNotEmpty) ...[
            const SizedBox(height: DshSpace.xs),
            Text(account, style: DshType.xs13.copyWith(color: c.ink3)),
          ],
          const SizedBox(height: DshSpace.md),
          if (source.kind == 'balance')
            _balanceBody(source)
          else
            _quotaBody(source),
        ],
      ),
    );
  }

  Widget _balanceBody(UsageSource source) {
    final c = DshPalette.of(context);
    final currency = source.currency == 'CNY'
        ? '¥'
        : (source.currency == null || source.currency!.isEmpty
              ? ''
              : '${source.currency} ');
    final amount = source.amountNumber;
    final color = source.available ? c.ink : c.ink3;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(currency, style: DshType.m16.copyWith(color: c.ink2)),
        Flexible(
          child: Text(
            amount == null ? (source.amount ?? '—') : amount.toStringAsFixed(2),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: DshType.l20.copyWith(color: color),
          ),
        ),
        const SizedBox(width: DshSpace.sm),
        Padding(
          padding: const EdgeInsets.only(bottom: DshSpace.xs),
          child: Text(
            source.available
                ? L10n.t('可用余额', 'available balance')
                : L10n.t('余额不可用', 'balance unavailable'),
            style: DshType.xs13.copyWith(color: c.ink3),
          ),
        ),
      ],
    );
  }

  Widget _quotaBody(UsageSource source) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final window in source.windows) _windowRow(window),
        if (source.credits != null) ...[
          if (source.windows.isNotEmpty) const SizedBox(height: DshSpace.sm),
          _detailTile(
            L10n.t('Credits', 'Credits'),
            _creditsText(source.credits!),
          ),
        ],
        if (source.individualLimit != null) ...[
          if (source.windows.isNotEmpty || source.credits != null)
            const SizedBox(height: DshSpace.xs),
          _detailTile(
            L10n.t('个人消费上限', 'Individual limit'),
            '${source.individualLimit!.remaining} / ${source.individualLimit!.limit}',
            sub: L10n.t('已用 ', 'Used ') + source.individualLimit!.used,
          ),
        ],
      ],
    );
  }

  Widget _windowRow(UsageWindow window) {
    final c = DshPalette.of(context);
    final remaining = window.remainingPercent.clamp(0, 100).toDouble();
    final color = _quotaColor(remaining, limited: window.limited);
    return Padding(
      padding: const EdgeInsets.only(bottom: DshSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        _windowName(window.window),
                        style: DshType.s14.copyWith(color: c.ink),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (window.limited) ...[
                      const SizedBox(width: DshSpace.xs),
                      DshTag(
                        label: L10n.t('已限流', 'Rate limited'),
                        color: c.danger,
                        background: c.dangerSoft,
                        dense: true,
                      ),
                    ],
                  ],
                ),
              ),
              Text(
                '${_percentText(remaining)}${L10n.t(' 剩余', ' left')}',
                style: DshType.xs13.copyWith(color: color),
              ),
            ],
          ),
          const SizedBox(height: DshSpace.sm),
          // 进度条占满整行（DshProgressBar 内部按比例填充，需要紧宽度约束）
          SizedBox(
            width: double.infinity,
            child: DshProgressBar(value: remaining / 100, color: color),
          ),
          if (window.resetAt != null) ...[
            const SizedBox(height: DshSpace.xs),
            Text(
              _resetText(window.resetAt!),
              style: DshType.xs13.copyWith(color: c.ink3),
            ),
          ],
        ],
      ),
    );
  }

  String _creditsText(UsageCredits credits) {
    if (credits.unlimited) return L10n.t('无限', 'Unlimited');
    final value = credits.balance ?? '—';
    if (value == '—' || value.startsWith('\$')) return value;
    return '\$$value';
  }

  /// 明细行：标签 + 取值（DshTile dense，贴着卡片内衬不额外缩进）。
  Widget _detailTile(String label, String value, {String? sub}) {
    final c = DshPalette.of(context);
    return DshTile(
      dense: true,
      title: label,
      subtitle: sub,
      padding: const EdgeInsets.symmetric(vertical: DshSpace.xs),
      trailing: Text(value, style: DshType.sStrong14.copyWith(color: c.ink)),
    );
  }

  /// 额度颜色：正常 brand、接近上限 warn、超限/限流 danger。
  Color _quotaColor(double percent, {bool limited = false}) {
    final c = DshPalette.of(context);
    if (limited || percent <= 0) return c.danger;
    if (percent < 20) return c.warn;
    return c.brand;
  }

  String _windowName(String id) => switch (id) {
    '5h' => L10n.t('5 小时滚动窗口', '5-hour rolling window'),
    'weekly' => L10n.t('每周窗口', 'Weekly window'),
    'monthly' => L10n.t('每月窗口', 'Monthly window'),
    'credits' => L10n.t('Credits', 'Credits'),
    _ => id,
  };

  String _percentText(double value) => value == value.roundToDouble()
      ? '${value.round()}%'
      : '${value.toStringAsFixed(1)}%';

  String _resetText(DateTime resetAt) {
    final local = resetAt.toLocal();
    final delta = resetAt.difference(_now);
    if (delta.isNegative) {
      return L10n.t(
        '已到重置时间 · ${_formatDate(resetAt)}',
        'Reset due · ${_formatDate(resetAt)}',
      );
    }
    final totalSeconds = delta.inSeconds;
    final totalMinutes = delta.inMinutes;
    final relative = totalSeconds < 60
        ? L10n.t('$totalSeconds 秒后', 'in ${totalSeconds}s')
        : totalMinutes < 60
        ? L10n.t('$totalMinutes 分钟后', 'in ${totalMinutes}m')
        : totalMinutes < 24 * 60
        ? L10n.t('${delta.inHours} 小时后', 'in ${delta.inHours}h')
        : L10n.t('${delta.inDays} 天后', 'in ${delta.inDays}d');
    return '${L10n.t('重置 ', 'Resets ')}${_formatDate(local)} · $relative';
  }

  String _formatDate(DateTime date) {
    final local = date.toLocal();
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return '${local.month}/${local.day} $hh:$mm';
  }
}
