// 工作区文档浏览器（v3.2.0）——在手机上浏览电脑侧的文件，直接打开可读文档。
//
// 只读设计：这里是「找文档 → 打开」的入口，不做上传/删除/重命名，避免误触改坏
// 电脑上的工作目录。可读格式由 docs/model.dart 的 kReadableExtensions 单点定义，
// 与 Android intent-filter 的能力保持一致。
import 'package:flutter/material.dart';

import '../api.dart';
import '../docs/model.dart';
import '../l10n.dart';
import '../theme.dart';
import 'doc_viewer_screen.dart';

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

  @override
  Widget build(BuildContext context) {
    final ink2 = DshColors.ink2(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(L10n.t('文档', 'Documents'), maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: L10n.t('刷新', 'Refresh'),
            onPressed: () => _load(_path),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          // 路径条
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            color: DshColors.brandSoft(context),
            child: Row(
              children: [
                IconButton(
                  tooltip: L10n.t('上一级', 'Up'),
                  visualDensity: VisualDensity.compact,
                  onPressed: _loading ? null : _up,
                  icon: const Icon(Icons.arrow_upward, size: 18),
                ),
                Expanded(
                  child: Text(
                    _path.isEmpty ? L10n.t('（选择位置）', '(choose a location)') : _path,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: ink2),
                  ),
                ),
                if (_files.isNotEmpty)
                  TextButton(
                    onPressed: () => setState(() => _showAll = !_showAll),
                    child: Text(
                      _showAll ? L10n.t('只看可读', 'Readable only') : L10n.t('全部文件', 'All files'),
                      style: const TextStyle(fontSize: 11.5),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(child: _list()),
        ],
      ),
    );
  }

  Widget _list() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    final err = _error;
    if (err != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off_outlined, size: 40, color: DshColors.danger(context)),
              const SizedBox(height: 12),
              Text(L10n.t('读取目录失败：$err', 'Failed to read directory: $err'),
                  textAlign: TextAlign.center, style: const TextStyle(fontSize: 14)),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => _load(_path),
                child: Text(L10n.t('重试', 'Retry')),
              ),
            ],
          ),
        ),
      );
    }

    final files = _shownFiles;
    final ink2 = DshColors.ink2(context);

    return ListView(
      children: [
        if (_workspaces.isNotEmpty && _path.isEmpty) ...[
          _sectionTitle(L10n.t('工作区', 'Workspaces'), ink2),
          for (final w in _workspaces)
            ListTile(
              leading: const Icon(Icons.workspaces_outline, size: 20),
              title: Text((w['title'] as String?) ?? (w['path'] as String? ?? '')),
              subtitle: Text('${w['path'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis),
              onTap: () {
                final p = w['path'] as String?;
                if (p == null) return;
                _stack.add(_path);
                _load(p);
              },
            ),
          const Divider(height: 1),
        ],
        if (_dirs.isNotEmpty) ...[
          _sectionTitle(L10n.t('文件夹', 'Folders'), ink2),
          for (final d in _dirs)
            ListTile(
              leading: Icon(Icons.folder_outlined, size: 20, color: ink2),
              title: Text(d, maxLines: 1, overflow: TextOverflow.ellipsis),
              onTap: () => _enter(d),
            ),
        ],
        if (files.isNotEmpty) ...[
          _sectionTitle(L10n.t('文档（可点击打开）', 'Documents (tap to open)'), ink2),
          for (final f in files)
            ListTile(
              leading: Icon(_iconOf(f), size: 20, color: _colorOf(context, f)),
              title: Text(f, maxLines: 1, overflow: TextOverflow.ellipsis),
              trailing: const Icon(Icons.chevron_right, size: 18),
              onTap: () => _open(f),
            ),
        ],
        if (_dirs.isEmpty && files.isEmpty)
          Padding(
            padding: const EdgeInsets.all(32),
            child: Center(
              child: Text(
                _files.isEmpty
                    ? L10n.t('此目录为空', 'This folder is empty')
                    : L10n.t('此目录没有可打开的文档\n（点右上「全部文件」查看）',
                        'No openable documents here\n(tap "All files" above)'),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: ink2, height: 1.6),
              ),
            ),
          ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _sectionTitle(String text, Color color) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
        child: Text(
          text,
          style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, letterSpacing: 0.5, color: color),
        ),
      );

  static IconData _iconOf(String name) => switch (detectFormat(name)) {
        DocFormat.markdown => Icons.article_outlined,
        DocFormat.docx => Icons.description_outlined,
        DocFormat.xlsx => Icons.table_chart_outlined,
        DocFormat.text => Icons.notes_outlined,
        DocFormat.unknown => Icons.insert_drive_file_outlined,
      };

  Color _colorOf(BuildContext c, String name) =>
      isReadableFormat(name) ? DshColors.brand(c) : DshColors.ink3(c);
}
