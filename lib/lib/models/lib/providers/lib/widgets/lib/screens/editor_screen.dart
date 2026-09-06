import 'dart:async';
import 'dart:convert';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import '../models/node.dart';
import '../providers/node_provider.dart';

/// EditorScreen —— 单个节点的富文本编辑页
class EditorScreen extends ConsumerStatefulWidget {
  const EditorScreen({super.key, required this.nodeId});
  final int nodeId;

  @override
  ConsumerState<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends ConsumerState<EditorScreen> {
  late quill.QuillController _controller;
  late TextEditingController _titleController;
  Timer? _debounce;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _controller = quill.QuillController.basic();
    _titleController = TextEditingController();
    _loadNode();
    _controller.document.changes.listen((event) => _onContentChanged());
  }

  Future<void> _loadNode() async {
    final isar = await ref.read(isarProvider.future);
    final node = await isar.noteNodes.get(widget.nodeId);
    if (node == null || !mounted) return;
    _titleController.text = node.title;
    try {
      final doc = quill.Document.fromJson(jsonDecode(node.contentJson));
      _controller = quill.QuillController(
        document: doc,
        selection: const TextSelection.collapsed(offset: 0),
      );
    } catch (_) {
      _controller = quill.QuillController.basic();
    }
    _controller.document.changes.listen((event) => _onContentChanged());
    setState(() => _loaded = true);
  }

  void _onContentChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), _save);

    final text = _controller.document.toPlainText();
    final selection = _controller.selection;
    if (selection.baseOffset >= 2 &&
        selection.baseOffset <= text.length &&
        text.substring(selection.baseOffset - 2, selection.baseOffset) ==
            '[[') {
      _openLinkSearch();
    }
  }

  Future<void> _save() async {
    final repo = ref.read(nodeRepositoryProvider);
    final deltaJson = jsonEncode(_controller.document.toDelta().toJson());
    await repo.updateContent(
      widget.nodeId,
      title: _titleController.text,
      contentJson: deltaJson,
    );
  }

  Future<void> _openLinkSearch() async {
    final selected = await showCupertinoModalPopup<NoteNode>(
      context: context,
      builder: (_) => _LinkSearchSheet(excludeId: widget.nodeId),
    );
    if (selected == null) return;
    final offset = _controller.selection.baseOffset;
    final linkText = 'id:${selected.id}|${selected.title}]]';
    _controller.document.insert(offset, linkText);
    _controller.updateSelection(
      TextSelection.collapsed(offset: offset + linkText.length),
      quill.ChangeSource.local,
    );
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _save();
    _controller.dispose();
    _titleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const CupertinoPageScaffold(
        child: Center(child: CupertinoActivityIndicator()),
      );
    }

    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: _BreadcrumbPath(nodeId: widget.nodeId),
      ),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: CupertinoTextField(
                controller: _titleController,
                placeholder: '标题',
                decoration: null,
                style: const TextStyle(
                    fontSize: 24, fontWeight: FontWeight.bold),
                onChanged: (_) => _onContentChanged(),
              ),
            ),
            Expanded(
              child: GestureDetector(
                onTap: () => FocusScope.of(context).requestFocus(),
                behavior: HitTestBehavior.translucent,
                child: quill.QuillEditor.basic(
                  controller: _controller,
                  config: const quill.QuillEditorConfig(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    placeholder: '开始输入…（输入 [[ 可插入双向链接）',
                  ),
                ),
              ),
            ),
            _BacklinksPanel(nodeId: widget.nodeId),
            _buildToolbar(),
          ],
        ),
      ),
    );
  }

  Widget _buildToolbar() {
    return Container(
      decoration: BoxDecoration(
        color: CupertinoColors.secondarySystemBackground
            .resolveFrom(context),
        border: Border(
          top: BorderSide(color: CupertinoColors.separator.resolveFrom(context)),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: quill.QuillSimpleToolbar(
        controller: _controller,
        config: const quill.QuillSimpleToolbarConfig(
          showFontFamily: false,
          showFontSize: false,
          showColorButton: false,
          showBackgroundColorButton: false,
          showClearFormat: false,
          showAlignmentButtons: false,
          showHeaderStyle: false,
          showListNumbers: false,
          showQuote: true,
          showCodeBlock: true,
          showListBullets: true,
          showListCheck: true,
          showBoldButton: true,
          showItalicButton: true,
          showUnderLineButton: true,
          showLink: false,
          showSearchButton: false,
          multiRowsDisplay: false,
        ),
      ),
    );
  }
}

class _BreadcrumbPath extends ConsumerWidget {
  const _BreadcrumbPath({required this.nodeId});
  final int nodeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nodes = ref.watch(allNodesProvider).valueOrNull ?? [];
    final byId = {for (final n in nodes) n.id: n};

    final chain = <NoteNode>[];
    int? cursor = nodeId;
    while (cursor != null && byId.containsKey(cursor)) {
      chain.add(byId[cursor]!);
      cursor = byId[cursor]!.parentId;
    }
    final path = chain.reversed.toList();

    if (path.isEmpty) return const Text('笔记');

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (int i = 0; i < path.length; i++) ...[
            if (i > 0)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4),
                child: Icon(CupertinoIcons.chevron_right,
                    size: 12, color: CupertinoColors.systemGrey),
              ),
            Text(
              path[i].title.isEmpty ? '无标题' : path[i].title,
              style: TextStyle(
                fontSize: 14,
                fontWeight:
                    i == path.length - 1 ? FontWeight.w600 : FontWeight.normal,
                color: i == path.length - 1
                    ? CupertinoColors.label.resolveFrom(context)
                    : CupertinoColors.systemGrey,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _BacklinksPanel extends ConsumerWidget {
  const _BacklinksPanel({required this.nodeId});
  final int nodeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final backlinks = ref.watch(backlinksProvider(nodeId));
    if (backlinks.isEmpty) return const SizedBox.shrink();

    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        title: Text('反向链接 (${backlinks.length})'),
        childrenPadding: const EdgeInsets.only(bottom: 8),
        children: backlinks
            .map((n) => ListTile(
                  dense: true,
                  leading: const Icon(CupertinoIcons.link, size: 16),
                  title: Text(n.title.isEmpty ? '无标题' : n.title),
                  onTap: () => Navigator.of(context).pushReplacement(
                    CupertinoPageRoute(
                        builder: (_) => EditorScreen(nodeId: n.id)),
                  ),
                ))
            .toList(),
      ),
    );
  }
}

class _LinkSearchSheet extends ConsumerStatefulWidget {
  const _LinkSearchSheet({required this.excludeId});
  final int excludeId;

  @override
  ConsumerState<_LinkSearchSheet> createState() => _LinkSearchSheetState();
}

class _LinkSearchSheetState extends ConsumerState<_LinkSearchSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final nodes = ref.watch(allNodesProvider).valueOrNull ?? [];
    final results = nodes
        .where((n) =>
            n.id != widget.excludeId &&
            n.title.toLowerCase().contains(_query.toLowerCase()))
        .take(30)
        .toList();

    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: const Text('链接到节点'),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: CupertinoSearchTextField(
                autofocus: true,
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: results.length,
                itemBuilder: (context, i) {
                  final n = results[i];
                  return ListTile(
                    title: Text(n.title.isEmpty ? '无标题' : n.title),
                    onTap: () => Navigator.pop(context, n),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
