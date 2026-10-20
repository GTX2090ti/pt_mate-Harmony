import 'downloader_models.dart';

/// 下载器可选能力。
///
/// 增强功能（Tracker 编辑、文件勾选、分类保存路径等）过去靠 `client is
/// QbittorrentClient` 判断，接了 Deluge 之后必须换成显式能力位：Deluge 能做到的
/// 要和做不到的分得很清楚，否则 UI 会把按钮点亮再报错。
enum DownloaderFeature {
  /// 分类之外的独立标签体系
  tags,

  /// 分类可以绑定保存路径
  categorySavePath,

  /// 增 / 删 / 改 Tracker
  trackerWrite,

  /// 强制开始（忽略队列与限速）
  forceStart,

  /// 超级做种
  superSeeding,

  /// 顺序下载
  sequentialDownload,

  /// 首尾分块优先
  firstLastPiecePriority,

  /// 自动种子管理
  autoManagement,

  /// 队列置顶 / 置底 / 上移 / 下移
  queue,

  /// 按需勾选文件
  fileSelection,

  /// 查看连接节点
  peers,

  /// 全局与单任务限速
  speedLimits,

  /// 备选速率模式（Alt Limit）
  altSpeedLimits,

  /// 「服务器设置」页：可读写下载器自身的偏好键值
  ///
  /// 两边键空间完全不同（qB 是 `/app/preferences`，Deluge 是 `core.get_config`），
  /// 能力位只表示「读得到、写得回去」，字段表由各自的 pref schema 提供。
  serverPreferences,

  /// 历史累计统计（总下载 / 总上传）；qB 还额外给缓存与队列指标
  cumulativeStats,
}

/// 某个下载器实现支持的能力集合
class DownloaderCapabilities {
  const DownloaderCapabilities({required this.features});

  final Set<DownloaderFeature> features;

  bool has(DownloaderFeature feature) => features.contains(feature);

  /// Transmission / ruTorrent 只实现基础契约，增强能力全缺
  static const DownloaderCapabilities none = DownloaderCapabilities(
    features: {},
  );

  /// 按配置类型取能力集合，供 UI 门控使用
  ///
  /// 服务层是拿到客户端实例再查 capabilities，设置页手里只有配置，不想到时就建一个
  /// 客户端；这里给出同源映射，免得两边各写一份「是不是 qB」的判断。
  static DownloaderCapabilities forType(DownloaderType type) {
    return switch (type) {
      DownloaderType.qbittorrent => qbittorrent,
      DownloaderType.deluge => deluge,
      DownloaderType.transmission || DownloaderType.rutorrent => none,
    };
  }

  /// qBittorrent WebAPI 覆盖全部能力
  static const DownloaderCapabilities qbittorrent = DownloaderCapabilities(
    features: {
      DownloaderFeature.tags,
      DownloaderFeature.categorySavePath,
      DownloaderFeature.trackerWrite,
      DownloaderFeature.forceStart,
      DownloaderFeature.superSeeding,
      DownloaderFeature.sequentialDownload,
      DownloaderFeature.firstLastPiecePriority,
      DownloaderFeature.autoManagement,
      DownloaderFeature.queue,
      DownloaderFeature.fileSelection,
      DownloaderFeature.peers,
      DownloaderFeature.speedLimits,
      DownloaderFeature.altSpeedLimits,
      DownloaderFeature.serverPreferences,
      DownloaderFeature.cumulativeStats,
    },
  );

  /// Deluge：没有标签体系，也没有 qB 那样的强制开始 / 备选速率。
  ///
  /// 分类保存路径走 Label 插件的 `move_completed_path`，语义是「下载完成后移动到
  /// 该路径」而不是 qB 的「直接落盘到该路径」，能力位仍算支持，文案上要说明。
  /// 累计统计只能给出总下载/总上传（按种子求和，2.2.0 实机核对），
  /// 缓存与队列指标拿不到。
  /// 服务器设置读写 `core.get_config` 的扁平键，限速单位本身就是 KiB/s。
  static const DownloaderCapabilities deluge = DownloaderCapabilities(
    features: {
      DownloaderFeature.categorySavePath,
      DownloaderFeature.trackerWrite,
      DownloaderFeature.superSeeding,
      DownloaderFeature.sequentialDownload,
      DownloaderFeature.firstLastPiecePriority,
      DownloaderFeature.autoManagement,
      DownloaderFeature.queue,
      DownloaderFeature.fileSelection,
      DownloaderFeature.peers,
      DownloaderFeature.speedLimits,
      DownloaderFeature.serverPreferences,
      DownloaderFeature.cumulativeStats,
    },
  );
}

/// 专业增强 API 契约（qBittorrent 风格），由 [QbittorrentClient] 与
/// [DelugeClient] 实现。
///
/// 这里的每个方法都对应下载管理页 / 种子详情页 / 服务器设置页的一个真实交互，
/// 服务层用 `client is TorrentManagementClient` 决定能不能调，用
/// [TorrentManagementClient.capabilities] 决定具体哪一项能调。
abstract class TorrentManagementClient {
  DownloaderCapabilities get capabilities;

  // ---------- Tracker ----------

  Future<List<TorrentTracker>> getTrackers(String hash);

  Future<void> reannounceTorrents(List<String> hashes);

  Future<void> addTracker(String hash, String trackerUrl);

  Future<void> editTracker(String hash, String originalUrl, String newUrl);

  Future<void> removeTrackers(String hash, List<String> urls);

  // ---------- 任务属性 ----------

  Future<TorrentProperties> getTorrentProperties(String hash);

  /// 单任务原始信息，字段名按 qB 别名补齐，供概览页直接取值
  Future<Map<String, dynamic>?> getTorrentInfoRaw(String hash);

  // ---------- 任务开关 ----------

  Future<void> setForceStart(List<String> hashes, bool value);

  Future<void> setSuperSeeding(List<String> hashes, bool value);

  Future<void> setAutoManagement(List<String> hashes, bool value);

  Future<void> toggleSequentialDownload(List<String> hashes);

  Future<void> toggleFirstLastPiecePrio(List<String> hashes);

  // ---------- 队列 ----------

  Future<void> topPriority(List<String> hashes);

  Future<void> bottomPriority(List<String> hashes);

  Future<void> increasePriority(List<String> hashes);

  Future<void> decreasePriority(List<String> hashes);

  // ---------- 分类 / 标签 ----------

  Future<void> addTags(List<String> hashes, List<String> tags);

  Future<void> removeTags(List<String> hashes, List<String> tags);

  Future<void> createTags(List<String> tags);

  Future<void> deleteTags(List<String> tags);

  Future<void> setCategory(List<String> hashes, String category);

  Future<void> recheckTorrents(List<String> hashes);

  Future<void> createCategory(String category, {String? savePath});

  Future<void> deleteCategory(String category);

  /// 分类明细：名称 -> 保存路径
  Future<Map<String, String>> getCategoryDetails();

  Future<void> setCategorySavePath(String category, String savePath);

  // ---------- 节点 / 文件 ----------

  Future<List<TorrentPeer>> getTorrentPeers(String hash);

  Future<List<TorrentFile>> getTorrentFiles(String hash);

  /// [ids] 为文件 index 列表，[priority] 取值见 [FilePriority]
  Future<void> setFilePriority({
    required String hash,
    required List<int> ids,
    required int priority,
  });

  // ---------- 偏好 / 限速 ----------

  Future<GlobalPreferences> getGlobalPreferences();

  Future<Map<String, dynamic>> getPreferencesRaw();

  Future<void> setPreferences(Map<String, dynamic> deltas);

  /// 单位 KiB/s，-1 表示不限速
  Future<void> setGlobalDownloadLimit(int limitKib);

  Future<void> setGlobalUploadLimit(int limitKib);

  /// 0=全局 1=备选 2=调度
  Future<void> setSpeedLimitsMode(int mode);
}
