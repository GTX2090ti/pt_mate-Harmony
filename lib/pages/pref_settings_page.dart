import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/downloader/downloader_config.dart';
import '../services/downloader/pref_schema.dart';
import '../services/storage/storage_service.dart';
import '../utils/notification_helper.dart';

/// 「服务器设置」页骨架：分组手风琴 + 脏值统计 + 单字段编辑。
///
/// 各下载器的偏好键空间不一样（qB 是 `/app/preferences`，Deluge 是
/// `core.get_config`），所以页面只认 [PrefGroup] 字段表和一对读写回调，
/// 具体下载器给出薄页面（见 qb_server_settings_page / deluge_server_settings_page）。
class PrefSettingsPage extends StatefulWidget {
  const PrefSettingsPage({
    super.key,
    required this.typeLabel,
    required this.groups,
    required this.accepts,
    required this.loadPreferences,
    required this.savePreferences,
    this.extraSections = const {},
    this.initialExpanded = const ['download'],
  });

  /// 下载器名称，用于「仅支持 xxx」这类提示与保存按钮文案
  final String typeLabel;
  final List<PrefGroup> groups;

  /// 当前默认下载器是否适用本字段表
  final bool Function(DownloaderConfig config) accepts;
  final Future<Map<String, dynamic>> Function(
    DownloaderConfig config,
    String password,
  )
  loadPreferences;
  final Future<void> Function(
    DownloaderConfig config,
    String password,
    Map<String, dynamic> deltas,
  )
  savePreferences;

  /// 不走偏好读写的分组（如 qB 的 RSS、分类与标签），按 group.routeHint 索引
  final Map<String, Widget Function(DownloaderConfig config, String password)>
  extraSections;
  final List<String> initialExpanded;

  @override
  State<PrefSettingsPage> createState() => _PrefSettingsPageState();
}

class _PrefSettingsPageState extends State<PrefSettingsPage> {
  DownloaderConfig? _config;
  String? _password;
  Map<String, dynamic> _prefs = const {};
  final Map<String, dynamic> _values = {};

  bool _loading = true;
  bool _saving = false;
  String? _error;

  late final Set<String> _expanded = widget.initialExpanded.toSet();

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
      if (!widget.accepts(config)) {
        throw Exception('服务器设置仅支持 ${widget.typeLabel}');
      }
      final pwd = await StorageService.instance.loadDownloaderPassword(
        config.id,
      );
      if ((pwd ?? '').isEmpty) throw Exception('请先保存下载器密码');

      final prefs = await widget.loadPreferences(config, pwd!);
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

  int _dirtyCountIn(PrefGroup group) {
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
      await widget.savePreferences(config, pwd!, deltas);
      final fresh = await widget.loadPreferences(config, pwd);
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

  void _discard() {
    setState(() {
      _values
        ..clear()
        ..addAll(_prefs);
    });
  }

  // ============================================================
  // 字段编辑
  // ============================================================

  Future<void> _editField(ResolvedPrefField resolved) async {
    if (resolved.field.options != null) {
      await _pickOption(resolved);
      return;
    }
    final multiline = resolved.field.kind == PrefKind.stringList;
    final controller = TextEditingController(text: prefValueToText(resolved));
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
                keyboardType: resolved.field.kind == PrefKind.number
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

  Future<void> _pickOption(ResolvedPrefField resolved) async {
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
                    const <PrefOption>[])
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
  // 渲染
  // ============================================================

  void _toggleSection(String id) {
    setState(() {
      if (_expanded.contains(id)) {
        _expanded.remove(id);
      } else {
        _expanded.add(id);
      }
    });
  }

  Widget _section({
    required PrefGroup group,
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

  Widget _fieldRow(ResolvedPrefField resolved) {
    final value = _values[resolved.key];
    if (resolved.field.kind == PrefKind.boolToggle) {
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

  Widget _groupBody(PrefGroup group) {
    final resolved = resolveGroupFields(group, _prefs);
    if (resolved.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          '当前 ${widget.typeLabel} 未提供该分组的可配置项',
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
      );
    }
    return Column(
      children: [for (final r in resolved) _fieldRow(r)],
    );
  }

  Widget _bodyFor(PrefGroup group) {
    final hint = group.routeHint;
    final config = _config;
    final password = _password;
    final builder = hint == null ? null : widget.extraSections[hint];
    if (builder != null && config != null && password != null) {
      return builder(config, password);
    }
    return _groupBody(group);
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
                for (final group in widget.groups)
                  _section(group: group, children: [_bodyFor(group)]),
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
                    TextButton(
                      onPressed: _saving ? null : _discard,
                      child: const Text('放弃'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: _saving ? null : _save,
                      child: Text('保存到 ${widget.typeLabel}'),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
