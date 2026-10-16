import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/downloader/downloader_config.dart';
import '../services/downloader/downloader_service.dart';
import '../services/downloader/qb_pref_schema.dart';
import '../services/storage/storage_service.dart';
import '../utils/notification_helper.dart';
import 'rss_auto_download_page.dart';

/// qBittorrent 服务器设置
///
/// 分组：下载 / 连接 / 速度 / BitTorrent / RSS / 分类与标签。
/// 偏好字段以实机 `/app/preferences` 返回的键为准，版本没有的键不显示也不写入。
class QbServerSettingsPage extends StatefulWidget {
  const QbServerSettingsPage({super.key});

  @override
  State<QbServerSettingsPage> createState() => _QbServerSettingsPageState();
}

class _QbServerSettingsPageState extends State<QbServerSettingsPage> {
  DownloaderConfig? _config;
  String? _password;
  Map<String, dynamic> _prefs = const {};
  final Map<String, dynamic> _values = {};

  bool _loading = true;
  bool _saving = false;
  String? _error;

  final Set<String> _expanded = {'download'};

  Map<String, String> _categories = const {};
  List<String> _tags = const [];
  bool _catTagLoading = false;
  String? _catTagError;

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
      final defId = await StorageService.instance.loadDefaultDownloaderId();
      if (defId == null) throw Exception('尚未设置默认下载器');
      final configs = await StorageService.instance.loadDownloaderConfigs();
      final configMap = configs.firstWhere(
        (e) => e['id'] == defId,
        orElse: () =>
            configs.isNotEmpty ? configs.first : throw Exception('未找到默认下载器'),
      );
      final config = DownloaderConfig.fromJson(configMap);
      if (config is! QbittorrentConfig) {
        throw Exception('服务器设置仅支持 qBittorrent');
      }
      final pwd = await StorageService.instance.loadDownloaderPassword(
        config.id,
      );
      if ((pwd ?? '').isEmpty) throw Exception('请先保存下载器密码');

      final prefs = await DownloaderService.instance.getPreferences(
        config: config,
        password: pwd!,
      );
      if (!mounted) return;
      setState(() {
        _config = config;
        _password = pwd;
        _prefs = prefs;
        _values
          ..clear()
          ..addAll(prefs);
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

  bool _same(dynamic a, dynamic b) {
    if (a is List && b is List) return listEquals(a, b);
    return a == b;
  }

  List<String> get _dirtyKeys {
    final result = <String>[];
    for (final entry in _values.entries) {
      if (!_same(entry.value, _prefs[entry.key])) result.add(entry.key);
    }
    return result;
  }

  int _dirtyCountIn(QbPrefGroup group) {
    final keys = group.fields
        .map((f) => f.keys.firstWhere(_prefs.containsKey, orElse: () => ''))
        .toSet();
    return _dirtyKeys.where(keys.contains).length;
  }

  Future<void> _save() async {
    final config = _config;
    final pwd = _password;
    if (config == null || (pwd ?? '').isEmpty) return;
    final deltas = <String, dynamic>{};
    for (final key in _dirtyKeys) {
      deltas[key] = _values[key];
    }
    if (deltas.isEmpty) return;
    setState(() => _saving = true);
    try {
      await DownloaderService.instance.setPreferences(
        config: config,
        password: pwd!,
        deltas: deltas,
      );
      final fresh = await DownloaderService.instance.getPreferences(
        config: config,
        password: pwd,
      );
      if (!mounted) return;
      setState(() {
        _prefs = fresh;
        _values
          ..clear()
          ..addAll(fresh);
      });
      NotificationHelper.showInfo(context, '已保存 ${deltas.length} 项设置');
    } catch (e) {
      if (!mounted) return;
      NotificationHelper.showError(context, '保存失败：$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _discard() async {
    setState(() {
      _values
        ..clear()
        ..addAll(_prefs);
    });
  }

  // ============================================================
  // 字段编辑
  // ============================================================

  Future<void> _editField(ResolvedQbPrefField resolved) async {
    if (resolved.field.options != null) {
      await _pickOption(resolved);
      return;
    }
    final multiline = resolved.field.kind == QbPrefKind.stringList;
    final controller = TextEditingController(
      text: prefValueToText(resolved),
    );
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(resolved.field.label),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (resolved.field.hint != null) ...[
                Text(
                  resolved.field.hint!,
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 8),
              ],
              TextField(
                controller: controller,
                autofocus: true,
                maxLines: multiline ? 6 : 1,
                keyboardType: resolved.field.kind == QbPrefKind.number
                    ? const TextInputType.numberWithOptions(
                        signed: true,
                        decimal: true,
                      )
                    : TextInputType.text,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() {
      _values[resolved.key] = prefValueFromInput(resolved, controller.text);
    });
  }

  Future<void> _pickOption(ResolvedQbPrefField resolved) async {
    final current = '${_values[resolved.key]}';
    final picked = await showDialog<String>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text(resolved.field.label),
        children: [
          RadioGroup<String>(
            groupValue: current,
            onChanged: (value) {
              if (value != null) Navigator.pop(dialogContext, value);
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final option in resolved.field.options ??
                    const <QbPrefOption>[])
                  ListTile(
                    dense: true,
                    title: Text(option.label),
                    leading: Radio<String>(value: option.value),
                    onTap: () => Navigator.pop(dialogContext, option.value),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
    if (picked == null) return;
    setState(() {
      _values[resolved.key] = prefValueFromInput(resolved, picked);
    });
  }

  // ============================================================
  // 分类 / 标签
  // ============================================================

  Future<void> _loadCategoriesAndTags() async {
    final config = _config;
    final pwd = _password;
    if (config == null || (pwd ?? '').isEmpty) return;
    setState(() {
      _catTagLoading = true;
      _catTagError = null;
    });
    try {
      final categories = await DownloaderService.instance.getCategoryDetails(
        config: config,
        password: pwd!,
      );
      final tags = await DownloaderService.instance.getTags(
        config: config,
        password: pwd,
      );
      if (!mounted) return;
      setState(() {
        _categories = categories;
        _tags = tags;
        _catTagLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _catTagError = '加载失败：$e';
        _catTagLoading = false;
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
            onPressed: () => Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (result == null) return null;
    if (result.isEmpty && !allowEmpty) return null;
    return result;
  }

  Future<void> _runAsync(Future<void> Function() body, String okMessage) async {
    try {
      await body();
      if (!mounted) return;
      if (okMessage.isNotEmpty) NotificationHelper.showInfo(context, okMessage);
      await _loadCategoriesAndTags();
    } catch (e) {
      if (!mounted) return;
      NotificationHelper.showError(context, '操作失败：$e');
    }
  }

  Future<void> _addAction() async {
    final config = _config;
    final pwd = _password;
    if (config == null || (pwd ?? '').isEmpty) return;
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
      await _runAsync(
        () => DownloaderService.instance.createCategory(
          config: config,
          password: pwd!,
          category: name,
          savePath: savePath,
        ),
        '分类已创建',
      );
    } else {
      final name = await _promptText('新增标签', hint: '标签名称');
      if (name == null) return;
      await _runAsync(
        () => DownloaderService.instance.createTags(
          config: config,
          password: pwd!,
          tags: [name],
        ),
        '标签已创建',
      );
    }
  }

  Future<void> _editCategoryPath(String category, String currentPath) async {
    final config = _config;
    final pwd = _password;
    if (config == null || (pwd ?? '').isEmpty) return;
    final newPath = await _promptText(
      '「$category」的保存路径',
      initial: currentPath,
      hint: '留空表示使用默认保存路径',
      allowEmpty: true,
    );
    if (newPath == null || newPath == currentPath) return;
    await _runAsync(
      () => DownloaderService.instance.setCategorySavePath(
        config: config,
        password: pwd!,
        category: category,
        savePath: newPath,
      ),
      newPath.isEmpty ? '已恢复默认保存路径' : '保存路径已更新',
    );
  }

  Future<void> _deleteCategory(String name) async {
    final config = _config;
    final pwd = _password;
    if (config == null || (pwd ?? '').isEmpty) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除分类'),
        content: Text('确定删除分类"$name"吗？不会删除已归类任务的文件。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    await _runAsync(
      () => DownloaderService.instance.deleteCategory(
        config: config,
        password: pwd!,
        category: name,
      ),
      '分类已删除',
    );
  }

  Future<void> _deleteTag(String name) async {
    final config = _config;
    final pwd = _password;
    if (config == null || (pwd ?? '').isEmpty) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除标签'),
        content: Text('确定删除标签"$name"吗？不会删除种子本身。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    await _runAsync(
      () => DownloaderService.instance.deleteTags(
        config: config,
        password: pwd!,
        tags: [name],
      ),
      '标签已删除',
    );
  }

  // ============================================================
  // 渲染
  // ============================================================

  void _toggleSection(String id, {bool? open}) {
    setState(() {
      if (open == true) {
        _expanded.add(id);
      } else if (_expanded.contains(id)) {
        _expanded.remove(id);
      } else {
        _expanded.add(id);
      }
    });
    if (id == 'categorytag' && _expanded.contains(id) && !_catTagLoading) {
      _loadCategoriesAndTags();
    }
  }

  Widget _section({
    required QbPrefGroup group,
    required List<Widget> children,
  }) {
    final expanded = _expanded.contains(group.id);
    final dirty = group.fields.isEmpty ? 0 : _dirtyCountIn(group);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: Theme.of(context).colorScheme.outlineVariant.withValues(
            alpha: 0.4,
          ),
        ),
      ),
      child: Column(
        children: [
          ListTile(
            leading: Icon(group.icon),
            title: Text(group.title),
            subtitle: Text(
              dirty > 0 ? '$dirty 项待保存' : (group.summary ?? ''),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (dirty > 0)
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
                Icon(expanded ? Icons.expand_less : Icons.expand_more),
              ],
            ),
            onTap: () => _toggleSection(group.id),
          ),
          if (expanded)
            Column(
              children: [
                const Divider(height: 1),
                ...children,
              ],
            ),
        ],
      ),
    );
  }

  Widget _fieldRow(ResolvedQbPrefField resolved) {
    final value = _values[resolved.key];
    if (resolved.field.kind == QbPrefKind.boolToggle) {
      return SwitchListTile(
        dense: true,
        title: Text(resolved.field.label),
        subtitle: resolved.field.hint == null
            ? null
            : Text(resolved.field.hint!, style: const TextStyle(fontSize: 12)),
        value: value == true,
        onChanged: (v) => setState(() => _values[resolved.key] = v),
      );
    }
    final shown = describePrefValue(resolved.field, value);
    final hint = resolved.field.hint;
    return ListTile(
      dense: true,
      title: Text(resolved.field.label),
      subtitle: Text(
        hint == null ? shown : '$shown · $hint',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: const Icon(Icons.edit_outlined, size: 18),
      onTap: () => _editField(resolved),
    );
  }

  Widget _prefGroupBody(QbPrefGroup group) {
    final resolved = resolveGroupFields(group, _prefs);
    if (resolved.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text(
          '当前 qBittorrent 版本未提供该分组的可配置项',
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ),
      );
    }
    return Column(
      children: [for (final r in resolved) _fieldRow(r)],
    );
  }

  Widget _rssBody() {
    return Column(
      children: [
        ListTile(
          dense: true,
          leading: const Icon(Icons.rss_feed),
          title: const Text('订阅源与自动下载规则'),
          subtitle: const Text('在 RSS 页管理订阅源、刷新与自动下载规则'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () {
            Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const RssAutoDownloadPage()));
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

  Widget _catTagBody() {
    if (_catTagLoading) {
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
    if (_catTagError != null) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Text(
              _catTagError!,
              style: const TextStyle(fontSize: 12, color: Colors.red),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _loadCategoriesAndTags,
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
                  icon: const Icon(Icons.delete_outline, size: 20, color: Colors.red),
                  tooltip: '删除分类',
                  onPressed: () => _deleteCategory(entry.key),
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
              icon: const Icon(Icons.delete_outline, size: 20, color: Colors.red),
              tooltip: '删除标签',
              onPressed: () => _deleteTag(tag),
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

  @override
  Widget build(BuildContext context) {
    final dirtyCount = _dirtyKeys.length;
    return Scaffold(
      appBar: AppBar(
        title: const Text('服务器设置'),
        actions: [
          IconButton(
            tooltip: '重新读取',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.warning_amber_rounded, size: 40),
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 13),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton(onPressed: _load, child: const Text('重试')),
                  ],
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.only(top: 8, bottom: 24),
              children: [
                for (final group in qbPrefGroups)
                  if (group.routeHint == 'rss')
                    _section(group: group, children: [_rssBody()])
                  else if (group.routeHint == 'categorytag')
                    _section(group: group, children: [_catTagBody()])
                  else
                    _section(group: group, children: [_prefGroupBody(group)]),
              ],
            ),
      bottomNavigationBar: (_loading || _error != null || dirtyCount == 0)
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _saving ? '正在保存…' : '$dirtyCount 项未保存',
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                    TextButton(onPressed: _saving ? null : _discard, child: const Text('放弃')),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: _saving ? null : _save,
                      child: const Text('保存到 qB'),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
