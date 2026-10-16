import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/storage/storage_service.dart';
import '../services/theme/theme_manager.dart';
import '../services/downloader/downloader_config.dart';
import '../utils/notification_helper.dart';
import 'download_health_page.dart';
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
  bool _groupByCategory = true;
  bool _loading = true;

  // 服务器设置入口需要判断当前下载器是否为 qBittorrent
  DownloaderConfig? _config;

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
      if (!mounted) return;
      setState(() {
        _config = DownloaderConfig.fromJson(configMap);
      });
    } catch (_) {
      // 无下载器配置时服务器设置入口置灰
    }
  }

  Future<void> _load() async {
    final interval = await StorageService.instance
        .loadDownloadTasksRefreshInterval();
    final showAll = await StorageService.instance.loadDownloadTasksShowAll();
    final groupByCategory = await StorageService.instance
        .loadDownloadTasksGroupByCategory();
    if (!mounted) return;
    setState(() {
      _refreshInterval = interval;
      _showAllTasks = showAll;
      _groupByCategory = groupByCategory;
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

  Future<void> _saveGroupByCategory(bool value) async {
    setState(() {
      _groupByCategory = value;
    });
    await StorageService.instance.saveDownloadTasksGroupByCategory(value);
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
                _sectionHeader(context, '服务器设置'),
                _serverSettingsCard(context),
                const SizedBox(height: 16),
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
                      const Divider(height: 1, indent: 56),
                      SwitchListTile(
                        secondary: const Icon(Icons.folder_outlined),
                        title: const Text('按分类分组'),
                        subtitle: const Text('同分类折叠成一组，点击组头展开收起'),
                        value: _groupByCategory,
                        onChanged: _saveGroupByCategory,
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _serverSettingsCard(BuildContext context) {
    final isQb = _config is QbittorrentConfig;
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
        title: const Text('qBittorrent 选项'),
        subtitle: Text(
          isQb
              ? '下载、连接、速度、BitTorrent、RSS、分类与标签'
              : '需要 qBittorrent 下载器',
        ),
        enabled: isQb,
        trailing: const Icon(Icons.chevron_right),
        onTap: isQb
            ? () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const QbServerSettingsPage()),
              )
            : null,
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
