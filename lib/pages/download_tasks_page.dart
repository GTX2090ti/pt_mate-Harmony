import 'package:flutter/material.dart';
import 'dart:async';
import 'package:dio/dio.dart';
import '../services/storage/storage_service.dart';
import '../services/downloader/downloader_config.dart';
import '../services/downloader/downloader_service.dart';
import '../services/downloader/downloader_models.dart';
import '../services/downloader/qbittorrent_client.dart';
import '../services/downloader/seed_health_monitor.dart';
import '../services/downloader/disk_guard_service.dart';
import '../utils/format.dart';

import '../widgets/responsive_layout.dart';
import '../widgets/qb_speed_indicator.dart';
import 'downloader_settings_page.dart';
import 'package:pt_mate/utils/notification_helper.dart';
import 'tracker_manager_page.dart';
import 'download_health_page.dart';
import 'qb_settings_page.dart';
import '../widgets/category_picker_dialog.dart';
import '../widgets/tag_picker_dialog.dart';
import '../utils/screen_utils.dart';

enum SortField {
  name,
  dlSpeed,
  upSpeed,
  addedOn,
  completionOn,
  ratio,
  size,
  progress,
}

/// qBittorrent 用于表示"无限"ETA 的值（100天，单位：秒）
const int kInfinityEtaInSeconds = 8640000;

extension SortFieldLabel on SortField {
  String get label => switch (this) {
    SortField.name => '名称',
    SortField.dlSpeed => '下载速度',
    SortField.upSpeed => '上传速度',
    SortField.addedOn => '添加时间',
    SortField.completionOn => '完成时间',
    SortField.ratio => '分享率',
    SortField.size => '大小',
    SortField.progress => '进度',
  };
}


class DownloadTasksPage extends StatefulWidget {
  const DownloadTasksPage({super.key});

  @override
  State<DownloadTasksPage> createState() => _DownloadTasksPageState();
}

/// 任务状态筛选
enum _TaskFilter {
  all('全部'),
  downloading('下载中'),
  uploading('做种中'),
  paused('已暂停'),
  completed('已完成');

  const _TaskFilter(this.label);
  final String label;
}

class _DownloadTasksPageState extends State<DownloadTasksPage> {
  Timer? _refreshTimer;
  StreamSubscription<String>? _configChangeSubscription;

  // 状态变量
  bool _isLoading = true;
  String? _errorMessage;
  List<DownloadTask> _tasks = [];
  ServerState? _serverState;
  DownloaderConfig? _downloaderConfig;
  String? _password;
  bool _showAllTasks = false; // 控制是否显示全部任务
  // ===== 专业增强状态 =====
  bool _selectionMode = false; // 批量选择模式
  final Set<String> _selectedHashes = {}; // 选中的任务哈希
  DiskGuardConfig? _diskGuardConfig; // 磁盘守卫配置
  List<DownloadTask> _readyToDelete = []; // 已达可删种标准的任务
  String _searchQuery = ''; // 搜索关键词
  final TextEditingController _searchController = TextEditingController();

  // 排序状态
  SortField _sortField = SortField.addedOn;
  bool _sortAscending = false;

  // 状态筛选 Tab（qB 风格）
  _TaskFilter _statusFilter = _TaskFilter.all;

  // 筛选面板：单选中的分类，空集表示「全部」
  final Set<String> _categoryFilter = {};

  // 筛选面板：多选中的标签（命中任一即显示），空集表示不限
  final Set<String> _tagFilter = {};

  @override
  void initState() {
    super.initState();
    StorageService.instance.loadDownloadTasksShowAll().then((value) {
      if (mounted) {
        setState(() {
          _showAllTasks = value;
        });
      }
    });
    StorageService.instance.loadDownloadTasksCategoryFilter().then((value) {
      if (mounted) setState(() => _categoryFilter.addAll(value));
    });
    StorageService.instance.loadDownloadTasksTagFilter().then((value) {
      if (mounted) setState(() => _tagFilter.addAll(value));
    });
    _loadDownloaderConfig();
    _startAutoRefresh();

    // 监听配置变更
    _configChangeSubscription = DownloaderService.instance.configChangeStream
        .listen((configId) {
          // 当配置发生变更时，重置 client 并重新加载配置
          _resetClient();
          _loadDownloaderConfig();
        });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _configChangeSubscription?.cancel();
    _searchController.dispose();
    _resetClient(); // 清理 client 实例
    super.dispose();
  }

  // 启动自动刷新（间隔从设置读取）
  void _startAutoRefresh() {
    StorageService.instance.loadDownloadTasksRefreshInterval().then((seconds) {
      if (!mounted) return;
      _refreshTimer = Timer.periodic(Duration(seconds: seconds), (timer) {
        if (_downloaderConfig != null && _password != null && mounted) {
          _loadTasks(silent: true); // 使用静默模式
        }
      });
    });
  }

  // 加载下载器配置
  Future<void> _loadDownloaderConfig() async {
    try {
      final defId = await StorageService.instance.loadDefaultDownloaderId();
      if (defId == null) {
        setState(() {
          _isLoading = false;
          _downloaderConfig = null;
          _password = null;
          _errorMessage = '未配置下载器';
        });
        return;
      }

      final configs = await StorageService.instance.loadDownloaderConfigs();
      final configMap = configs.firstWhere(
        (e) => e['id'] == defId,
        orElse: () =>
            configs.isNotEmpty ? configs.first : throw Exception('未找到默认下载器'),
      );

      final config = DownloaderConfig.fromJson(configMap);
      final password = await StorageService.instance.loadDownloaderPassword(
        config.id,
      );
      if ((password ?? '').isEmpty) {
        setState(() {
          _isLoading = false;
          _downloaderConfig = config;
          _password = null;
          _errorMessage = '未保存密码';
        });
        return;
      }

      setState(() {
        _downloaderConfig = config;
        _password = password;
      });

      // 配置更改时重置 client
      _resetClient();

      await _loadTasks();
    } catch (e) {
      setState(() {
        _isLoading = false;
        _downloaderConfig = null;
        _password = null;
        _errorMessage = '加载配置失败: $e';
      });
    }
  }

  // 获取或创建 client 实例
  dynamic _getClient() {
    if (_downloaderConfig == null || _password == null) {
      return null;
    }

    // 使用 DownloaderService 的缓存机制（包含配置更新回调）
    return DownloaderService.instance.getClient(
      config: _downloaderConfig!,
      password: _password!,
    );
  }

  /// 重置客户端
  void _resetClient() {
    // 清除 DownloaderService 中的缓存
    if (_downloaderConfig != null) {
      DownloaderService.instance.clearConfigCache(_downloaderConfig!.id);
    }
  }

  // 加载下载任务
  Future<void> _loadTasks({bool silent = false}) async {
    if (_downloaderConfig == null || _password == null) return;

    if (!silent) {
      setState(() {
        _isLoading = true;
        _errorMessage = '';
      });
    }

    try {
      final client = _getClient();
      if (client == null) return;

      final List<dynamic> futures = await Future.wait([
        client.getTasks(),
        client.getServerState(),
      ]);

      final diskConfig = await DiskGuardService.instance.loadConfig();
      final seedConfig = await SeedHealthMonitor.instance.loadConfig();
      final tasks = futures[0] as List<DownloadTask>;
      final ready = SeedHealthMonitor.findReadyToDelete(tasks, seedConfig);

      setState(() {
        _tasks = tasks;
        _serverState = futures[1] as ServerState;
        _diskGuardConfig = diskConfig;
        _readyToDelete = ready;
        if (!silent) _isLoading = false;
        _errorMessage = null; // 清除错误信息
      });
    } catch (e) {
      // 静默模式下不更新错误状态，避免干扰用户
      if (!silent) {
        setState(() {
          _isLoading = false;
          _errorMessage = _friendlyTaskError(e);
        });
      }
    }
  }

  /// 把下载器连接异常转成可操作的中文提示
  String _friendlyTaskError(Object e) {
    if (e is DioException) {
      switch (e.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.receiveTimeout:
          return '连接下载器超时：请检查手机与下载器是否在同一网络（WiFi 下访问内网地址；流量下需公网地址/内网穿透）';
        case DioExceptionType.connectionError:
          return '无法连接下载器：请确认下载器在线、地址端口正确，且手机网络可访问该地址';
        default:
          break;
      }
    }
    return '加载任务失败: $e';
  }

  @override
  Widget build(BuildContext context) {
    return ResponsiveLayout(
      currentRoute: '/download_tasks',
      appBar: AppBar(
        title: Text(_selectionMode ? '已选 ${_selectedHashes.length} 项' : '下载管理'),
        leading: _selectionMode
            ? IconButton(
                tooltip: '退出批量选择',
                icon: const Icon(Icons.close),
                onPressed: () {
                  setState(() {
                    _selectionMode = false;
                    _selectedHashes.clear();
                  });
                },
              )
            : null,
        actions: [
          if (_selectionMode) ...[
            IconButton(
              tooltip: '全选',
              icon: const Icon(Icons.select_all),
              onPressed: _selectAll,
            ),
            IconButton(
              tooltip: '批量暂停',
              icon: const Icon(Icons.pause),
              onPressed: _selectedHashes.isEmpty ? null : () => _bulkPause(),
            ),
            IconButton(
              tooltip: '批量恢复',
              icon: const Icon(Icons.play_arrow),
              onPressed: _selectedHashes.isEmpty ? null : () => _bulkResume(),
            ),
            PopupMenuButton<String>(
              tooltip: '批量分类 / 标签',
              enabled: _selectedHashes.isNotEmpty,
              icon: const Icon(Icons.drive_file_rename_outline),
              onSelected: (value) {
                if (value == 'category') {
                  _bulkSetCategory();
                } else if (value == 'tags') {
                  _bulkAddTags();
                }
              },
              itemBuilder: (context) => const [
                PopupMenuItem<String>(
                  value: 'category',
                  child: ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.folder_outlined),
                    title: Text('批量修改分类'),
                  ),
                ),
                PopupMenuItem<String>(
                  value: 'tags',
                  child: ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.label_outline),
                    title: Text('批量添加标签'),
                  ),
                ),
              ],
            ),
            IconButton(
              tooltip: '批量删除',
              icon: const Icon(Icons.delete_outline),
              onPressed: _selectedHashes.isEmpty ? null : () => _bulkDelete(),
            ),
          ] else ...[
            const QbSpeedIndicator(),
          ],
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                if (_errorMessage != null && _errorMessage!.isNotEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    color: _downloaderConfig == null
                        ? Theme.of(context).colorScheme.primaryContainer
                        : Theme.of(context).colorScheme.errorContainer,
                    child: _downloaderConfig == null
                        ? Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                '未配置下载器',
                                style: TextStyle(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onPrimaryContainer,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(width: 12),
                              TextButton(
                                onPressed: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          const DownloaderSettingsPage(),
                                      settings: const RouteSettings(
                                        name: '/downloader_settings',
                                      ),
                                    ),
                                  );
                                },
                                style: TextButton.styleFrom(
                                  side: BorderSide(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.outline,
                                    width: 1.0,
                                  ),
                                ),
                                child: const Text('去配置'),
                              ),
                            ],
                          )
                        : Text(
                            _errorMessage!,
                            style: TextStyle(
                              color: Theme.of(
                                context,
                              ).colorScheme.onErrorContainer,
                              fontSize: 14,
                            ),
                            textAlign: TextAlign.center,
                          ),
                  ),
                if (_serverState != null &&
                    _diskGuardConfig != null &&
                    DiskGuardService.instance.isWarning(
                      _serverState!.freeSpaceOnDisk,
                      _diskGuardConfig!,
                    ))
                  _buildDiskWarningBanner(),
                if (_readyToDelete.isNotEmpty && !_selectionMode)
                  _buildSeedHealthBanner(),
                // 搜索和过滤UI
                _buildSearchAndFilterBar(),
                Expanded(child: _buildAllTasksList()),
              ],
            ),
      floatingActionButton: Builder(
        builder: (context) {
          final isDesktop = ScreenUtils.isLargeScreen(context);
          return Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (isDesktop)
                FloatingActionButton.extended(
                  heroTag: 'switch_downloader',
                  onPressed: _showDownloaderPicker,
                  icon: const Icon(Icons.swap_vert),
                  label: const Text('切换'),
                )
              else
                FloatingActionButton(
                  heroTag: 'switch_downloader',
                  tooltip: '切换',
                  onPressed: _showDownloaderPicker,
                  child: const Icon(Icons.swap_vert),
                ),
              const SizedBox(height: 16),
              if (isDesktop)
                FloatingActionButton.extended(
                  heroTag: 'refresh_download',
                  onPressed: () {
                    _loadTasks();
                    NotificationHelper.showInfo(context, '刷新任务列表');
                  },
                  icon: const Icon(Icons.refresh),
                  label: const Text('刷新'),
                )
              else
                FloatingActionButton(
                  heroTag: 'refresh_download',
                  tooltip: '刷新',
                  onPressed: () {
                    _loadTasks();
                    NotificationHelper.showInfo(context, '刷新任务列表');
                  },
                  child: const Icon(Icons.refresh),
                ),
              const SizedBox(height: 16),
              // 设置入口（右下角方形齿轮按钮，打开 qB 风格设置页）
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: IconButton(
                  tooltip: '设置',
                  icon: const Icon(Icons.settings, color: Colors.white),
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const QbSettingsPage(),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // 暂停任务
  Future<void> _pauseTask(String hash) async {
    if (_downloaderConfig == null || _password == null) return;

    try {
      final client = _getClient();
      if (client == null) return;

      await client.pauseTask(hash);

      if (!mounted) return;
      NotificationHelper.showInfo(context, '已暂停');
    } catch (e) {
      if (!mounted) return;
      NotificationHelper.showError(context, '暂停失败: $e');
    }
  }

  // 恢复任务
  Future<void> _resumeTask(String hash) async {
    if (_downloaderConfig == null || _password == null) return;

    try {
      final client = _getClient();
      if (client == null) return;

      await client.resumeTask(hash);
      if (!mounted) return;
      NotificationHelper.showInfo(context, '已启动');
    } catch (e) {
      if (!mounted) return;
      NotificationHelper.showError(context, '恢复失败: $e');
    }
  }

  // 删除任务
  Future<void> _deleteTask(String hash, bool deleteFiles) async {
    if (_downloaderConfig == null || _password == null) return;

    try {
      final client = _getClient();
      if (client == null) return;

      await client.deleteTask(hash, deleteFiles: deleteFiles);

      if (!mounted) return;
      NotificationHelper.showInfo(context, deleteFiles ? '已删除任务和文件' : '已删除任务');
    } catch (e) {
      if (!mounted) return;
      NotificationHelper.showError(context, '删除任务失败: $e');
    }
  }
  // ===== 批量操作 =====
  void _selectAll() {
    setState(() {
      if (_selectedHashes.length == _tasks.length) {
        _selectedHashes.clear();
      } else {
        _selectedHashes.addAll(_tasks.map((t) => t.hash));
      }
    });
  }

  Future<void> _bulkPause() async {
    try {
      final client = _getClient();
      if (client == null) return;
      await client.pauseTasks(_selectedHashes.toList());
      if (!mounted) return;
      NotificationHelper.showInfo(context, '已暂停 ' + _selectedHashes.length.toString() + ' 个任务');
      setState(() {
        _selectionMode = false;
        _selectedHashes.clear();
      });
      await _loadTasks(silent: true);
    } catch (e) {
      if (!mounted) return;
      NotificationHelper.showError(context, '批量暂停失败: ' + e.toString());
    }
  }

  Future<void> _bulkResume() async {
    try {
      final client = _getClient();
      if (client == null) return;
      await client.resumeTasks(_selectedHashes.toList());
      if (!mounted) return;
      NotificationHelper.showInfo(context, '已恢复 ' + _selectedHashes.length.toString() + ' 个任务');
      setState(() {
        _selectionMode = false;
        _selectedHashes.clear();
      });
      await _loadTasks(silent: true);
    } catch (e) {
      if (!mounted) return;
      NotificationHelper.showError(context, '批量恢复失败: ' + e.toString());
    }
  }

  Future<void> _bulkDelete() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('批量删除'),
        content: const Text('是否同时删除文件？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('仅任务'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('同时删除文件'),
          ),
        ],
      ),
    );
    if (confirm == null) return;
    try {
      final client = _getClient();
      if (client == null) return;
      await client.deleteTasks(_selectedHashes.toList(), deleteFiles: confirm);
      if (!mounted) return;
      NotificationHelper.showInfo(context, '已删除 ' + _selectedHashes.length.toString() + ' 个任务');
      setState(() {
        _selectionMode = false;
        _selectedHashes.clear();
      });
      await _loadTasks(silent: true);
    } catch (e) {
      if (!mounted) return;
      NotificationHelper.showError(context, '批量删除失败: ' + e.toString());
    }
  }

  // 修改单个任务分类
  Future<void> _setTaskCategory(DownloadTask task) async {
    final config = _downloaderConfig;
    final pwd = _password;
    if (config == null || (pwd ?? '').isEmpty) {
      NotificationHelper.showError(context, '未配置下载器');
      return;
    }
    final category = await CategoryPickerDialog.show(
      context,
      config: config,
      password: pwd!,
      allowCreate: true,
    );
    if (category == null) return;
    try {
      await DownloaderService.instance.setCategory(
        config: config,
        password: pwd,
        hashes: [task.hash],
        category: category,
      );
      if (!mounted) return;
      NotificationHelper.showInfo(
        context,
        category.isEmpty ? '已清除分类' : '已分类为：$category',
      );
      await _loadTasks(silent: true);
    } catch (e) {
      if (!mounted) return;
      NotificationHelper.showError(context, '修改分类失败: $e');
    }
  }

  // 批量修改分类
  Future<void> _bulkSetCategory() async {
    final config = _downloaderConfig;
    final pwd = _password;
    if (config == null || (pwd ?? '').isEmpty) {
      NotificationHelper.showError(context, '未配置下载器');
      return;
    }
    final category = await CategoryPickerDialog.show(
      context,
      config: config,
      password: pwd!,
      allowCreate: true,
    );
    if (category == null) return;
    try {
      await DownloaderService.instance.setCategory(
        config: config,
        password: pwd,
        hashes: _selectedHashes.toList(),
        category: category,
      );
      if (!mounted) return;
      NotificationHelper.showInfo(
        context,
        '已为 ${_selectedHashes.length} 个任务设置分类：$category',
      );
      setState(() {
        _selectionMode = false;
        _selectedHashes.clear();
      });
      await _loadTasks(silent: true);
    } catch (e) {
      if (!mounted) return;
      NotificationHelper.showError(context, '批量修改分类失败: $e');
    }
  }

  // 批量添加标签
  Future<void> _bulkAddTags() async {
    final config = _downloaderConfig;
    final pwd = _password;
    if (config == null || (pwd ?? '').isEmpty) {
      NotificationHelper.showError(context, '未配置下载器');
      return;
    }
    final tags = await TagPickerDialog.show(
      context,
      config: config,
      password: pwd!,
    );
    if (tags == null || tags.isEmpty) return;
    try {
      final client = _getClient();
      if (client == null) return;
      await client.addTags(_selectedHashes.toList(), tags);
      if (!mounted) return;
      NotificationHelper.showInfo(
        context,
        '已为 ${_selectedHashes.length} 个任务添加 ${tags.length} 个标签',
      );
      setState(() {
        _selectionMode = false;
        _selectedHashes.clear();
      });
      await _loadTasks(silent: true);
    } catch (e) {
      if (!mounted) return;
      NotificationHelper.showError(context, '批量添加标签失败: $e');
    }
  }

  /// qBittorrent 没有「把任务设成第 N 档优先级」的接口（4.6/5.0/master 都查过），
  /// 队列只能相对移动或置顶/置底，所以这里走那四个真实存在的端点。
  Future<void> _queueAction(
    String label,
    Future<void> Function(QbittorrentClient client, List<String> hashes) action,
  ) async {
    final client = _getClient();
    if (client is! QbittorrentClient) {
      NotificationHelper.showError(context, '队列调整需要 qBittorrent 下载器');
      return;
    }
    final hashes = _selectedHashes.toList();
    if (hashes.isEmpty) return;
    try {
      await action(client, hashes);
      if (!mounted) return;
      NotificationHelper.showInfo(context, '$label（${hashes.length} 个任务）');
      setState(() {
        _selectionMode = false;
        _selectedHashes.clear();
      });
      await _loadTasks(silent: true);
    } catch (e) {
      if (!mounted) return;
      NotificationHelper.showError(context, '$label 失败: $e');
    }
  }

  void _showPriorityMenu() {
    showModalBottomSheet<int>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text(
                '批量操作',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              trailing: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(sheetContext),
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.arrow_upward),
              title: const Text('队列上移'),
              subtitle: const Text('在下载队列中前移一位'),
              onTap: () {
                Navigator.pop(sheetContext);
                _queueAction('队列上移', (c, h) => c.increasePriority(h));
              },
            ),
            ListTile(
              leading: const Icon(Icons.arrow_downward),
              title: const Text('队列下移'),
              subtitle: const Text('在下载队列中后移一位'),
              onTap: () {
                Navigator.pop(sheetContext);
                _queueAction('队列下移', (c, h) => c.decreasePriority(h));
              },
            ),
            ListTile(
              leading: const Icon(Icons.vertical_align_top),
              title: const Text('队列置顶'),
              onTap: () {
                Navigator.pop(sheetContext);
                _queueAction('队列置顶', (c, h) => c.topPriority(h));
              },
            ),
            ListTile(
              leading: const Icon(Icons.vertical_align_bottom),
              title: const Text('队列置底'),
              onTap: () {
                Navigator.pop(sheetContext);
                _queueAction('队列置底', (c, h) => c.bottomPriority(h));
              },
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.folder_copy_outlined),
              title: const Text('批量修改分类'),
              onTap: () {
                Navigator.pop(sheetContext);
                _bulkSetCategory();
              },
            ),
            ListTile(
              leading: const Icon(Icons.label_outline),
              title: const Text('批量添加标签'),
              onTap: () {
                Navigator.pop(sheetContext);
                _bulkAddTags();
              },
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.replay),
              title: const Text('批量重新校验'),
              onTap: () {
                Navigator.pop(sheetContext);
                _bulkRecheck();
              },
            ),
            ListTile(
              leading: const Icon(Icons.sync),
              title: const Text('批量重新宣告'),
              onTap: () {
                Navigator.pop(sheetContext);
                _bulkReannounce();
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _bulkRecheck() async {
    try {
      final client = _getClient();
      if (client == null) return;
      await client.recheckTorrents(_selectedHashes.toList());
      if (!mounted) return;
      NotificationHelper.showInfo(context, '已发起 ' + _selectedHashes.length.toString() + ' 个任务校验');
      setState(() {
        _selectionMode = false;
        _selectedHashes.clear();
      });
    } catch (e) {
      if (!mounted) return;
      NotificationHelper.showError(context, '批量校验失败: ' + e.toString());
    }
  }

  Future<void> _bulkReannounce() async {
    try {
      final client = _getClient();
      if (client == null) return;
      await client.reannounceTorrents(_selectedHashes.toList());
      if (!mounted) return;
      NotificationHelper.showInfo(context, '已重新宣告 ' + _selectedHashes.length.toString() + ' 个任务');
      setState(() {
        _selectionMode = false;
        _selectedHashes.clear();
      });
    } catch (e) {
      if (!mounted) return;
      NotificationHelper.showError(context, '批量重新宣告失败: ' + e.toString());
    }
  }

  // 构建搜索和过滤UI
  Widget _buildSearchAndFilterBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        children: [
          // 状态筛选 Tab（qB 风格）
          SizedBox(
            height: 36,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: _TaskFilter.values.map((f) {
                final selected = _statusFilter == f;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(f.label),
                    selected: selected,
                    showCheckmark: false,
                    onSelected: (_) {
                      setState(() {
                        _statusFilter = f;
                      });
                    },
                    labelStyle: TextStyle(
                      fontSize: 12,
                      fontWeight: selected
                          ? FontWeight.w600
                          : FontWeight.normal,
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              // 搜索框
              Expanded(
                child: SizedBox(
                  height: 40,
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: '搜索...',
                      prefixIcon: const Icon(Icons.search, size: 20),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 16),
                              tooltip: '清除搜索',
                              onPressed: () {
                                _searchController.clear();
                                setState(() {
                                  _searchQuery = '';
                                });
                              },
                            )
                          : null,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: Theme.of(
                        context,
                      ).colorScheme.surfaceContainerHighest,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                      ),
                      isDense: true,
                    ),
                    style: const TextStyle(fontSize: 14),
                    onChanged: (value) {
                      setState(() {
                        _searchQuery = value;
                      });
                    },
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              _buildQuickChip(
                icon: Icons.folder_outlined,
                label: _filterChipLabel(_categoryFilter, '分类'),
                active: _categoryFilter.isNotEmpty,
                onTap: _showCategorySheet,
              ),
              const SizedBox(width: 6),
              _buildQuickChip(
                icon: Icons.label_outlined,
                label: _filterChipLabel(_tagFilter, '标签'),
                active: _tagFilter.isNotEmpty,
                onTap: _showTagSheet,
              ),
              const SizedBox(width: 6),
              _buildQuickChip(
                icon: _sortAscending
                    ? Icons.arrow_upward
                    : Icons.arrow_downward,
                label: _sortField.label,
                onTap: _showSortSheet,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDiskWarningBanner() {
    return Material(
      color: Theme.of(context).colorScheme.errorContainer,
      child: InkWell(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const DownloadHealthPage(),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Icon(
                Icons.warning_amber,
                size: 16,
                color: Theme.of(context).colorScheme.onErrorContainer,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '磁盘空间不足：剩余 ' +
                      Formatters.dataFromBytes(_serverState!.freeSpaceOnDisk) +
                      '，点击查看详情',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onErrorContainer,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSeedHealthBanner() {
    return Material(
      color: Colors.green.withValues(alpha: 0.12),
      child: InkWell(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const DownloadHealthPage(),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Icon(Icons.eco, size: 16, color: Colors.green.shade700),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _readyToDelete.length.toString() + ' 个任务已达可删种标准，点击查看',
                  style: TextStyle(fontSize: 12, color: Colors.green.shade800),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAllTasksList() {
    // 首先根据状态 Tab 过滤任务
    List<DownloadTask> statusFilteredTasks = _tasks.where((task) {
      switch (_statusFilter) {
        case _TaskFilter.all:
          return true;
        case _TaskFilter.downloading:
          return DownloadTaskState.isDownloading(task.state) ||
              task.state == DownloadTaskState.queuedDL ||
              task.state == DownloadTaskState.checkingDL ||
              task.state == DownloadTaskState.allocating ||
              task.state == DownloadTaskState.checkingResumeData ||
              task.state == DownloadTaskState.moving;
        case _TaskFilter.uploading:
          return task.state == DownloadTaskState.uploading ||
              task.state == DownloadTaskState.forcedUP ||
              task.state == DownloadTaskState.stalledUP ||
              task.state == DownloadTaskState.queuedUP ||
              task.state == DownloadTaskState.checkingUP;
        case _TaskFilter.paused:
          return DownloadTaskState.isPaused(task.state) ||
              task.state == DownloadTaskState.stoppedDL;
        case _TaskFilter.completed:
          return task.progress >= 1.0 &&
              (task.state == DownloadTaskState.uploading ||
                  task.state == DownloadTaskState.forcedUP ||
                  task.state == DownloadTaskState.stalledUP ||
                  task.state == DownloadTaskState.queuedUP ||
                  task.state == DownloadTaskState.checkingUP ||
                  task.state == DownloadTaskState.pausedUP);
      }
    }).toList();

    // 兼容旧开关：showAll 为 false 时仅显示活跃状态
    if (!_showAllTasks && _statusFilter == _TaskFilter.all) {
      statusFilteredTasks = statusFilteredTasks
          .where(
            (task) =>
                task.state == DownloadTaskState.downloading ||
                task.state == DownloadTaskState.uploading ||
                task.state == DownloadTaskState.pausedDL ||
                task.state == DownloadTaskState.stalledDL ||
                task.state == DownloadTaskState.stoppedDL,
          )
          .toList();
    }

    // 筛选面板：仅展示单选中的分类（空集表示「全部」）
    if (_categoryFilter.isNotEmpty) {
      statusFilteredTasks = statusFilteredTasks
          .where((task) => _categoryFilter.contains(task.category.trim()))
          .toList();
    }

    // 标签维度：命中所选任一标签即保留
    if (_tagFilter.isNotEmpty) {
      statusFilteredTasks = statusFilteredTasks
          .where(
            (task) => task.tags.any((tag) => _tagFilter.contains(tag.trim())),
          )
          .toList();
    }

    // 然后根据搜索关键词过滤任务名称
    final filteredTasks = _searchQuery.isEmpty
        ? statusFilteredTasks
        : statusFilteredTasks
              .where(
                (task) => task.name.toLowerCase().contains(
                  _searchQuery.toLowerCase(),
                ),
              )
              .toList();

    // 排序
    filteredTasks.sort((a, b) {
      int cmp;
      switch (_sortField) {
        case SortField.name:
          cmp = a.name.compareTo(b.name);
          break;
        case SortField.dlSpeed:
          cmp = a.dlspeed.compareTo(b.dlspeed);
          break;
        case SortField.upSpeed:
          cmp = a.upspeed.compareTo(b.upspeed);
          break;
        case SortField.addedOn:
          cmp = a.addedOn.compareTo(b.addedOn);
          break;
        case SortField.completionOn:
          cmp = a.completionOn.compareTo(b.completionOn);
          break;
        case SortField.ratio:
          cmp = a.ratio.compareTo(b.ratio);
          break;
        case SortField.size:
          cmp = a.size.compareTo(b.size);
          break;
        case SortField.progress:
          cmp = a.progress.compareTo(b.progress);
          break;
      }
      return _sortAscending ? cmp : -cmp;
    });

    if (filteredTasks.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.inbox_outlined,
              size: 64,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 12),
            Text(
              '没有下载任务',
              style: TextStyle(
                fontSize: 16,
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _searchQuery.isNotEmpty
                  ? '换个关键词试试'
                  : _categoryFilter.isNotEmpty
                  ? '试试放宽筛选面板里的分类'
                  : '下拉可刷新任务列表',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadTasks,
      child: ListView.builder(
        itemCount: filteredTasks.length,
        padding: const EdgeInsets.only(
          left: 16,
          top: 4,
          right: 16,
          bottom: 150,
        ),
        itemBuilder: (context, index) {
          final task = filteredTasks[index];
          return KeyedSubtree(
            key: ValueKey('task_${task.hash}'),
            child: _buildTaskCard(task),
          );
        },
      ),
    );
  }

  int _compareCategoryKey(String a, String b) {
    if (a.isEmpty) return 1;
    if (b.isEmpty) return -1;
    return a.toLowerCase().compareTo(b.toLowerCase());
  }

  // 当前任务列表里出现过的分类及其任务数（未分类 key 为空串）
  Map<String, int> _categoryCounts() {
    final counts = <String, int>{};
    for (final task in _tasks) {
      final key = task.category.trim();
      counts[key] = (counts[key] ?? 0) + 1;
    }
    final keys = counts.keys.toList()..sort(_compareCategoryKey);
    return {for (final key in keys) key: counts[key]!};
  }

  String _optionLabel(String key) => key.isEmpty ? '未分类' : key;

  // 快捷按钮上的文案：只选了一个就直接显示它的名字
  String _filterChipLabel(Set<String> picked, String noun) {
    if (picked.isEmpty) return noun;
    if (picked.length == 1) return _optionLabel(picked.first);
    return '${picked.length} 个$noun';
  }

  Widget _buildQuickChip({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool active = false,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final foreground = active ? scheme.primary : scheme.onSurface;
    return Expanded(
      child: SizedBox(
        height: 32,
        child: Material(
          color: active
              ? scheme.primary.withValues(alpha: 0.12)
              : scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(9),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 14, color: foreground),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: foreground,
                        fontWeight: active
                            ? FontWeight.w600
                            : FontWeight.normal,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Map<String, int> _tagCounts() {
    final counts = <String, int>{};
    for (final task in _tasks) {
      for (final raw in task.tags) {
        final tag = raw.trim();
        if (tag.isEmpty) continue;
        counts[tag] = (counts[tag] ?? 0) + 1;
      }
    }
    final keys = counts.keys.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return {for (final key in keys) key: counts[key]!};
  }

  void _applyCategoryFilter(Iterable<String> keys) {
    setState(() {
      _categoryFilter
        ..clear()
        ..addAll(keys);
    });
    StorageService.instance.saveDownloadTasksCategoryFilter(
      _categoryFilter.toList(),
    );
  }

  void _applyTagFilter(Iterable<String> keys) {
    setState(() {
      _tagFilter
        ..clear()
        ..addAll(keys);
    });
    StorageService.instance.saveDownloadTasksTagFilter(_tagFilter.toList());
  }

  void _showCategorySheet() => _showPickSheet(
    title: '分类',
    icon: Icons.folder_outlined,
    searchHint: '搜索分类',
    options: _categoryCounts(),
    initial: _categoryFilter,
    single: true,
    onApply: _applyCategoryFilter,
  );

  void _showTagSheet() => _showPickSheet(
    title: '标签',
    icon: Icons.label_outline,
    searchHint: '搜索标签',
    options: _tagCounts(),
    initial: _tagFilter,
    onApply: _applyTagFilter,
  );

  /// 搜索 + 选择 + 清除/应用 的草稿态面板，分类（单选）和标签（多选）共用一套。
  Future<void> _showPickSheet({
    required String title,
    required IconData icon,
    required String searchHint,
    required Map<String, int> options,
    required Set<String> initial,
    required void Function(Iterable<String> keys) onApply,
    bool single = false,
  }) async {
    final allKeys = options.keys.toSet();
    final remembered = initial.where(allKeys.contains).toSet();
    // 单选面板里空集就是「全部」，所以「全部」项是否选中直接看 draft 是否为空
    final draft = single
        ? (remembered.isEmpty ? <String>{} : {remembered.first})
        : (remembered.isEmpty ? allKeys.toSet() : remembered);
    final searchController = TextEditingController();
    var query = '';

    final picked = await showModalBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            final scheme = Theme.of(sheetContext).colorScheme;
            final shown = query.isEmpty
                ? options.entries.toList()
                : options.entries
                      .where(
                        (e) => _optionLabel(e.key).toLowerCase().contains(
                          query,
                        ),
                      )
                      .toList();
            return Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Material(
                color: scheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(24),
                clipBehavior: Clip.antiAlias,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(sheetContext).size.height * 0.82,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                        child: Row(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: scheme.primary.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(icon, color: scheme.primary),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              title,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                        child: SizedBox(
                          height: 48,
                          child: TextField(
                            controller: searchController,
                            style: const TextStyle(fontSize: 15),
                            onChanged: (value) {
                              query = value.trim().toLowerCase();
                              setSheetState(() {});
                            },
                            decoration: InputDecoration(
                              hintText: searchHint,
                              hintStyle: TextStyle(color: scheme.outline),
                              prefixIcon: Icon(
                                Icons.search,
                                size: 20,
                                color: scheme.outline,
                              ),
                              filled: true,
                              fillColor: scheme.surfaceContainerHighest,
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 14,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: BorderSide.none,
                              ),
                            ),
                          ),
                        ),
                      ),
                      Flexible(
                        child: shown.isEmpty
                            ? Padding(
                                padding: const EdgeInsets.only(bottom: 28),
                                child: Center(
                                  child: Text(
                                    options.isEmpty
                                        ? '暂无$title'
                                        : '没有匹配的结果',
                                    style: TextStyle(color: scheme.outline),
                                  ),
                                ),
                              )
                            : ListView.builder(
                                padding: const EdgeInsets.only(bottom: 8),
                                itemCount: shown.length + (single ? 1 : 0),
                                itemBuilder: (context, index) {
                                  final isAll = single && index == 0;
                                  final entry = isAll
                                      ? null
                                      : shown[index - (single ? 1 : 0)];
                                  final selected = isAll
                                      ? draft.isEmpty
                                      : draft.contains(entry!.key);
                                  return Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      12,
                                      0,
                                      12,
                                      6,
                                    ),
                                    child: Material(
                                      color: selected
                                          ? scheme.primary.withValues(
                                              alpha: 0.12,
                                            )
                                          : Colors.transparent,
                                      borderRadius: BorderRadius.circular(14),
                                      clipBehavior: Clip.antiAlias,
                                      child: InkWell(
                                        onTap: () {
                                          setSheetState(() {
                                            if (single) {
                                              draft.clear();
                                              if (entry != null) {
                                                draft.add(entry.key);
                                              }
                                              return;
                                            }
                                            if (!draft.remove(entry!.key)) {
                                              draft.add(entry.key);
                                            }
                                          });
                                        },
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 16,
                                            vertical: 18,
                                          ),
                                          child: Row(
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  isAll
                                                      ? '全部'
                                                      : _optionLabel(
                                                          entry!.key,
                                                        ),
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                    fontSize: 17,
                                                    color: selected
                                                        ? scheme.primary
                                                        : scheme.onSurface,
                                                  ),
                                                ),
                                              ),
                                              Icon(
                                                selected
                                                    ? Icons.check_circle
                                                    : Icons
                                                          .radio_button_unchecked,
                                                size: 26,
                                                color: selected
                                                    ? scheme.primary
                                                    : scheme.outline,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
                        child: Row(
                          children: [
                            Expanded(
                              child: SizedBox(
                                height: 52,
                                child: FilledButton(
                                  style: FilledButton.styleFrom(
                                    backgroundColor:
                                        scheme.surfaceContainerHighest,
                                    foregroundColor: scheme.onSurface,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                  ),
                                  onPressed: () =>
                                      Navigator.pop(sheetContext, <String>{}),
                                  child: const Text(
                                    '清除筛选',
                                    style: TextStyle(fontSize: 16),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              flex: 2,
                              child: SizedBox(
                                height: 52,
                                child: FilledButton(
                                  style: FilledButton.styleFrom(
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                  ),
                                  onPressed: () {
                                    if (single) {
                                      Navigator.pop(
                                        sheetContext,
                                        draft.toSet(),
                                      );
                                      return;
                                    }
                                    final coversAll =
                                        allKeys.isEmpty ||
                                        allKeys.every(draft.contains);
                                    Navigator.pop(
                                      sheetContext,
                                      coversAll ? <String>{} : draft.toSet(),
                                    );
                                  },
                                  child: const Text(
                                    '应用',
                                    style: TextStyle(fontSize: 16),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    searchController.dispose();
    if (picked != null) onApply(picked);
  }

  void _showSortSheet() {
    showModalBottomSheet(
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
                      '排序',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    trailing: TextButton.icon(
                      icon: Icon(
                        _sortAscending
                            ? Icons.arrow_upward
                            : Icons.arrow_downward,
                        size: 18,
                      ),
                      label: Text(_sortAscending ? '升序' : '降序'),
                      onPressed: () {
                        setState(() => _sortAscending = !_sortAscending);
                        setSheetState(() {});
                      },
                    ),
                  ),
                  const Divider(height: 1),
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        for (final field in SortField.values)
                          ListTile(
                            leading: Icon(
                              _sortField == field
                                  ? Icons.radio_button_checked
                                  : Icons.radio_button_off,
                              color: _sortField == field
                                  ? scheme.primary
                                  : null,
                            ),
                            title: Text(field.label),
                            onTap: () {
                              setState(() => _sortField = field);
                              Navigator.pop(sheetContext);
                            },
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showDownloaderPicker() async {
    final configMaps = await StorageService.instance.loadDownloaderConfigs();
    if (configMaps.isEmpty) {
      if (mounted) NotificationHelper.showInfo(context, '未配置下载器');
      return;
    }

    final configs = configMaps
        .map((e) => DownloaderConfig.fromJson(e))
        .toList();
    final defaultId = await StorageService.instance.loadDefaultDownloaderId();

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: const Text(
                  '切换下载器',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(sheetContext),
                ),
              ),
              const Divider(height: 1),
              ...configs.map((config) {
                final isActive = config.id == defaultId;
                return ListTile(
                  leading: Icon(
                    isActive
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off,
                    color: isActive ? Theme.of(context).primaryColor : null,
                  ),
                  title: Text(config.name),
                  subtitle: Text('${config.type.displayName} - ${config.host}'),
                  onTap: () async {
                    Navigator.pop(sheetContext);
                    if (!isActive) {
                      await StorageService.instance.saveDownloaderConfigs(
                        configs,
                        defaultId: config.id,
                      );
                      DownloaderService.instance.notifyConfigChanged(config.id);
                      if (mounted) {
                        NotificationHelper.showInfo(
                          context,
                          '已切换至 ${config.name}',
                        );
                      }
                    }
                  },
                );
              }),
            ],
          ),
        );
      },
    );
  }

  // 确认删除
  void _confirmDelete(DownloadTask task) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除任务'),
        content: const Text('是否同时删除文件？'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _deleteTask(task.hash, false);
            },
            child: const Text('仅任务'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _deleteTask(task.hash, true);
            },
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('同时删除文件'),
          ),
        ],
      ),
    );
  }

  Widget _buildTaskCard(DownloadTask task) {
    final bool isDownloading =
        task.state == DownloadTaskState.downloading ||
        task.state == DownloadTaskState.stalledDL ||
        task.state == DownloadTaskState.metaDL ||
        task.state == DownloadTaskState.forcedDL ||
        task.state == DownloadTaskState.queuedDL ||
        task.state == DownloadTaskState.checkingDL ||
        task.state == DownloadTaskState.allocating ||
        task.state == DownloadTaskState.checkingResumeData;
    final bool isPaused =
        task.state == DownloadTaskState.pausedDL ||
        task.state == DownloadTaskState.pausedUP ||
        task.state == DownloadTaskState.queuedUP ||
        task.state == DownloadTaskState.error ||
        task.state == DownloadTaskState.stoppedDL ||
        task.state == DownloadTaskState.missingFiles;

    final bool isSelected = _selectedHashes.contains(task.hash);
    // 状态徽章文案与颜色
    String statusText;
    Color statusColor;
    if (task.state == DownloadTaskState.error ||
        task.state == DownloadTaskState.missingFiles) {
      statusText = '错误';
      statusColor = Theme.of(context).colorScheme.error;
    } else if (task.progress >= 1.0) {
      statusText = task.state == DownloadTaskState.pausedUP
          ? '已完成·暂停'
          : '已完成';
      statusColor = Colors.green;
    } else if (DownloadTaskState.isDownloading(task.state)) {
      statusText = '下载中';
      statusColor = Theme.of(context).colorScheme.primary;
    } else if (DownloadTaskState.isPaused(task.state) ||
        task.state == DownloadTaskState.stoppedDL) {
      statusText = '已暂停';
      statusColor = Theme.of(context).colorScheme.tertiary;
    } else if (task.state == DownloadTaskState.uploading ||
        task.state == DownloadTaskState.forcedUP ||
        task.state == DownloadTaskState.stalledUP ||
        task.state == DownloadTaskState.queuedUP ||
        task.state == DownloadTaskState.checkingUP) {
      statusText = '做种中';
      statusColor = Colors.green;
    } else {
      statusText = '等待中';
      statusColor = Theme.of(context).colorScheme.secondary;
    }
    return GestureDetector(
      onTap: () {
        if (_selectionMode) return;
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => TrackerManagerPage(
              taskHash: task.hash,
              taskName: task.name,
            ),
          ),
        );
      },
      onLongPress: () {
        setState(() {
          _selectionMode = true;
          _selectedHashes.add(task.hash);
        });
      },
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 0, vertical: 4),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(
            color: _selectionMode && isSelected
                ? Theme.of(context).colorScheme.primary
                : Theme.of(
                    context,
                  ).colorScheme.outlineVariant.withValues(alpha: 0.5),
            width: _selectionMode && isSelected ? 2 : 1,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top Row: Title and Actions
              Row(
                children: [
                  if (_selectionMode)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Icon(
                        isSelected
                            ? Icons.check_circle
                            : Icons.radio_button_unchecked,
                        size: 20,
                        color: isSelected
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.outline,
                      ),
                    ),
                  // Title and Info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                task.name,
                                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: statusColor.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                statusText,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: statusColor,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                      // Category and Tags
                      if (task.category.isNotEmpty || task.tags.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Row(
                            children: [
                              if (task.category.isNotEmpty)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.primaryContainer,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    task.category,
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onPrimaryContainer,
                                    ),
                                  ),
                                ),
                              if (task.category.isNotEmpty &&
                                  task.tags.isNotEmpty)
                                const SizedBox(width: 6),
                              ...task.tags.map(
                                (tag) => Padding(
                                  padding: const EdgeInsets.only(right: 4),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.secondaryContainer,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      tag,
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onSecondaryContainer,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      // Status Info Row 1: Static Info
                      Row(
                        children: [
                          // Size
                          Text(
                            FormatUtil.formatFileSize(task.size),
                            style: TextStyle(
                              fontSize: 11,
                              color: Theme.of(context).colorScheme.secondary,
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Uploaded
                          Icon(
                            Icons.upload_file,
                            size: 12,
                            color: Theme.of(context).colorScheme.secondary,
                          ),
                          const SizedBox(width: 2),
                          Text(
                            FormatUtil.formatFileSize(task.uploaded),
                            style: TextStyle(
                              fontSize: 11,
                              color: Theme.of(context).colorScheme.secondary,
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Ratio
                          Icon(
                            Icons.compare_arrows,
                            size: 12,
                            color: Theme.of(context).colorScheme.secondary,
                          ),
                          const SizedBox(width: 2),
                          Text(
                            task.ratio.toStringAsFixed(2),
                            style: TextStyle(
                              fontSize: 11,
                              color: Theme.of(context).colorScheme.secondary,
                            ),
                          ),
                        ],
                      ),

                      // Status Info Row 2: Dynamic Info (Speed & ETA)
                      if (task.dlspeed > 0 ||
                          task.upspeed > 0 ||
                          (isDownloading &&
                              task.eta > 0 &&
                              task.eta < kInfinityEtaInSeconds))
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Row(
                            children: [
                              // DL Speed
                              if (task.dlspeed > 0) ...[
                                Icon(
                                  Icons.download,
                                  size: 12,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                                const SizedBox(width: 2),
                                Text(
                                  FormatUtil.formatSpeed(task.dlspeed),
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.primary,
                                  ),
                                ),
                                const SizedBox(width: 8),
                              ],
                              // UP Speed
                              if (task.upspeed > 0) ...[
                                Icon(
                                  Icons.upload,
                                  size: 12,
                                  color: Theme.of(context).colorScheme.tertiary,
                                ),
                                const SizedBox(width: 2),
                                Text(
                                  FormatUtil.formatSpeed(task.upspeed),
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.tertiary,
                                  ),
                                ),
                                const SizedBox(width: 8),
                              ],
                              // ETA
                              if (isDownloading &&
                                  task.eta > 0 &&
                                  task.eta < kInfinityEtaInSeconds) ...[
                                Icon(
                                  Icons.timer,
                                  size: 12,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.secondary,
                                ),
                                const SizedBox(width: 2),
                                Text(
                                  FormatUtil.formatEta(task.eta),
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.secondary,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                // Actions
                if (_selectionMode)
                  IconButton(
                    icon: const Icon(Icons.more_vert, size: 20),
                    tooltip: '批量操作',
                    constraints: const BoxConstraints(
                      minWidth: 32,
                      minHeight: 32,
                    ),
                    padding: EdgeInsets.zero,
                    onPressed: _showPriorityMenu,
                  )
                else ...[
                  IconButton(
                    icon: Icon(
                      isPaused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                      size: 20,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    tooltip: isPaused ? '恢复' : '暂停',
                    constraints: const BoxConstraints(
                      minWidth: 32,
                      minHeight: 32,
                    ),
                    padding: EdgeInsets.zero,
                    onPressed: () =>
                        isPaused ? _resumeTask(task.hash) : _pauseTask(task.hash),
                  ),
                  IconButton(
                    icon: const Icon(Icons.folder_outlined, size: 20),
                    tooltip: '修改分类',
                    constraints: const BoxConstraints(
                      minWidth: 32,
                      minHeight: 32,
                    ),
                    padding: EdgeInsets.zero,
                    onPressed: () => _setTaskCategory(task),
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.delete_outline,
                      size: 20,
                      color: Colors.red,
                    ),
                    tooltip: '删除',
                    constraints: const BoxConstraints(
                      minWidth: 32,
                      minHeight: 32,
                    ),
                    padding: EdgeInsets.zero,
                    onPressed: () => _confirmDelete(task),
                  ),
                ],
              ],
            ),

            const SizedBox(height: 6),

            // Progress Bar
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: task.progress,
                      minHeight: 4,
                      backgroundColor: Theme.of(
                        context,
                      ).colorScheme.surfaceContainerHighest,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        isDownloading
                            ? Theme.of(context).colorScheme.primary
                            : (task.progress >= 1.0
                                  ? Colors.green
                                  : Theme.of(context).colorScheme.secondary),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${(task.progress * 100).toStringAsFixed(1)}%',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      ),
    );
  }
}
