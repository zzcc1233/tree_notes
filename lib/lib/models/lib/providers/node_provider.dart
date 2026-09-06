import 'dart:async';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:isar/isar.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/node.dart';

/// ==================== Isar 数据库实例 ====================
final isarProvider = FutureProvider<Isar>((ref) async {
  final dir = await getApplicationDocumentsDirectory();
  final isar = await Isar.open(
    [NoteNodeSchema],
    directory: dir.path,
    inspector: false,
  );
  ref.onDispose(() => isar.close());
  return isar;
});

/// ==================== 当前视图模式 ====================
enum ViewMode { outline, kanban, mindmap }

final viewModeProvider = StateProvider<ViewMode>((ref) => ViewMode.outline);

/// ==================== 聚焦模式（Focus Mode） ====================
final focusedNodeIdProvider = StateProvider<int?>((ref) => null);

/// ==================== 搜索关键字 ====================
final searchQueryProvider = StateProvider<String>((ref) => '');

/// ==================== 全量节点缓存 ====================
final allNodesProvider = StreamProvider<List<NoteNode>>((ref) async* {
  final isar = await ref.watch(isarProvider.future);
  yield* isar.noteNodes
      .filter()
      .isDeletedEqualTo(false)
      .watch(fireImmediately: true);
});

/// 按 parentId 分组
final childrenMapProvider = Provider<Map<int?, List<NoteNode>>>((ref) {
  final nodes = ref.watch(allNodesProvider).valueOrNull ?? [];
  final map = <int?, List<NoteNode>>{};
  for (final n in nodes) {
    map.putIfAbsent(n.parentId, () => []).add(n);
  }
  for (final entry in map.entries) {
    entry.value.sort((a, b) => a.updatedAt.compareTo(b.updatedAt));
  }
  return map;
});

/// 全局搜索结果
final searchResultsProvider = Provider<List<NoteNode>>((ref) {
  final query = ref.watch(searchQueryProvider).trim();
  if (query.isEmpty) return [];
  final nodes = ref.watch(allNodesProvider).valueOrNull ?? [];
  final lower = query.toLowerCase();
  final results = nodes.where((n) {
    return n.title.toLowerCase().contains(lower) ||
        n.plainText.toLowerCase().contains(lower);
  }).toList();
  results.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  return results;
});

/// 反向链接
final backlinksProvider = Provider.family<List<NoteNode>, int>((ref, nodeId) {
  final nodes = ref.watch(allNodesProvider).valueOrNull ?? [];
  return nodes.where((n) => n.linkedNodeIds.contains(nodeId)).toList();
});

/// ==================== 节点操作 ====================
class NodeRepository {
  NodeRepository(this.ref);
  final Ref ref;

  Future<Isar> get _isar => ref.read(isarProvider.future);

  Future<int> createNode({
    required int? parentId,
    String title = '',
    int? insertAfterId,
  }) async {
    final isar = await _isar;
    final node = NoteNode()
      ..parentId = parentId
      ..title = title
      ..createdAt = DateTime.now()
      ..updatedAt = DateTime.now();

    await isar.writeTxn(() async {
      final newId = await isar.noteNodes.put(node);
      if (parentId != null) {
        final parent = await isar.noteNodes.get(parentId);
        if (parent != null) {
          final list = List<int>.from(parent.childrenIds);
          if (insertAfterId != null && list.contains(insertAfterId)) {
            list.insert(list.indexOf(insertAfterId) + 1, newId);
          } else {
            list.add(newId);
          }
          parent.childrenIds = list;
          parent.updatedAt = DateTime.now();
          await isar.noteNodes.put(parent);
        }
      }
    });
    return node.id;
  }

  Future<void> updateContent(
    int id, {
    String? title,
    String? contentJson,
  }) async {
    final isar = await _isar;
    await isar.writeTxn(() async {
      final node = await isar.noteNodes.get(id);
      if (node == null) return;
      if (title != null) node.title = title;
      if (contentJson != null) {
        node.contentJson = contentJson;
        final tagReg = RegExp(r'#([^\s#@]+)');
        node.tags = tagReg
            .allMatches(node.plainText)
            .map((m) => m.group(1) ?? '')
            .where((t) => t.isNotEmpty)
            .toSet()
            .toList();
        final statusReg = RegExp(r'@([^\s#@]+)');
        final statusMatch = statusReg.firstMatch(node.plainText);
        node.status = statusMatch?.group(1);
      }
      node.updatedAt = DateTime.now();
      await isar.noteNodes.put(node);
    });
  }

  Future<void> toggleCollapsed(int id) async {
    final isar = await _isar;
    await isar.writeTxn(() async {
      final node = await isar.noteNodes.get(id);
      if (node == null) return;
      node.isCollapsed = !node.isCollapsed;
      await isar.noteNodes.put(node);
    });
  }

  Future<void> toggleStar(int id) async {
    final isar = await _isar;
    await isar.writeTxn(() async {
      final node = await isar.noteNodes.get(id);
      if (node == null) return;
      node.isStarred = !node.isStarred;
      await isar.noteNodes.put(node);
    });
  }

  Future<void> softDelete(int id) async {
    final isar = await _isar;
    await isar.writeTxn(() async {
      final node = await isar.noteNodes.get(id);
      if (node == null) return;
      node.isDeleted = true;
      await isar.noteNodes.put(node);
      if (node.parentId != null) {
        final parent = await isar.noteNodes.get(node.parentId!);
        if (parent != null) {
          parent.childrenIds = List<int>.from(parent.childrenIds)..remove(id);
          await isar.noteNodes.put(parent);
        }
      }
    });
  }

  Future<void> indent(int id) async {
    final isar = await _isar;
    await isar.writeTxn(() async {
      final node = await isar.noteNodes.get(id);
      if (node == null) return;
      final siblings = await isar.noteNodes
          .filter()
          .parentIdEqualTo(node.parentId)
          .isDeletedEqualTo(false)
          .findAll();
      siblings.sort((a, b) => a.updatedAt.compareTo(b.updatedAt));
      final idx = siblings.indexWhere((n) => n.id == id);
      if (idx <= 0) return;

      final newParent = siblings[idx - 1];
      if (node.parentId != null) {
        final oldParent = await isar.noteNodes.get(node.parentId!);
        if (oldParent != null) {
          oldParent.childrenIds = List<int>.from(oldParent.childrenIds)
            ..remove(id);
          await isar.noteNodes.put(oldParent);
        }
      }
      node.parentId = newParent.id;
      node.updatedAt = DateTime.now();
      newParent.childrenIds = List<int>.from(newParent.childrenIds)..add(id);
      newParent.isCollapsed = false;
      await isar.noteNodes.put(node);
      await isar.noteNodes.put(newParent);
    });
  }

  Future<void> outdent(int id) async {
    final isar = await _isar;
    await isar.writeTxn(() async {
      final node = await isar.noteNodes.get(id);
      if (node == null || node.parentId == null) return;

      final oldParent = await isar.noteNodes.get(node.parentId!);
      if (oldParent == null) return;
      oldParent.childrenIds = List<int>.from(oldParent.childrenIds)
        ..remove(id);
      await isar.noteNodes.put(oldParent);

      final grandParentId = oldParent.parentId;
      node.parentId = grandParentId;
      node.updatedAt = DateTime.now();
      await isar.noteNodes.put(node);

      if (grandParentId != null) {
        final grandParent = await isar.noteNodes.get(grandParentId);
        if (grandParent != null) {
          final list = List<int>.from(grandParent.childrenIds);
          final pos = list.indexOf(oldParent.id);
          list.insert(pos == -1 ? list.length : pos + 1, id);
          grandParent.childrenIds = list;
          await isar.noteNodes.put(grandParent);
        }
      }
    });
  }

  /// 导出 Markdown：递归遍历整棵树，标题层级转为对应数量的 #，
  /// 正文转为普通 Markdown 段落，写入本地文件后触发系统分享面板。
  Future<void> exportMarkdown() async {
    final isar = await _isar;
    final allNodes =
        await isar.noteNodes.filter().isDeletedEqualTo(false).findAll();
    final byParent = <int?, List<NoteNode>>{};
    for (final n in allNodes) {
      byParent.putIfAbsent(n.parentId, () => []).add(n);
    }

    final buffer = StringBuffer();
    void writeNode(NoteNode node, int depth) {
      final hashes = '#' * (depth + 1).clamp(1, 6);
      buffer.writeln('$hashes ${node.title.isEmpty ? "无标题" : node.title}');
      if (node.plainText.trim().isNotEmpty) {
        buffer.writeln();
        buffer.writeln(node.plainText.trim());
      }
      buffer.writeln();
      for (final child in byParent[node.id] ?? []) {
        writeNode(child, depth + 1);
      }
    }

    for (final root in byParent[null] ?? []) {
      writeNode(root, 0);
    }

    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/tree_notes_export.md');
    await file.writeAsString(buffer.toString());
    await Share.shareXFiles([XFile(file.path)], text: '我的笔记导出');
  }
}

final nodeRepositoryProvider = Provider((ref) => NodeRepository(ref));
