import 'package:flutter/material.dart';

import '../services/downloader/downloader_config.dart';
import '../services/downloader/downloader_service.dart';
import '../utils/notification_helper.dart';

/// 标签选择对话框：多选服务器已有标签，支持就地新建
///
/// 返回要添加的标签列表（空列表 = 一个都没选）；取消返回 null。
class TagPickerDialog extends StatefulWidget {
  final DownloaderConfig config;
  final String password;

  const TagPickerDialog({
    super.key,
    required this.config,
    required this.password,
  });

  static Future<List<String>?> show(
    BuildContext context, {
    required DownloaderConfig config,
    required String password,
  }) {
    return showDialog<List<String>>(
      context: context,
      builder: (_) =>
          TagPickerDialog(config: config, password: password),
    );
  }

  @override
  State<TagPickerDialog> createState() => _TagPickerDialogState();
}

class _TagPickerDialogState extends State<TagPickerDialog> {
  List<String> _tags = [];
  final Set<String> _picked = {};
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final tags = await DownloaderService.instance.getTags(
        config: widget.config,
        password: widget.password,
      );
      if (!mounted) return;
      final keep = _picked.where(tags.contains).toSet();
      setState(() {
        _tags = tags;
        _picked
          ..clear()
          ..addAll(keep);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '加载标签失败：$e';
        _loading = false;
      });
    }
  }

  Future<void> _createTag() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('新建标签'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: '标签名称',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('创建'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    try {
      await DownloaderService.instance.createTags(
        config: widget.config,
        password: widget.password,
        tags: [name],
      );
      if (!mounted) return;
      NotificationHelper.showInfo(context, '标签已创建');
      await _load();
      if (!mounted) return;
      setState(() => _picked.add(name));
    } catch (e) {
      if (!mounted) return;
      NotificationHelper.showError(context, '创建失败：$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Text(_picked.isEmpty ? '选择标签' : '已选 ${_picked.length} 个标签'),
      content: SizedBox(
        width: 360,
        height: 340,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(_error!, style: const TextStyle(color: Colors.red)),
                    const SizedBox(height: 16),
                    ElevatedButton(onPressed: _load, child: const Text('重试')),
                  ],
                ),
              )
            : ListView(
                children: [
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final tag in _picked)
                        InputChip(
                          label: Text(tag),
                          onDeleted: () => setState(() => _picked.remove(tag)),
                        ),
                    ],
                  ),
                  if (_picked.isNotEmpty) const SizedBox(height: 8),
                  if (_tags.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                        child: Text('服务器暂无标签', style: TextStyle(color: scheme.outline)),
                      ),
                    ),
                  ..._tags.map(
                    (tag) => CheckboxListTile(
                      dense: true,
                      value: _picked.contains(tag),
                      title: Text(tag, style: const TextStyle(fontSize: 14)),
                      onChanged: (value) {
                        setState(() {
                          if (value == true) {
                            _picked.add(tag);
                          } else {
                            _picked.remove(tag);
                          }
                        });
                      },
                    ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.add),
                    title: const Text('新建标签…'),
                    textColor: scheme.primary,
                    onTap: _createTag,
                  ),
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _picked.toList()),
          child: const Text('添加'),
        ),
      ],
    );
  }
}
