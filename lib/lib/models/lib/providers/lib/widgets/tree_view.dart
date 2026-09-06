import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/node.dart';
import '../providers/node_provider.dart';
import '../screens/editor_screen.dart';

/// TreeView —— 递归渲染节点树的大纲视图
class TreeView extends ConsumerWidget {
  const TreeView({super.key, required this.parentId, this.depth = 0});

  final int? parentId;
  final int depth;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final childrenMap = ref.watch(childrenMapProvider);
    final children = childrenMap[parentId] ?? [];

    if (children.isEmpty && depth == 0) {
      return const _EmptyState();
    }

    return ListView.builder(
      padding: const EdgeInsets.only(top: 8, bottom: 120),
      itemCount: children.length,
      itemBuilder: (context, index) {
        final node = children[index];
        return _AnimatedListItem(
          index: index,
          child: _TreeNodeTile(node: node, depth: depth),
        );
      },
    );
  }
}

class _AnimatedListItem extends StatefulWidget {
  const _AnimatedListItem({required this.index, required this.child});
  final int index;
  final Widget child;

  @override
  State<_AnimatedListItem> createState() => _AnimatedListItemState();
}

class _AnimatedListItemState extends State<_AnimatedListItem>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<Offset> _offset;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    _offset = Tween<Offset>(begin: const Offset(0, 0.15), end: Offset.zero)
        .animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    Future.delayed(Duration(milliseconds: 50 * (widget.index % 12)), () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(position: _offset, child: widget.child),
    );
  }
}

class _TreeNodeTile extends ConsumerWidget {
  const _TreeNodeTile({required this.node, required this.depth});

  final NoteNode node;
  final int depth;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final childrenMap = ref.watch(childrenMapProvider);
    final childCount = (childrenMap[node.id] ?? []).length;
    final repo = ref.read(nodeRepositoryProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => Navigator.of(context).push(
            CupertinoPageRoute(builder: (_) => EditorScreen(nodeId: node.id)),
          ),
          onLongPress: () => _showNodeActions(context, ref, node),
          child: Padding(
            padding: EdgeInsets.only(
              left: 12.0 + depth * 20.0,
              right: 12,
              top: 10,
              bottom: 10,
            ),
            child: Row(
              children: [
                if (depth > 0) _IndentGuides(depth: depth),
                GestureDetector(
                  onTap: childCount > 0
                      ? () => repo.toggleCollapsed(node.id)
                      : null,
                  child: SizedBox(
                    width: 24,
                    child: childCount > 0
                        ? AnimatedRotation(
                            turns: node.isCollapsed ? 0 : 0.25,
                            duration: const Duration(milliseconds: 200),
                            child: const Icon(CupertinoIcons.chevron_right,
                                size: 16, color: CupertinoColors.systemGrey),
                          )
                        : const Icon(CupertinoIcons.circle_fill,
                            size: 6, color: CupertinoColors.systemGrey3),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    node.title.isEmpty ? '无标题' : node.title,
                    style: TextStyle(
                      fontSize: 16,
                      color: node.title.isEmpty
                          ? CupertinoColors.systemGrey
                          : CupertinoColors.label.resolveFrom(context),
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (node.isStarred)
                  const Icon(CupertinoIcons.star_fill,
                      size: 14, color: CupertinoColors.systemYellow),
                if (node.tags.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  Text('#${node.tags.first}',
                      style: const TextStyle(
                          fontSize: 12, color: CupertinoColors.activeBlue)),
                ],
              ],
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeInOut,
          child: node.isCollapsed || childCount == 0
              ? const SizedBox.shrink()
              : _ChildrenList(parentId: node.id, depth: depth + 1),
        ),
      ],
    );
  }

  void _showNodeActions(BuildContext context, WidgetRef ref, NoteNode node) {
    final repo = ref.read(nodeRepositoryProvider);
    showCupertinoModalPopup(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: Text(node.title.isEmpty ? '无标题' : node.title),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () async {
              Navigator.pop(ctx);
              await repo.createNode(
                  parentId: node.parentId, insertAfterId: node.id);
            },
            child: const Text('在下方插入'),
          ),
          CupertinoActionSheetAction(
            onPressed: () async {
              Navigator.pop(ctx);
              await repo.createNode(parentId: node.parentId);
            },
            child: const Text('在上方插入'),
          ),
          CupertinoActionSheetAction(
            onPressed: () async {
              Navigator.pop(ctx);
              await repo.indent(node.id);
            },
            child: const Text('缩进（右移）'),
          ),
          CupertinoActionSheetAction(
            onPressed: () async {
              Navigator.pop(ctx);
              await repo.outdent(node.id);
            },
            child: const Text('提升（左移）'),
          ),
          CupertinoActionSheetAction(
            onPressed: () async {
              Navigator.pop(ctx);
              await repo.toggleStar(node.id);
            },
            child: Text(node.isStarred ? '取消收藏' : '收藏'),
          ),
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(ctx);
              ref.read(focusedNodeIdProvider.notifier).state = node.id;
            },
            child: const Text('聚焦'),
          ),
          CupertinoActionSheetAction(
            isDestructiveAction: true,
            onPressed: () => _confirmDelete(context, ref, node),
            child: const Text('删除'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('取消'),
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context, WidgetRef ref, NoteNode node) {
    Navigator.pop(context);
    showCupertinoDialog(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('删除节点'),
        content: const Text('该节点及其所有子节点将移入回收站，可稍后恢复。确定删除吗？'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () {
              Navigator.pop(ctx);
              ref.read(nodeRepositoryProvider).softDelete(node.id);
            },
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }
}

class _ChildrenList extends ConsumerWidget {
  const _ChildrenList({required this.parentId, required this.depth});
  final int parentId;
  final int depth;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final childrenMap = ref.watch(childrenMapProvider);
    final children = childrenMap[parentId] ?? [];
    return Column(
      children: children
          .map((n) => _TreeNodeTile(node: n, depth: depth))
          .toList(growable: false),
    );
  }
}

class _IndentGuides extends StatelessWidget {
  const _IndentGuides({required this.depth});
  final int depth;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 0,
      height: 20,
      child: Stack(
        clipBehavior: Clip.none,
        children: List.generate(depth, (i) {
          return Positioned(
            left: -12.0 - (depth - i) * 20.0 + 20,
            top: -10,
            bottom: -10,
            child: Container(
              width: 1,
              color: CupertinoColors.systemGrey4.resolveFrom(context),
            ),
          );
        }),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(CupertinoIcons.square_pencil,
              size: 48, color: CupertinoColors.systemGrey3.resolveFrom(context)),
          const SizedBox(height: 12),
          Text('还没有笔记，点击右下角开始',
              style: TextStyle(color: CupertinoColors.systemGrey.resolveFrom(context))),
        ],
      ),
    );
  }
}
