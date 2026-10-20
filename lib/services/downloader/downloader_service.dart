import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';

import '../../models/app_models.dart';
import 'downloader_capabilities.dart';
import 'downloader_config.dart';
import 'downloader_factory.dart';
import 'downloader_models.dart';
import '../network/timeout_retry.dart';
import '../storage/storage_service.dart';

/// 下载器服务
///
/// 管理下载器配置，提供统一的下载器访问接口
class DownloaderService {
  final StorageService _storageService;

  DownloaderService._([StorageService? storageService])
    : _storageService = storageService ?? StorageService.instance;

  static final DownloaderService instance = DownloaderService._();

  @visibleForTesting
  DownloaderService.test({StorageService? storageService})
    : _storageService = storageService ?? StorageService.instance;

  static final Logger _logger = Logger();

  /// 配置变更通知流
  final StreamController<String> _configChangeController =
      StreamController<String>.broadcast();

  /// 配置变更通知流
  Stream<String> get configChangeStream => _configChangeController.stream;

  /// 清除所有缓存
  void clearCache() {
    DownloaderFactory.clearCache();
  }

  /// 清除指定配置的缓存
  void clearConfigCache(String configId) {
    DownloaderFactory.clearConfigCache(configId);
  }

  /// 通知配置变更
  ///
  /// [configId] 变更的配置ID
  void notifyConfigChanged(String configId) {
    clearConfigCache(configId);
    _configChangeController.add(configId);
  }

  /// 获取客户端实例
  ///
  /// [config] 下载器配置
  /// [password] 密码
  dynamic getClient({
    required DownloaderConfig config,
    required String password,
  }) {
    return DownloaderFactory.getClient(
      config: config,
      password: password,
      onConfigUpdated: (updatedConfig) async {
        // 当配置更新时（比如获取到版本信息），持久化到存储中
        try {
          final configs = await _storageService.loadDownloaderConfigs();
          final currentDefaultId = await _storageService
              .loadDefaultDownloaderId();

          // 找到对应的配置并更新
          final configIndex = configs.indexWhere(
            (c) => c['id'] == updatedConfig.id,
          );
          if (configIndex != -1) {
            configs[configIndex] = updatedConfig.toJson();
            await _storageService.saveDownloaderConfigs(
              configs.map((c) => DownloaderConfig.fromJson(c)).toList(),
              defaultId: currentDefaultId, // 保留当前的默认下载器ID
            );

            if (kDebugMode) {
              _logger.i(
                '配置已更新并持久化: ${updatedConfig.id}, 版本: ${updatedConfig is QbittorrentConfig ? updatedConfig.version : 'N/A'}',
              );
            }
          }
        } catch (e) {
          if (kDebugMode) {
            _logger.e('保存配置更新失败: $e');
          }
        }
      },
    );
  }

  /// 测试连接
  ///
  /// [config] 下载器配置
  /// [password] 密码
  Future<void> testConnection({
    required DownloaderConfig config,
    required String password,
  }) async {
    await DownloaderFactory.testConnection(config: config, password: password);
  }

  /// 获取传输信息
  ///
  /// [config] 下载器配置
  /// [password] 密码
  Future<TransferInfo> getTransferInfo({
    required DownloaderConfig config,
    required String password,
  }) async {
    final client = DownloaderFactory.getClient(
      config: config,
      password: password,
    );
    return await client.getTransferInfo();
  }

  /// 获取服务器状态
  ///
  /// [config] 下载器配置
  /// [password] 密码
  Future<ServerState> getServerState({
    required DownloaderConfig config,
    required String password,
  }) async {
    final client = DownloaderFactory.getClient(
      config: config,
      password: password,
    );
    return await client.getServerState();
  }

  /// 获取下载任务列表
  ///
  /// [config] 下载器配置
  /// [password] 密码
  /// [params] 查询参数
  Future<List<DownloadTask>> getTasks({
    required DownloaderConfig config,
    required String password,
    GetTasksParams? params,
  }) async {
    final client = DownloaderFactory.getClient(
      config: config,
      password: password,
    );
    return await client.getTasks(params);
  }

  /// 添加下载任务
  ///
  /// [config] 下载器配置
  /// [password] 密码
  /// [params] 添加任务参数
  Future<void> addTask({
    required DownloaderConfig config,
    required String password,
    required AddTaskParams params,
    SiteConfig? siteConfig,
  }) async {
    var effectiveParams = params;
    final siteName = siteConfig?.name.trim();
    if (config.type.supportsTags &&
        siteName != null &&
        siteName.isNotEmpty &&
        await _storageService.loadAutoAddSiteTag()) {
      final siteTag = '站点/$siteName';
      final tags = [...?params.tags];
      if (!tags.contains(siteTag)) {
        tags.add(siteTag);
      }
      effectiveParams = params.copyWith(tags: tags);
    }

    final client = getClient(config: config, password: password);
    await retryOnTimeout<void>(
      () => client.addTask(effectiveParams, siteConfig: siteConfig),
    );
  }

  /// 暂停下载任务
  ///
  /// [config] 下载器配置
  /// [password] 密码
  /// [hashes] 任务哈希列表
  Future<void> pauseTasks({
    required DownloaderConfig config,
    required String password,
    required List<String> hashes,
  }) async {
    final client = DownloaderFactory.getClient(
      config: config,
      password: password,
    );
    await client.pauseTasks(hashes);
  }

  /// 恢复下载任务
  ///
  /// [config] 下载器配置
  /// [password] 密码
  /// [hashes] 任务哈希列表
  Future<void> resumeTasks({
    required DownloaderConfig config,
    required String password,
    required List<String> hashes,
  }) async {
    final client = DownloaderFactory.getClient(
      config: config,
      password: password,
    );
    await client.resumeTasks(hashes);
  }

  /// 删除下载任务
  ///
  /// [config] 下载器配置
  /// [password] 密码
  /// [hashes] 任务哈希列表
  /// [deleteFiles] 是否删除文件
  Future<void> deleteTasks({
    required DownloaderConfig config,
    required String password,
    required List<String> hashes,
    bool deleteFiles = false,
  }) async {
    final client = DownloaderFactory.getClient(
      config: config,
      password: password,
    );
    await client.deleteTasks(hashes, deleteFiles: deleteFiles);
  }

  /// 获取分类列表
  ///
  /// [config] 下载器配置
  /// [password] 密码
  Future<List<String>> getCategories({
    required DownloaderConfig config,
    required String password,
  }) async {
    final client = DownloaderFactory.getClient(
      config: config,
      password: password,
    );
    return await client.getCategories();
  }

  /// 获取标签列表
  ///
  /// [config] 下载器配置
  /// [password] 密码
  Future<List<String>> getTags({
    required DownloaderConfig config,
    required String password,
  }) async {
    final client = DownloaderFactory.getClient(
      config: config,
      password: password,
    );
    return await client.getTags();
  }

  /// 获取版本信息
  ///
  /// [config] 下载器配置
  /// [password] 密码
  Future<String> getVersion({
    required DownloaderConfig config,
    required String password,
  }) async {
    final client = DownloaderFactory.getClient(
      config: config,
      password: password,
    );
    return await client.getVersion();
  }

  /// 取专业增强 API 客户端
  ///
  /// 过去这里靠 `client is QbittorrentClient` 判断能力，接了第二个支持增强 API 的
  /// 下载器之后必须改成显式能力位：能调到但该项功能不存在的下载器（如 Deluge 没有
  /// 标签），要给出具体缺哪一项的提示而不是笼统的「不支持」。
  TorrentManagementClient _managementClient(
    DownloaderConfig config,
    String password, {
    DownloaderFeature? feature,
    String? featureLabel,
  }) {
    final client = DownloaderFactory.getClient(
      config: config,
      password: password,
    );
    if (client is! TorrentManagementClient) {
      throw Exception('当前下载器（${config.type.displayName}）不支持该功能');
    }
    final management = client as TorrentManagementClient;
    if (feature != null && !management.capabilities.has(feature)) {
      throw Exception(
        '当前下载器（${config.type.displayName}）不支持$featureLabel',
      );
    }
    return management;
  }

  /// 新增分类
  Future<void> createCategory({
    required DownloaderConfig config,
    required String password,
    required String category,
    String? savePath,
  }) async {
    await _managementClient(config, password).createCategory(
      category,
      savePath: savePath,
    );
  }

  /// 删除分类
  Future<void> deleteCategory({
    required DownloaderConfig config,
    required String password,
    required String category,
  }) async {
    await _managementClient(config, password).deleteCategory(category);
  }

  /// 批量设置任务分类
  Future<void> setCategory({
    required DownloaderConfig config,
    required String password,
    required List<String> hashes,
    required String category,
  }) async {
    await _managementClient(config, password).setCategory(hashes, category);
  }

  /// 获取下载器自身的原始偏好（qB 走 `/app/preferences`，Deluge 走 `core.get_config`）
  Future<Map<String, dynamic>> getPreferences({
    required DownloaderConfig config,
    required String password,
  }) async {
    return _managementClient(
      config,
      password,
      feature: DownloaderFeature.serverPreferences,
      featureLabel: '服务器设置',
    ).getPreferencesRaw();
  }

  /// 写入偏好增量（键名以目标下载器实机返回的为准）
  Future<void> setPreferences({
    required DownloaderConfig config,
    required String password,
    required Map<String, dynamic> deltas,
  }) async {
    await _managementClient(
      config,
      password,
      feature: DownloaderFeature.serverPreferences,
      featureLabel: '服务器设置',
    ).setPreferences(deltas);
  }

  /// 获取分类明细：名称 -> 保存路径
  Future<Map<String, String>> getCategoryDetails({
    required DownloaderConfig config,
    required String password,
  }) async {
    return _managementClient(config, password).getCategoryDetails();
  }

  /// 修改分类的保存路径
  Future<void> setCategorySavePath({
    required DownloaderConfig config,
    required String password,
    required String category,
    required String savePath,
  }) async {
    await _managementClient(
      config,
      password,
      feature: DownloaderFeature.categorySavePath,
      featureLabel: '分类保存路径',
    ).setCategorySavePath(category, savePath);
  }

  /// 新建标签
  Future<void> createTags({
    required DownloaderConfig config,
    required String password,
    required List<String> tags,
  }) async {
    await _managementClient(
      config,
      password,
      feature: DownloaderFeature.tags,
      featureLabel: '标签管理',
    ).createTags(tags);
  }

  /// 删除标签
  Future<void> deleteTags({
    required DownloaderConfig config,
    required String password,
    required List<String> tags,
  }) async {
    await _managementClient(
      config,
      password,
      feature: DownloaderFeature.tags,
      featureLabel: '标签管理',
    ).deleteTags(tags);
  }

  /// 获取任务连接节点
  Future<List<TorrentPeer>> getTorrentPeers({
    required DownloaderConfig config,
    required String password,
    required String hash,
  }) async {
    return _managementClient(
      config,
      password,
      feature: DownloaderFeature.peers,
      featureLabel: '节点查看',
    ).getTorrentPeers(hash);
  }

  /// 获取任务文件列表
  Future<List<TorrentFile>> getTorrentFiles({
    required DownloaderConfig config,
    required String password,
    required String hash,
  }) async {
    return _managementClient(
      config,
      password,
      feature: DownloaderFeature.fileSelection,
      featureLabel: '文件列表查看',
    ).getTorrentFiles(hash);
  }

  /// 设置文件优先级
  /// priority 取值见 [FilePriority]：0=跳过 1=普通 6=高 7=最高
  Future<void> setFilePriority({
    required DownloaderConfig config,
    required String password,
    required String hash,
    required List<int> ids,
    required int priority,
  }) async {
    await _managementClient(
      config,
      password,
      feature: DownloaderFeature.fileSelection,
      featureLabel: '文件选择',
    ).setFilePriority(hash: hash, ids: ids, priority: priority);
  }

  /// 获取现有下载路径列表
  ///
  /// [config] 下载器配置
  /// [password] 密码
  Future<List<String>> getPaths({
    required DownloaderConfig config,
    required String password,
  }) async {
    final client = DownloaderFactory.getClient(
      config: config,
      password: password,
    );
    return await client.getPaths();
  }

  /// 获取包含版本信息的配置并自动保存
  ///
  /// [config] 下载器配置
  /// [password] 密码
  /// [autoSave] 是否自动保存更新后的配置，默认为true
  /// 返回包含版本信息的配置
  Future<DownloaderConfig> getUpdatedConfigAndSave({
    required DownloaderConfig config,
    required String password,
    bool autoSave = true,
  }) async {
    // 如果配置中已有版本信息，直接返回
    if ((config is QbittorrentConfig || config is DelugeConfig) &&
        config.version != null &&
        config.version!.isNotEmpty) {
      return config;
    }

    try {
      // 获取版本信息
      final version = await getVersion(config: config, password: password);

      // 创建包含版本信息的新配置
      DownloaderConfig updatedConfig;
      if (config is QbittorrentConfig) {
        updatedConfig = config.copyWith(version: version);
      } else if (config is DelugeConfig) {
        updatedConfig = config.copyWith(version: version);
      } else {
        // 其他类型的下载器配置暂时直接返回原配置
        updatedConfig = config;
      }

      // 自动保存配置
      if (autoSave) {
        await _saveUpdatedConfig(updatedConfig);
      }

      return updatedConfig;
    } catch (e) {
      // 如果获取版本失败，返回原配置
      return config;
    }
  }

  /// 保存更新后的配置
  ///
  /// [updatedConfig] 更新后的配置
  Future<void> _saveUpdatedConfig(DownloaderConfig updatedConfig) async {
    try {
      // 加载当前所有配置
      final allConfigMaps = await _storageService.loadDownloaderConfigs();
      final allConfigs = allConfigMaps
          .map((configMap) => DownloaderConfig.fromJson(configMap))
          .toList();
      final defaultId = await _storageService.loadDefaultDownloaderId();

      // 查找并更新对应的配置
      bool configUpdated = false;
      for (int i = 0; i < allConfigs.length; i++) {
        if (allConfigs[i].id == updatedConfig.id) {
          allConfigs[i] = updatedConfig;
          configUpdated = true;
          break;
        }
      }

      // 如果找到了配置并且有更新，保存到存储
      if (configUpdated) {
        await _storageService.saveDownloaderConfigs(
          allConfigs,
          defaultId: defaultId,
        );

        // 清除缓存，确保下次使用新配置
        clearConfigCache(updatedConfig.id);
      }
    } catch (e) {
      // 保存失败时不抛出异常，避免影响主要功能
      debugPrint('保存配置失败: $e');
    }
  }

  /// 暂停单个任务
  ///
  /// [config] 下载器配置
  /// [password] 密码
  /// [hash] 任务哈希
  Future<void> pauseTask({
    required DownloaderConfig config,
    required String password,
    required String hash,
  }) async {
    await pauseTasks(config: config, password: password, hashes: [hash]);
  }

  /// 恢复单个任务
  ///
  /// [config] 下载器配置
  /// [password] 密码
  /// [hash] 任务哈希
  Future<void> resumeTask({
    required DownloaderConfig config,
    required String password,
    required String hash,
  }) async {
    await resumeTasks(config: config, password: password, hashes: [hash]);
  }

  /// 删除单个任务
  ///
  /// [config] 下载器配置
  /// [password] 密码
  /// [hash] 任务哈希
  /// [deleteFiles] 是否删除文件
  Future<void> deleteTask({
    required DownloaderConfig config,
    required String password,
    required String hash,
    bool deleteFiles = false,
  }) async {
    await deleteTasks(
      config: config,
      password: password,
      hashes: [hash],
      deleteFiles: deleteFiles,
    );
  }
}
