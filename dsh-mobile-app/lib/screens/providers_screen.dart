// 模型提供商管理页（v2.6）：与 PC 端 设置→模型 同一配置通道。
// 列表：搜索 + 已连接（官方设置卡片）/ 未配置（默认折叠紧凑行）；
// 点击可编辑 baseURL / API Key / 模型目录 / 探测模型。
//
// 版式：搜索框（主题 R12 输入框）→ DshSectionHeader 分组 → DshCardGroup/ DshTile；
// 编辑弹层用 showDshSheet + DshSheet（R28 面 + 按钮一律 DshButton）。
import 'package:flutter/material.dart';
import '../api.dart';
import '../dsh_kit.dart';
import '../l10n.dart';
import '../store.dart';
import '../theme.dart';
import '../toast.dart';

/// 提供商首字母方块圆角：40×40 控件介于 sm(8) 与 md(12) 之间，取 10。
/// （令牌阶梯无 10 档，这里用 sm + 2 派生，避免在页面里写死数字圆角。）
const double _avatarRadius = DshRadius.tile;

/// Phase 2：统一打开「模型提供商」管理页（设置页与模型弹层共用入口）。
void openProviders(BuildContext context, AppStore store) {
  Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => ProvidersScreen(store: store)),
  );
}

class ProvidersScreen extends StatefulWidget {
  final AppStore store;
  const ProvidersScreen({super.key, required this.store});

  @override
  State<ProvidersScreen> createState() => _ProvidersScreenState();
}

class _ProvidersScreenState extends State<ProvidersScreen> {
  List<Map<String, dynamic>>? _providers;
  String? _error;
  String _query = '';
  bool _dormantExpanded = false;
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _providers = null;
      _error = null;
    });
    try {
      final list = await api.llmProviders();
      if (!mounted) return;
      setState(() => _providers = list);
    } catch (e) {
      if (!mounted) return;
      final msg = '$e';
      // 旧插件没有 /api/llm-providers 端点（404 not-found）：给出可操作的提示
      if (msg.contains('not-found') || msg.contains('404')) {
        setState(() => _error = L10n.t('电脑端插件版本过旧：缺少「模型提供商」接口。\n请升级 dsh-mobile-remote 插件后重启桌面端（已配置的模型不受影响）。', 'The desktop plugin is outdated: the "Model Providers" API is missing.\nPlease upgrade the dsh-mobile-remote plugin and restart the desktop app (configured models are unaffected).'));
      } else {
        setState(() => _error = msg);
      }
    }
  }

  bool _match(Map<String, dynamic> p, String q) {
    if (q.isEmpty) return true;
    final name = (p['name'] as String? ?? '').toLowerCase();
    final id = (p['id'] as String? ?? '').toLowerCase();
    return name.contains(q) || id.contains(q);
  }

  @override
  Widget build(BuildContext context) {
    return DshPage(
      title: L10n.t('模型提供商', 'Model Providers'),
      child: _error != null
          ? DshError(
              message: '$_error',
              onRetry: _load,
              retryLabel: L10n.t('重试', 'Retry'),
            )
          : _providers == null
              ? DshLoading(label: L10n.t('加载中…', 'Loading…'))
              : RefreshIndicator(onRefresh: _load, child: _buildList()),
    );
  }

  Widget _buildList() {
    final c = DshPalette.of(context);
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(top: DshSpace.md, bottom: DshSpace.xxl),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: DshSpace.pageH),
          child: Text(
            L10n.t('与 PC 端「设置 → 模型」同一配置通道；手机修改即时生效，两端一致。', 'Same configuration channel as "Settings → Model" on the desktop; changes on your phone apply instantly on both ends.'),
            style: DshType.xs13.copyWith(color: c.ink3),
          ),
        ),
        const SizedBox(height: DshSpace.md),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: DshSpace.pageH),
          child: SizedBox(
            height: DshSpace.controlMd,
            child: TextField(
              controller: _searchCtrl,
              textAlignVertical: TextAlignVertical.center,
              style: DshType.s14.copyWith(color: c.ink),
              onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
              decoration: InputDecoration(
                isDense: true,
                contentPadding: EdgeInsets.zero,
                hintText: L10n.t('搜索提供商（名称 / ID）', 'Search providers (name / ID)'),
                hintStyle: DshType.s14.copyWith(color: c.caption),
                prefixIcon: Icon(Icons.search, size: 18, color: c.ink3),
                prefixIconConstraints: const BoxConstraints(
                  minWidth: DshSpace.controlMd,
                  minHeight: DshSpace.controlMd,
                  maxHeight: DshSpace.controlMd,
                ),
                suffixIcon: _query.isEmpty
                    ? null
                    : GestureDetector(
                        onTap: () {
                          _searchCtrl.clear();
                          setState(() => _query = '');
                        },
                        child: Icon(Icons.close, size: 16, color: c.ink3),
                      ),
                suffixIconConstraints: const BoxConstraints(
                  minWidth: DshSpace.controlMd,
                  minHeight: DshSpace.controlMd,
                  maxHeight: DshSpace.controlMd,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: DshSpace.xs),
        _buildSections(),
      ],
    );
  }

  Widget _buildSections() {
    final all = _providers ?? [];
    final live = all.where((p) => p['dormant'] != true && _match(p, _query)).toList();
    final dormant = all.where((p) => p['dormant'] == true && _match(p, _query)).toList();
    final c = DshPalette.of(context);
    if (live.isEmpty && dormant.isEmpty) {
      return DshEmpty(
        icon: Icons.search_off,
        title: L10n.t('没有匹配的提供商', 'No matching providers'),
        message: L10n.t(
          '换个关键词，或确认电脑端已配置模型提供商。',
          'Try another keyword, or make sure a provider is configured on the desktop.',
        ),
        compact: true,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (live.isNotEmpty) ...[
          DshSectionHeader(
            '${L10n.t('已连接', 'Connected')} (${live.length})',
          ),
          DshCardGroup(
            children: [
              for (final p in live)
                _ProviderRow(
                  provider: p,
                  active: true,
                  onEdit: () => _openEditor(p),
                ),
            ],
          ),
        ],
        if (dormant.isNotEmpty) ...[
          // 未配置区：默认折叠（点分组标题行展开/收起）
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _dormantExpanded = !_dormantExpanded),
            child: DshSectionHeader(
              '${L10n.t('未配置', 'Not configured')} (${dormant.length})',
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _dormantExpanded
                        ? L10n.t('收起', 'Collapse')
                        : L10n.t('展开', 'Expand'),
                    style: DshType.xs13.copyWith(color: c.ink3),
                  ),
                  const SizedBox(width: DshSpace.xs),
                  Icon(
                    _dormantExpanded ? Icons.expand_less : Icons.expand_more,
                    size: 16,
                    color: c.ink3,
                  ),
                ],
              ),
            ),
          ),
          if (_dormantExpanded)
            DshCardGroup(
              children: [
                for (final p in dormant)
                  _ProviderRow(
                    provider: p,
                    active: false,
                    onEdit: () => _openEditor(p),
                  ),
              ],
            ),
        ],
      ],
    );
  }

  void _openEditor(Map<String, dynamic> p) {
    final ns = p['settingsNs'] as String?;
    if (ns == null || ns.isEmpty) {
      showToast(context, L10n.t('该提供商由内核内置，配置入口在 PC 端', 'This provider is built into the kernel; configure it on the desktop app.'));
      return;
    }
    final msgr = ScaffoldMessenger.of(context);
    showDshSheet<void>(
      context: context,
      // 键盘避让由 DshSheet 内置（MediaQuery.viewInsets），这里不再重复顶起。
      builder: (ctx) => _ProviderEditor(
        provider: p,
        onSaved: () {
          Navigator.of(ctx).pop();
          showToastAt(msgr, L10n.t('已保存', 'Saved'));
          _load();
        },
      ),
    );
  }
}

/// 提供商行（官方设置行版式）：40×40 首字母方块 + 名称/摘要 + 状态标签。
class _ProviderRow extends StatelessWidget {
  const _ProviderRow({
    required this.provider,
    required this.active,
    required this.onEdit,
  });

  final Map<String, dynamic> provider;
  final bool active;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final c = DshPalette.of(context);
    final baseURL = provider['baseURL'] as String?;
    final keyConfigured = provider['keyConfigured'] == true;
    final catalogModels = provider['catalogModels'] as List?;
    final id = provider['id'] as String? ?? '';
    final name = provider['name'] as String? ?? id;
    final subs = <String>[
      id,
      if (provider['id'] == 'deepseek-official')
        L10n.t('内置模型已可用，无需探测', 'Built-in models are ready; no probing needed'),
      if (baseURL != null && baseURL.isNotEmpty) baseURL,
      keyConfigured ? L10n.t('密钥已配置', 'API key set') : L10n.t('未设置密钥', 'No API key set'),
      if (catalogModels != null) '${L10n.t('目录 ', 'Catalog: ')}${catalogModels.length}${L10n.t(' 个模型', ' models')}',
    ];
    return DshTile(
      leading: _ProviderAvatar(name: name, active: active),
      title: name,
      subtitle: subs.join(' · '),
      onTap: onEdit,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (active)
            DshTag(
              label: L10n.t('已配置', 'Configured'),
              color: c.ok,
              background: c.okSoft,
              dense: true,
            ),
          const SizedBox(width: DshSpace.sm),
          Icon(Icons.edit_outlined, size: 18, color: c.ink2),
        ],
      ),
    );
  }
}

/// 40×40 首字母方块：module 底 + 0.5px line4 发丝边（已配置用 okSoft 淡染）。
class _ProviderAvatar extends StatelessWidget {
  const _ProviderAvatar({required this.name, required this.active});

  final String name;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final c = DshPalette.of(context);
    final letter = name.isEmpty ? '?' : name.substring(0, 1).toUpperCase();
    return Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: active ? c.okSoft : c.module,
        borderRadius: BorderRadius.circular(_avatarRadius),
        border: Border.fromBorderSide(DshStroke.side(c.line4)),
      ),
      child: Text(
        letter,
        style: DshType.sStrong14.copyWith(color: active ? c.ok : c.ink2),
      ),
    );
  }
}

class _ProviderEditor extends StatefulWidget {
  final Map<String, dynamic> provider;
  final VoidCallback onSaved;
  const _ProviderEditor({required this.provider, required this.onSaved});

  @override
  State<_ProviderEditor> createState() => _ProviderEditorState();
}

class _ProviderEditorState extends State<_ProviderEditor> {
  late final TextEditingController _baseCtrl;
  final _keyCtrl = TextEditingController();
  final _modelIdCtrl = TextEditingController();
  bool _busy = false;
  String? _status;
  DshBannerTone _statusTone = DshBannerTone.info;
  List<Map<String, dynamic>>? _discovered;
  final List<Map<String, dynamic>> _models = [];

  bool get _isPiAiStyle => (widget.provider['settingsPath'] as List? ?? []).isNotEmpty;

  @override
  void initState() {
    super.initState();
    _baseCtrl = TextEditingController(text: widget.provider['baseURL'] as String? ?? '');
    _models.addAll((widget.provider['catalogModels'] as List? ?? []).map((m) => Map<String, dynamic>.from(m as Map)));
  }

  @override
  void dispose() {
    _baseCtrl.dispose();
    _keyCtrl.dispose();
    _modelIdCtrl.dispose();
    super.dispose();
  }

  /// v3.0.0 review：baseURL 格式校验（http/https + 主机名），非法值不再提交到服务端
  String? _validBase(String base) {
    if (base.isEmpty) return L10n.t('请先填写 baseURL', 'Please enter a baseURL first');
    final u = Uri.tryParse(base);
    if (u == null || (u.scheme != 'http' && u.scheme != 'https') || u.host.isEmpty) {
      return L10n.t('baseURL 非法：需以 http:// 或 https:// 开头并含主机名（如 https://api.example.com/v1）',
          'Invalid baseURL: must start with http:// or https:// and include a host (e.g. https://api.example.com/v1)');
    }
    return null;
  }

  /// v3.0.0 review：模型 ID 合法性（非空、无空白与路径分隔符、长度上限）
  String? _validModelId(String id) {
    final t = id.trim();
    if (t.isEmpty) return L10n.t('模型 ID 不能为空', 'Model ID cannot be empty');
    if (t.length > 200 || RegExp(r'[\s/\\]').hasMatch(t)) {
      return L10n.t('模型 ID 非法：不能含空白或 / \\ 且不超过 200 字符',
          'Invalid model ID: no whitespace or / \\ and at most 200 characters');
    }
    return null;
  }

  Future<void> _probe() async {
    final ns = widget.provider['settingsNs'] as String? ?? '';
    final base = _baseCtrl.text.trim();
    final keyEmpty = _keyCtrl.text.trim().isEmpty;
    final hasStoredKey = widget.provider['keyConfigured'] == true;
    final err = _validBase(base);
    if (err != null) {
      setState(() {
        _status = err;
        _statusTone = DshBannerTone.danger;
      });
      return;
    }
    setState(() {
      _busy = true;
      _status = L10n.t('探测中…', 'Probing…');
      _statusTone = DshBannerTone.info;
      _discovered = null;
    });
    try {
      final models = await api.probeLlmProvider(
        settingsNs: ns,
        baseURL: base,
        apiKey: _keyCtrl.text.trim().isEmpty ? null : _keyCtrl.text.trim(),
      );
      if (!mounted) return;
      setState(() {
        _discovered = models;
        _status = '${L10n.t('探测成功：', 'Probe succeeded: ')}${models.length}${L10n.t(' 个模型', ' models')}';
        _statusTone = DshBannerTone.success;
      });
    } catch (e) {
      if (!mounted) return;
      var msg = '$e';
      // v3.1.0：已存密钥不会随探测请求发送；401 时给出可操作指引（避免"411/HTTP 401"裸文案困惑）
      if (keyEmpty && hasStoredKey && (msg.contains('401') || msg.contains('403'))) {
        msg = '${L10n.t('该条目已保存密钥，但探测请求不会携带已存密钥——请临时填入有效 API Key 后重试；'
            'DeepSeek 官方模型内置可用，无需探测。', 'This provider has a saved API key, but probe requests do not carry it — '
            'temporarily paste a valid key and retry; built-in DeepSeek models work without probing.')}\n$msg';
      }
      setState(() {
        _status = '${L10n.t('探测失败：', 'Probe failed: ')}$msg';
        _statusTone = DshBannerTone.danger;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _adoptAll() {
    final existing = _models.map((m) => m['id']).toSet();
    final added = <Map<String, dynamic>>[];
    for (final m in _discovered ?? []) {
      if (!existing.contains(m['id'])) {
        added.add(Map<String, dynamic>.from(m));
        existing.add(m['id']);
      }
    }
    setState(() {
      _models.addAll(added);
      _status = added.isEmpty ? L10n.t('没有新模型（已全部在列表）', 'No new models (all are already in the list)') : '${L10n.t('已采用 ', 'Adopted ')}${added.length}${L10n.t(' 个模型', ' models')}';
      _statusTone = added.isEmpty ? DshBannerTone.info : DshBannerTone.success;
    });
  }

  void _addModel() {
    final id = _modelIdCtrl.text.trim();
    final err = _validModelId(id);
    if (err != null) {
      setState(() {
        _status = err;
        _statusTone = DshBannerTone.danger;
      });
      return;
    }
    if (_models.any((m) => m['id'] == id)) {
      setState(() {
        _status = '${L10n.t('模型已存在：', 'Model already exists: ')}$id';
        _statusTone = DshBannerTone.warn;
      });
      return;
    }
    setState(() {
      _models.add({'id': id, 'name': id});
      _modelIdCtrl.clear();
      _status = '${L10n.t('已添加：', 'Added: ')}$id';
      _statusTone = DshBannerTone.success;
    });
  }

  void _removeModel(String id) {
    setState(() => _models.removeWhere((m) => m['id'] == id));
  }

  Future<void> _save() async {
    final ns = widget.provider['settingsNs'] as String? ?? '';
    final base = _baseCtrl.text.trim();
    final err = _validBase(base);
    if (err != null) {
      setState(() {
        _status = err;
        _statusTone = DshBannerTone.danger;
      });
      return;
    }
    if (_isPiAiStyle && _models.isEmpty) {
      setState(() {
        _status = L10n.t('请至少添加一个模型（探测采用或手动输入模型 ID）', 'Please add at least one model (adopt from probe or enter a model ID manually)');
        _statusTone = DshBannerTone.warn;
      });
      return;
    }
    setState(() {
      _busy = true;
      _status = L10n.t('保存中…', 'Saving…');
      _statusTone = DshBannerTone.info;
    });
    try {
      await api.saveLlmProvider(
        provider: widget.provider['id'] as String? ?? '',
        settingsNs: ns,
        baseURL: base,
        apiKey: _keyCtrl.text.trim().isEmpty ? null : _keyCtrl.text.trim(),
        models: _models.isEmpty ? null : _models,
        api: 'openai-completions',
        displayName: widget.provider['name'] as String?,
      );
      if (!mounted) return;
      widget.onSaved();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _status = '${L10n.t('保存失败：', 'Save failed: ')}$e';
        _statusTone = DshBannerTone.danger;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _removeKey() async {
    final ns = widget.provider['settingsNs'] as String? ?? '';
    setState(() {
      _busy = true;
      _status = L10n.t('清除中…', 'Clearing…');
      _statusTone = DshBannerTone.info;
    });
    try {
      await api.saveLlmProvider(
        provider: widget.provider['id'] as String? ?? '',
        settingsNs: ns,
        removeKey: true,
      );
      if (!mounted) return;
      widget.onSaved();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _status = '${L10n.t('清除失败：', 'Clear failed: ')}$e';
        _statusTone = DshBannerTone.danger;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 输入框统一外观：主题已给 R12 + line4 发丝边，这里只补字号与内衬。
  InputDecoration _fieldDeco(String label, DshPalette c) => InputDecoration(
        labelText: label,
        labelStyle: DshType.xs13.copyWith(color: c.ink3),
        floatingLabelStyle: DshType.xs13.copyWith(color: c.ink3),
        hintStyle: DshType.s14.copyWith(color: c.caption),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: DshSpace.md,
          vertical: DshSpace.md,
        ),
      );

  @override
  Widget build(BuildContext context) {
    final c = DshPalette.of(context);
    final p = widget.provider;
    final name = p['name'] as String? ?? p['id'] as String? ?? '';
    final id = p['id'] as String? ?? '';
    final existingIds = _models.map((m) => m['id']).toSet();

    return DshSheet(
      title: name,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(id, style: DshType.xs13.copyWith(color: c.ink3)),
          const SizedBox(height: DshSpace.md),
          TextField(
            controller: _baseCtrl,
            keyboardType: TextInputType.url,
            style: DshType.s14.copyWith(color: c.ink),
            decoration: _fieldDeco('baseURL', c).copyWith(
              hintText: 'https://api.deepseek.com',
            ),
          ),
          const SizedBox(height: DshSpace.md),
          TextField(
            controller: _keyCtrl,
            obscureText: true,
            style: DshType.s14.copyWith(color: c.ink),
            decoration: _fieldDeco(
              p['keyConfigured'] == true
                  ? L10n.t('API Key（已配置，留空不修改）', 'API Key (set — leave empty to keep)')
                  : 'API Key',
              c,
            ),
          ),
          const SizedBox(height: DshSpace.md),
          Row(
            children: [
              Expanded(
                child: DshButton(
                  label: L10n.t('探测模型', 'Probe Models'),
                  icon: Icons.radar,
                  variant: DshButtonVariant.outline,
                  onPressed: _busy ? null : _probe,
                ),
              ),
              const SizedBox(width: DshSpace.sm),
              Expanded(
                child: DshButton(
                  label: L10n.t('保存', 'Save'),
                  icon: Icons.check,
                  onPressed: _busy ? null : _save,
                ),
              ),
            ],
          ),
          if (p['keyConfigured'] == true) ...[
            const SizedBox(height: DshSpace.sm),
            DshButton(
              label: L10n.t('清除已存密钥', 'Clear saved key'),
              icon: Icons.key_off_outlined,
              variant: DshButtonVariant.ghost,
              size: DshButtonSize.sm,
              onPressed: _busy ? null : _removeKey,
            ),
          ],
          if (_busy) ...[
            const SizedBox(height: DshSpace.md),
            DshLoading(label: L10n.t('正在与提供商通信…', 'Talking to the provider…')),
          ] else if (_status != null) ...[
            const SizedBox(height: DshSpace.md),
            DshBanner(
              message: _status!,
              tone: _statusTone,
              icon: switch (_statusTone) {
                DshBannerTone.success => Icons.check_circle_outline,
                DshBannerTone.danger => Icons.error_outline,
                DshBannerTone.warn => Icons.warning_amber_outlined,
                DshBannerTone.info => Icons.info_outline,
              },
            ),
          ],
          if (_discovered != null && _discovered!.isNotEmpty) ...[
            const SizedBox(height: DshSpace.lg),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${L10n.t('探测到的模型', 'Discovered models')} (${_discovered!.length})',
                    style: DshType.xsStrong13.copyWith(color: c.ink3),
                  ),
                ),
                DshButton(
                  label: L10n.t('全部采用', 'Adopt All'),
                  icon: Icons.playlist_add_check,
                  size: DshButtonSize.sm,
                  variant: DshButtonVariant.ghost,
                  onPressed: _busy ? null : _adoptAll,
                ),
              ],
            ),
            const SizedBox(height: DshSpace.sm),
            DshCardGroup(
              margin: EdgeInsets.zero,
              children: [
                for (final m in _discovered!)
                  DshTile(
                    dense: true,
                    leading: const Icon(Icons.smart_toy_outlined),
                    title: (m['name'] as String? ?? m['id'] as String? ?? '').toString(),
                    subtitle: m['id'] as String? ?? '',
                    trailing: existingIds.contains(m['id'])
                        ? Icon(Icons.check, size: 16, color: c.brand)
                        : null,
                  ),
              ],
            ),
          ],
          const SizedBox(height: DshSpace.lg),
          Text(
            '${L10n.t('模型目录', 'Model catalog')} (${_models.length})',
            style: DshType.xsStrong13.copyWith(color: c.ink3),
          ),
          const SizedBox(height: DshSpace.sm),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: DshSpace.controlMd,
                  child: TextField(
                    controller: _modelIdCtrl,
                    textAlignVertical: TextAlignVertical.center,
                    style: DshType.s14.copyWith(color: c.ink),
                    decoration: InputDecoration(
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                      hintText: L10n.t('手动输入模型 ID', 'Enter a model ID manually'),
                      hintStyle: DshType.s14.copyWith(color: c.caption),
                      prefixIcon: Icon(Icons.tag, size: 16, color: c.ink3),
                      prefixIconConstraints: const BoxConstraints(
                        minWidth: DshSpace.controlMd,
                        minHeight: DshSpace.controlMd,
                        maxHeight: DshSpace.controlMd,
                      ),
                    ),
                    onSubmitted: (_) => _addModel(),
                  ),
                ),
              ),
              const SizedBox(width: DshSpace.sm),
              DshButton(
                label: L10n.t('添加', 'Add'),
                size: DshButtonSize.sm,
                variant: DshButtonVariant.outline,
                onPressed: _addModel,
              ),
            ],
          ),
          const SizedBox(height: DshSpace.sm),
          if (_models.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: DshSpace.xs),
              child: Text(
                L10n.t('未添加模型', 'No models added'),
                style: DshType.xs13.copyWith(color: c.ink3),
              ),
            )
          else
            DshCardGroup(
              margin: EdgeInsets.zero,
              children: [
                for (final m in _models)
                  DshTile(
                    dense: true,
                    leading: const Icon(Icons.model_training_outlined),
                    title: (m['name'] as String? ?? m['id'] as String? ?? '').toString(),
                    subtitle: m['id'] as String? ?? '',
                    trailing: DshIconButton(
                      icon: Icons.close,
                      iconSize: 16,
                      onTap: () => _removeModel(m['id'] as String? ?? ''),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
