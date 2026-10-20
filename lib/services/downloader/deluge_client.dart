// Keep the public `onConfigUpdated` named parameter stable.
// ignore_for_file: prefer_initializing_formals

import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart';

import '../../models/app_models.dart';
import '../../utils/format.dart';
import '../network/proxy_service.dart';
import '../network/timeout_retry.dart';
import 'downloader_capabilities.dart';
import 'downloader_client.dart';
import 'downloader_config.dart';
import 'downloader_models.dart';
import 'torrent_file_downloader_mixin.dart';

/// Deluge 下载器客户端实现（WebUI JSON-RPC）
///
/// 协议要点（对照 Deluge 2.1.1 源码 `deluge/ui/web/json_api.py`，并用
/// Deluge 2.2.0 / libtorrent 2.0.13 实机核对过字段与接口名）：
/// * 所有调用都是 `POST /json`，请求体 `{"method":..., "params":[位置参数], "id":n}`；
/// * 业务失败仍然是 HTTP 200，错误放在响应体的 `error` 里，`code` 含义：
///   1=未认证、2=方法不存在、3=核心异常、4=延迟失败、5=请求格式错误；
/// * 登录只有密码一项（WebUI 是单用户，用户名固定 admin），成功后服务端下发
///   `_session_id` Cookie，作用域是 `/json`；
/// * 明文 http 地址常被 WebUI/反向代理用 307 跳到 https，而 Dart 的 HTTP 客户端
///   不会替 POST 跟随重定向，所以 [_postJson] 自己按 Location 重发。
///
/// Deluge 的分类就是 Label 插件的 label，一个种子只能挂一个 label，且没有与分类
/// 并列的标签体系，因此 [DownloaderFeature.tags] 为 false。Label 未启用时所有
/// `label.*` 调用抛 [DelugeMethodUnavailableException]。
class DelugeClient
    with TorrentFileDownloaderMixin
    implements DownloaderClient, TorrentManagementClient {
  final DelugeConfig config;
  final String password;

  late final Dio _dio;
  String? _authCookieHeader;
  String? _cachedVersion;

  /// WebUI 把 http 明文请求跳到 https 之后记下的真实地址；后续请求直接打这里，
  /// 免得每次轮询都多走一跳重定向。
  Uri? _resolvedJsonUri;
  int _requestId = 0;

  final Function(DelugeConfig)? _onConfigUpdated;

  DelugeClient({
    required this.config,
    required this.password,
    Function(DelugeConfig)? onConfigUpdated,
    Dio? dio,
  }) : _onConfigUpdated = onConfigUpdated {
    _dio = dio ?? _createDio(config);
  }

  static const String _jsonPath = '/json';

  /// JSON-RPC 错误码
  static const int _errNotAuthenticated = 1;
  static const int _errUnknownMethod = 2;

  /// 任务列表需要的状态键。只列确定存在的键：Deluge 对未知键的处理不保证兼容，
  /// 拿不准的键一律不放进来。
  ///
  /// 2.2.0 实机回报：没有 `total_downloaded`（历史累计下载叫
  /// `all_time_download`）；`label` 只有装了 Label 插件才出现，缺键不影响其它字段。
  static const List<String> _taskKeys = [
    'name',
    'state',
    'paused',
    'progress',
    'total_size',
    'total_done',
    'all_time_download',
    'total_uploaded',
    'download_payload_rate',
    'upload_payload_rate',
    'eta',
    'ratio',
    'seeding_time',
    'active_time',
    'time_added',
    'download_location',
    'save_path',
    'label',
    'num_seeds',
    'num_peers',
    'total_seeds',
    'total_peers',
    'is_seed',
    'is_finished',
    'auto_managed',
    'super_seeding',
    'sequential_download',
    'prioritize_first_last',
    'queue',
    'message',
    'private',
    'trackers',
    'tracker_host',
    'tracker_status',
  ];

  static Dio _createDio(DelugeConfig config) {
    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 20),
        receiveTimeout: const Duration(seconds: 30),
        headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/143.0.0.0 Safari/537.36',
        },
        followRedirects: true,
        maxRedirects: 5,
      ),
    );
    if (config.allowSelfSignedCert) {
      dio.httpClientAdapter = IOHttpClientAdapter(
        createHttpClient: () {
          final HttpClient client = HttpClient()
            ..badCertificateCallback = (
              X509Certificate cert,
              String host,
              int port,
            ) => true;
          return client;
        },
      );
    }
    return dio;
  }

  String get _baseUrl => _buildBase(config);

  /// 构建基础URL，处理各种格式的主机地址（与 qBittorrent 客户端一致）
  String _buildBase(DelugeConfig c) {
    var urlStr = c.host.trim();
    if (!urlStr.startsWith(RegExp(r'https?://'))) {
      urlStr = 'http://$urlStr';
    }

    try {
      final uri = Uri.parse(urlStr);
      final port = (c.port > 0) ? c.port : (uri.hasPort ? uri.port : null);
      var result = uri.replace(port: port).toString();
      if (result.endsWith('/')) {
        result = result.substring(0, result.length - 1);
      }
      return result;
    } catch (e) {
      return urlStr;
    }
  }

  @override
  DownloaderCapabilities get capabilities => DownloaderCapabilities.deluge;

  // ============================================================
  // JSON-RPC 通道
  // ============================================================

  Map<String, String> get _jsonHeaders => {
    'Content-Type': 'application/json',
    // Deluge WebUI 自带的 fetch 封装会带这个头，部分反代/网关只放行它
    'X-Requested-With': 'XMLHttpRequest',
  };

  /// 调用一个 RPC 方法，返回 `result`
  Future<dynamic> _call(
    String method, [
    List<dynamic> params = const [],
    bool allowRetry = true,
  ]) async {
    if (_authCookieHeader == null) {
      await _login();
    }

    final response = await _postJson(
      jsonEncode({'method': method, 'params': params, 'id': ++_requestId}),
    );

    final data = response.data;
    if (data is! Map) {
      throw Exception(
        'Deluge 返回的不是 JSON：请确认填写的是 WebUI 地址（默认端口 8112），'
        '而不是某个反向代理的静态页面',
      );
    }

    final error = data['error'];
    if (error is Map) {
      final code = _asInt(error['code']);
      final message = error['message']?.toString() ?? '未知错误';
      if (code == _errNotAuthenticated) {
        _authCookieHeader = null;
        if (allowRetry) {
          return _call(method, params, false);
        }
        throw Exception('Deluge 会话已失效，重新登录后仍被拒绝：$message');
      }
      if (code == _errUnknownMethod) {
        throw DelugeMethodUnavailableException(method, message);
      }
      throw HttpException('Deluge 接口「$method」失败: $message');
    }

    return data['result'];
  }

  static const int _maxRedirectHops = 3;

  Future<Response> _postJson(String body) async {
    final headers = _jsonHeaders;
    final cookie = _authCookieHeader;
    if (cookie != null) headers['Cookie'] = cookie;

    // Deluge WebUI 常把 http 明文请求用 307 跳到 https，而 Dart 的 HTTP 客户端
    // 不会替 POST 跟随重定向（即使 followRedirects=true 也只返回 3xx 空响应体），
    // 所以自己按 Location 重发一次，并把跳转后的地址记住。
    var target = _resolvedJsonUri ?? Uri.parse('$_baseUrl$_jsonPath');
    for (var hop = 0; hop <= _maxRedirectHops; hop++) {
      try {
        final response = await _dio.post(
          target.toString(),
          data: body,
          options: Options(
            headers: headers,
            responseType: ResponseType.json,
            followRedirects: false,
            // Deluge 的业务错误也在 200 里，交给 _call 解析
            validateStatus: (status) => status != null && status < 400,
          ),
        );
        final next = _redirectTarget(response, target);
        if (next == null) return response;
        target = next;
        _resolvedJsonUri = next;
      } on DioException catch (e) {
        throw _transportError(e);
      }
    }
    throw Exception('Deluge 地址反复重定向，最后停在 $target：请检查反向代理配置');
  }

  /// 响应是 3xx 且带 Location 时返回下一个请求地址，否则返回 null
  Uri? _redirectTarget(Response response, Uri from) {
    const redirecting = [301, 302, 303, 307, 308];
    final status = response.statusCode ?? 0;
    if (!redirecting.contains(status)) return null;
    final location = response.headers.value('location')?.trim();
    if (location == null || location.isEmpty) return null;
    return from.resolve(location);
  }

  Object _transportError(DioException e) {
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.sendTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.connectionError) {
      ProxyService.instance.scheduleProbeIfNeeded();
    }
    if (isTimeoutError(e)) return e;

    final status = e.response?.statusCode;
    if (status == 401 || status == 403) {
      _authCookieHeader = null;
      return Exception(
        'Deluge 拒绝了请求（HTTP $status）：请检查 WebUI 密码与访问来源',
      );
    }
    if (status == 405) {
      return Exception('Deluge 的 $_jsonPath 只接受 POST，地址可能被代理改写');
    }
    if (status != null && status >= 400) {
      return HttpException('HTTP $status: ${e.response?.data}');
    }
    return Exception('请求 Deluge 失败: ${e.message}');
  }

  /// 登录：Deluge WebUI 只校验密码，成功后取 `_session_id` Cookie
  Future<void> _login() async {
    final body = jsonEncode({
      'method': 'auth.login',
      'params': [password],
      'id': ++_requestId,
    });

    _authCookieHeader = null;
    final response = await _postJson(body);

    final data = response.data;
    if (data is! Map) {
      throw Exception('Deluge 登录响应不是 JSON，请检查 WebUI 地址');
    }
    final error = data['error'];
    if (error is Map) {
      throw Exception('Deluge 登录失败: ${error['message']}');
    }
    if (data['result'] != true) {
      throw Exception('Deluge 登录失败：密码不正确');
    }

    final cookieHeader = _extractCookieHeader(response.headers['set-cookie']);
    if (cookieHeader == null || cookieHeader.isEmpty) {
      throw Exception('Deluge 登录后没有下发会话 Cookie（_session_id）');
    }
    _authCookieHeader = cookieHeader;
  }

  String? _extractCookieHeader(List<String>? setCookieHeaders) {
    if (setCookieHeaders == null || setCookieHeaders.isEmpty) {
      return null;
    }

    final cookieMap = <String, String>{};
    final cookieOrder = <String>[];

    for (final header in setCookieHeaders) {
      final firstPart = header.split(';').first.trim();
      final separatorIndex = firstPart.indexOf('=');
      if (separatorIndex <= 0) {
        continue;
      }

      final name = firstPart.substring(0, separatorIndex).trim();
      final value = firstPart.substring(separatorIndex + 1).trim();
      if (name.isEmpty) {
        continue;
      }

      if (!cookieMap.containsKey(name)) {
        cookieOrder.add(name);
      }
      cookieMap[name] = value;
    }

    if (cookieMap.isEmpty) {
      return null;
    }

    return cookieOrder.map((name) => '$name=${cookieMap[name]}').join('; ');
  }

  @visibleForTesting
  String? get debugAuthCookieHeader => _authCookieHeader;

  @visibleForTesting
  String? debugExtractCookieHeader(List<String>? setCookieHeaders) {
    return _extractCookieHeader(setCookieHeaders);
  }

  /// 枚举实例支持的全部方法，探测与排障用
  @visibleForTesting
  Future<List<String>> listMethods() async {
    // Deluge 从来没有 system.listMethods，方法表由 daemon 提供
    final result = await _callAny(
      const ['daemon.get_method_list', 'system.listMethods'],
    );
    if (result is! List) return const [];
    return result.map((e) => e.toString()).toList()..sort();
  }

  /// 依次尝试候选方法，全部「方法不存在」时抛出最后一个异常。
  /// 用于跨版本兼容：Deluge 小版本改过接口名。
  Future<dynamic> _callAny(
    List<String> methods, [
    List<dynamic> params = const [],
  ]) async {
    Object? lastError;
    for (final method in methods) {
      try {
        return await _call(method, params);
      } on DelugeMethodUnavailableException catch (e) {
        lastError = e;
      }
    }
    throw lastError!;
  }

  // ============================================================
  // DownloaderClient
  // ============================================================

  @override
  Future<void> testConnection() async {
    try {
      await _login();
      await getVersion();
    } catch (e) {
      throw Exception('Connection test failed: $e');
    }
  }

  @override
  Future<TransferInfo> getTransferInfo() async {
    // Deluge 的 session_status 键集在各小版本间不稳定（2.2.0 实测只剩 num_peers、
    // dht_nodes），改成按种子求和：这恰好也是 WebUI 自己算「Total DL/UL」的方式。
    final torrents = await _torrentStatusMap(
      const [
        'download_payload_rate',
        'upload_payload_rate',
        'all_time_download',
        'total_uploaded',
      ],
    );

    var dlSpeed = 0;
    var upSpeed = 0;
    var dlTotal = 0;
    var upTotal = 0;
    for (final torrent in torrents.values) {
      dlSpeed += _asInt(torrent['download_payload_rate']);
      upSpeed += _asInt(torrent['upload_payload_rate']);
      dlTotal += _downloadedBytes(torrent);
      upTotal += _asInt(torrent['total_uploaded']);
    }

    return TransferInfo(
      upSpeed: upSpeed,
      dlSpeed: dlSpeed,
      upTotal: upTotal,
      dlTotal: dlTotal,
    );
  }

  @override
  Future<ServerState> getServerState() async {
    // 不带路径时 Deluge 用默认下载目录查询剩余空间；2.2.0 实测直接回报整数
    final free = _asInt(await _call('core.get_free_space'));

    // 累计流量：core.get_session_status 在 2.x 已经不再回报这些键，
    // 只能按种子求和（与 getTransferInfo 同一口径）
    final torrents = await _torrentStatusMap(
      const ['all_time_download', 'total_uploaded'],
    );
    var dlTotal = 0;
    var upTotal = 0;
    for (final torrent in torrents.values) {
      dlTotal += _downloadedBytes(torrent);
      upTotal += _asInt(torrent['total_uploaded']);
    }

    return ServerState(
      freeSpaceOnDisk: free,
      alltimeDl: dlTotal,
      alltimeUl: upTotal,
    );
  }

  @override
  Future<List<DownloadTask>> getTasks([GetTasksParams? params]) async {
    final raw = await _torrentStatusMap(_taskKeys);
    var tasks = raw.entries
        .map((e) => _convertToDownloadTask(e.key, e.value))
        .toList();

    // Deluge 没有服务端筛选/排序/分页，全部在本地做
    if (params != null) {
      final filter = params.filter;
      if (filter != null && filter != 'all') {
        tasks = tasks.where((t) => _matchesFilter(t, filter)).toList();
      }
      final category = params.category;
      if (category != null && category.isNotEmpty && category != 'all') {
        tasks = tasks.where((t) => t.category == category).toList();
      }
      final tag = params.tag;
      if (tag != null && tag.isNotEmpty && tag != 'all') {
        tasks = tasks.where((t) => t.tags.contains(tag)).toList();
      }
      final sort = params.sort;
      if (sort != null && sort.isNotEmpty) {
        tasks.sort((a, b) => _compareBySort(a, b, sort));
        if (params.reverse == true) {
          tasks = tasks.reversed.toList();
        }
      }
      final limit = params.limit;
      final offset = params.offset ?? 0;
      if (offset > 0 || limit != null) {
        final start = offset.clamp(0, tasks.length);
        final end = limit == null
            ? tasks.length
            : (start + limit).clamp(start, tasks.length);
        tasks = tasks.sublist(start, end);
      }
    }

    return tasks;
  }

  @override
  Future<void> addTask(AddTaskParams params, {SiteConfig? siteConfig}) async {
    var url = params.url;
    var forceRelay = false;
    if (url.startsWith('##')) {
      url = url.substring(2);
      forceRelay = true;
    }

    final options = <String, dynamic>{};
    // 添加接口只带 download_location：Deluge 各小版本对 add_torrent_* 的选项键名
    // 不一致（paused / auto_managed 会被判成非法选项直接报错），这两项改用添加
    // 之后的专用接口设置。
    if (params.savePath != null && params.savePath!.isNotEmpty) {
      options['download_location'] = params.savePath;
    }

    // Deluge 的 add_torrent_url 不会带站点 Cookie，PT 站需要勾选「本地中转」，
    // 勾选后先把种子下载到本地再以 base64 上传（core.add_torrent_file）。
    final useRelay = config.useLocalRelay || forceRelay;
    final dynamic added;
    if (useRelay) {
      final torrentData = await downloadTorrentFileCommon(
        _dio,
        url,
        siteConfig: siteConfig,
      );
      added = await _call('core.add_torrent_file', [
        'ptmate.torrent',
        base64Encode(torrentData),
        options,
      ]);
    } else {
      added = await _call('core.add_torrent_url', [url, options]);
    }

    final hash = _addedHash(added);
    if (hash == null) {
      if (params.category != null && params.category!.isNotEmpty) {
        debugPrint('Deluge 添加任务未回传种子 ID，分类「${params.category}」需稍后手动设置: $added');
      }
      return;
    }

    if (params.startPaused == true) {
      await _call('core.pause_torrents', [[hash]]);
    }
    final autoTMM = params.autoTMM;
    if (autoTMM != null) {
      await _call('core.set_torrent_auto_managed', [hash, autoTMM]);
    }

    final category = params.category;
    if (category == null || category.isEmpty) return;
    try {
      await _setLabel(hash, category);
    } on DelugeMethodUnavailableException {
      // 种子这时已经在下载器里了，Label 插件没开只影响分类，不该把整次添加判失败
      debugPrint('Deluge 未启用 Label 插件，分类「$category」未设置: $hash');
    }
  }

  /// 添加接口返回的是种子 ID 字符串；个别版本会附带前后缀或返回状态串
  String? _addedHash(dynamic added) {
    if (added is! String) return null;
    final match = RegExp(r'([0-9a-fA-F]{40})').firstMatch(added);
    return match?.group(1)?.toLowerCase();
  }

  @override
  Future<void> pauseTasks(List<String> hashes) async {
    if (hashes.isEmpty) return;
    await _call('core.pause_torrents', [hashes]);
  }

  @override
  Future<void> resumeTasks(List<String> hashes) async {
    if (hashes.isEmpty) return;
    await _call('core.resume_torrents', [hashes]);
  }

  @override
  Future<void> deleteTasks(List<String> hashes, {bool deleteFiles = false}) async {
    if (hashes.isEmpty) return;
    await _call('core.remove_torrents', [hashes, deleteFiles]);
  }

  @override
  Future<List<String>> getCategories() async {
    return (await _labelOptions()).keys.toList()..sort();
  }

  @override
  Future<List<String>> getTags() async {
    // Deluge 只有 label，标签体系由能力位关闭，页面不会走到这里
    return const [];
  }

  @override
  Future<String> getVersion() async {
    if (_cachedVersion != null) {
      return _cachedVersion!;
    }

    // 2.x 提供 daemon.get_version，1.3.x 只有 daemon.info
    final version = (await _callAny(
      const ['daemon.get_version', 'daemon.info'],
    )).toString();

    _cachedVersion = version;

    if (config.version == null || config.version?.isEmpty == true) {
      _onConfigUpdated?.call(config.copyWith(version: version));
    }

    return version;
  }

  @override
  Future<List<String>> getPaths() async {
    final raw = await _torrentStatusMap(const ['download_location']);
    final paths = <String>{};
    for (final torrent in raw.values) {
      final path = torrent['download_location']?.toString() ?? '';
      if (path.isNotEmpty) paths.add(path);
    }
    final result = paths.toList()..sort();
    return result;
  }

  @override
  Future<void> pauseTask(String hash) => pauseTasks([hash]);

  @override
  Future<void> resumeTask(String hash) => resumeTasks([hash]);

  @override
  Future<void> deleteTask(String hash, {bool deleteFiles = false}) =>
      deleteTasks([hash], deleteFiles: deleteFiles);

  // ============================================================
  // 专业增强 API：Tracker
  // ============================================================

  @override
  Future<List<TorrentTracker>> getTrackers(String hash) async {
    final status = await _torrentStatus(hash, const [
      'trackers',
      'tracker_host',
      'tracker_status',
      'num_seeds',
      'num_peers',
    ]);
    final entries = status['trackers'];
    if (entries is! List) return const [];

    final currentHost = _hostOf(status['tracker_host']?.toString() ?? '');
    final trackerStatus = status['tracker_status']?.toString() ?? '';

    final result = <TorrentTracker>[];
    for (final entry in entries.whereType<Map>()) {
      final url = entry['url']?.toString() ?? '';
      // Deluge 的 tracker 字典只给 swarm 统计（scrape_*）与失败次数，
      // 逐条状态要靠这些间接信号 + 种子级 tracker_status 兜底
      final seeds = _asInt(entry['scrape_complete']);
      final leeches = _asInt(entry['scrape_incomplete']);
      final isCurrent = _sameTrackerHost(_hostOf(url), currentHost);
      final ownMessage =
          (entry['message'] ?? entry['msg'])?.toString() ?? '';
      result.add(
        TorrentTracker(
          url: url,
          status: _trackerStatus(
            url: url,
            rawStatus: entry['status'] ?? entry['state'],
            fails: _asInt(entry['fails']),
            updating: entry['updating'] == true,
            isCurrent: isCurrent,
            trackerStatus: trackerStatus,
          ),
          // Deluge 的逐条 message 常为空串，此时用种子级 tracker_status 兜底
          message: ownMessage.isNotEmpty
              ? ownMessage
              : (isCurrent ? trackerStatus : ''),
          numPeers: _asInt(entry['num_peers'] ?? entry['peers']),
          numSeeds: seeds,
          numLeeches: leeches,
          numDownloads: _asInt(entry['scrape_downloaded']),
          lastSeen: _asInt(entry['last_seen']),
          tier: _asInt(entry['tier']),
          seeds: seeds,
          leeches: leeches,
          peers: _asInt(entry['num_peers'] ?? entry['peers']),
        ),
      );
    }
    return result;
  }

  /// Deluge 只回报种子级的 tracker 汇总信息，逐条状态要按当前 tracker 近似
  int _trackerStatus({
    required String url,
    required dynamic rawStatus,
    required int fails,
    required bool updating,
    required bool isCurrent,
    required String trackerStatus,
  }) {
    if (url.isEmpty) return 0; // 已禁用
    final direct = _asInt(rawStatus);
    if (direct > 0) return direct;
    if (updating) return 3; // 正在更新
    if (fails > 0) return 4; // 本轮 announce 失败

    final normalized = trackerStatus.toLowerCase();
    final isError =
        normalized.contains('error') ||
        normalized.contains('unreachable') ||
        normalized.contains('timed out') ||
        normalized.contains('timeout') ||
        normalized.contains('failed') ||
        normalized.contains('tracker error') ||
        normalized.contains('no peers');
    if (isCurrent) {
      if (isError) return 4; // 工作不正常 / 红种
      if (normalized.contains('updating') || normalized.contains('announce sent')) {
        return 3;
      }
      return trackerStatus.isEmpty ? 1 : 2;
    }
    return isError ? 4 : 1; // 未联系
  }

  String _hostOf(String url) {
    if (url.isEmpty) return '';
    try {
      final uri = Uri.parse(url.startsWith('http') ? url : 'http://$url');
      return uri.host.isEmpty ? url : uri.host;
    } catch (e) {
      return url;
    }
  }

  /// Deluge 的 tracker_host 有时只给注册域名（pandapt.net），
  /// 而 tracker.url 里是完整主机名（tracker.pandapt.net），两边要能互认
  bool _sameTrackerHost(String a, String b) {
    if (a.isEmpty || b.isEmpty) return false;
    if (a == b) return true;
    return a.endsWith('.$b') || b.endsWith('.$a');
  }

  @override
  Future<void> reannounceTorrents(List<String> hashes) async {
    if (hashes.isEmpty) return;
    await _call('core.force_reannounce', [hashes]);
  }

  @override
  Future<void> addTracker(String hash, String trackerUrl) async {
    final current = await _trackerEntries(hash);
    if (current.any((e) => e['url'] == trackerUrl)) return;
    final maxTier = current.isEmpty
        ? 0
        : current.map((e) => _asInt(e['tier'])).reduce((a, b) => a > b ? a : b);
    current.add({'url': trackerUrl, 'tier': maxTier});
    await _call('core.set_torrent_trackers', [hash, current]);
  }

  @override
  Future<void> editTracker(String hash, String originalUrl, String newUrl) async {
    final current = await _trackerEntries(hash);
    final replaced = current
        .map((e) => e['url'] == originalUrl ? {...e, 'url': newUrl} : e)
        .toList();
    await _call('core.set_torrent_trackers', [hash, replaced]);
  }

  @override
  Future<void> removeTrackers(String hash, List<String> urls) async {
    final current = await _trackerEntries(hash);
    final kept = current.where((e) => !urls.contains(e['url'])).toList();
    await _call('core.set_torrent_trackers', [hash, kept]);
  }

  Future<List<Map<String, dynamic>>> _trackerEntries(String hash) async {
    final status = await _torrentStatus(hash, const ['trackers']);
    final entries = status['trackers'];
    if (entries is! List) return [];
    return entries
        .whereType<Map>()
        .map(
          (e) => <String, dynamic>{
            'url': e['url']?.toString() ?? '',
            'tier': _asInt(e['tier']),
          },
        )
        .where((e) => (e['url'] as String).isNotEmpty)
        .toList();
  }

  // ============================================================
  // 专业增强 API：任务属性
  // ============================================================

  @override
  Future<TorrentProperties> getTorrentProperties(String hash) async {
    final status = await _torrentStatus(hash, _taskKeys);
    return TorrentProperties(
      addedOn: _asInt(status['time_added']),
      completionOn: 0, // Deluge 不回报完成时间戳
      savePath: _savePathOf(status),
      contentPath: _contentPath(status),
      seedingTime: _asInt(status['seeding_time']),
      totalSize: _asInt(status['total_size']),
      shareRatio: _asDouble(status['ratio']),
      upTotal: _asInt(status['total_uploaded']),
      dlTotal: _downloadedBytes(status),
      timeActive: _asInt(status['active_time']),
      numSeeds: _asInt(status['total_seeds'] ?? status['num_seeds']),
      // Deluge 的 total_* 是 swarm 规模，num_* 是当前连接数
      numLeeches: _asInt(status['total_peers'] ?? status['num_peers']),
      numPeers: _asInt(status['num_peers']),
      dlSpeed: _asInt(status['download_payload_rate']),
      upSpeed: _asInt(status['upload_payload_rate']),
    );
  }

  @override
  Future<Map<String, dynamic>?> getTorrentInfoRaw(String hash) async {
    final status = await _torrentStatus(hash, _taskKeys);
    if (status.isEmpty) return null;

    final size = _asInt(status['total_size']);
    final done = _asInt(status['total_done']);

    // 概览页沿用 qB 的字段名，这里把 Deluge 的键补齐成同一套别名，
    // 页面不需要为 Deluge 再写一套取值逻辑。
    return <String, dynamic>{
      ...status,
      'hash': hash,
      'size': size,
      'amount_left': done >= size ? 0 : size - done,
      'downloaded': _downloadedBytes(status),
      'uploaded': status['total_uploaded'],
      'dlspeed': status['download_payload_rate'],
      'upspeed': status['upload_payload_rate'],
      'added_on': status['time_added'],
      'time_active': status['active_time'],
      'category': _categoryOf(status['label']),
      'tags': '',
      'save_path': _savePathOf(status),
      'content_path': _contentPath(status),
      'num_complete': status['total_seeds'] ?? status['num_seeds'],
      'num_incomplete': status['total_peers'] ?? status['num_peers'],
      'num_peers': status['num_peers'],
      'f_l_piece_prio': status['prioritize_first_last'],
      'first_last_piece_prio': status['prioritize_first_last'],
      'auto_tmm': status['auto_managed'],
      'private': status['private'],
    };
  }

  /// 2.x 会同时回报 `save_path` 与 `download_location`（取值一致），前者优先
  String _savePathOf(Map<String, dynamic> status) {
    final savePath = status['save_path']?.toString() ?? '';
    if (savePath.isNotEmpty) return savePath;
    return status['download_location']?.toString() ?? '';
  }

  String _contentPath(Map<String, dynamic> status) {
    final savePath = _savePathOf(status);
    final name = status['name']?.toString() ?? '';
    if (savePath.isEmpty || name.isEmpty) return savePath;
    if (savePath.endsWith('/')) return '$savePath$name';
    return '$savePath/$name';
  }

  /// 历史累计下载字节：2.x 叫 `all_time_download`，老版本叫 `total_downloaded`，
  /// 两个都没有时退回 `total_done`（下载完成的种子里两者相等）
  int _downloadedBytes(Map<String, dynamic> status) {
    final raw = status['all_time_download'] ?? status['total_downloaded'];
    if (raw != null) return _asInt(raw);
    return _asInt(status['total_done']);
  }

  // ============================================================
  // 专业增强 API：任务开关
  // ============================================================

  @override
  Future<void> setForceStart(List<String> hashes, bool value) async {
    throw _unsupported(DownloaderFeature.forceStart, '强制开始');
  }

  @override
  Future<void> setSuperSeeding(List<String> hashes, bool value) async {
    await _setOptions(hashes, {'super_seeding': value});
  }

  @override
  Future<void> setAutoManagement(List<String> hashes, bool value) async {
    await _setOptions(hashes, {'auto_managed': value});
  }

  @override
  Future<void> toggleSequentialDownload(List<String> hashes) async {
    // Deluge 的 set_torrent_options 是写值而不是翻转，先读当前值
    for (final hash in hashes) {
      final status = await _torrentStatus(hash, const ['sequential_download']);
      await _setOptions([hash], {
        'sequential_download': status['sequential_download'] != true,
      });
    }
  }

  @override
  Future<void> toggleFirstLastPiecePrio(List<String> hashes) async {
    for (final hash in hashes) {
      final status = await _torrentStatus(hash, const ['prioritize_first_last']);
      await _setOptions([hash], {
        'prioritize_first_last': status['prioritize_first_last'] != true,
      });
    }
  }

  Future<void> _setOptions(List<String> hashes, Map<String, dynamic> options) async {
    if (hashes.isEmpty) return;
    await _call('core.set_torrent_options', [hashes, options]);
  }

  // ============================================================
  // 专业增强 API：队列
  // ============================================================

  @override
  Future<void> topPriority(List<String> hashes) async {
    if (hashes.isEmpty) return;
    await _call('core.queue_top', [hashes]);
  }

  @override
  Future<void> bottomPriority(List<String> hashes) async {
    if (hashes.isEmpty) return;
    await _call('core.queue_bottom', [hashes]);
  }

  @override
  Future<void> increasePriority(List<String> hashes) async {
    if (hashes.isEmpty) return;
    await _call('core.queue_up', [hashes]);
  }

  @override
  Future<void> decreasePriority(List<String> hashes) async {
    if (hashes.isEmpty) return;
    await _call('core.queue_down', [hashes]);
  }

  // ============================================================
  // 专业增强 API：分类 / 标签
  // ============================================================

  @override
  Future<void> addTags(List<String> hashes, List<String> tags) async {
    throw _unsupported(DownloaderFeature.tags, '标签管理');
  }

  @override
  Future<void> removeTags(List<String> hashes, List<String> tags) async {
    throw _unsupported(DownloaderFeature.tags, '标签管理');
  }

  @override
  Future<void> createTags(List<String> tags) async {
    throw _unsupported(DownloaderFeature.tags, '标签管理');
  }

  @override
  Future<void> deleteTags(List<String> tags) async {
    throw _unsupported(DownloaderFeature.tags, '标签管理');
  }

  @override
  Future<void> setCategory(List<String> hashes, String category) async {
    for (final hash in hashes) {
      await _setLabel(hash, category);
    }
  }

  /// Deluge 一个种子只能挂一个 label，空分类要显式回到内置的 No Label
  Future<void> _setLabel(String hash, String category) async {
    await _call('label.set_torrent', [hash, category.isEmpty ? 'No Label' : category]);
  }

  @override
  Future<void> recheckTorrents(List<String> hashes) async {
    if (hashes.isEmpty) return;
    await _call('core.force_recheck', [hashes]);
  }

  @override
  Future<void> createCategory(String category, {String? savePath}) async {
    await _call('label.add', [category]);
    if (savePath != null && savePath.isNotEmpty) {
      await setCategorySavePath(category, savePath);
    }
  }

  @override
  Future<void> deleteCategory(String category) async {
    await _call('label.remove', [category]);
  }

  /// 分类明细：名称 -> 「完成后移动到」路径
  ///
  /// Deluge 2.1 的 Label 选项里没有「直接落盘路径」，只有 `move_completed_path`，
  /// 所以这里给 UI 的是完成后的目标目录，界面上已按这个语义说明。
  @override
  Future<Map<String, String>> getCategoryDetails() async {
    final labels = await _labelOptions();
    final result = <String, String>{};
    labels.forEach((name, options) {
      final path =
          options['move_completed_path']?.toString() ??
          options['path']?.toString() ??
          '';
      result[name] = path;
    });
    return result;
  }

  @override
  Future<void> setCategorySavePath(String category, String savePath) async {
    final enabled = savePath.isNotEmpty;
    await _call('label.set_options', [
      category,
      {
        'apply_move_completed': enabled,
        'move_completed': enabled,
        'move_completed_path': savePath,
      },
    ]);
  }

  Future<Map<String, Map<String, dynamic>>> _labelOptions() async {
    final Object? result;
    try {
      result = await _call('label.get_labels');
    } on DelugeMethodUnavailableException {
      // Label 插件没启用时 label.* 直接是未知方法。读列表退化成「一个分类都没有」，
      // 好过把下载弹窗整页挡下来；写操作（改名、设路径）仍会抛出可读提示。
      return const {};
    }
    if (result is! Map) return const {};
    final labels = <String, Map<String, dynamic>>{};
    result.forEach((name, options) {
      final label = name.toString();
      if (label.isEmpty || label == 'No Label') return;
      labels[label] = options is Map
          ? options.map((k, v) => MapEntry(k.toString(), v))
          : <String, dynamic>{};
    });
    return labels;
  }

  String _categoryOf(dynamic label) {
    final text = label?.toString() ?? '';
    if (text.isEmpty || text == 'No Label') return '';
    return text;
  }

  // ============================================================
  // 专业增强 API：节点 / 文件
  // ============================================================

  @override
  Future<List<TorrentPeer>> getTorrentPeers(String hash) async {
    List<dynamic> peers;
    try {
      final status = await _torrentStatus(hash, const ['peers']);
      final raw = status['peers'];
      if (raw is! List) return const [];
      peers = raw;
    } catch (e) {
      // 未开始传输时 Deluge 拿不到节点列表，按空列表处理而不是报错
      debugPrint('Deluge 获取节点失败（hash=$hash）: $e');
      return const [];
    }

    final list = <TorrentPeer>[];
    for (final peer in peers.whereType<Map>()) {
      final ip = peer['ip']?.toString() ?? '';
      final port = _asInt(peer['port']);
      list.add(
        TorrentPeer(
          peerId: peer['peer_id']?.toString() ?? (port > 0 ? '$ip:$port' : ip),
          ip: ip,
          port: port,
          client: peer['client']?.toString() ?? '',
          connectionType: _asInt(peer['connection_type'] ?? peer['flags']),
          country: peer['country']?.toString() ?? peer['geo']?.toString() ?? '',
          // Deluge 各版本给过 downspeed / download_payload_rate 两种命名
          dlSpeed: _asInt(
            peer['down_speed'] ??
                peer['downspeed'] ??
                peer['download_payload_rate'],
          ),
          upSpeed: _asInt(
            peer['up_speed'] ??
                peer['upspeed'] ??
                peer['upload_payload_rate'],
          ),
          downloaded: _asInt(
            peer['total_payload_down'] ??
                peer['total_downloaded'] ??
                peer['downloaded'],
          ),
          uploaded: _asInt(
            peer['total_payload_up'] ??
                peer['total_uploaded'] ??
                peer['uploaded'],
          ),
          flags: peer['flags']?.toString() ?? '',
          flagsDesc: peer['flags_desc']?.toString() ?? '',
          progress: _normalizedProgress(peer['progress']),
          relevance: _asDouble(peer['relevance'] ?? peer['file_relevance']),
        ),
      );
    }
    list.sort((a, b) => b.dlSpeed.compareTo(a.dlSpeed));
    return list;
  }

  @override
  Future<List<TorrentFile>> getTorrentFiles(String hash) async {
    final status = await _torrentStatus(hash, const [
      'files',
      'file_progress',
      'file_priorities',
      'is_finished',
    ]);
    final files = status['files'];
    if (files is! List) return const [];
    final progress = status['file_progress'] is List
        ? status['file_progress'] as List
        : const [];
    final priorities = status['file_priorities'] is List
        ? status['file_priorities'] as List
        : const [];
    final isSeed = status['is_finished'] == true;

    final result = <TorrentFile>[];
    for (var i = 0; i < files.length; i++) {
      final file = files[i];
      if (file is! Map) continue;
      result.add(
        TorrentFile(
          index: _asInt(file['index'], fallback: i),
          name: file['path']?.toString() ?? file['name']?.toString() ?? '',
          size: _asInt(file['size']),
          progress: _normalizedProgress(i < progress.length ? progress[i] : 0),
          priority: _filePriorityFromDeluge(
            _asInt(i < priorities.length ? priorities[i] : 4, fallback: 4),
          ),
          isSeed: isSeed,
        ),
      );
    }
    return result;
  }

  // Deluge 直接把 libtorrent 的 0..7 文件优先级透出来（实机默认档是 4），
  // 而详情页沿用 qB 的枚举子集（0/1/6/7），这里做双向归一。
  static int _filePriorityFromDeluge(int raw) {
    if (raw <= 0) return FilePriority.skipped;
    if (raw >= 7) return FilePriority.maximum;
    if (raw >= 6) return FilePriority.high;
    return FilePriority.normal;
  }

  static int _filePriorityToDeluge(int value) {
    if (value <= FilePriority.skipped) return FilePriority.skipped;
    if (value >= FilePriority.maximum) return 7;
    if (value >= FilePriority.high) return 6;
    // qB 的「普通」是枚举 1，Deluge 的默认档是 libtorrent 的 4；越界值也夹到这里
    return 4;
  }

  @override
  Future<void> setFilePriority({
    required String hash,
    required List<int> ids,
    required int priority,
  }) async {
    if (ids.isEmpty) return;

    // Deluge 只能整表写回 file_priorities，所以先读现有列表再改目标下标。
    final status = await _torrentStatus(hash, const ['file_priorities']);
    final raw = status['file_priorities'];
    if (raw is! List) {
      throw Exception('Deluge 未返回文件优先级列表，无法修改（种子元数据可能还没下完）');
    }

    final targets = ids.toSet();
    final updated = <int>[];
    for (var i = 0; i < raw.length; i++) {
      final value = targets.contains(i)
          ? _filePriorityToDeluge(priority)
          : _asInt(raw[i], fallback: 4);
      updated.add(value.clamp(0, 7));
    }

    await _call('core.set_torrent_file_priorities', [hash, updated]);
  }

  // ============================================================
  // 专业增强 API：偏好 / 限速
  // ============================================================

  @override
  Future<GlobalPreferences> getGlobalPreferences() async {
    final prefs = await getPreferencesRaw();
    // Deluge 的全局限速就是 max_*_speed（KiB/s，-1 表示不限）。
    // 备选限速属于 Toggle 插件、定时限速属于 Scheduler 插件，两者都通过
    // 各自的配置命名空间生效，core.get_config 里没有对应键，恒报未启用。
    return GlobalPreferences(
      dlLimit: _asInt(prefs['max_download_speed'], fallback: -1),
      upLimit: _asInt(prefs['max_upload_speed'], fallback: -1),
      altDlLimit: -1,
      altUpLimit: -1,
      speedLimitMode: 0,
      schedulerEnabled: false,
      dlLimitApplied: _asInt(prefs['max_download_speed'], fallback: -1) > 0,
      upLimitApplied: _asInt(prefs['max_upload_speed'], fallback: -1) > 0,
    );
  }

  @override
  Future<Map<String, dynamic>> getPreferencesRaw() async {
    final result = await _call('core.get_config');
    if (result is! Map) return const {};
    return result.map((k, v) => MapEntry(k.toString(), v));
  }

  @override
  Future<void> setPreferences(Map<String, dynamic> deltas) async {
    if (deltas.isEmpty) return;
    await _call('core.set_config', [deltas]);
  }

  @override
  Future<void> setGlobalDownloadLimit(int limitKib) async {
    // Deluge 的 max_download_speed 单位就是 KiB/s，-1 表示不限速
    await _call('core.set_config', [
      {'max_download_speed': limitKib},
    ]);
  }

  @override
  Future<void> setGlobalUploadLimit(int limitKib) async {
    await _call('core.set_config', [
      {'max_upload_speed': limitKib},
    ]);
  }

  @override
  Future<void> setSpeedLimitsMode(int mode) async {
    throw _unsupported(DownloaderFeature.altSpeedLimits, '备选限速模式');
  }

  // ============================================================
  // 内部工具
  // ============================================================

  Exception _unsupported(DownloaderFeature feature, String label) {
    return Exception('当前下载器（Deluge）不支持$label');
  }

  Future<Map<String, Map<String, dynamic>>> _torrentStatusMap(
    List<String> keys,
  ) async {
    final result = await _call('core.get_torrents_status', [{}, keys]);
    if (result is! Map) return const {};
    return result.map(
      (id, value) => MapEntry(
        id.toString(),
        value is Map
            ? value.map((k, v) => MapEntry(k.toString(), v))
            : <String, dynamic>{},
      ),
    );
  }

  Future<Map<String, dynamic>> _torrentStatus(String hash, List<String> keys) async {
    final result = await _call('core.get_torrent_status', [hash, keys]);
    if (result is! Map) return const {};
    return result.map((k, v) => MapEntry(k.toString(), v));
  }

  DownloadTask _convertToDownloadTask(String hash, Map<String, dynamic> status) {
    final size = _asInt(status['total_size']);
    final done = _asInt(status['total_done']);
    final state = _normalizeState(status);

    return DownloadTask(
      hash: hash,
      name: status['name']?.toString() ?? '',
      state: state,
      size: size,
      progress: _normalizedProgress(status['progress']),
      dlspeed: _asInt(status['download_payload_rate']),
      upspeed: _asInt(status['upload_payload_rate']),
      eta: _asInt(status['eta']),
      category: _categoryOf(status['label']),
      tags: const [],
      completionOn: 0,
      contentPath: _contentPath(status),
      addedOn: _asInt(status['time_added']),
      amountLeft: done >= size ? 0 : size - done,
      ratio: _asDouble(status['ratio']),
      timeActive: _asInt(status['active_time']),
      uploaded: _asInt(status['total_uploaded']),
    );
  }

  /// Deluge 的状态串归一到本应用沿用的 qB 状态词表
  ///
  /// 实机（2.2.0）回报的是首字母大写的单词，`core.get_filter_tree` 给出的完整
  /// 取值还有 Allocating / Checking / Error / Moving / Queued / Paused /
  /// Seeding / Downloading，加上强制与元数据下载这些派生态。
  String _normalizeState(Map<String, dynamic> status) {
    final raw = (status['state']?.toString() ?? '').toLowerCase();
    final finished =
        status['is_finished'] == true || status['is_seed'] == true;
    final paused = status['paused'] == true;

    switch (raw) {
      case 'error':
        return DownloadTaskState.error;
      case 'moving':
        return DownloadTaskState.moving;
      case 'allocating':
        return DownloadTaskState.allocating;
      case 'checking paused':
        return finished
            ? DownloadTaskState.pausedUP
            : DownloadTaskState.pausedDL;
      case 'checking':
        return finished
            ? DownloadTaskState.checkingUP
            : DownloadTaskState.checkingDL;
      case 'meta download':
        return DownloadTaskState.metaDL;
      case 'forced download':
        return DownloadTaskState.forcedDL;
      case 'forced seeding':
      case 'forced upload':
        return DownloadTaskState.forcedUP;
      case 'stalled download':
        return DownloadTaskState.stalledDL;
      case 'stalled seeding':
      case 'stalled upload':
        return DownloadTaskState.stalledUP;
      case 'queued':
        if (paused) {
          return finished ? DownloadTaskState.pausedUP : DownloadTaskState.pausedDL;
        }
        return finished ? DownloadTaskState.queuedUP : DownloadTaskState.queuedDL;
      case 'paused':
        return finished ? DownloadTaskState.pausedUP : DownloadTaskState.pausedDL;
      case 'downloading':
        return paused ? DownloadTaskState.pausedDL : DownloadTaskState.downloading;
      case 'seeding':
        return paused ? DownloadTaskState.pausedUP : DownloadTaskState.uploading;
    }

    if (paused) {
      return finished ? DownloadTaskState.pausedUP : DownloadTaskState.pausedDL;
    }
    return DownloadTaskState.unknown;
  }

  bool _matchesFilter(DownloadTask task, String filter) {
    switch (filter) {
      case 'downloading':
        return DownloadTaskState.isDownloading(task.state) ||
            task.state == DownloadTaskState.queuedDL ||
            task.state == DownloadTaskState.checkingDL ||
            task.state == DownloadTaskState.allocating;
      case 'seeding':
        return task.state == DownloadTaskState.uploading ||
            task.state == DownloadTaskState.forcedUP ||
            task.state == DownloadTaskState.stalledUP ||
            task.state == DownloadTaskState.queuedUP ||
            task.state == DownloadTaskState.checkingUP ||
            task.state == DownloadTaskState.pausedUP;
      case 'completed':
        return task.progress >= 1 ||
            task.state == DownloadTaskState.uploading ||
            task.state == DownloadTaskState.pausedUP;
      case 'paused':
        return DownloadTaskState.isPaused(task.state) ||
            task.state == DownloadTaskState.stoppedDL;
      case 'active':
        return task.dlspeed > 0 || task.upspeed > 0;
      case 'inactive':
        return task.dlspeed == 0 && task.upspeed == 0;
      case 'errored':
        return task.state == DownloadTaskState.error ||
            task.state == DownloadTaskState.missingFiles;
      default:
        return true;
    }
  }

  int _compareBySort(DownloadTask a, DownloadTask b, String sort) {
    switch (sort) {
      case 'size':
        return a.size.compareTo(b.size);
      case 'progress':
        return a.progress.compareTo(b.progress);
      case 'added_on':
      case 'timeAdded':
        return a.addedOn.compareTo(b.addedOn);
      case 'dlspeed':
      case 'down_speed':
        return a.dlspeed.compareTo(b.dlspeed);
      case 'upspeed':
      case 'up_speed':
        return a.upspeed.compareTo(b.upspeed);
      case 'eta':
        return a.eta.compareTo(b.eta);
      case 'ratio':
      case 'seed_ratio':
      case 'shareRatio':
        return a.ratio.compareTo(b.ratio);
      case 'category':
        return a.category.compareTo(b.category);
      case 'name':
      default:
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    }
  }

  int _asInt(dynamic value, {int fallback = 0}) {
    if (value == null) return fallback;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return FormatUtil.parseInt(value.toString()) ?? fallback;
  }

  double _asDouble(dynamic value) {
    if (value == null) return 0;
    if (value is double) return value;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? 0;
  }

  /// Deluge 的进度是 0..100 的百分数，本应用统一用 0..1
  double _normalizedProgress(dynamic value) {
    final raw = _asDouble(value);
    if (raw <= 0) return 0;
    return raw > 1 ? raw / 100 : raw;
  }

  /// 释放 HTTP 客户端
  void dispose() {
    _dio.close(force: true);
  }
}

/// Deluge 返回 JSON-RPC 错误码 2：这个方法在这个实例上不存在。
///
/// 两种成因：插件没启用（Label、Scheduler…），或版本较老换了接口名。
/// 调用方可捕获它做版本兼容回退。
class DelugeMethodUnavailableException implements Exception {
  const DelugeMethodUnavailableException(this.method, this.message);

  final String method;
  final String message;

  @override
  String toString() =>
      'Deluge 不支持接口「$method」：$message（插件未启用？）';
}
