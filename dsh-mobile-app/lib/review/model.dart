// 本轮改动（v3.2.14）——Host 侧 workspace-changes 摘要与逐文件对比的**只读投影**。
//
// 数据源：@deepseek-ai/dsh-workspace-changes 在 PC 端每个顶层轮次结束时，用 git 工作树
// 快照 + 文件工具编辑前后的整文件捕获，算出「改了哪些文件、各增删几行」，并在会话存活
// 期间按宣告事件 seq 保存摘要与两侧内容。App 不重算 diff、不缓存基线——它只是把 PC 端
// 已经算好的事实读出来，按手机尺寸重排（与 PC 端改动文件卡片 / review tab 同源）。
//
// 契约（lib/index.js /api/changes.summary、/api/changes.diff）：
//   summary = { turn, cwd, files[{path, display, added, deleted, binary?, oversized?}],
//               total, added, deleted, snapshot? }
//   diff    = { kind: 'text', path, display, before, after,
//               hunks[{oldStart, oldLines, newStart, newLines, lines[]}], coarse }
//             | { kind: 'binary' | 'oversized', path, display }
//
// 解析一律容错：旧宿主缺字段、数据被裁剪、hunk 行缺前缀，都退化成「能读但不完美」，
// 绝不因为一个字段让整页打不开（手机端没有控制台可看）。

/// 单个改动文件。字段与 Host 的 WorkspaceChangedFile 一一对应。
class ChangedFile {
  /// 会话工作目录相对路径，或工作区外的绝对路径（Windows 保留原生分隔符）。
  final String path;

  /// 展示名：工作目录内为相对路径、仓库上层为 ../、家目录下为 ~，其余绝对路径。
  /// 始终用斜杠分隔，且是 Host 排好的顺序键。
  final String display;

  /// 新增行数（二进制/过大文件为 0）。
  final int added;

  /// 删除行数（二进制/过大文件为 0）。
  final int deleted;

  /// git 判定二进制，或某一侧含 NUL 字节。
  final bool binary;

  /// 某一侧超过 Host 的 maxFileBytes（默认 2 MB），既没有行数也没有对比。
  final bool oversized;

  const ChangedFile({
    required this.path,
    required this.display,
    this.added = 0,
    this.deleted = 0,
    this.binary = false,
    this.oversized = false,
  });

  /// 容错解析：缺 path/display 时视为无效记录返回 null（不渲染一行空白）。
  static ChangedFile? tryParse(Object? value) {
    if (value is! Map) return null;
    final path = _str(value['path']);
    final display = _str(value['display']);
    if (path.isEmpty && display.isEmpty) return null;
    return ChangedFile(
      path: path.isEmpty ? display : path,
      display: display.isEmpty ? path : display,
      added: _int(value['added']),
      deleted: _int(value['deleted']),
      binary: value['binary'] == true,
      oversized: value['oversized'] == true,
    );
  }

  /// 文件名（展示用的最后一段）。
  String get name {
    final i = display.lastIndexOf('/');
    return i < 0 ? display : display.substring(i + 1);
  }

  /// 目录前缀（无目录时为空串），供两行式路径展示。
  String get dir {
    final i = display.lastIndexOf('/');
    return i <= 0 ? '' : display.substring(0, i);
  }

  /// 是否有逐行行数（二进制/过大文件没有）。
  bool get hasCounts => !binary && !oversized;

  /// 增删摘要（+12 −3）；二进制/过大给状态词。
  String get countsLabel {
    if (binary) return '二进制';
    if (oversized) return '过大';
    return '+$added −$deleted';
  }
}

/// 一轮的改动摘要。
class TurnChanges {
  final int turn;

  /// 会话工作目录（path 相对它的基准；工作区外文件为绝对路径）。
  final String cwd;

  /// 已列出的文件（Host 按 display 码元序排序，最多 maxFiles 条）。
  final List<ChangedFile> files;

  /// 完整文件数（含被 maxFiles 截掉的）。
  final int total;

  /// 全部文件的增删行数合计（含被截掉的）。
  final int added;
  final int deleted;

  const TurnChanges({
    required this.turn,
    this.cwd = '',
    this.files = const [],
    this.total = 0,
    this.added = 0,
    this.deleted = 0,
  });

  static TurnChanges? tryParse(Object? value) {
    if (value is! Map) return null;
    final files = <ChangedFile>[];
    final raw = value['files'];
    if (raw is List) {
      for (final item in raw) {
        final file = ChangedFile.tryParse(item);
        if (file != null) files.add(file);
      }
    }
    final total = _int(value['total']);
    return TurnChanges(
      turn: _int(value['turn']),
      cwd: _str(value['cwd']),
      files: files,
      total: total == 0 ? files.length : total,
      added: _int(value['added']),
      deleted: _int(value['deleted']),
    );
  }

  bool get isEmpty => files.isEmpty;

  /// Host 的 maxFiles 上限把列表截短了（总数仍完整）。
  bool get capped => total > files.length;
}

/// 对比类型：文本 / 二进制 / 过大。
enum FileDiffKind { text, binary, oversized }

/// 一个文件的轮次前后对比（Host 已算好的 hunk，三行上下文）。
class FileDiff {
  final FileDiffKind kind;
  final String path;
  final String display;

  /// 轮次开始时该文件是否存在。
  final bool before;

  /// 轮次结束时该文件是否存在。
  final bool after;

  /// 按文件顺序的 hunk；两侧行相同则为空。
  final List<DiffHunk> hunks;

  /// 逐行对比超过 Host 的 diffTimeoutMs，退化成「整文件替换」。
  final bool coarse;

  const FileDiff({
    required this.kind,
    required this.path,
    required this.display,
    this.before = false,
    this.after = false,
    this.hunks = const [],
    this.coarse = false,
  });

  static FileDiff? tryParse(Object? value) {
    if (value is! Map) return null;
    final kind = switch (_str(value['kind'])) {
      'binary' => FileDiffKind.binary,
      'oversized' => FileDiffKind.oversized,
      _ => FileDiffKind.text,
    };
    final hunks = <DiffHunk>[];
    final raw = value['hunks'];
    if (raw is List) {
      for (final item in raw) {
        final hunk = DiffHunk.tryParse(item);
        if (hunk != null) hunks.add(hunk);
      }
    }
    return FileDiff(
      kind: kind,
      path: _str(value['path']),
      display: _str(value['display']),
      before: value['before'] == true,
      after: value['after'] == true,
      hunks: hunks,
      coarse: value['coarse'] == true,
    );
  }

  /// 本轮新建。
  bool get created => !before && after;

  /// 本轮删除。
  bool get removed => before && !after;

  /// 两侧内容相同（只差末尾换行等 Host 判定为相同的情况）。
  bool get identical => kind == FileDiffKind.text && hunks.isEmpty;

  /// 文件的行数变化（逐 hunk 统计；摘要里的 git numstat 可能与之差 ±1）。
  (int, int) get lineDelta {
    var add = 0;
    var del = 0;
    for (final h in hunks) {
      for (final line in h.lines) {
        if (line.startsWith('+')) add++;
        if (line.startsWith('-')) del++;
      }
    }
    return (add, del);
  }

  /// 状态说明行（新建 / 删除 / 相同 / 超时退化 / 二进制 / 过大），无特殊状态返回 null。
  String? get statusNote {
    if (kind == FileDiffKind.binary) return '二进制文件，没有逐行对比';
    if (kind == FileDiffKind.oversized) return '文件超过 2 MB，未生成对比';
    if (created) return '本轮新建文件';
    if (removed) return '本轮删除文件';
    if (identical) return '本轮内容没有变化（可能只改了末尾换行）';
    if (coarse) return '逐行对比超时，按整文件替换显示';
    return null;
  }
}

/// 一个 unified-diff hunk（每行保留 + / - / 空格 前缀）。
class DiffHunk {
  final int oldStart;
  final int oldLines;
  final int newStart;
  final int newLines;

  /// hunk 正文，按顺序；每个元素的首字符是 +、- 或空格。
  final List<String> lines;

  const DiffHunk({
    required this.oldStart,
    required this.oldLines,
    required this.newStart,
    required this.newLines,
    required this.lines,
  });

  static DiffHunk? tryParse(Object? value) {
    if (value is! Map) return null;
    final raw = value['lines'];
    final lines = raw is List
        ? raw.map((e) => e?.toString() ?? '').toList(growable: false)
        : const <String>[];
    return DiffHunk(
      oldStart: _int(value['oldStart']),
      oldLines: _int(value['oldLines']),
      newStart: _int(value['newStart']),
      newLines: _int(value['newLines']),
      lines: lines,
    );
  }

  /// hunk 头：@@ -旧起始,行数 +新起始,行数 @@。
  String get header => '@@ -$oldStart,$oldLines +$newStart,$newLines @@';
}

/// 一行 diff 的语义（已配好两侧行号）。
enum DiffLineKind { add, del, context }

class DiffLine {
  final DiffLineKind kind;
  final int? oldNo;
  final int? newNo;
  final String text;

  const DiffLine(this.kind, this.oldNo, this.newNo, this.text);

  /// 前缀标记：+ / − / 空格（删除用 U+2212 保证等宽对齐）。
  String get marker => switch (kind) {
        DiffLineKind.add => '+',
        DiffLineKind.del => '−',
        DiffLineKind.context => ' ',
      };
}

/// 按 unified diff 语义给 hunk 编号：上下文两侧都计数，删除只算旧侧，新增只算新侧。
List<DiffLine> hunkLines(DiffHunk hunk) {
  final out = <DiffLine>[];
  var oldNo = hunk.oldStart;
  var newNo = hunk.newStart;
  for (final raw in hunk.lines) {
    if (raw.startsWith('+')) {
      out.add(DiffLine(DiffLineKind.add, null, newNo++, raw.length > 1 ? raw.substring(1) : ''));
    } else if (raw.startsWith('-')) {
      out.add(DiffLine(DiffLineKind.del, oldNo++, null, raw.length > 1 ? raw.substring(1) : ''));
    } else {
      // 上下文行（旧宿主可能不带前缀，按上下文兜底）
      final text = raw.startsWith(' ') ? raw.substring(1) : raw;
      out.add(DiffLine(DiffLineKind.context, oldNo++, newNo++, text));
    }
  }
  return out;
}

/// 渲染上限：与 PC 端 review tab 同值，防止一次展开上万行把手机主线程拖死。
const int kMaxRenderedDiffLines = 5000;

/// 分批展开的步长（先渲一段，用户点「显示更多」再加一段）。
const int kDiffChunkLines = 400;

/// 这组 hunk 的总行数（截断判定用）。
int diffLineCount(List<DiffHunk> hunks) {
  var n = 0;
  for (final h in hunks) {
    n += h.lines.length;
  }
  return n;
}

/// 行号列宽（按最大行号的十进制位数；至少 2 位，最多 5 位）。
int gutterDigits(List<DiffHunk> hunks) {
  var maxNo = 1;
  for (final h in hunks) {
    final a = h.oldStart + h.oldLines;
    final b = h.newStart + h.newLines;
    if (a > maxNo) maxNo = a;
    if (b > maxNo) maxNo = b;
  }
  final digits = maxNo.toString().length;
  return digits < 2 ? 2 : (digits > 5 ? 5 : digits);
}

/// 把摘要里的 path 还原成可交给 /api/files 的绝对路径。
///
/// Host 的 path 在工作目录内是相对路径（可能含 .. 上溯），工作区外是绝对路径。
String absolutePathOf(ChangedFile file, String cwd) {
  final raw = file.path;
  if (raw.isEmpty) return raw;
  if (raw.startsWith('/') || RegExp(r'^[A-Za-z]:[\\/]').hasMatch(raw)) return raw;
  if (cwd.isEmpty) return raw;
  final sep = cwd.contains('\\') ? '\\' : '/';
  final base = cwd.endsWith('\\') || cwd.endsWith('/') ? cwd : '$cwd$sep';
  final normalized = sep == '\\' ? raw.replaceAll('/', '\\') : raw.replaceAll('\\', '/');
  return '$base$normalized';
}

String _str(Object? v) => v is String ? v : (v == null ? '' : v.toString());

int _int(Object? v) => v is num ? v.toInt() : (v is String ? (int.tryParse(v) ?? 0) : 0);
