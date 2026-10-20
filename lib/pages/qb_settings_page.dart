import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/storage/storage_service.dart';
import '../services/theme/theme_manager.dart';
import '../services/downloader/downloader_capabilities.dart';
import '../services/downloader/downloader_config.dart';
import '../services/downloader/downloader_models.dart';
import '../services/downloader/downloader_service.dart';
import '../utils/format.dart';
import '../utils/notification_helper.dart';
import 'download_health_page.dart';
import 'deluge_server_settings_page.dart';
import 'qb_server_settings_page.dart';
import 'speed_scheduler_page.dart';

/// qB 客户端风格的下载管理设置页
/// 板块化布局：外观 / 高级，与 qBittorrent 客户端设置页一致
class QbSettingsPage extends StatefulWidget {
  const QbSettingsPage({super.key});

  @override
  State<QbSettingsPage> createState() => _QbSettingsPageState();
}

class _QbSettingsPageState extends State<QbSettingsPage> {
  int _refreshInterval = 5; // 秒
  bool _showAllTasks = false;
  bool _loading = true;

  // 服务器设置入口与累计统计按下载器能力决定是否展示
  DownloaderConfig? _config;
  String? _password;

  // 累计统计取自下载器的 server_state，各家给的指标不全一样，取不到的行不显示
  ServerState? _stats;
  String? _savePath;
  bool _statsLoading = false;
  String? _statsError;

  DownloaderCapabilities get _caps => _config == null
      ? DownloaderCapabilities.none
      : DownloaderCapabilities.forType(_config!.type);

  @override
  void initState() {
    super.initState();
    _load();
    _loadDownloader();
  }

  Future<void> _loadDownloader() async {
    try {
      final defId = await StorageService.instance.loadDefaultDownloaderId();
      if (defId == null) return;
      final configs = await StorageService.instance.loadDownloaderConfigs();
      final configMap = configs.firstWhere(
        (e) => e['id'] == defId,
        orElse: () =>
            configs.isNotEmpty ? configs.first : throw Exception('未找到默认下载器'),
      );
      final config = DownloaderConfig.fromJson(configMap);
      final pwd = await StorageService.instance.loadDownloaderPassword(
        config.id,
      );
      if (!mounted) return;
      setState(() {
        _config = config;
        _password = pwd;
      });
      _loadStats();
    } catch (_) {
      // 无下载器配置时服务器设置入口置灰
    }
  }

  Future<void> _loadStats() async {
    final config = _config;
    final password = _password;
    if (config == null || password == null || password.isEmpty) return;
    if (!_caps.has(DownloaderFeature.cumulativeStats)) return;
    setState(() {
      _statsLoading = true;
      _statsError = null;
    });
    try {
      final state = await DownloaderService.instance.getServerState(
        config: config,
        password: password,
      );
      String? savePath;
      if (_caps.has(DownloaderFeature.serverPreferences)) {
        final prefs = await DownloaderService.instance.getPreferences(
          config: config,
          password: password,
        );
        final raw = prefs[_defaultSavePathKey(config)];
        savePath = (raw is String && raw.isNotEmpty) ? raw : null;
      }
      if (!mounted) return;
      setState(() {
        _stats = state;
        _savePath = savePath;
        _statsLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _statsLoading = false;
        _statsError = '$e';
      });
    }
  }

  Future<void> _load() async {
    final interval = await StorageService.instance
        .loadDownloadTasksRefreshInterval();
    final showAll = await StorageService.instance.loadDownloadTasksShowAll();
    if (!mounted) return;
    setState(() {
      _refreshInterval = interval;
      _showAllTasks = showAll;
      _loading = false;
    });
  }

  Future<void> _saveRefreshInterval(int seconds) async {
    setState(() {
      _refreshInterval = seconds;
    });
    await StorageService.instance
        .saveDownloadTasksRefreshInterval(seconds);
    if (!mounted) return;
    NotificationHelper.showInfo(context, '刷新间隔已设为 $seconds 秒');
  }

  Future<void> _saveShowAll(bool value) async {
    setState(() {
      _showAllTasks = value;
    });
    await StorageService.instance.saveDownloadTasksShowAll(value);
  }

  String _getThemeModeText(AppThemeMode mode) {
    switch (mode) {
      case AppThemeMode.system:
        return '跟随系统（夜间模式跟随系统）';
      case AppThemeMode.light:
        return '浅色';
      case AppThemeMode.dark:
        return '深色';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
        leading: IconButton(
          tooltip: '返回',
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        automaticallyImplyLeading: false,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                _sectionHeader(context, '外观'),
                Card(
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(
                      color: Theme.of(
                        context,
                      ).colorScheme.outlineVariant.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Column(
                    children: [
                      Consumer<ThemeManager>(
                        builder: (context, themeManager, child) {
                          return Column(
                            children: [
                              ListTile(
                                leading: const Icon(Icons.brightness_6),
                                title: const Text('主题'),
                                subtitle: Text(
                                  _getThemeModeText(themeManager.themeMode),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                ),
                                child: SegmentedButton<AppThemeMode>(
                                  segments: const [
                                    ButtonSegment(
                                      value: AppThemeMode.system,
                                      label: Text('自动'),
                                      icon: Icon(Icons.brightness_auto),
                                    ),
                                    ButtonSegment(
                                      value: AppThemeMode.light,
                                      label: Text('浅色'),
                                      icon: Icon(Icons.light_mode),
                                    ),
                                    ButtonSegment(
                                      value: AppThemeMode.dark,
                                      label: Text('深色'),
                                      icon: Icon(Icons.dark_mode),
                                    ),
                                  ],
                                  selected: {themeManager.themeMode},
                                  onSelectionChanged: (selection) {
                                    themeManager.setThemeMode(selection.first);
                                  },
                                ),
                              ),
                              const SizedBox(height: 8),
                            ],
                          );
                        },
                      ),
                      const Divider(height: 1, indent: 56),
                      Consumer<ThemeManager>(
                        builder: (context, themeManager, child) {
                          return SwitchListTile(
                            secondary: const Icon(Icons.palette),
                            title: const Text('动态取色'),
                            subtitle: const Text('根据壁纸自动调整主题色'),
                            value: themeManager.useDynamicColor,
                            onChanged: (value) {
                              themeManager.setUseDynamicColor(value);
                            },
                          );
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                // 下载器没声明的能力，整块直接不出现，不再置灰占位
                if (_caps.has(DownloaderFeature.serverPreferences)) ...[
                  _sectionHeader(context, '服务器设置'),
                  _serverSettingsCard(context),
                  const SizedBox(height: 16),
                ],
                if (_caps.has(DownloaderFeature.cumulativeStats)) ...[
                  _statsSection(context),
                  const SizedBox(height: 16),
                ],
                _sectionHeader(context, '任务工具'),
                Card(
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(
                      color: Theme.of(
                        context,
                      ).colorScheme.outlineVariant.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.monitor_heart_outlined),
                        title: const Text('下载健康'),
                        subtitle: const Text('做种健康度、保种提醒与磁盘预警'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const DownloadHealthPage(),
                            ),
                          );
                        },
                      ),
                      const Divider(height: 1, indent: 56),
                      ListTile(
                        leading: const Icon(Icons.schedule),
                        title: const Text('限速调度'),
                        subtitle: const Text('按时间段自动限速/提速'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const SpeedSchedulerPage(),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _sectionHeader(context, '高级'),
                Card(
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(
                      color: Theme.of(
                        context,
                      ).colorScheme.outlineVariant.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.autorenew),
                        title: const Text('自动刷新间隔'),
                        subtitle: const Text('任务列表自动刷新间隔'),
                        trailing: DropdownButton<int>(
                          value: _refreshInterval,
                          underline: const SizedBox.shrink(),
                          items: const [
                            DropdownMenuItem(value: 3, child: Text('3 秒')),
                            DropdownMenuItem(value: 5, child: Text('5 秒')),
                            DropdownMenuItem(value: 10, child: Text('10 秒')),
                            DropdownMenuItem(value: 30, child: Text('30 秒')),
                          ],
                          onChanged: (value) {
                            if (value != null) _saveRefreshInterval(value);
                          },
                        ),
                      ),
                      const Divider(height: 1, indent: 56),
                      SwitchListTile(
                        secondary: const Icon(Icons.filter_list),
                        title: const Text('显示全部任务'),
                        subtitle: const Text('默认显示所有状态的任务（含完成/暂停）'),
                        value: _showAllTasks,
                        onChanged: _saveShowAll,
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _statsSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _statsHeader(context),
        _card(context, child: _statsBody(context)),
      ],
    );
  }

  Widget _statsHeader(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 8, 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '累计统计',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          if (_statsLoading && _stats != null)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            IconButton(
              tooltip: '刷新统计',
              icon: const Icon(Icons.refresh),
              onPressed: _statsLoading ? null : _loadStats,
            ),
        ],
      ),
    );
  }

  Widget _statsBody(BuildContext context) {
    final theme = Theme.of(context);
    final state = _stats;
    if (state == null) {
      if (_statsLoading) {
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: Center(
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        );
      }
      final message = _statsError ??
          (_config == null ? '请先配置下载器' : '请先保存下载器密码');
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Text(
                message,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ),
            if (_statsError != null)
              TextButton(onPressed: _loadStats, child: const Text('重试')),
          ],
        ),
      );
    }

    final rows = <(String, String)>[
      ('磁盘空间', '${Formatters.dataFromBytes(state.freeSpaceOnDisk)} 可用'),
      if (_savePath != null) ('默认保存路径', _savePath!),
      // 各下载器给不全同一批指标（Deluge 只有总下载/总上传，缓存与队列是 qB 独有），
      // 取不到值的行直接不显示，避免出现一片 '-'
      if (state.alltimeDl != null) ('历史下载', _bytes(state.alltimeDl)),
      if (state.alltimeUl != null) ('历史上传', _bytes(state.alltimeUl)),
      if (state.globalRatio != null) ('分享率', state.globalRatio!),
      if (state.totalWastedSession != null)
        ('会话浪费', _bytes(state.totalWastedSession)),
      if (state.readCacheHits != null)
        ('读缓存命中', _percent(state.readCacheHits)),
      if (state.totalBuffersSize != null)
        ('总缓冲大小', _bytes(state.totalBuffersSize)),
      if (state.writeCacheOverload != null)
        ('写入缓存超载', _percent(state.writeCacheOverload)),
      if (state.readCacheOverload != null)
        ('读取缓存超载', _percent(state.readCacheOverload)),
      if (state.queuedIoJobs != null) ('队列 I/O', _count(state.queuedIoJobs)),
      if (state.averageTimeQueue != null)
        ('平均队列时间', _ms(state.averageTimeQueue)),
      if (state.totalQueuedSize != null)
        ('总队列大小', _bytes(state.totalQueuedSize)),
    ];

    return Column(
      children: [for (final row in rows) _statRow(context, row.$1, row.$2)],
    );
  }

  Widget _statRow(BuildContext context, String label, String value) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _card(BuildContext context, {required Widget child}) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: Theme.of(
            context,
          ).colorScheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: child,
    );
  }

  String _bytes(int? value) =>
      value == null ? '-' : Formatters.dataFromBytes(value);

  /// 默认保存路径的偏好键：qB 是 save_path，Deluge 是 download_location
  static String _defaultSavePathKey(DownloaderConfig config) =>
      config is DelugeConfig ? 'download_location' : 'save_path';

  String _percent(String? value) => value == null ? '-' : '$value%';

  String _count(int? value) => value == null ? '-' : '$value';

  String _ms(int? value) => value == null ? '-' : '$value ms';

  /// 「服务器设置」入口：只在下载器声明了 serverPreferences 能力时渲染，
  /// 目前 qBittorrent 与 Deluge 各有一套字段表。
  Widget _serverSettingsCard(BuildContext context) {
    final isDeluge = _config is DelugeConfig;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: Theme.of(
            context,
          ).colorScheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: ListTile(
        leading: const Icon(Icons.dns_outlined),
        title: Text(isDeluge ? 'Deluge 选项' : 'qBittorrent 选项'),
        subtitle: Text(
          isDeluge
              ? '下载、队列与做种、速度、连接、其它'
              : '下载、连接、速度、BitTorrent、RSS、分类与标签',
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => isDeluge
                ? const DelugeServerSettingsPage()
                : const QbServerSettingsPage(),
          ),
        ),
      ),
    );
  }

  Widget _sectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          title,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}
