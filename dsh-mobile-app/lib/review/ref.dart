// 文档阅读器的「改动」坐标（v3.2.14）：哪个会话、哪次宣告、第几个文件。
//
// 单独一个文件是为了避免循环依赖：api.dart 依赖 review/model.dart（解析摘要/对比），
// 而阅读页要同时拿到 Api 与坐标——坐标本身不带 Api，谁都能安全引用。
class DocReviewRef {
  final String sessionId;

  /// workspace/changes 宣告事件的 seq（Host 按它保存这一轮的摘要与两侧内容）。
  final int seq;

  /// 该文件在摘要 files 数组里的原始下标（Host 以此定位对比）。
  final int index;

  const DocReviewRef({
    required this.sessionId,
    required this.seq,
    required this.index,
  });
}
