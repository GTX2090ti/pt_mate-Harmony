import 'dart:async';

import 'package:flutter/material.dart';

import '../services/downloader/downloader_config.dart';
import '../services/downloader/downloader_models.dart';
import '../services/downloader/downloader_service.dart';
import '../utils/format.dart';
import 'package:pt_mate/utils/notification_helper.dart';

/// 文件类型桶，供文件列表与选择页的筛查栏共用
enum _FileKind {
  video('视频', Icons.movie_outlined),
  image('图片', Icons.image_outlined),
  doc('文档', Icons.description_outlined),
  other('其他', Icons.more_horiz);

  const _FileKind(this.label, this.icon);

  final String label;
  final IconData icon;
}

// 与原先「只看视频」的扩展名口径保持一致（含 iso），避免两处判定打架
const Set<String> _videoExts = {
  'mp4', 'mkv', 'avi', 'mov', 'wmv', 'flv', 'ts', 'm4v',
  'webm', 'rmvb', 'mpg', 'mpeg', 'vob', 'iso',
};

const Set<String> _imageExts = {
  'jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp', 'heic', 'heif',
  'tif', 'tiff', 'svg', 'avif', 'ico', 'raw', 'cr2', 'nef',
};

const Set<String> _docExts = {
  'pdf', 'epub', 'mobi', 'azw', 'azw3', 'djvu', 'txt', 'doc',
  'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'chm', 'srt', 'ass',
  'ssa', 'sub', 'lrc', 'nfo', 'md',
};

/// 按扩展名归类；没有扩展名（目录项、无后缀文件）算「其他」
_FileKind _kindOf(String name) {
  final dot = name.lastIndexOf('.');
  if (dot <= 0 || dot == name.length - 1) return _FileKind.other;
  final ext = name.substring(dot + 1).toLowerCase();
  if (_videoExts.contains(ext)) return _FileKind.video;
  if (_imageExts.contains(ext)) return _FileKind.image;
  if (_docExts.contains(ext)) return _FileKind.doc;
  return _FileKind.other;
}

/// 任务文件视图
/// 对应 qBittorrent 客户端种子详情的"文件"标签，可嵌入 Tab 页
/// 显示文件列表，支持勾选下载/跳过文件（通过文件优先级实现）
class TorrentFilesView extends StatefulWidget {
  final String taskHash;
  final DownloaderConfig config;
  final String password;

  const TorrentFilesView({
    super.key,
    required this.taskHash,
    required this.config,
    required this.password,
  });

  @override
  State<TorrentFilesView> createState() => _TorrentFilesViewState();
}

class _TorrentFilesViewState extends State<TorrentFilesView>
    with AutomaticKeepAliveClientMixin {
  List<TorrentFile> _files = [];
  bool _loading = true;
  String? _error;
  bool _applying = false;

  // 文件标签页的搜索 / 排序 / 筛选状态
  String _query = '';
  int _sortKey = 4; // 0=优先级 1=进度 2=大小 3=名称 4=默认（原始顺序）
  bool _ascending = true;
  bool _videoOnly = false;
  final Set<int> _busyIndexes = {};
  final TextEditingController _searchController = TextEditingController();

  static const List<String> _sortLabels = ['优先级', '进度', '文件大小', '名称', '默认'];

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final files = await DownloaderService.instance.getTorrentFiles(
        config: widget.config,
        password: widget.password,
        hash: widget.taskHash,
      );
      if (!mounted) return;
      setState(() {
        _files = files;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        if (!silent) _error = '加载文件失败：$e';
        _loading = false;
      });
    }
  }

  /// 打开文件选择对话框：勾选要下载的文件，其余跳过
  Future<void> _openFileSelector() async {
    final files = _files;
    if (files.isEmpty) return;
    final selected = <int>{};
    for (final f in files) {
      if (f.selected) selected.add(f.index);
    }

    // 全屏选择页
    final result = await Navigator.of(context).push<Set<int>>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _FileSelectorPage(
          files: files,
          initiallySelected: selected,
        ),
      ),
    );

    if (result == null) return;

    // 勾选的文件设为优先级「普通」，未勾选的设为「跳过」
    setState(() => _applying = true);
    try {
      final selectedIds = result.toList()..sort();
      final skippedIds = files
          .where((f) => !selectedIds.contains(f.index))
          .map((f) => f.index)
          .toList();
      if (skippedIds.isNotEmpty) {
        await DownloaderService.instance.setFilePriority(
          config: widget.config,
          password: widget.password,
          hash: widget.taskHash,
          ids: skippedIds,
          priority: FilePriority.skipped,
        );
      }
      if (selectedIds.isNotEmpty) {
        await DownloaderService.instance.setFilePriority(
          config: widget.config,
          password: widget.password,
          hash: widget.taskHash,
          ids: selectedIds,
          priority: FilePriority.normal,
        );
      }
      if (!mounted) return;
      NotificationHelper.showInfo(context, '文件选择已应用');
      await _load(silent: true);
    } catch (e) {
      if (!mounted) return;
      NotificationHelper.showError(context, '应用失败：$e');
    } finally {
      if (mounted) setState(() => _applying = false);
    }
  }

  /// 应用搜索 + 视频筛选 + 排序后的展示列表
  List<TorrentFile> get _visibleFiles {
    final query = _query.trim().toLowerCase();
    var list = _files.where((f) {
      if (_videoOnly && _kindOf(f.name) != _FileKind.video) return false;
      if (query.isNotEmpty && !f.name.toLowerCase().contains(query)) {
        return false;
      }
      return true;
    }).toList();
    if (_sortKey == 4) {
      list.sort((a, b) => a.index.compareTo(b.index));
    } else {
      list.sort((a, b) {
        final cmp = switch (_sortKey) {
          0 => a.priority.compareTo(b.priority),
          1 => a.progress.compareTo(b.progress),
          2 => a.size.compareTo(b.size),
          _ => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        };
        return cmp;
      });
    }
    if (!_ascending) list = list.reversed.toList();
    return list;
  }

  /// 优先级：跳过 → 普通 → 高 → 最高，点击 chip 循环切换（取值见 [FilePriority]）
  Future<void> _cyclePriority(TorrentFile file) async {
    if (_applying || _busyIndexes.contains(file.index)) return;
    final next = FilePriority.next(file.priority);
    setState(() => _busyIndexes.add(file.index));
    try {
      await DownloaderService.instance.setFilePriority(
        config: widget.config,
        password: widget.password,
        hash: widget.taskHash,
        ids: [file.index],
        priority: next,
      );
      await _load(silent: true);
    } catch (e) {
      if (!mounted) return;
      NotificationHelper.showError(context, '优先级设置失败：$e');
    } finally {
      if (mounted) setState(() => _busyIndexes.remove(file.index));
    }
  }

  String _priorityLabel(int priority) => switch (priority) {
    FilePriority.skipped => '跳过',
    FilePriority.high => '高',
    FilePriority.maximum => '最高',
    _ => '普通',
  };

  Future<void> _showFilterSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            final scheme = Theme.of(sheetContext).colorScheme;
            return SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    title: const Text(
                      '排序与筛选',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(sheetContext),
                    ),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: Icon(
                      _ascending
                          ? Icons.arrow_upward
                          : Icons.arrow_downward,
                    ),
                    title: Text(_ascending ? '升序' : '降序'),
                    onTap: () {
                      setState(() => _ascending = !_ascending);
                      setSheetState(() {});
                    },
                  ),
                  for (var i = 0; i < _sortLabels.length; i++)
                    ListTile(
                      leading: Icon(
                        _sortKey == i
                            ? Icons.check_circle
                            : Icons.radio_button_unchecked,
                        color: _sortKey == i ? scheme.primary : scheme.outline,
                      ),
                      title: Text('按${_sortLabels[i]}排序'),
                      onTap: () {
                        setState(() => _sortKey = i);
                        Navigator.pop(sheetContext);
                      },
                    ),
                  const Divider(height: 1),
                  ListTile(
                    leading: Icon(
                      _videoOnly ? Icons.movie_filter : Icons.filter_alt,
                    ),
                    title: Text(_videoOnly ? '只看视频（已开启）' : '全部文件'),
                    subtitle: Text(
                      _videoOnly
                          ? '只显示视频扩展名'
                          : '显示全部 ${_files.length} 个文件',
                      style: TextStyle(fontSize: 11, color: scheme.secondary),
                    ),
                    onTap: () {
                      setState(() => _videoOnly = !_videoOnly);
                      setSheetState(() {});
                    },
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final scheme = Theme.of(context).colorScheme;
    final visible = _visibleFiles;
    return _loading
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
        : _files.isEmpty
        ? Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.folder_open, size: 64, color: scheme.outline),
                const SizedBox(height: 12),
                Text(
                  '没有文件',
                  style: TextStyle(fontSize: 16, color: scheme.outline),
                ),
                const SizedBox(height: 4),
                Text(
                  '该任务没有可管理的文件',
                  style: TextStyle(fontSize: 12, color: scheme.outline),
                ),
              ],
            ),
          )
        : Column(
            children: [
              _buildToolbar(scheme, visible.length),
              Expanded(
                child: visible.isEmpty
                    ? Center(
                        child: Text(
                          '没有匹配的文件',
                          style: TextStyle(color: scheme.outline),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.only(bottom: 16),
                        itemCount: visible.length,
                        itemBuilder: (context, index) {
                          return _buildFileCard(visible[index]);
                        },
                      ),
              ),
            ],
          );
  }

  Widget _buildToolbar(ColorScheme scheme, int shownCount) {
    return Container(
      width: double.infinity,
      color: scheme.surfaceContainerLow,
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '共 ${_files.length} 个文件 · '
                  '${_files.where((f) => f.selected).length} 个选中'
                  '${shownCount == _files.length ? '' : ' · 显示 $shownCount'}',
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.secondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              IconButton(
                tooltip: '排序与筛选',
                icon: Icon(
                  (_videoOnly || _sortKey != 4 || _query.isNotEmpty)
                      ? Icons.filter_alt
                      : Icons.filter_alt_outlined,
                  size: 20,
                ),
                onPressed: _showFilterSheet,
              ),
              TextButton.icon(
                onPressed: _applying ? null : _openFileSelector,
                icon: _applying
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.checklist, size: 16),
                label: const Text('选择文件'),
              ),
            ],
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 40,
            child: TextField(
              controller: _searchController,
              style: const TextStyle(fontSize: 13),
              onChanged: (value) => setState(() => _query = value),
              decoration: InputDecoration(
                hintText: '搜索文件',
                hintStyle: TextStyle(fontSize: 13, color: scheme.outline),
                isDense: true,
                prefixIcon: const Icon(Icons.search, size: 18),
                prefixIconConstraints: const BoxConstraints(minWidth: 36),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        tooltip: '清空',
                        icon: const Icon(Icons.close, size: 16),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _query = '');
                        },
                      ),
                filled: true,
                fillColor: scheme.surfaceContainerHighest,
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPriorityChip(TorrentFile file) {
    final scheme = Theme.of(context).colorScheme;
    final busy = _busyIndexes.contains(file.index);
    final colors = switch (file.priority) {
      FilePriority.skipped => (
        bg: scheme.surfaceContainerHighest,
        fg: scheme.outline,
      ),
      FilePriority.high => (
        bg: scheme.tertiaryContainer,
        fg: scheme.onTertiaryContainer,
      ),
      FilePriority.maximum => (
        bg: scheme.errorContainer,
        fg: scheme.onErrorContainer,
      ),
      _ => (bg: scheme.primaryContainer, fg: scheme.onPrimaryContainer),
    };
    final icon = switch (file.priority) {
      FilePriority.skipped => Icons.block,
      FilePriority.high => Icons.arrow_upward,
      FilePriority.maximum => Icons.vertical_align_top,
      _ => Icons.check,
    };
    return Tooltip(
      message: '点击切换优先级：跳过 → 普通 → 高 → 最高',
      child: InkWell(
        onTap: busy || _applying ? null : () => _cyclePriority(file),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: colors.bg,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              busy
                  ? const SizedBox(
                      width: 10,
                      height: 10,
                      child: CircularProgressIndicator(strokeWidth: 1.5),
                    )
                  : Icon(icon, size: 11, color: colors.fg),
              const SizedBox(width: 4),
              Text(
                _priorityLabel(file.priority),
                style: TextStyle(fontSize: 10, color: colors.fg),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFileCard(TorrentFile file) {
    final scheme = Theme.of(context).colorScheme;
    final selected = file.selected;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: selected
              ? scheme.primary.withValues(alpha: 0.4)
              : scheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  selected
                      ? Icons.insert_drive_file_outlined
                      : Icons.block,
                  size: 16,
                  color: selected ? scheme.primary : scheme.outline,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    file.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: selected ? null : scheme.outline,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                _buildPriorityChip(file),
                const SizedBox(width: 8),
                Text(
                  Formatters.dataFromBytes(file.size),
                  style: TextStyle(fontSize: 11, color: scheme.secondary),
                ),
                const Spacer(),
                Text(
                  '${(file.progress * 100).toStringAsFixed(1)}%',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: selected ? null : scheme.outline,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: file.progress.clamp(0.0, 1.0),
                minHeight: 4,
                backgroundColor: scheme.surfaceContainerHighest,
              ),
            ),
          ],
        ),
      ),
    );
  }
}


/// 全屏文件选择页：勾选要下载的文件，其余跳过
class _FileSelectorPage extends StatefulWidget {
  final List<TorrentFile> files;
  final Set<int> initiallySelected;

  const _FileSelectorPage({
    required this.files,
    required this.initiallySelected,
  });

  @override
  State<_FileSelectorPage> createState() => _FileSelectorPageState();
}

class _FileSelectorPageState extends State<_FileSelectorPage> {
  late final Set<int> _selected = {...widget.initiallySelected};
  final TextEditingController _searchController = TextEditingController();
  final Set<_FileKind> _kinds = {};
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String get _keyword => _query.trim().toLowerCase();

  bool _matchKeyword(TorrentFile file) =>
      _keyword.isEmpty || file.name.toLowerCase().contains(_keyword);

  bool _matches(TorrentFile file) {
    if (_kinds.isNotEmpty && !_kinds.contains(_kindOf(file.name))) {
      return false;
    }
    return _matchKeyword(file);
  }

  // 计数只跟随搜索词，不跟随类型勾选，否则点一下 chip 数字就全变了
  Map<_FileKind, int> get _kindCounts {
    final counts = {for (final kind in _FileKind.values) kind: 0};
    for (final file in widget.files) {
      if (!_matchKeyword(file)) continue;
      final kind = _kindOf(file.name);
      counts[kind] = counts[kind]! + 1;
    }
    return counts;
  }

  List<TorrentFile> get _visible => widget.files.where(_matches).toList();

  void _selectAll() {
    setState(() {
      _selected.addAll(_visible.map((f) => f.index));
    });
  }

  void _clearAll() {
    setState(() {
      _selected.removeAll(_visible.map((f) => f.index));
    });
  }

  @override
  Widget build(BuildContext context) {
    final files = _visible;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          '选择下载文件（${_selected.length}/${widget.files.length}）',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          TextButton(
            onPressed: _clearAll,
            child: const Text('全不选'),
          ),
          TextButton(
            onPressed: _selectAll,
            child: const Text('全选'),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: TextField(
              controller: _searchController,
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                hintText: '搜索文件名',
                isDense: true,
                prefixIcon: const Icon(Icons.search, size: 18),
                prefixIconConstraints: const BoxConstraints(minWidth: 36),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        tooltip: '清空',
                        icon: const Icon(Icons.close, size: 16),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _query = '');
                        },
                      ),
                filled: true,
                fillColor: scheme.surfaceContainerHighest,
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: (value) => setState(() => _query = value),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final entry in _kindCounts.entries)
                  _buildKindChip(entry.key, entry.value),
                if (_kinds.isNotEmpty || _query.isNotEmpty)
                  _buildResetChip(),
              ],
            ),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            child: Text(
              '已选 ${_selected.length} 个 · 列出 ${files.length} 个 · '
              '取消勾选的文件将跳过下载',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.secondary,
              ),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: files.isEmpty
                ? const Center(child: Text('没有匹配的文件'))
                : ListView.builder(
                    itemCount: files.length,
                    itemBuilder: (context, index) {
                      final f = files[index];
                      final checked = _selected.contains(f.index);
                      return CheckboxListTile(
                        dense: true,
                        value: checked,
                        title: Text(
                          f.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13),
                        ),
                        subtitle: Text(
                          '${Formatters.dataFromBytes(f.size)}'
                          ' · ${(f.progress * 100).toStringAsFixed(1)}%'
                          '${f.selected ? '' : ' · 未下载'}',
                          style: const TextStyle(fontSize: 11),
                        ),
                        onChanged: (value) {
                          setState(() {
                            if (value == true) {
                              _selected.add(f.index);
                            } else {
                              _selected.remove(f.index);
                            }
                          });
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('取消'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: _selected.isEmpty
                      ? null
                      : () => Navigator.of(context).pop(_selected),
                  child: const Text('确定'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildKindChip(_FileKind kind, int count) {
    final scheme = Theme.of(context).colorScheme;
    final active = _kinds.contains(kind);
    final foreground = active ? scheme.primary : scheme.onSurfaceVariant;
    return Material(
      color: active
          ? scheme.primary.withValues(alpha: 0.12)
          : scheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          setState(() {
            if (active) {
              _kinds.remove(kind);
            } else {
              _kinds.add(kind);
            }
          });
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(kind.icon, size: 14, color: foreground),
              const SizedBox(width: 4),
              Text(
                '${kind.label} $count',
                style: TextStyle(
                  fontSize: 12,
                  color: foreground,
                  fontWeight: active ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResetChip() {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          _searchController.clear();
          setState(() {
            _query = '';
            _kinds.clear();
          });
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Text(
            '清除筛选',
            style: TextStyle(fontSize: 12, color: scheme.primary),
          ),
        ),
      ),
    );
  }
}
