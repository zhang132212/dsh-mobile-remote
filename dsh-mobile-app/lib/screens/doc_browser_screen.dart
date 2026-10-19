// 工作区文档浏览器（v3.2.0）——在手机上浏览电脑侧的文件，直接打开可读文档。
//
// 只读设计：这里是「找文档 → 打开」的入口，不做上传/删除/重命名，避免误触改坏
// 电脑上的工作目录。可读格式由 docs/model.dart 的 kReadableExtensions 单点定义，
// 与 Android intent-filter 的能力保持一致。
//
// v3.3.0（官方风格）：标题栏 DshAppBar + DshIconButton，路径条用 module 底 + 发丝分隔，
// 列表行一律 DshTile（左leading 是 40×40 的文件类型图标方块），空状态用 DshEmpty。
import 'package:flutter/material.dart';

import '../api.dart';
import '../docs/model.dart';
import '../dsh_kit.dart';
import '../l10n.dart';
import '../theme.dart';
import 'doc_viewer_screen.dart';

/// 文件类型图标方块边长。
const double _iconBoxSize = 40;

/// 文件类型图标方块圆角。
///
/// 版式要求 R10，但 DshRadius 阶梯里没有 10 这一档（4/8/12/16/20/28），
/// 按「紧凑控件」角色取最接近的 R8；缺档已在交付说明里列为建议补充的令牌。
const double _iconBoxRadius = DshRadius.sm;

class DocBrowserScreen extends StatefulWidget {
  const DocBrowserScreen({super.key});

  @override
  State<DocBrowserScreen> createState() => _DocBrowserScreenState();
}

class _DocBrowserScreenState extends State<DocBrowserScreen> {
  /// 当前路径（'' = 根/盘符列表）
  String _path = '';
  final _stack = <String>[];
  String? _sep = '\\';
  List<String> _dirs = const [];
  List<String> _files = const [];
  List<Map<String, dynamic>> _workspaces = const [];
  bool _loading = true;
  String? _error;
  bool _showAll = false;

  @override
  void initState() {
    super.initState();
    _load('');
  }

  Future<void> _load(String path) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final listing = await api.directories(path);
      List<Map<String, dynamic>> ws = const [];
      if (path.isEmpty) {
        try {
          ws = await api.workspaces();
        } catch (_) {/* 工作区列表拿不到不影响盘符浏览 */}
      }
      if (!mounted) return;
      setState(() {
        _path = path;
        _sep = listing.sep ?? '\\';
        _dirs = listing.dirs;
        _files = listing.files;
        _workspaces = ws;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  void _enter(String dirName) {
    final sep = _sep ?? '\\';
    final base = _path;
    final next = base.isEmpty
        ? dirName
        : (base.endsWith(sep) || base.endsWith('/') ? '$base$dirName' : '$base$sep$dirName');
    _stack.add(_path);
    _load(next);
  }

  void _up() {
    if (_stack.isEmpty) {
      _load('');
      return;
    }
    final prev = _stack.removeLast();
    _load(prev);
  }

  Future<void> _open(String fileName) async {
    final sep = _sep ?? '\\';
    final full = _path.endsWith(sep) || _path.endsWith('/') ? '$_path$fileName' : '$_path$sep$fileName';
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DocViewerScreen(name: fileName, remotePath: full, api: api),
      ),
    );
  }

  List<String> get _shownFiles =>
      _showAll ? _files : _files.where(isReadableFormat).toList();

  /// 文件类型图标方块：40×40 + module 底 + 发丝边（官方列表行的图形锚点）。
  Widget _iconBox(DshPalette c, IconData icon, Color color) => Container(
        width: _iconBoxSize,
        height: _iconBoxSize,
        decoration: BoxDecoration(
          color: c.module,
          borderRadius: BorderRadius.circular(_iconBoxRadius),
          border: Border.fromBorderSide(DshStroke.side(c.line4)),
        ),
        child: Icon(icon, size: 20, color: color),
      );

  /// 列表行统一左右内衬 4px：内容与分组标题（16）对齐，选中/hover 底不至于贴边。
  Widget _row(Widget child) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: DshSpace.xs),
        child: child,
      );

  @override
  Widget build(BuildContext context) {
    final c = DshPalette.of(context);
    return Scaffold(
      backgroundColor: c.bg,
      appBar: DshAppBar(
        title: L10n.t('文档', 'Documents'),
        actions: [
          Center(
            child: DshIconButton(
              icon: Icons.refresh,
              tooltip: L10n.t('刷新', 'Refresh'),
              onTap: () => _load(_path),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          _pathBar(c),
          Expanded(child: _list()),
        ],
      ),
    );
  }

  /// 路径条：module 底 + 底部发丝线，左侧返回上一级，右侧切换「全部/只看可读」。
  Widget _pathBar(DshPalette c) {
    final hasPath = _path.isNotEmpty;
    return Container(
      padding: const EdgeInsets.fromLTRB(
        DshSpace.sm,
        DshSpace.sm,
        DshSpace.md,
        DshSpace.sm,
      ),
      decoration: BoxDecoration(
        color: c.module,
        border: Border(
          bottom: BorderSide(color: c.line2, width: DshStroke.hairline),
        ),
      ),
      child: Row(
        children: [
          DshIconButton(
            icon: Icons.arrow_upward,
            iconSize: 18,
            tooltip: L10n.t('上一级', 'Up'),
            onTap: _loading ? null : _up,
          ),
          const SizedBox(width: DshSpace.sm),
          Expanded(
            child: Text(
              hasPath ? _path : L10n.t('（选择位置）', '(choose a location)'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: DshType.xxs12.copyWith(color: hasPath ? c.ink2 : c.ink3),
            ),
          ),
          if (_files.isNotEmpty) ...[
            const SizedBox(width: DshSpace.sm),
            DshButton(
              label: _showAll
                  ? L10n.t('只看可读', 'Readable only')
                  : L10n.t('全部文件', 'All files'),
              variant: DshButtonVariant.outline,
              size: DshButtonSize.sm,
              onPressed: () => setState(() => _showAll = !_showAll),
            ),
          ],
        ],
      ),
    );
  }

  Widget _list() {
    final c = DshPalette.of(context);
    if (_loading) return const DshLoading();

    final err = _error;
    if (err != null) {
      return DshError(
        message: L10n.t('读取目录失败：$err', 'Failed to read directory: $err'),
        onRetry: () => _load(_path),
      );
    }

    final files = _shownFiles;
    final showWorkspaces = _workspaces.isNotEmpty && _path.isEmpty;
    final isEmpty = _dirs.isEmpty && files.isEmpty;

    if (isEmpty && !showWorkspaces) {
      return _emptyState();
    }

    return ListView(
      children: [
        if (showWorkspaces) ...[
          DshSectionHeader(L10n.t('工作区', 'Workspaces')),
          for (final w in _workspaces)
            _row(DshTile(
              leading: _iconBox(c, Icons.workspaces_outline, c.ink2),
              title: (w['title'] as String?) ?? (w['path'] as String? ?? ''),
              subtitle: '${w['path'] ?? ''}',
              chevron: true,
              onTap: () {
                final p = w['path'] as String?;
                if (p == null) return;
                _stack.add(_path);
                _load(p);
              },
            )),
        ],
        if (_dirs.isNotEmpty) ...[
          DshSectionHeader(L10n.t('文件夹', 'Folders')),
          for (final d in _dirs)
            _row(DshTile(
              leading: _iconBox(c, Icons.folder_outlined, c.ink2),
              title: d,
              chevron: true,
              onTap: () => _enter(d),
            )),
        ],
        if (files.isNotEmpty) ...[
          DshSectionHeader(L10n.t('文档（可点击打开）', 'Documents (tap to open)')),
          for (final f in files)
            _row(DshTile(
              leading: _iconBox(c, _iconOf(f), _colorOf(c, f)),
              title: f,
              chevron: true,
              onTap: () => _open(f),
            )),
        ],
        // 只剩工作区（当前目录没有文件夹/可读文件）时补一条空提示
        if (isEmpty) _emptyState(compact: true),
        const SizedBox(height: DshSpace.xxl),
      ],
    );
  }

  /// 空状态：区分「目录真的空」与「有文件但没有可打开的格式」。
  Widget _emptyState({bool compact = false}) => DshEmpty(
        compact: compact,
        icon: _files.isEmpty ? Icons.folder_open_outlined : Icons.search_off_outlined,
        title: _files.isEmpty
            ? L10n.t('此目录为空', 'This folder is empty')
            : L10n.t('此目录没有可打开的文档', 'No openable documents here'),
        message: _files.isEmpty
            ? null
            : L10n.t('点上方「全部文件」查看', 'Tap "All files" above to see everything'),
      );

  static IconData _iconOf(String name) => switch (detectFormat(name)) {
        DocFormat.markdown => Icons.article_outlined,
        DocFormat.docx => Icons.description_outlined,
        DocFormat.xlsx => Icons.table_chart_outlined,
        DocFormat.text => Icons.notes_outlined,
        DocFormat.unknown => Icons.insert_drive_file_outlined,
      };

  Color _colorOf(DshPalette c, String name) =>
      isReadableFormat(name) ? c.ink : c.ink3;
}
