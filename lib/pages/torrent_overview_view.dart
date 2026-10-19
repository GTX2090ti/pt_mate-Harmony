import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/downloader/downloader_capabilities.dart';
import '../services/downloader/downloader_config.dart';
import '../services/downloader/downloader_models.dart';
import '../services/downloader/downloader_service.dart';
import '../utils/format.dart';
import '../utils/notification_helper.dart';

/// 「其他设置项」里一个开关的定义
typedef _FlagDef = ({
  String id,
  String label,
  String hint,
  IconData icon,
  bool toggleOnly,
  DownloaderFeature feature,
});

/// 种子详情 · 概览
///
/// 对齐 qBittorrent 官方「种子属性」面板：其他设置项（可直接写回服务器）、
/// 基本信息、时间信息、哈希值四张卡。
class TorrentOverviewView extends StatefulWidget {
  final String taskHash;
  final String taskName;
  final DownloaderConfig config;
  final String password;

  const TorrentOverviewView({
    super.key,
    required this.taskHash,
    required this.taskName,
    required this.config,
    required this.password,
  });

  @override
  State<TorrentOverviewView> createState() => _TorrentOverviewViewState();
}

class _TorrentOverviewViewState extends State<TorrentOverviewView>
    with AutomaticKeepAliveClientMixin {
  Map<String, dynamic> _info = const {};
  TorrentProperties? _props;
  bool _loading = true;
  String? _error;

  /// 当前下载器的能力集合，决定「其他设置项」里哪些开关真的能按
  DownloaderCapabilities? _caps;

  /// 开关已点下、等服务端回包期间的期望值（key 为 [_flags] 的 id）
  final Map<String, bool> _pendingFlags = {};

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent && mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final client = DownloaderService.instance.getClient(
        config: widget.config,
        password: widget.password,
      );
      final raw = await client.getTorrentInfoRaw(widget.taskHash);
      TorrentProperties? props;
      try {
        props = await client.getTorrentProperties(widget.taskHash);
      } catch (_) {
        // properties 在部分 qB 版本字段不全，取不到就只用 info 渲染
      }
      if (!mounted) return;
      setState(() {
        _info = (raw is Map<String, dynamic>) ? raw : const {};
        _props = props;
        _caps = client is TorrentManagementClient ? client.capabilities : null;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (!silent) _error = '加载概览失败：$e';
      });
    }
  }

  // ============================================================
  // 字段读取：qB 各版本别名差异在这里兜住
  // ============================================================

  dynamic _raw(List<String> keys) {
    for (final key in keys) {
      final value = _info[key];
      if (value != null) return value;
    }
    return null;
  }

  int _num(List<String> keys, {int fallback = 0}) {
    final value = _raw(keys);
    if (value is int) return value;
    if (value is num) return value.toInt();
    return FormatUtil.parseInt(value) ?? fallback;
  }

  double _dbl(List<String> keys, {double fallback = 0}) {
    final value = _raw(keys);
    if (value is double) return value;
    if (value is num) return value.toDouble();
    return double.tryParse('$value') ?? fallback;
  }

  String _str(List<String> keys) {
    final value = _raw(keys);
    if (value == null) return '';
    return value.toString();
  }

  bool _flag(String name) {
    if (_pendingFlags.containsKey(name)) return _pendingFlags[name]!;
    final keys = switch (name) {
      'forceStart' => const ['force_start'],
      'sequential' => const ['seq_dl', 'sequential_download'],
      'firstLast' => const ['f_l_piece_prio', 'first_last_piece_prio'],
      'superSeeding' => const ['super_seeding'],
      'autoTmm' => const ['auto_tmm'],
      _ => const ['private', 'is_private'],
    };
    final value = _raw(keys);
    if (value is bool) return value;
    if (value is num) return value != 0;
    return value == 'true' || value == '1';
  }

  // ============================================================
  // 开关写回
  // ============================================================

  static const List<_FlagDef> _flags = [
    (
      id: 'forceStart',
      label: '强制开始',
      hint: '忽略队列与速度限制，立即上传/下载',
      icon: Icons.rocket_launch_outlined,
      toggleOnly: false,
      feature: DownloaderFeature.forceStart,
    ),
    (
      id: 'sequential',
      label: '顺序下载',
      hint: '按文件顺序下载分块',
      icon: Icons.format_list_numbered_rtl,
      toggleOnly: true,
      feature: DownloaderFeature.sequentialDownload,
    ),
    (
      id: 'firstLast',
      label: '首尾分块优先',
      hint: '优先下载每个文件的首尾块，便于边下边播',
      icon: Icons.compress,
      toggleOnly: true,
      feature: DownloaderFeature.firstLastPiecePriority,
    ),
    (
      id: 'superSeeding',
      label: '超级做种',
      hint: '只做种已校验完成的文件，减少无效传输',
      icon: Icons.workspace_premium,
      toggleOnly: false,
      feature: DownloaderFeature.superSeeding,
    ),
    (
      id: 'autoTmm',
      label: '自动种子管理',
      hint: '分类变化时跟随该分类的保存路径',
      icon: Icons.autorenew,
      toggleOnly: false,
      feature: DownloaderFeature.autoManagement,
    ),
  ];

  /// 能力未就绪时先不画开关，避免点下去才发现不支持
  List<_FlagDef> get _visibleFlags =>
      _flags.where((f) => _caps?.has(f.feature) ?? false).toList(growable: false);

  Future<void> _applyFlag(_FlagDef def, bool value) async {
    if (_flag(def.id) == value) return;
    setState(() => _pendingFlags[def.id] = value);
    try {
      final client = DownloaderService.instance.getClient(
        config: widget.config,
        password: widget.password,
      );
      final hashes = [widget.taskHash];
      if (def.toggleOnly) {
        if (def.id == 'sequential') {
          await client.toggleSequentialDownload(hashes);
        } else {
          await client.toggleFirstLastPiecePrio(hashes);
        }
      } else if (def.id == 'forceStart') {
        await client.setForceStart(hashes, value);
      } else if (def.id == 'superSeeding') {
        await client.setSuperSeeding(hashes, value);
      } else {
        await client.setAutoManagement(hashes, value);
      }
      await _load(silent: true);
      if (!mounted) return;
      NotificationHelper.showInfo(context, '${def.label}已${value ? '开启' : '关闭'}');
    } catch (e) {
      if (!mounted) return;
      NotificationHelper.showError(context, '${def.label}设置失败：$e');
      await _load(silent: true);
    } finally {
      if (mounted) setState(() => _pendingFlags.remove(def.id));
    }
  }

  // ============================================================
  // 渲染
  // ============================================================

  String _duration(int seconds) {
    if (seconds <= 0) return '-';
    final days = seconds ~/ 86400;
    final hours = (seconds % 86400) ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    if (days > 0) return '$days 天 $hours 小时';
    if (hours > 0) return '$hours 小时 $minutes 分钟';
    return '$minutes 分钟';
  }

  String _epochTime(List<String> keys) {
    final seconds = _num(keys);
    if (seconds <= 0) return '-';
    return Formatters.formatTorrentCreatedDate(
      DateTime.fromMillisecondsSinceEpoch(seconds * 1000),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _info.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_error!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: _load, child: const Text('重试')),
          ],
        ),
      );
    }

    final scheme = Theme.of(context).colorScheme;
    final size = _num(['total_size', 'size']);
    final amountLeft = _num(['amount_left']);
    final tags = _str(['tags']);
    final category = _str(['category']);
    final hashV1 = _str(['infohash_v1']).isEmpty
        ? _str(['hash'])
        : _str(['infohash_v1']);
    final hashV2 = _str(['infohash_v2']);
    final ratio = _dbl(['ratio'], fallback: _props?.shareRatio ?? 0);

    return RefreshIndicator(
      onRefresh: () => _load(silent: true),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
        children: [
          if (_visibleFlags.isNotEmpty) ...[
            _sectionCard(
              title: '其他设置项',
              children: _visibleFlags
                  .map(
                    (def) => _flagTile(def, scheme),
                  )
                  .toList(growable: false),
            ),
            const SizedBox(height: 12),
          ],
          _sectionCard(
            title: '基本信息',
            children: [
              _infoRow('总大小', '${Formatters.dataFromBytes(size)}'
                  '${amountLeft > 0 ? ' · 剩余 ${Formatters.dataFromBytes(amountLeft)}' : ''}'),
              _infoRow('分享率', Formatters.shareRate(ratio)),
              _infoRow(
                '已上传',
                Formatters.dataFromBytes(
                  _num(['uploaded'], fallback: _props?.upTotal ?? 0),
                ),
              ),
              _infoRow(
                '已下载',
                Formatters.dataFromBytes(
                  _num(['downloaded'], fallback: _props?.dlTotal ?? 0),
                ),
              ),
              _infoRow('做种 / 下载', _seedsAndLeeches()),
              _infoRow('保存路径', _str(['save_path', 'content_path'])),
              _infoRow('分类', category.isEmpty ? '未分类' : category),
              if (widget.config.type.supportsTags)
                _infoRow(
                  '标签',
                  tags.isEmpty ? '无标签' : tags.replaceAll(',', '、'),
                ),
              _infoRow('隐私', _flag('private') ? '私有种子' : '公开种子'),
            ],
          ),
          const SizedBox(height: 12),
          _sectionCard(
            title: '时间信息',
            children: [
              _infoRow('添加时间', _epochTime(['added_on'])),
              _infoRow('完成时间', _epochTime(['completion_on'])),
              _infoRow('最后活动', _epochTime(['last_activity'])),
              _infoRow('已用时间', _duration(_num(['time_active']))),
              _infoRow('做种时间', _duration(_num(['seeding_time']))),
            ],
          ),
          const SizedBox(height: 12),
          _sectionCard(
            title: '哈希值',
            children: [
              _hashRow('Info Hash v1', hashV1),
              if (hashV2.isNotEmpty) _hashRow('Info Hash v2', hashV2),
            ],
          ),
        ],
      ),
    );
  }

  String _seedsAndLeeches() {
    final seeds = _num(['num_complete'], fallback: _props?.numSeeds ?? 0);
    final leeches = _num(['num_incomplete'], fallback: _props?.numLeeches ?? 0);
    final peers = _num(['num_peers'], fallback: _props?.numPeers ?? 0);
    return '$seeds / $leeches · 节点 $peers';
  }

  Widget _sectionCard({
    required String title,
    required List<Widget> children,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: scheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Text(
              title,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: scheme.primary,
              ),
            ),
          ),
          ...children,
          const SizedBox(height: 6),
        ],
      ),
    );
  }

  Widget _flagTile(_FlagDef def, ColorScheme scheme) {
    final busy = _pendingFlags.containsKey(def.id);
    return SwitchListTile(
      dense: true,
      contentPadding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
      title: Text(def.label, style: const TextStyle(fontSize: 14)),
      subtitle: Text(
        def.hint,
        style: TextStyle(fontSize: 11, color: scheme.secondary),
      ),
      value: _flag(def.id),
      secondary: busy
          ? const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(def.icon, size: 22, color: scheme.secondary),
      onChanged: busy ? null : (value) => _applyFlag(def, value),
    );
  }

  Widget _infoRow(String label, String value) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 76,
            child: Text(
              label,
              style: TextStyle(fontSize: 12, color: scheme.secondary),
            ),
          ),
          Expanded(
            child: SelectableText(
              value.isEmpty ? '-' : value,
              style: TextStyle(
                fontSize: 13,
                color: value.isEmpty ? scheme.outline : scheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _hashRow(String label, String value) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.fromLTRB(16, 0, 8, 0),
      title: Text(
        label,
        style: TextStyle(fontSize: 12, color: scheme.secondary),
      ),
      subtitle: SelectableText(
        value.isEmpty ? '-' : value,
        style: const TextStyle(
          fontSize: 12,
          fontFamily: 'monospace',
          letterSpacing: 0.2,
        ),
      ),
      trailing: value.isEmpty
          ? null
          : IconButton(
              tooltip: '复制哈希',
              icon: const Icon(Icons.copy_rounded, size: 18),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: value));
                if (!mounted) return;
                NotificationHelper.showInfo(context, '已复制到剪贴板');
              },
            ),
    );
  }
}
