import 'dart:async';

import 'package:flutter/material.dart';

import '../services/storage/storage_service.dart';
import '../services/downloader/downloader_config.dart';
import '../services/downloader/downloader_models.dart';
import '../services/downloader/downloader_service.dart';
import '../utils/format.dart';
import 'package:pt_mate/utils/notification_helper.dart';
import 'torrent_peers_page.dart';
import 'torrent_files_page.dart';
import 'torrent_overview_view.dart';

/// 种子详情页
///
/// 概览 / 文件 / Tracker / 用户 四个标签，对齐 qBittorrent 官方种子属性面板。
/// Tracker 标签可查看红种/工作/未连接状态、一键 reannounce、添加/编辑/删除。
class TrackerManagerPage extends StatefulWidget {
  final String taskHash;
  final String taskName;

  const TrackerManagerPage({
    super.key,
    required this.taskHash,
    required this.taskName,
  });

  @override
  State<TrackerManagerPage> createState() => _TrackerManagerPageState();
}

class _TrackerManagerPageState extends State<TrackerManagerPage> {
  bool _loading = true;
  String? _error;
  List<TorrentTracker> _trackers = [];
  DownloaderConfig? _config;
  String? _password;

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
      if (defId == null) {
        setState(() {
          _loading = false;
          _error = '未配置下载器';
        });
        return;
      }
      final configMaps = await StorageService.instance.loadDownloaderConfigs();
      final configMap = configMaps.firstWhere(
        (c) => c['id'] == defId,
        orElse: () => configMaps.first,
      );
      final config = DownloaderConfig.fromJson(configMap);
      final password = await StorageService.instance.loadDownloaderPassword(
        config.id,
      );
      if ((password ?? '').isEmpty) {
        setState(() {
          _loading = false;
          _error = '未保存密码';
        });
        return;
      }
      _config = config;
      _password = password;

      if (config.type != DownloaderType.qbittorrent) {
        setState(() {
          _loading = false;
          _error = 'Tracker 管理仅支持 qBittorrent 下载器（当前：${config.type.displayName}）';
        });
        return;
      }

      final client = DownloaderService.instance.getClient(
        config: config,
        password: password!,
      );
      final trackers = await client.getTrackers(widget.taskHash)
          as List<TorrentTracker>;
      if (!mounted) return;
      setState(() {
        _trackers = trackers;
        _loading = false;
      });
    } catch (e, st) {
      print('[TRACKER] 加载异常: $e');
      print('[TRACKER] $st');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '加载 Tracker 失败: ${e.runtimeType}: $e';
      });
    }
  }

  Future<void> _reannounceAll() async {
    try {
      final client = DownloaderService.instance.getClient(
        config: _config!,
        password: _password!,
      );
      await client.reannounceTorrents([widget.taskHash]);
      if (!mounted) return;
      NotificationHelper.showInfo(context, '已重新宣告所有 Tracker');
      await _load();
    } catch (e) {
      if (!mounted) return;
      NotificationHelper.showError(context, '重新宣告失败: $e');
    }
  }

  Future<void> _addTracker() async {
    final controller = TextEditingController();
    final url = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('添加 Tracker'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'https://tracker.example.com/announce',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('添加'),
          ),
        ],
      ),
    );
    if (url == null || url.trim().isEmpty) return;
    try {
      final client = DownloaderService.instance.getClient(
        config: _config!,
        password: _password!,
      );
      await client.addTracker(widget.taskHash, url.trim());
      if (!mounted) return;
      NotificationHelper.showInfo(context, 'Tracker 已添加');
      await _load();
    } catch (e) {
      if (!mounted) return;
      NotificationHelper.showError(context, '添加失败: $e');
    }
  }

  Future<void> _editTracker(TorrentTracker tracker) async {
    final controller = TextEditingController(text: tracker.url);
    final url = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('编辑 Tracker'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: '新 URL'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (url == null || url.trim().isEmpty || url.trim() == tracker.url) {
      return;
    }
    try {
      final client = DownloaderService.instance.getClient(
        config: _config!,
        password: _password!,
      );
      await client.editTracker(widget.taskHash, tracker.url, url.trim());
      if (!mounted) return;
      NotificationHelper.showInfo(context, 'Tracker 已更新');
      await _load();
    } catch (e) {
      if (!mounted) return;
      NotificationHelper.showError(context, '更新失败: $e');
    }
  }

  Future<void> _removeTracker(TorrentTracker tracker) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除 Tracker'),
        content: Text('确定删除 ${tracker.url} 吗？'),
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
    try {
      final client = DownloaderService.instance.getClient(
        config: _config!,
        password: _password!,
      );
      await client.removeTrackers(widget.taskHash, [tracker.url]);
      if (!mounted) return;
      NotificationHelper.showInfo(context, 'Tracker 已删除');
      await _load();
    } catch (e) {
      if (!mounted) return;
      NotificationHelper.showError(context, '删除失败: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            widget.taskName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 16),
          ),
          leading: IconButton(
            tooltip: '返回',
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.of(context).pop(),
          ),
          automaticallyImplyLeading: false,
          bottom: const TabBar(
            // 等宽铺满：可滚动的左对齐会让四段宽度随文字长短变化，指示条位置也跟着漂
            tabAlignment: TabAlignment.fill,
            indicatorSize: TabBarIndicatorSize.tab,
            labelPadding: EdgeInsets.symmetric(horizontal: 8),
            tabs: [
              Tab(text: '概览'),
              Tab(text: '文件'),
              Tab(text: 'Tracker'),
              Tab(text: '用户'),
            ],
          ),
          actions: [
            IconButton(
              tooltip: '重新宣告',
              onPressed: (_loading || !_hasClient) ? null : _reannounceAll,
              icon: const Icon(Icons.sync),
            ),
          ],
        ),
        body: TabBarView(
          children: [
            _buildOverviewTab(),
            if (_hasClient)
              TorrentFilesView(
                taskHash: widget.taskHash,
                config: _config!,
                password: _password!,
              )
            else
              _configPlaceholder(),
            _buildTrackerTab(),
            if (_hasClient)
              TorrentPeersView(
                taskHash: widget.taskHash,
                config: _config!,
                password: _password!,
              )
            else
              _configPlaceholder(),
          ],
        ),
        floatingActionButton: FloatingActionButton(
          heroTag: 'add_tracker',
          tooltip: '添加 Tracker',
          onPressed: (_loading || !_hasClient) ? null : _addTracker,
          child: const Icon(Icons.add),
        ),
      ),
    );
  }

  bool get _hasClient => _config != null && (_password ?? '').isNotEmpty;

  Widget _configPlaceholder() {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _error!,
            textAlign: TextAlign.center,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
      );
    }
    return const Center(child: Text('加载配置中…'));
  }

  Widget _buildOverviewTab() {
    if (!_hasClient) return _configPlaceholder();
    return TorrentOverviewView(
      taskHash: widget.taskHash,
      taskName: widget.taskName,
      config: _config!,
      password: _password!,
    );
  }

  /// DHT / PeX / LSD 这类伪节点没有 URL，单独成一组
  bool _isSpecialNode(TorrentTracker tracker) {
    final url = tracker.url.trim();
    return url.isEmpty || url.startsWith('**');
  }

  Widget _buildTrackerTab() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _trackers.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                _error!,
                textAlign: TextAlign.center,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: _load, child: const Text('重试')),
          ],
        ),
      );
    }
    final special = _trackers.where(_isSpecialNode).toList();
    final normal = _trackers.where((t) => !_isSpecialNode(t)).toList();
    if (normal.isEmpty && special.isEmpty) {
      final scheme = Theme.of(context).colorScheme;
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.wifi_off_rounded, size: 56, color: scheme.outline),
            const SizedBox(height: 10),
            Text('没有 Tracker', style: TextStyle(color: scheme.outline)),
            const SizedBox(height: 4),
            Text(
              '点右下角 + 添加 Tracker',
              style: TextStyle(fontSize: 12, color: scheme.outline),
            ),
          ],
        ),
      );
    }

    // 按层级分组，-1（未分层）排最后
    final byTier = <int, List<TorrentTracker>>{};
    for (final tracker in normal) {
      byTier.putIfAbsent(tracker.tier, () => <TorrentTracker>[]).add(tracker);
    }
    final tiers = byTier.keys.toList()
      ..sort((a, b) {
        if (a < 0) return 1;
        if (b < 0) return -1;
        return a.compareTo(b);
      });

    return ListView(
      padding: const EdgeInsets.only(bottom: 88),
      children: [
        if (special.isNotEmpty) _buildSpecialNodes(special),
        for (final tier in tiers) ...[
          _buildTierHeader(tier, byTier[tier]!.length),
          for (final tracker in byTier[tier]!) _buildTrackerCard(tracker),
        ],
      ],
    );
  }

  Widget _buildTierHeader(int tier, int count) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      child: Row(
        children: [
          Text(
            tier < 0 ? '未分层' : '层级 $tier',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: scheme.primary,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '$count 个',
            style: TextStyle(fontSize: 11, color: scheme.secondary),
          ),
        ],
      ),
    );
  }

  /// 特殊节点（DHT / PeX / LSD）合成一张卡，只读展示状态
  Widget _buildSpecialNodes(List<TorrentTracker> special) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '特殊节点',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: scheme.primary,
              ),
            ),
            const SizedBox(height: 6),
            for (final tracker in special)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Icon(
                      Icons.circle,
                      size: 8,
                      color: tracker.isDisabled
                          ? scheme.outline
                          : (tracker.isWorking ? Colors.green : scheme.tertiary),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        tracker.url.replaceAll('*', '').trim().isEmpty
                            ? tracker.url
                            : tracker.url.replaceAll('*', '').trim(),
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                    Text(
                      _trackerStatusText(tracker),
                      style: TextStyle(fontSize: 11, color: scheme.secondary),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Tracker 状态文案（对应 qB status: 0=已禁用 1=未联系 2=正常 3=更新中 4=红种）
  String _trackerStatusText(TorrentTracker tracker) {
    switch (tracker.status) {
      case 0:
        return '已禁用';
      case 1:
        return '未联系';
      case 2:
        return '正常';
      case 3:
        return '更新中';
      case 4:
        return '红种';
      default:
        return '未知';
    }
  }

  /// -1/负数 表示未知或未联系，显示为 '-'
  String _trackerNum(int value) => value < 0 ? '-' : '$value';

  Widget _buildTrackerCard(TorrentTracker tracker) {
    final scheme = Theme.of(context).colorScheme;
    final statusColor = tracker.isError
        ? scheme.error
        : (tracker.isDisabled
              ? scheme.outline
              : (tracker.isWorking ? Colors.green : scheme.tertiary));
    final statusText = _trackerStatusText(tracker);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: statusColor.withValues(alpha: 0.5),
          width: tracker.isError ? 1.5 : 1,
        ),
      ),
      child: ListTile(
        title: Row(
          children: [
            Icon(Icons.circle, size: 10, color: statusColor),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                tracker.url,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13),
              ),
            ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    statusText,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: statusColor,
                    ),
                  ),
                ),
                if (tracker.tier >= 0) ...[
                  const SizedBox(width: 8),
                  Text(
                    '层级 ${tracker.tier}',
                    style: TextStyle(fontSize: 11, color: scheme.secondary),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '节点 ${_trackerNum(tracker.numPeers)} · 种子 ${_trackerNum(tracker.numSeeds)} · 下载者 ${_trackerNum(tracker.numLeeches)} · 已下载 ${_trackerNum(tracker.numDownloads)}',
              style: TextStyle(fontSize: 11, color: scheme.secondary),
            ),
            if (tracker.message.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                tracker.message,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: tracker.isError
                      ? FontWeight.w600
                      : FontWeight.normal,
                  color: tracker.isError ? scheme.error : scheme.secondary,
                ),
              ),
            ],
            const SizedBox(height: 2),
            Text(
              '最后活动: ${_formatLastSeen(tracker.lastSeen)}',
              style: TextStyle(fontSize: 10, color: scheme.secondary),
            ),
          ],
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (value) {
            switch (value) {
              case 'edit':
                _editTracker(tracker);
                break;
              case 'remove':
                _removeTracker(tracker);
                break;
              case 'reannounce':
                _reannounceTracker(tracker.url);
                break;
            }
          },
          itemBuilder: (context) => [
            const PopupMenuItem<String>(
              value: 'reannounce',
              child: Text('重新宣告'),
            ),
            const PopupMenuItem<String>(
              value: 'edit',
              child: Text('编辑'),
            ),
            const PopupMenuItem<String>(
              value: 'remove',
              child: Text('删除'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _reannounceTracker(String url) async {
    try {
      final client = DownloaderService.instance.getClient(
        config: _config!,
        password: _password!,
      );
      await client.reannounceTorrents([widget.taskHash]);
      if (!mounted) return;
      NotificationHelper.showInfo(context, '已重新宣告');
    } catch (e) {
      if (!mounted) return;
      NotificationHelper.showError(context, '重新宣告失败: $e');
    }
  }

  String _formatLastSeen(int lastSeen) {
    if (lastSeen <= 0) return '从未';
    final diff = DateTime.now().difference(
      DateTime.fromMillisecondsSinceEpoch(lastSeen * 1000),
    );
    return FormatUtil.formatEta(diff.inSeconds);
  }
}
