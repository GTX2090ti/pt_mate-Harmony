import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pt_mate/services/downloader/downloader_config.dart';
import 'package:pt_mate/services/downloader/downloader_models.dart';
import 'package:pt_mate/services/downloader/qbittorrent_client.dart';

class _RecordedRequest {
  _RecordedRequest(
    this.method,
    this.path,
    this.headers,
    this.data,
    this.query,
  );

  final String method;
  final String path;
  final Map<String, dynamic> headers;
  final Object? data;
  final Map<String, dynamic> query;

  Map<dynamic, dynamic> get form => data as Map<dynamic, dynamic>;
}

class _FakeHttpClientAdapter implements HttpClientAdapter {
  final List<_RecordedRequest> requests = [];
  final List<String> loginCookies = [];
  int _loginCount = 0;
  int _transferInfoCount = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(
      _RecordedRequest(
        options.method,
        options.path,
        Map<String, dynamic>.from(options.headers),
        options.data,
        Map<String, dynamic>.from(options.queryParameters),
      ),
    );

    if (options.path.endsWith('/auth/login')) {
      final cookie = loginCookies[_loginCount++];
      return ResponseBody.fromString(
        'Ok.',
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.formUrlEncodedContentType],
          'set-cookie': [cookie],
        },
      );
    }

    if (options.path.endsWith('/torrents/add')) {
      return ResponseBody.fromString('', 204);
    }

    if (options.path.endsWith('/transfer/info')) {
      _transferInfoCount++;
      if (_transferInfoCount == 1) {
        return ResponseBody.fromString('Forbidden', 403);
      }
      return ResponseBody.fromString(
        jsonEncode({
          'up_info_speed': 1,
          'dl_info_speed': 2,
          'up_info_data': 3,
          'dl_info_data': 4,
        }),
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }

    if (options.path.endsWith('/app/preferences')) {
      return ResponseBody.fromString(
        jsonEncode({
          'save_path': '/downloads',
          'listen_port': 8999,
          'dl_limit': -1,
          'max_ratio': 2.5,
          'queueing': true,
          'add_trackers': ['http://tracker-1/announce'],
        }),
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }

    if (options.path.endsWith('/torrents/info')) {
      return ResponseBody.fromString(
        jsonEncode([
          {
            'hash': 'aabbcc',
            'name': 'GETCHU-4070060',
            'force_start': true,
            'seq_dl': false,
            'f_l_piece_prio': 1,
            'super_seeding': false,
            'auto_tmm': true,
            'private': true,
            'total_size': 1024,
          },
        ]),
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }

    if (options.path.endsWith('/sync/maindata')) {
      return ResponseBody.fromString(
        jsonEncode({
          'rid': 1,
          'server_state': {
            'free_space_on_disk': 1073741824,
            'alltime_dl': 1210563673,
            // 部分统计项 qB 侧按字符串下发（已格式化），解析时不能只认 int
            'alltime_ul': '38797307904',
            'global_ratio': '0.03',
            'total_wasted_session': 64592211,
            'read_cache_hits': '0',
            'read_cache_overload': '0',
            'write_cache_overload': '0',
            'queued_io_jobs': 0,
            'average_time_queue': 213,
            'total_buffers_size': 0,
            'total_queued_size': 0,
          },
        }),
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }

    if (options.path.endsWith('/app/setPreferences') ||
        options.path.endsWith('/torrents/createTags') ||
        options.path.endsWith('/torrents/deleteTags') ||
        options.path.endsWith('/torrents/createCategory') ||
        options.path.endsWith('/torrents/editCategory') ||
        options.path.endsWith('/torrents/setForceStart') ||
        options.path.endsWith('/torrents/setSuperSeeding') ||
        options.path.endsWith('/torrents/setAutoManagement') ||
        options.path.endsWith('/torrents/toggleSequentialDownload') ||
        options.path.endsWith('/torrents/toggleFirstLastPiecePrio') ||
        options.path.endsWith('/torrents/filePrio') ||
        options.path.endsWith('/torrents/increasePrio') ||
        options.path.endsWith('/torrents/decreasePrio') ||
        options.path.endsWith('/torrents/topPrio') ||
        options.path.endsWith('/torrents/bottomPrio')) {
      return ResponseBody.fromString('', 204);
    }

    throw UnsupportedError(
      'Unexpected request: ${options.method} ${options.path}',
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  group('QbittorrentClient', () {
    QbittorrentConfig buildConfig() {
      return const QbittorrentConfig(
        id: 'qb-1',
        name: 'qb',
        host: 'http://localhost',
        port: 8080,
        username: 'admin',
        password: '',
      );
    }

    test('extracts legacy SID cookie header', () {
      final client = QbittorrentClient(
        config: buildConfig(),
        password: 'secret',
      );

      final header = client.debugExtractCookieHeader([
        'SID=legacy-session; HttpOnly; path=/',
      ]);

      expect(header, 'SID=legacy-session');
    });

    test('extracts and deduplicates arbitrary cookie names', () {
      final client = QbittorrentClient(
        config: buildConfig(),
        password: 'secret',
      );

      final header = client.debugExtractCookieHeader([
        'cookie_id=v1; HttpOnly; path=/',
        'theme=dark; path=/',
        'cookie_id=v2; HttpOnly; path=/',
      ]);

      expect(header, 'cookie_id=v2; theme=dark');
    });

    test(
      'uses parsed login cookie for authenticated requests and accepts 204',
      () async {
        final adapter = _FakeHttpClientAdapter()
          ..loginCookies.add('cookie_id=new-value; HttpOnly; path=/');
        final dio = Dio()..httpClientAdapter = adapter;
        final client = QbittorrentClient(
          config: buildConfig(),
          password: 'secret',
          dio: dio,
        );

        await client.addTask(
          AddTaskParams(url: 'https://example.com/test.torrent'),
        );

        expect(client.debugAuthCookieHeader, 'cookie_id=new-value');
        expect(adapter.requests.length, 2);
        expect(
          adapter.requests[0].path,
          'http://localhost:8080/api/v2/auth/login',
        );
        expect(adapter.requests[1].headers['Cookie'], 'cookie_id=new-value');
      },
    );

    test('retries once after 403 with refreshed login cookie', () async {
      final adapter = _FakeHttpClientAdapter()
        ..loginCookies.addAll([
          'cookie_id=first-value; HttpOnly; path=/',
          'cookie_id=second-value; HttpOnly; path=/',
        ]);
      final dio = Dio()..httpClientAdapter = adapter;
      final client = QbittorrentClient(
        config: buildConfig(),
        password: 'secret',
        dio: dio,
      );

      final result = await client.getTransferInfo();

      expect(result.upSpeed, 1);
      expect(client.debugAuthCookieHeader, 'cookie_id=second-value');
      expect(adapter.requests.length, 4);
      expect(adapter.requests[1].headers['Cookie'], 'cookie_id=first-value');
      expect(adapter.requests[3].headers['Cookie'], 'cookie_id=second-value');
    });
    test('reads raw preferences from /app/preferences', () async {
      final adapter = _FakeHttpClientAdapter()
        ..loginCookies.add('cookie_id=prefs; HttpOnly; path=/');
      final dio = Dio()..httpClientAdapter = adapter;
      final client = QbittorrentClient(
        config: buildConfig(),
        password: 'secret',
        dio: dio,
      );

      final prefs = await client.getPreferencesRaw();

      expect(prefs['save_path'], '/downloads');
      expect(prefs['listen_port'], 8999);
      expect(prefs['add_trackers'], ['http://tracker-1/announce']);
      expect(adapter.requests[1].path, 'http://localhost:8080/api/v2/app/preferences');
    });

    test('writes preference deltas as encoded json form field', () async {
      final adapter = _FakeHttpClientAdapter()
        ..loginCookies.add('cookie_id=prefs; HttpOnly; path=/');
      final dio = Dio()..httpClientAdapter = adapter;
      final client = QbittorrentClient(
        config: buildConfig(),
        password: 'secret',
        dio: dio,
      );

      await client.setPreferences({'dl_limit': 1048576, 'queueing': false});

      final request = adapter.requests.last;
      expect(request.method, 'POST');
      expect(request.path, endsWith('/api/v2/app/setPreferences'));
      expect(request.form['json'], '{"dl_limit":1048576,"queueing":false}');

      final countBefore = adapter.requests.length;
      await client.setPreferences({});
      expect(adapter.requests.length, countBefore);
    });

    test('creates and deletes tags with comma-separated names', () async {
      final adapter = _FakeHttpClientAdapter()
        ..loginCookies.add('cookie_id=prefs; HttpOnly; path=/');
      final dio = Dio()..httpClientAdapter = adapter;
      final client = QbittorrentClient(
        config: buildConfig(),
        password: 'secret',
        dio: dio,
      );

      // tags 是逗号分隔（hashes 才是竖线），竖线会建出一个名叫「pt|hd」的标签
      await client.createTags(['pt', 'hd']);
      expect(adapter.requests.last.path, endsWith('/torrents/createTags'));
      expect(adapter.requests.last.form['tags'], 'pt,hd');

      await client.deleteTags(['pt']);
      expect(adapter.requests.last.path, endsWith('/torrents/deleteTags'));
      expect(adapter.requests.last.form['tags'], 'pt');
    });

    test('edits category save path with the params qBittorrent requires',
        () async {
      final adapter = _FakeHttpClientAdapter()
        ..loginCookies.add('cookie_id=prefs; HttpOnly; path=/');
      final dio = Dio()..httpClientAdapter = adapter;
      final client = QbittorrentClient(
        config: buildConfig(),
        password: 'secret',
        dio: dio,
      );

      await client.createCategory('tv', savePath: '/data/tv');
      expect(adapter.requests.last.path, endsWith('/torrents/createCategory'));
      expect(adapter.requests.last.form['category'], 'tv');
      expect(adapter.requests.last.form['savePath'], '/data/tv');

      // 4.6/5.0 的 editCategory 强制要求 savePath，清空路径也要把空串发出去
      await client.setCategorySavePath('tv', '');
      expect(adapter.requests.last.path, endsWith('/torrents/editCategory'));
      expect(adapter.requests.last.form['category'], 'tv');
      expect(adapter.requests.last.form.containsKey('savePath'), isTrue);
      expect(adapter.requests.last.form['savePath'], '');
    });

    test('reads single-torrent raw info for the overview tab', () async {
      final adapter = _FakeHttpClientAdapter()
        ..loginCookies.add('cookie_id=prefs; HttpOnly; path=/');
      final dio = Dio()..httpClientAdapter = adapter;
      final client = QbittorrentClient(
        config: buildConfig(),
        password: 'secret',
        dio: dio,
      );

      final info = await client.getTorrentInfoRaw('aabbcc');

      final request = adapter.requests.last;
      expect(request.method, 'GET');
      expect(request.path, endsWith('/torrents/info'));
      expect(request.query['hashes'], 'aabbcc');
      // 概览页要读到 DownloadTask 没覆盖的开关字段，且不能被类型差异吞掉
      expect(info?['force_start'], true);
      expect(info?['f_l_piece_prio'], 1);
      expect(info?['auto_tmm'], true);
    });

    test('writes overview switches, toggling the two without a set endpoint',
        () async {
      final adapter = _FakeHttpClientAdapter()
        ..loginCookies.add('cookie_id=prefs; HttpOnly; path=/');
      final dio = Dio()..httpClientAdapter = adapter;
      final client = QbittorrentClient(
        config: buildConfig(),
        password: 'secret',
        dio: dio,
      );

      await client.setForceStart(['h1', 'h2'], false);
      expect(adapter.requests.last.path, endsWith('/torrents/setForceStart'));
      expect(adapter.requests.last.form['hashes'], 'h1|h2');
      expect(adapter.requests.last.form['value'], 'false');

      await client.setSuperSeeding(['h1'], true);
      expect(adapter.requests.last.path, endsWith('/torrents/setSuperSeeding'));
      expect(adapter.requests.last.form['value'], 'true');

      // 自动种子管理的开关参数叫 enable，传 value 会被 qB 判成缺参直接 400
      await client.setAutoManagement(['h1'], true);
      expect(
        adapter.requests.last.path,
        endsWith('/torrents/setAutoManagement'),
      );
      expect(adapter.requests.last.form['enable'], 'true');
      expect(adapter.requests.last.form.containsKey('value'), isFalse);

      // qB 只有 toggle 版本，顺序下载与首尾分块优先不能传 value
      await client.toggleSequentialDownload(['h1']);
      expect(
        adapter.requests.last.path,
        endsWith('/torrents/toggleSequentialDownload'),
      );
      expect(adapter.requests.last.form.containsKey('value'), isFalse);

      await client.toggleFirstLastPiecePrio(['h1']);
      expect(
        adapter.requests.last.path,
        endsWith('/torrents/toggleFirstLastPiecePrio'),
      );
    });

    test('writes file priorities with pipe-separated ids and enum values',
        () async {
      final adapter = _FakeHttpClientAdapter()
        ..loginCookies.add('cookie_id=prio; HttpOnly; path=/');
      final dio = Dio()..httpClientAdapter = adapter;
      final client = QbittorrentClient(
        config: buildConfig(),
        password: 'secret',
        dio: dio,
      );

      // filePrio 按竖线切 id，用逗号会让服务端 toInt 失败：400「文件 ID 必须是整数」
      await client.setFilePriority(
        hash: 'h1',
        ids: [0, 2, 3],
        priority: FilePriority.skipped,
      );
      expect(adapter.requests.last.path, endsWith('/torrents/filePrio'));
      expect(adapter.requests.last.form['id'], '0|2|3');
      expect(adapter.requests.last.form['priority'], '0');

      // DownloadPriority 只有 0/1/6/7 四档，传 2/3 会 400「Priority is not valid」
      await client.setFilePriority(
        hash: 'h1',
        ids: [1],
        priority: FilePriority.maximum,
      );
      expect(adapter.requests.last.form['priority'], '7');

      expect(FilePriority.next(FilePriority.skipped), FilePriority.normal);
      expect(FilePriority.next(FilePriority.normal), FilePriority.high);
      expect(FilePriority.next(FilePriority.high), FilePriority.maximum);
      expect(FilePriority.next(FilePriority.maximum), FilePriority.skipped);
      // 元数据未就绪时 qB 给的是 Mixed=-1，回到普通档而不是报错
      expect(FilePriority.next(-1), FilePriority.normal);

      // 空列表不发请求，避免把空 id 传过去被判非法
      final requestCount = adapter.requests.length;
      await client.setFilePriority(
        hash: 'h1',
        ids: const [],
        priority: FilePriority.normal,
      );
      expect(adapter.requests.length, requestCount);
    });

    test('moves torrents in the queue with the four endpoints qB has', () async {
      final adapter = _FakeHttpClientAdapter()
        ..loginCookies.add('cookie_id=queue; HttpOnly; path=/');
      final dio = Dio()..httpClientAdapter = adapter;
      final client = QbittorrentClient(
        config: buildConfig(),
        password: 'secret',
        dio: dio,
      );

      // qB 按 `<action>Action` 反射派发，压根没有 setPriority 这个端点（4.6/5.0/master
      // 都确认过），只有下面四个相对移动接口
      await client.increasePriority(['h1', 'h2']);
      expect(adapter.requests.last.path, endsWith('/torrents/increasePrio'));
      expect(adapter.requests.last.form['hashes'], 'h1|h2');

      await client.decreasePriority(['h1']);
      expect(adapter.requests.last.path, endsWith('/torrents/decreasePrio'));

      await client.topPriority(['h1']);
      expect(adapter.requests.last.path, endsWith('/torrents/topPrio'));

      await client.bottomPriority(['h1']);
      expect(adapter.requests.last.path, endsWith('/torrents/bottomPrio'));
    });

    test('parses all-time statistics from server_state', () async {
      final adapter = _FakeHttpClientAdapter()
        ..loginCookies.add('cookie_id=stats; HttpOnly; path=/');
      final dio = Dio()..httpClientAdapter = adapter;
      final client = QbittorrentClient(
        config: buildConfig(),
        password: 'secret',
        dio: dio,
      );

      final state = await client.getServerState();

      expect(adapter.requests.last.path, endsWith('/sync/maindata'));
      expect(state.freeSpaceOnDisk, 1073741824);
      expect(state.alltimeDl, 1210563673);
      expect(state.alltimeUl, 38797307904);
      expect(state.totalWastedSession, 64592211);
      expect(state.globalRatio, '0.03');
      expect(state.readCacheHits, '0');
      expect(state.queuedIoJobs, 0);
      expect(state.averageTimeQueue, 213);
      expect(state.totalBuffersSize, 0);
      expect(state.totalQueuedSize, 0);
    });
  });
}
