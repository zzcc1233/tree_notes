import 'dart:convert';
import 'package:isar/isar.dart';

part 'node.g.dart'; // 由 build_runner 自动生成，运行:
// flutter pub run build_runner build --delete-conflicting-outputs

/// NoteNode —— 树状笔记的核心数据模型（Isar Collection）
///
/// 设计说明：
/// - 通过 [parentId] 指向父节点，null 表示根节点，从而构成无限层级的树。
/// - [contentJson] 以字符串形式存储 flutter_quill 的 Delta（JSON 数组），
///   Isar 原生不支持持久化任意嵌套 Map/List<dynamic>，因此在存取时使用
///   jsonEncode / jsonDecode 做序列化转换（见下方 getter/setter）。
/// - [childrenIds] 冗余保存了子节点的展示顺序，避免每次都用
///   "在上方插入/在下方插入"时重新计算排序号。
@collection
class NoteNode {
  Id id = Isar.autoIncrement; // Isar 自增主键，等价于时间戳递增的整型 ID

  @Index() // 加速 "查询某节点的所有直接子节点" (where parentId == x)
  int? parentId;

  @Index(type: IndexType.value, caseSensitive: false) // 加速标题全文检索
  String title = '';

  /// 富文本内容（Quill Delta 的 JSON 字符串形式）
  /// 默认是一个只包含换行符的空 Delta。
  @Index(type: IndexType.value, caseSensitive: false) // 加速正文全文检索
  String contentJson = '[{"insert":"\\n"}]';

  bool isCollapsed = true; // 默认折叠子节点，对齐 Workflowy 的默认体验

  List<String> tags = []; // 从正文中解析出的 #标签，编辑时自动同步

  String? status; // 从正文中解析出的 @状态，例如 @进行中 / @已完成

  DateTime createdAt = DateTime.now();
  DateTime updatedAt = DateTime.now();

  List<int> childrenIds = []; // 子节点 ID 的展示顺序（用于插入/移动排序）

  bool isStarred = false; // 收藏 / 星标

  bool isDeleted = false; // 软删除标记，用于"回收站"而不是物理删除

  // -------------------- 便捷方法（不持久化，仅内存计算） --------------------

  /// 将 contentJson 解析为 Quill Delta 可用的 List<dynamic>
  @ignore
  List<dynamic> get deltaOps {
    try {
      return jsonDecode(contentJson) as List<dynamic>;
    } catch (_) {
      return [
        {"insert": "\n"}
      ];
    }
  }

  /// 将 Delta 的 List<dynamic> 重新编码回 contentJson 字段
  set deltaOps(List<dynamic> ops) {
    contentJson = jsonEncode(ops);
  }

  /// 从 Delta 中提取纯文本（用于全文检索预览 / 反向链接扫描）
  @ignore
  String get plainText {
    final buffer = StringBuffer();
    for (final op in deltaOps) {
      if (op is Map && op['insert'] is String) {
        buffer.write(op['insert']);
      }
    }
    return buffer.toString();
  }

  /// 提取正文中形如 [[123]] 或 [[节点标题]] 的双向链接引用的节点 ID
  /// 约定：编辑器插入链接时，统一写成 [[id:123|标题]] 的形式，
  /// 便于用正则稳定提取，不依赖标题是否重名。
  @ignore
  List<int> get linkedNodeIds {
    final reg = RegExp(r'\[\[id:(\d+)(\|[^\]]*)?\]\]');
    return reg
        .allMatches(plainText)
        .map((m) => int.tryParse(m.group(1) ?? ''))
        .whereType<int>()
        .toList();
  }
}
