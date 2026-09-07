import 'dart:ui';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/node.dart';
import '../providers/node_provider.dart';
import '../widgets/tree_view.dart';
import 'editor_screen.dart';

/// HomeScreen —— App 主界面
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  bool _searching = false;
  final _searchController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final focusedId = ref.watch(focusedNodeIdProvider);
    final viewMode = ref.watch(viewModeProvider);
    final allNodesAsync = ref.watch(allNodesProvider);

    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.systemGroupedBackground,
      child: SafeArea(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          drawer: const _GlassSidebar(),
          body: Column(
            children: [
              _buildTopBar(context, focusedId),
              if (_searching) _buildSearchResults(),
              Expanded(
                child: allNodesAsync.when(
                  loading: () => const Center(child: CupertinoActivityIndicator()),
                  error: (e, _) => Center(child: Text('加载失败: $e')),
                  data: (_) => _searching
                      ? const SizedBox.shrink()
                      : _buildMainView(viewMode, focusedId),
                ),
              ),
            ],
          ),
          floatingActionButton: _searching
              ? null
              : FloatingActionButton(
                  onPressed: () async {
                    final repo = ref.read(nodeRepositoryProvider);
                    final id = await repo.createNode(parentId: focusedId);
                    if (context.mounted) {
                      Navigator.of(context).push(
                        CupertinoPageRoute(
                            builder: (_) => EditorScreen(nodeId: id)),
                      );
                    }
                  },
                  child: const Icon(CupertinoIcons.add),
                ),
        ),
      ),
    );
  }

  Widget _buildMainView(ViewMode mode, int? focusedId) {
    switch (mode) {
      case ViewMode.outline:
        return TreeView(parentId: focusedId);
      case ViewMode.kanban:
        return _KanbanView(parentId: focusedId);
      case ViewMode.mindmap:
        return _MindMapView(rootId: focusedId);
    }
  }

  Widget _buildTopBar(BuildContext context, int? focusedId) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(
        children: [
          Builder(
            builder: (ctx) => IconButton(
              icon: const Icon(CupertinoIcons.line_horizontal_3),
              onPressed: () => Scaffold.of(ctx).openDrawer(),
            ),
          ),
          if (focusedId != null)
            IconButton(
              icon: const Icon(CupertinoIcons.back),
              tooltip: '退出聚焦',
              onPressed: () =>
                  ref.read(focusedNodeIdProvider.notifier).state = null,
            ),
          Expanded(
            child: _searching
                ? CupertinoSearchTextField(
                    controller: _searchController,
                    autofocus: true,
                    onChanged: (v) =>
                        ref.read(searchQueryProvider.notifier).state = v,
                  )
                : Text(
                    focusedId != null ? '聚焦模式' : '所有笔记',
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w600),
                  ),
          ),
          IconButton(
            icon: Icon(_searching
                ? CupertinoIcons.xmark
                : CupertinoIcons.search),
            onPressed: () {
              setState(() {
                _searching = !_searching;
                if (!_searching) {
                  _searchController.clear();
                  ref.read(searchQueryProvider.notifier).state = '';
                }
              });
            },
          ),
          if (!_searching) _buildViewSwitcher(),
        ],
      ),
    );
  }

  Widget _buildViewSwitcher() {
    final mode = ref.watch(viewModeProvider);
    return CupertinoSlidingSegmentedControl<ViewMode>(
      groupValue: mode,
      onValueChanged: (v) {
        if (v != null) ref.read(viewModeProvider.notifier).state = v;
      },
      children: const {
        ViewMode.outline: Padding(
          padding: EdgeInsets.symmetric(horizontal: 8),
          child: Icon(CupertinoIcons.list_bullet, size: 18),
        ),
        ViewMode.kanban: Padding(
          padding: EdgeInsets.symmetric(horizontal: 8),
          child: Icon(CupertinoIcons.rectangle_split_3x1, size: 18),
        ),
        ViewMode.mindmap: Padding(
          padding: EdgeInsets.symmetric(horizontal: 8),
          child: Icon(CupertinoIcons.arrow_branch, size: 18),
        ),
      },
    );
  }

  Widget _buildSearchResults() {
    final results = ref.watch(searchResultsProvider);
    final query = ref.watch(searchQueryProvider);
    if (query.isEmpty) return const SizedBox.shrink();
    return Expanded(
      child: ListView.builder(
        itemCount: results.length,
        itemBuilder: (context, i) {
          final n = results[i];
          return ListTile(
            title: _highlightedText(n.title.isEmpty ? '无标题' : n.title, query),
            subtitle: Text(
              n.plainText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            onTap: () => Navigator.of(context).push(
              CupertinoPageRoute(builder: (_) => EditorScreen(nodeId: n.id)),
            ),
          );
        },
      ),
    );
  }

  Widget _highlightedText(String text, String query) {
    final lower = text.toLowerCase();
    final q = query.toLowerCase();
    final idx = lower.indexOf(q);
    if (idx < 0 || q.isEmpty) return Text(text);
    return RichText(
      text: TextSpan(
        style: DefaultTextStyle.of(context).style,
        children: [
          TextSpan(text: text.substring(0, idx)),
          TextSpan(
            text: text.substring(idx, idx + q.length),
            style: const TextStyle(
                backgroundColor: CupertinoColors.systemYellow,
                fontWeight: FontWeight.bold),
          ),
          TextSpan(text: text.substring(idx + q.length)),
        ],
      ),
    );
  }
}

class _GlassSidebar extends ConsumerWidget {
  const _GlassSidebar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nodes = ref.watch(allNodesProvider).valueOrNull ?? [];
    final tags = nodes.expand((n) => n.tags).toSet().toList()..sort();
    final starred = nodes.where((n) => n.isStarred).toList();

    return Drawer(
      backgroundColor: Colors.transparent,
      child: ClipRRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: Container(
            color: CupertinoColors.systemBackground
                .resolveFrom(context)
                .withOpacity(0.72),
            child: SafeArea(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 16),
                children: [
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    child: Text('浏览',
                        style: TextStyle(
                            fontSize: 22, fontWeight: FontWeight.bold)),
                  ),
                  ListTile(
                    leading: const Icon(CupertinoIcons.square_stack_3d_up),
                    title: const Text('所有节点'),
                    trailing: Text('${nodes.length}'),
                    onTap: () {
                      ref.read(focusedNodeIdProvider.notifier).state = null;
                      Navigator.pop(context);
                    },
                  ),
                  ListTile(
                    leading: const Icon(CupertinoIcons.star),
                    title: const Text('收藏 / 星标'),
                    trailing: Text('${starred.length}'),
                    onTap: () => Navigator.pop(context),
                  ),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(20, 20, 20, 8),
                    child: Text('标签筛选',
                        style: TextStyle(
                            fontSize: 13, color: CupertinoColors.systemGrey)),
                  ),
                  ...tags.map((t) => ListTile(
                        leading: const Icon(CupertinoIcons.tag),
                        title: Text('#$t'),
                        onTap: () {
                          Navigator.pop(context);
                          ref.read(searchQueryProvider.notifier).state = t;
                        },
                      )),
                  const Divider(height: 32),
                  ListTile(
                    leading: const Icon(CupertinoIcons.square_arrow_up),
                    title: const Text('导出 Markdown'),
                    onTap: () {
                      Navigator.pop(context);
                      ref.read(nodeRepositoryProvider).exportMarkdown();
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _KanbanView extends ConsumerWidget {
  const _KanbanView({required this.parentId});
  final int? parentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final childrenMap = ref.watch(childrenMapProvider);
    final children = childrenMap[parentId] ?? [];

    final Map<String, List<NoteNode>> groups = {};
    for (final n in children) {
      final key = n.tags.isEmpty ? '未分类' : n.tags.first;
      groups.putIfAbsent(key, () => []).add(n);
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: groups.entries.map((entry) {
          return Container(
            width: 240,
            margin: const EdgeInsets.symmetric(horizontal: 6),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: CupertinoColors.secondarySystemGroupedBackground
                  .resolveFrom(context),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('# ${entry.key}',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                ...entry.value.map((n) => Card(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      child: ListTile(
                        dense: true,
                        title: Text(n.title.isEmpty ? '无标题' : n.title),
                        onTap: () => Navigator.of(context).push(
                          CupertinoPageRoute(
                              builder: (_) => EditorScreen(nodeId: n.id)),
                        ),
                      ),
                    )),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _MindMapView extends ConsumerWidget {
  const _MindMapView({required this.rootId});
  final int? rootId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final childrenMap = ref.watch(childrenMapProvider);
    final roots = rootId != null
        ? [
            for (final n in ref.watch(allNodesProvider).valueOrNull ?? [])
              if (n.id == rootId) n
          ]
        : childrenMap[null] ?? [];

    if (roots.isEmpty) {
      return const Center(child: Text('暂无内容可供绘制思维导图'));
    }

    return InteractiveViewer(
      minScale: 0.3,
      maxScale: 2.5,
      constrained: false,
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: CustomPaint(
          painter: _MindMapPainter(
            roots: roots,
            childrenMap: childrenMap,
            textColor: CupertinoColors.label.resolveFrom(context),
            lineColor: CupertinoColors.systemGrey2.resolveFrom(context),
          ),
          size: const Size(2400, 1600),
        ),
      ),
    );
  }
}

class _MindMapPainter extends CustomPainter {
  _MindMapPainter({
    required this.roots,
    required this.childrenMap,
    required this.textColor,
    required this.lineColor,
  });

  final List<NoteNode> roots;
  final Map<int?, List<NoteNode>> childrenMap;
  final Color textColor;
  final Color lineColor;

  static const double levelWidth = 200;
  static const double rowHeight = 56;

  double _cursorY = 20;

  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = lineColor
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    for (final root in roots) {
      _drawNode(canvas, root, depth: 0, linePaint: linePaint);
    }
  }

  double _drawNode(Canvas canvas, NoteNode node,
      {required int depth, required Paint linePaint}) {
    final children = childrenMap[node.id] ?? [];
    final x = 20.0 + depth * levelWidth;

    late double y;
    if (children.isEmpty) {
      y = _cursorY;
      _cursorY += rowHeight;
    } else {
      final childYs = <double>[];
      for (final child in children) {
        childYs.add(_drawNode(canvas, child, depth: depth + 1, linePaint: linePaint));
      }
      y = (childYs.first + childYs.last) / 2;
      for (final childY in childYs) {
        final path = Path()
          ..moveTo(x + 90, y)
          ..cubicTo(x + 90 + levelWidth / 2, y, x + levelWidth - 20,
              childY, x + levelWidth, childY);
        canvas.drawPath(path, linePaint);
      }
    }

    _paintNodeBox(canvas, node, x, y);
    return y;
  }

  void _paintNodeBox(Canvas canvas, NoteNode node, double x, double y) {
    final textPainter = TextPainter(
      text: TextSpan(
        text: node.title.isEmpty ? '无标题' : node.title,
        style: TextStyle(color: textColor, fontSize: 13),
      ),
      maxLines: 1,
      ellipsis: '…',
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: 150);

    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(x, y - 18, 180, 36),
      const Radius.circular(10),
    );
    canvas.drawRRect(
        rect,
        Paint()
          ..color = textColor.withOpacity(0.06)
          ..style = PaintingStyle.fill);
    canvas.drawRRect(
        rect,
        Paint()
          ..color = textColor.withOpacity(0.25)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1);
    textPainter.paint(canvas, Offset(x + 12, y - textPainter.height / 2));
  }

  @override
  bool shouldRepaint(covariant _MindMapPainter oldDelegate) => true;
}
