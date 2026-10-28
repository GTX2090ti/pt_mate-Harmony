import 'package:flutter/material.dart';

import '../services/downloader/downloader_config.dart';
import '../services/downloader/downloader_service.dart';
import '../services/downloader/qb_pref_schema.dart';
import '../utils/notification_helper.dart';
import 'pref_settings_page.dart';
import 'rss_auto_download_page.dart';

/// qBittorrent 服务器设置
///
/// 偏好分组（下载 / 连接 / 速度 / BitTorrent）由 [PrefSettingsPage] 骨架渲染；
/// RSS 与「分类 / 标签」不走 preferences，作为独立分区注入。
class QbServerSettingsPage extends StatelessWidget {
  const QbServerSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return PrefSettingsPage(
      typeLabel: 'qBittorrent',
      groups: qbPrefGroups,
      accepts: (config) => config is QbittorrentConfig,
      loadPreferences:
          (config, password) => DownloaderService.instance.getPreferences(
            config: config,
            password: password,
          ),
      savePreferences:
          (config, password, deltas) => DownloaderService.instance.setPreferences(
            config: config,
            password: password,
            deltas: deltas,
          ),
      extraSections: const {
        'rss': _QbRssSection.section,
        'categorytag': _QbCategoryTagSection.section,
      },
    );
  }
}

/// qB 的 RSS 分区（配置在服务端，本页只做入口）
class _QbRssSection extends StatelessWidget {
  const _QbRssSection();

  static Widget section(DownloaderConfig config, String password) =>
      const _QbRssSection();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ListTile(
          dense: true,
          leading: const Icon(Icons.rss_feed),
          title: const Text('订阅源与自动下载规则'),
          subtitle: const Text('在 RSS 页管理订阅源、刷新与自动下载规则'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const RssAutoDownloadPage()),
            );
          },
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '提示：qBittorrent 的 RSS 解析配置保存在服务端，本页面不直接修改。',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ),
        ),
      ],
    );
  }
}

/// qB 的分类 / 标签管理分区
///
/// 分区自身持有列表状态：卡片折叠时不在渲染树上，展开才拉取。
class _QbCategoryTagSection extends StatefulWidget {
  const _QbCategoryTagSection({required this.config, required this.password});

  static Widget section(DownloaderConfig config, String password) =>
      _QbCategoryTagSection(config: config, password: password);

  final DownloaderConfig config;
  final String password;

  @override
  State<_QbCategoryTagSection> createState() => _QbCategoryTagSectionState();
}

class _QbCategoryTagSectionState extends State<_QbCategoryTagSection> {
  Map<String, String> _categories = const {};
  List<String> _tags = const [];
  bool _loading = false;
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
      final categories = await DownloaderService.instance.getCategoryDetails(
        config: widget.config,
        password: widget.password,
      );
      final tags = await DownloaderService.instance.getTags(
        config: widget.config,
        password: widget.password,
      );
      if (!mounted) return;
      setState(() {
        _categories = categories;
        _tags = tags;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '加载失败：$e';
        _loading = false;
      });
    }
  }

  Future<String?> _promptText(
    String title, {
    String? initial,
    String? hint,
    bool allowEmpty = false,
  }) async {
    final controller = TextEditingController(text: initial ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            hintText: hint,
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
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (result == null) return null;
    if (result.isEmpty && !allowEmpty) return null;
    return result;
  }

  Future<void> _run(
    Future<void> Function() body,
    String okMessage,
  ) async {
    try {
      await body();
      if (!mounted) return;
      if (okMessage.isNotEmpty) NotificationHelper.showInfo(context, okMessage);
      await _load();
    } catch (e) {
      if (!mounted) return;
      NotificationHelper.showError(context, '操作失败：$e');
    }
  }

  Future<void> _addAction() async {
    final kind = await showDialog<String>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('新增'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(dialogContext, 'category'),
            child: const Text('分类'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(dialogContext, 'tag'),
            child: const Text('标签'),
          ),
        ],
      ),
    );
    if (kind == null || !mounted) return;
    if (kind == 'category') {
      final name = await _promptText('新增分类', hint: '分类名称');
      if (name == null) return;
      final savePath = await _promptText(
        '「$name」的保存路径',
        hint: '留空表示使用默认保存路径',
      );
      await _run(
        () => DownloaderService.instance.createCategory(
          config: widget.config,
          password: widget.password,
          category: name,
          savePath: savePath,
        ),
        '分类已创建',
      );
    } else {
      final name = await _promptText('新增标签', hint: '标签名称');
      if (name == null) return;
      await _run(
        () => DownloaderService.instance.createTags(
          config: widget.config,
          password: widget.password,
          tags: [name],
        ),
        '标签已创建',
      );
    }
  }

  Future<void> _editCategoryPath(String category, String currentPath) async {
    final newPath = await _promptText(
      '「$category」的保存路径',
      initial: currentPath,
      hint: '留空表示使用默认保存路径',
      allowEmpty: true,
    );
    if (newPath == null || newPath == currentPath) return;
    await _run(
      () => DownloaderService.instance.setCategorySavePath(
        config: widget.config,
        password: widget.password,
        category: category,
        savePath: newPath,
      ),
      newPath.isEmpty ? '已恢复默认保存路径' : '保存路径已更新',
    );
  }

  /// 统计分类/标签下受影响的种子数量；查询失败返回 null（不阻断删除流程）
  Future<int?> _countAffectedTorrents(String kind, String name) async {
    if (!mounted) return null;
    final progress = showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => const AlertDialog(
        content: Row(
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 16),
            Expanded(child: Text('正在统计受影响的种子…')),
          ],
        ),
      ),
    );
    int? count;
    try {
      final tasks = await DownloaderService.instance.getTasks(
        config: widget.config,
        password: widget.password,
      );
      count = tasks
          .where(
            (task) => kind == '分类'
                ? task.category == name
                : task.tags.contains(name),
          )
          .length;
    } catch (_) {
      count = null;
    }
    if (mounted) Navigator.of(context, rootNavigator: true).pop();
    await progress;
    return count;
  }

  Future<void> _delete(String kind, String name) async {
    // 删除前先统计受影响的种子，避免误操作
    final affected = await _countAffectedTorrents(kind, name);
    if (!mounted) return;
    final message = kind == '分类'
        ? affected == null
            ? '确定删除分类"$name"吗？删除后该分类下的种子将变为未分类，文件不会被删除。'
            : '分类"$name"下有 $affected 个种子，删除后这些种子将变为未分类，文件不会被删除。'
        : affected == null
        ? '确定删除标签"$name"吗？删除后将从种子移除该标签，种子不会被删除。'
        : '标签"$name"下有 $affected 个种子，删除后将从这些种子移除该标签，种子不会被删除。';
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('删除$kind'),
        content: Text('$message\n\n此操作不可撤销，确认删除？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            child: const Text('确认删除'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    await _run(
      () => kind == '分类'
          ? DownloaderService.instance.deleteCategory(
              config: widget.config,
              password: widget.password,
              category: name,
            )
          : DownloaderService.instance.deleteTags(
              config: widget.config,
              password: widget.password,
              tags: [name],
            ),
      kind == '分类' ? '分类已删除' : '标签已删除',
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Text(
              _error!,
              style: const TextStyle(fontSize: 12, color: Colors.red),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('重试'),
            ),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_categories.isEmpty && _tags.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              '暂无分类与标签',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ),
        if (_categories.isNotEmpty)
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('分类', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
        for (final entry in _categories.entries)
          ListTile(
            dense: true,
            leading: const Icon(Icons.folder_outlined, size: 20),
            title: Text(entry.key),
            subtitle: Text(
              entry.value.isEmpty ? '默认路径' : entry.value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 20),
                  tooltip: '修改保存路径',
                  onPressed: () => _editCategoryPath(entry.key, entry.value),
                ),
                IconButton(
                  icon: const Icon(
                    Icons.delete_outline,
                    size: 20,
                    color: Colors.red,
                  ),
                  tooltip: '删除分类',
                  onPressed: () => _delete('分类', entry.key),
                ),
              ],
            ),
            onTap: () => _editCategoryPath(entry.key, entry.value),
          ),
        if (_tags.isNotEmpty)
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('标签', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
        for (final tag in _tags)
          ListTile(
            dense: true,
            leading: const Icon(Icons.label_outline, size: 20),
            title: Text(tag),
            trailing: IconButton(
              icon: const Icon(
                Icons.delete_outline,
                size: 20,
                color: Colors.red,
              ),
              tooltip: '删除标签',
              onPressed: () => _delete('标签', tag),
            ),
          ),
        ListTile(
          dense: true,
          leading: const Icon(Icons.add),
          title: const Text('新增分类 / 标签'),
          textColor: Theme.of(context).colorScheme.primary,
          onTap: _addAction,
        ),
        const SizedBox(height: 4),
      ],
    );
  }
}
