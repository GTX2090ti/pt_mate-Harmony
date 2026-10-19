import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pt_mate/services/downloader/deluge_client.dart';
import 'package:pt_mate/services/downloader/downloader_capabilities.dart';
import 'package:pt_mate/services/downloader/downloader_config.dart';
import 'package:pt_mate/services/downloader/downloader_models.dart';

/// Deluge 的 WebUI 只有一个 `/json` 端点，所有调用都靠请求体里的 `method` 区分，
/// 所以假适配器按 method 派发脚本化响应，并把每次调用的 params 记下来供断言。
class _RpcCall {
  _RpcCall(this.method, this.params, this.headers);

  final String method;
  final List<dynamic> params;
  final Map<String, dynamic> headers;

  dynamic get first => params.first;
  dynamic operator [](int index) => params[index];

  String? get cookie => header('cookie') as String?;

  Object? header(String name) {
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() == name) return entry.value;
    }
    return null;
  }
}

/// JSON-RPC 响应体里的 error 对象
class _RpcError {
  const _RpcError(this.code, [this.message = 'boom']);

  final int code;
  final String message;
}

/// 原样返回的响应体，用来模拟「不是 JSON」的网关/代理页面
class _RawBody {
  const _RawBody(this.body, this.contentType);

  final String body;
  final String contentType;
}

class _FakeDelugeAdapter implements HttpClientAdapter {
  final List<_RpcCall> calls = [];
  final List<String> downloadedUrls = [];
  final List<String> requestUrls = [];
  final Map<String, List<dynamic>> _script = {};

  /// 登录后是否下发 `_session_id` Cookie
  String? sessionCookie = '_session_id=cafebabe0000';
  int loginCount = 0;
  List<int> torrentFileBytes = const [0x64, 0x38, 0x21, 0x65];

  /// 前 N 次 /json 请求返回 307（模拟 WebUI/反代把明文 http 跳到 https）
  int redirectHops = 0;
  String? redirectLocation;

  int get jsonCallCount => calls.length;

  /// 该方法固定返回 result（重复调用沿用同一个值）
  void ok(String method, dynamic result) => _script[method] = [result];

  /// 同一个方法被多次调用时依次返回，最后一个值会一直沿用
  void script(String method, List<dynamic> responses) =>
      _script[method] = List<dynamic>.from(responses);

  _RpcCall callAt(int index) => calls[index];

  _RpcCall get last => calls.last;

  bool get askedAuthLogin => calls.any((c) => c.method == 'auth.login');

  List<String> get methods => calls.map((c) => c.method).toList();

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    // 非 /json：本地中转下载站点种子
    if (!options.path.endsWith('/json')) {
      downloadedUrls.add(options.path);
      return ResponseBody.fromBytes(
        Uint8List.fromList(torrentFileBytes),
        200,
        headers: {
          Headers.contentTypeHeader: ['application/x-bittorrent'],
        },
      );
    }

    if (redirectHops > 0) {
      redirectHops--;
      return ResponseBody.fromString('', 307, headers: {
        'location': [redirectLocation ?? 'https://192.168.1.50:8112/json'],
      });
    }

    final payload = jsonDecode(options.data as String) as Map<String, dynamic>;
    final method = payload['method'] as String;
    final params = (payload['params'] as List).cast<dynamic>();
    requestUrls.add(options.uri.toString());
    if (method == 'auth.login') {
      loginCount++;
    }
    calls.add(
      _RpcCall(
        method,
        params,
        Map<String, dynamic>.from(options.headers),
      ),
    );

    dynamic response;
    final queue = _script[method];
    if (queue == null) {
      response = method == 'auth.login' ? true : null;
    } else if (queue.length == 1) {
      response = queue.first;
    } else {
      response = queue.removeAt(0);
    }

    if (response is _RawBody) {
      return ResponseBody.fromString(
        response.body,
        200,
        headers: {
          Headers.contentTypeHeader: [response.contentType],
        },
      );
    }

    final error = response is _RpcError
        ? <String, dynamic>{'code': response.code, 'message': response.message}
        : null;
    final body = jsonEncode({
      'result': error == null ? response : null,
      'error': error,
      'id': payload['id'],
    });

    final headers = <String, List<String>>{
      Headers.contentTypeHeader: [Headers.jsonContentType],
    };
    final cookie = sessionCookie;
    if (method == 'auth.login' && cookie != null) {
      headers['set-cookie'] = [cookie];
    }
    return ResponseBody.fromString(body, 200, headers: headers);
  }

  @override
  void close({bool force = false}) {}
}

const String _hashA = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const String _hashB = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
const String _hashC = 'cccccccccccccccccccccccccccccccccccccccc';

/// 一条 `core.get_torrents_status` 返回的种子状态
Map<String, dynamic> seed({
  required String name,
  required String state,
  int size = 1000,
  int done = 0,
  double progress = 0,
  int addedOn = 1000,
  String label = '',
  bool? paused,
  bool? isSeed,
  bool? isFinished,
  int dl = 0,
  int up = 0,
  String? downloadLocation = '/data/downloads',
}) {
  return <String, dynamic>{
    'name': name,
    'state': state,
    'paused': paused,
    'is_seed': isSeed,
    'is_finished': isFinished,
    'progress': progress,
    'total_size': size,
    'total_done': done,
    // 2.x 的历史累计下载叫 all_time_download（实机核对）
    'all_time_download': done,
    'total_uploaded': up * 10,
    'download_payload_rate': dl,
    'upload_payload_rate': up,
    'eta': 60,
    'ratio': size == 0 ? 0.0 : done / size,
    'seeding_time': 120,
    'active_time': 300,
    'time_added': addedOn,
    'download_location': downloadLocation,
    'label': label,
    'num_seeds': 2,
    'num_peers': 3,
    'total_seeds': 5,
    'total_peers': 7,
    'auto_managed': true,
    'private': false,
    'queue': 0,
    'message': null,
  };
}

void main() {
  late _FakeDelugeAdapter adapter;
  late DelugeClient client;

  DelugeClient build({
    bool useLocalRelay = false,
    String? version,
    void Function(DelugeConfig)? onConfigUpdated,
  }) {
    final dio = Dio()..httpClientAdapter = adapter;
    return DelugeClient(
      config: DelugeConfig(
        id: 'deluge-1',
        name: '家庭 Deluge',
        host: '192.168.1.50',
        port: 8112,
        username: 'admin',
        password: 'deluge-pass',
        useLocalRelay: useLocalRelay,
        version: version,
      ),
      password: 'deluge-pass',
      onConfigUpdated: onConfigUpdated,
      dio: dio,
    );
  }

  setUp(() {
    adapter = _FakeDelugeAdapter();
    client = build();
  });

  Future<Object?> captureError<T>(Future<T> Function() body) async {
    try {
      await body();
    } catch (e) {
      return e;
    }
    return null;
  }

  group('登录与会话 Cookie', () {
    test('首次调用自动登录并复用 _session_id', () async {
      adapter.ok('core.get_free_space', 4096);
      adapter.ok('core.get_torrents_status', {});

      final state = await client.getServerState();

      expect(
        adapter.methods,
        ['auth.login', 'core.get_free_space', 'core.get_torrents_status'],
      );
      expect(adapter.callAt(0).first, 'deluge-pass');
      // 登录请求本身不带 Cookie，后续请求带上服务端下发的会话
      expect(adapter.callAt(0).cookie, isNull);
      expect(adapter.callAt(1).cookie, '_session_id=cafebabe0000');
      expect(client.debugAuthCookieHeader, '_session_id=cafebabe0000');
      expect(state.freeSpaceOnDisk, 4096);
      // 不带路径：Deluge 按默认下载目录查剩余空间
      expect(adapter.callAt(1).params, isEmpty);
    });

    test('请求头带 WebUI 需要的 X-Requested-With', () async {
      adapter.ok('core.get_free_space', 1);
      await client.getServerState();

      expect(adapter.callAt(1).header('x-requested-with'), 'XMLHttpRequest');
      expect(adapter.callAt(1).header('content-type'), 'application/json');
    });

    test('Cookie 解析只保留 name=value 并按出现顺序拼接', () {
      final header = client.debugExtractCookieHeader([
        '_session_id=abc123; Path=/json; HttpOnly',
        'csrftoken=xyz; Expires=Thu, 01 Jan 2099 00:00:00 GMT',
        'garbage-without-equals',
      ]);

      expect(header, '_session_id=abc123; csrftoken=xyz');
      expect(client.debugExtractCookieHeader(null), isNull);
      expect(client.debugExtractCookieHeader(const []), isNull);
    });

    test('密码错误：result 非 true 时报「密码不正确」', () async {
      adapter.ok('auth.login', false);

      final error = await captureError(client.getTransferInfo);
      expect(error.toString(), contains('密码不正确'));
      expect(client.debugAuthCookieHeader, isNull);
    });

    test('登录阶段就返回 error 时透出原因', () async {
      adapter.script(
        'auth.login',
        [const _RpcError(3, 'WebUI is rate limiting')],
      );

      final error = await captureError(client.getTransferInfo);
      expect(error.toString(), contains('Deluge 登录失败'));
      expect(error.toString(), contains('rate limiting'));
    });

    test('登录后没有下发会话 Cookie 要报错', () async {
      adapter.sessionCookie = null;
      adapter.ok('core.get_free_space', 1);

      final error = await captureError(client.getServerState);
      expect(error.toString(), contains('没有下发会话 Cookie'));
    });

    test('登录页返回 HTML 时提示检查 WebUI 地址', () async {
      adapter.script('auth.login', [
        const _RawBody(
          '<html><body>502 Bad Gateway</body></html>',
          'text/html',
        ),
      ]);

      final error = await captureError(client.getServerState);
      expect(error.toString(), contains('Deluge 登录响应不是 JSON'));
    });
  });

  group('明文地址被 307 跳转', () {
    test('跟随 Location 重发，并缓存跳转后的地址', () async {
      adapter.redirectHops = 1;
      adapter.redirectLocation = 'https://192.168.1.50:8112/json';
      adapter.ok('core.get_free_space', 4096);
      adapter.ok('core.get_torrents_status', {});

      final state = await client.getServerState();

      expect(state.freeSpaceOnDisk, 4096);
      // 跳转前的那次请求拿不到 JSON-RPC 响应体，不会被记进 calls，
      // 因此这里全部落在 https 就证明客户端自己重发了 POST
      expect(adapter.requestUrls, isNotEmpty);
      expect(adapter.requestUrls.every((u) => u.startsWith('https://')), isTrue);

      final before = adapter.requestUrls.length;
      await client.getServerState();
      // 后续请求直接打缓存地址，不再多走一跳
      expect(adapter.requestUrls.skip(before).every((u) => u.startsWith('https://')), isTrue);
      expect(adapter.redirectHops, 0);
    });

    test('Location 是相对路径时基于当前地址解析', () async {
      adapter.redirectHops = 1;
      adapter.redirectLocation = '/deluge/json';
      adapter.ok('core.get_free_space', 1);
      adapter.ok('core.get_torrents_status', {});

      await client.getServerState();

      expect(adapter.requestUrls.first, 'http://192.168.1.50:8112/deluge/json');
    });

    test('反复重定向时报可读错误，不会无限循环', () async {
      adapter.redirectHops = 20;

      final error = await captureError(client.getServerState);

      expect(error.toString(), contains('Deluge 地址反复重定向'));
    });
  });

  group('JSON-RPC 错误码路由', () {
    test('响应不是 JSON 对象时提示确认 WebUI 地址', () async {
      adapter.ok(
        'core.get_free_space',
        const _RawBody('<html>nginx</html>', 'text/html'),
      );

      final error = await captureError(client.getServerState);
      expect(error.toString(), contains('Deluge 返回的不是 JSON'));
      expect(error.toString(), contains('8112'));
    });

    test('code 1：清掉会话重新登录，重试一次后成功', () async {
      adapter.script('core.get_free_space', [
        const _RpcError(1, 'Not authorized'),
        8192,
      ]);
      adapter.ok('core.get_torrents_status', {});

      final state = await client.getServerState();

      expect(state.freeSpaceOnDisk, 8192);
      expect(adapter.loginCount, 2);
      expect(adapter.methods, [
        'auth.login',
        'core.get_free_space',
        'auth.login',
        'core.get_free_space',
        'core.get_torrents_status',
      ]);
    });

    test('code 1：重新登录仍被拒绝时不再无限重试', () async {
      adapter.ok('core.get_free_space', const _RpcError(1, 'Not authorized'));

      final error = await captureError(client.getServerState);
      expect(error.toString(), contains('会话已失效'));
      expect(adapter.loginCount, 2);
      expect(adapter.methods.length, 4);
    });

    test('code 2：写分类时提示插件未启用', () async {
      adapter.ok(
        'label.set_options',
        const _RpcError(2, 'No method for "label.set_options"'),
      );

      final error = await captureError(
        () => client.setCategorySavePath('tv', '/data/tv'),
      );
      expect(error.toString(), contains('Deluge 不支持接口「label.set_options」'));
      expect(error.toString(), contains('插件未启用'));
    });

    test('其它错误码按接口失败抛出 HttpException', () async {
      adapter.ok('core.pause_torrents', const _RpcError(3, 'Torrent not found'));

      final error = await captureError(() => client.pauseTasks([_hashA]));
      expect(error, isA<HttpException>());
      expect(error.toString(), contains('接口「core.pause_torrents」失败'));
    });

    test('方法表取自 daemon.get_method_list 并排序', () async {
      adapter.ok('daemon.get_method_list', [
        'core.get_free_space',
        'auth.login',
        'label.get_labels',
      ]);

      expect(await client.listMethods(), [
        'auth.login',
        'core.get_free_space',
        'label.get_labels',
      ]);
      expect(adapter.methods, ['auth.login', 'daemon.get_method_list']);
    });

    test('老版本没有 daemon.get_method_list 时回退 system.listMethods', () async {
      adapter.script('daemon.get_method_list', [
        const _RpcError(2, 'No method for "daemon.get_method_list"'),
      ]);
      adapter.ok('system.listMethods', ['core.get_config', 'auth.login']);

      expect(await client.listMethods(), ['auth.login', 'core.get_config']);
      expect(
        adapter.methods,
        ['auth.login', 'daemon.get_method_list', 'system.listMethods'],
      );
    });
  });

  group('任务列表：状态归一与本地筛选', () {
    final statuses = <String, dynamic>{
      _hashA: seed(
        name: 'Beta.2024',
        state: 'Downloading',
        size: 1000,
        done: 500,
        progress: 50.0,
        addedOn: 100,
        label: 'tv',
        dl: 1024,
        up: 64,
      ),
      _hashB: seed(
        name: 'alpha.mkv',
        state: 'Seeding',
        size: 2000,
        done: 2000,
        progress: 100.0,
        addedOn: 300,
        paused: true,
        isFinished: true,
      ),
      _hashC: seed(
        name: 'Gamma',
        state: 'Queued',
        size: 3000,
        done: 3000,
        progress: 100.0,
        addedOn: 200,
        label: 'movie',
        isSeed: true,
      ),
    };

    setUp(() => adapter.ok('core.get_torrents_status', statuses));

    test('Deluge 状态串归一到 qB 词表，进度按百分数还原', () async {
      final tasks = await client.getTasks();
      final byHash = {for (final t in tasks) t.hash: t};

      expect(tasks, hasLength(3));
      expect(byHash[_hashA]!.state, DownloadTaskState.downloading);
      expect(byHash[_hashB]!.state, DownloadTaskState.pausedUP);
      expect(byHash[_hashC]!.state, DownloadTaskState.queuedUP);

      final beta = byHash[_hashA]!;
      expect(beta.progress, 0.5);
      expect(beta.amountLeft, 500);
      expect(beta.size, 1000);
      expect(beta.dlspeed, 1024);
      expect(beta.category, 'tv');
      expect(beta.tags, isEmpty);
      expect(beta.contentPath, '/data/downloads/Beta.2024');
      expect(beta.addedOn, 100);
      expect(beta.uploaded, 640);
    });

    test('筛选：downloading / seeding / completed / paused / active', () async {
      Future<List<DownloadTask>> byFilter(String filter) =>
          client.getTasks(GetTasksParams(filter: filter));

      final downloading = await byFilter('downloading');
      expect(downloading.single.hash, _hashA);

      expect(
        (await byFilter('seeding')).map((t) => t.hash).toSet(),
        {_hashB, _hashC},
      );
      expect(
        (await byFilter('completed')).map((t) => t.hash).toSet(),
        {_hashB, _hashC},
      );
      expect(
        (await byFilter('paused')).map((t) => t.hash).toSet(),
        {_hashB},
      );
      expect(
        (await byFilter('active')).map((t) => t.hash).toSet(),
        {_hashA},
      );
      expect(await byFilter('all'), hasLength(3));
    });

    test('按 label 过滤分类', () async {
      final tasks = await client.getTasks(GetTasksParams(category: 'movie'));

      expect(tasks.single.hash, _hashC);
      expect(await client.getTasks(GetTasksParams(category: 'all')), hasLength(3));
    });

    test('排序大小写无关，reverse 与分页在本地完成', () async {
      final sorted = await client.getTasks(GetTasksParams(sort: 'name'));
      expect(sorted.map((t) => t.name).toList(),
          ['alpha.mkv', 'Beta.2024', 'Gamma']);

      final reversed = await client.getTasks(
        GetTasksParams(sort: 'name', reverse: true),
      );
      expect(reversed.map((t) => t.name).toList(),
          ['Gamma', 'Beta.2024', 'alpha.mkv']);

      final bySize = await client.getTasks(
        GetTasksParams(sort: 'size', reverse: true),
      );
      expect(bySize.map((t) => t.size).toList(), [3000, 2000, 1000]);

      final paged = await client.getTasks(
        GetTasksParams(sort: 'name', offset: 1, limit: 1),
      );
      expect(paged.single.name, 'Beta.2024');
    });

    test('其余状态串的归一', () async {
      adapter.ok('core.get_torrents_status', {
        _hashA: seed(name: 'a', state: 'Checking'),
        _hashB: seed(name: 'b', state: 'Checking', isFinished: true),
        _hashC: seed(name: 'c', state: 'Moving'),
      });
      final tasks = await client.getTasks();
      expect(tasks[0].state, DownloadTaskState.checkingDL);
      expect(tasks[1].state, DownloadTaskState.checkingUP);
      expect(tasks[2].state, DownloadTaskState.moving);

      adapter.ok('core.get_torrents_status', {
        _hashA: seed(name: 'a', state: 'Allocating'),
        _hashB: seed(name: 'b', state: 'Error'),
        _hashC: seed(name: 'c', state: 'SomethingNew'),
      });
      final rest = await client.getTasks();
      expect(rest[0].state, DownloadTaskState.allocating);
      expect(rest[1].state, DownloadTaskState.error);
      expect(rest[2].state, DownloadTaskState.unknown);

      adapter.ok('core.get_torrents_status', {
        _hashA: seed(name: 'a', state: 'Downloading', paused: true),
        _hashB: seed(name: 'b', state: 'Queued', paused: true),
        _hashC: seed(name: 'c', state: 'Queued', paused: true, isSeed: true),
      });
      final paused = await client.getTasks();
      expect(paused[0].state, DownloadTaskState.pausedDL);
      expect(paused[1].state, DownloadTaskState.pausedDL);
      expect(paused[2].state, DownloadTaskState.pausedUP);
    });

    test('getTransferInfo 按种子求和（Deluge session_status 不可靠）', () async {
      adapter.ok('core.get_torrents_status', {
        _hashA: <String, dynamic>{
          'download_payload_rate': 100,
          'upload_payload_rate': 20,
          'all_time_download': 900,
          'total_uploaded': 400,
        },
        _hashB: <String, dynamic>{
          'download_payload_rate': 50,
          'upload_payload_rate': 5,
          'all_time_download': 100,
          'total_uploaded': 60,
        },
      });

      final info = await client.getTransferInfo();
      expect(info.dlSpeed, 150);
      expect(info.upSpeed, 25);
      expect(info.dlTotal, 1000);
      expect(info.upTotal, 460);
    });

    test('累计下载量兼容老键名，都没有时退回 total_done', () async {
      adapter.ok('core.get_torrents_status', {
        _hashA: <String, dynamic>{'total_downloaded': 700},
        _hashB: <String, dynamic>{'total_size': 500, 'total_done': 300},
      });

      final info = await client.getTransferInfo();
      expect(info.dlTotal, 1000);
      expect(info.upTotal, 0);
    });

    test('getServerState 汇总累计流量与剩余空间', () async {
      adapter.ok('core.get_free_space', 1 << 30);
      adapter.ok('core.get_torrents_status', {
        _hashA: <String, dynamic>{
          'all_time_download': 900,
          'total_uploaded': 400,
        },
        _hashB: <String, dynamic>{
          'all_time_download': 100,
          'total_uploaded': 60,
        },
      });

      final state = await client.getServerState();
      expect(state.freeSpaceOnDisk, 1 << 30);
      expect(state.alltimeDl, 1000);
      expect(state.alltimeUl, 460);
    });
  });

  group('添加任务', () {
    test('直投链接走 core.add_torrent_url 并按返回值挂 label', () async {
      adapter.ok('core.add_torrent_url', _hashA);

      await client.addTask(
        const AddTaskParams(
          url: 'http://site.example/download.php?id=1',
          category: 'tv',
        ),
      );

      expect(adapter.methods,
          ['auth.login', 'core.add_torrent_url', 'label.set_torrent']);
      expect(adapter.callAt(1).first, 'http://site.example/download.php?id=1');
      expect(adapter.callAt(1)[1], <String, dynamic>{});
      expect(adapter.last.params, [_hashA, 'tv']);
    });

    test('保存路径进添加选项，暂停与自动管理改用专用接口', () async {
      adapter.ok('core.add_torrent_url', _hashA);

      await client.addTask(
        const AddTaskParams(
          url: 'http://site.example/download.php?id=2',
          savePath: '/data/incomplete',
          startPaused: true,
          autoTMM: false,
        ),
      );

      // add_torrent_* 各版本接受的选项键名不一致，只带官方示例里的 download_location
      expect(adapter.callAt(1)[1], {'download_location': '/data/incomplete'});
      expect(adapter.methods, [
        'auth.login',
        'core.add_torrent_url',
        'core.pause_torrents',
        'core.set_torrent_auto_managed',
      ]);
      expect(adapter.callAt(2).params, [[_hashA]]);
      expect(adapter.callAt(3).params, [_hashA, false]);
      // 没有分类就不该再调 label
      expect(adapter.methods.contains('label.set_torrent'), isFalse);
    });

    test('空分类显式回到内置 No Label', () async {
      await client.setCategory([_hashA, _hashB], '');

      expect(adapter.methods, [
        'auth.login',
        'label.set_torrent',
        'label.set_torrent',
      ]);
      expect(adapter.callAt(1).params, [_hashA, 'No Label']);
      expect(adapter.callAt(2).params, [_hashB, 'No Label']);
    });

    test('勾选本地中转：先取种子字节再以 base64 上传', () async {
      final relayClient = build(useLocalRelay: true);
      adapter.torrentFileBytes = const [0x64, 0x38, 0x21, 0x65];
      adapter.ok('core.add_torrent_file', _hashC);

      await relayClient.addTask(
        const AddTaskParams(
          url: 'http://site.example/download.php?id=3',
          category: 'movie',
        ),
      );

      expect(adapter.downloadedUrls, ['http://site.example/download.php?id=3']);
      expect(adapter.methods, [
        'auth.login',
        'core.add_torrent_file',
        'label.set_torrent',
      ]);
      expect(adapter.callAt(1)[0], 'ptmate.torrent');
      expect(base64Decode(adapter.callAt(1)[1] as String),
          adapter.torrentFileBytes);
      expect(adapter.last.params, [_hashC, 'movie']);
    });

    test('## 前缀强制走中转且不会漏进 URL', () async {
      adapter.ok('core.add_torrent_file', _hashA);

      await client.addTask(
        const AddTaskParams(url: '##http://site.example/download.php?id=4'),
      );

      expect(adapter.downloadedUrls.single,
          'http://site.example/download.php?id=4');
      expect(adapter.methods.contains('core.add_torrent_url'), isFalse);
    });

    test('添加接口没回传种子 ID 时不抛错，只跳过分类', () async {
      adapter.ok('core.add_torrent_url', 'Torrent added');

      await client.addTask(
        const AddTaskParams(url: 'http://site.example/d.php', category: 'tv'),
      );

      expect(adapter.methods.contains('label.set_torrent'), isFalse);
    });

    test('批量暂停/恢复/删除映射到 core.*', () async {
      await client.pauseTasks([_hashA]);
      expect(adapter.last.method, 'core.pause_torrents');
      expect(adapter.last.first, [_hashA]);

      await client.resumeTask(_hashB);
      expect(adapter.last.method, 'core.resume_torrents');

      await client.deleteTasks([_hashA, _hashB], deleteFiles: true);
      expect(adapter.last.method, 'core.remove_torrents');
      expect(adapter.last.first, [_hashA, _hashB]);
      expect(adapter.last[1], isTrue);
    });

    test('空 hash 列表不发起 RPC', () async {
      final before = adapter.jsonCallCount;

      await client.pauseTasks(const []);
      await client.resumeTasks(const []);
      await client.deleteTasks(const []);
      await client.topPriority(const []);
      await client.setCategory(const [], 'tv');

      expect(adapter.jsonCallCount, before);
      expect(adapter.askedAuthLogin, isFalse);
    });
  });

  group('Tracker 整表读写', () {
    test('读取时按当前 tracker 近似逐条状态', () async {
      adapter.ok('core.get_torrent_status', {
        'tracker_host': 'http://t1.example/announce',
        'tracker_status': 'Tracker status unregistered',
        'num_seeds': 2,
        'num_peers': 3,
        'trackers': [
          {'url': 'http://t1.example/announce', 'num_peers': 4},
          {'url': 'http://t2.example/announce', 'msg': 'explicit note'},
          {'url': ''},
        ],
      });

      final trackers = await client.getTrackers(_hashA);

      expect(trackers, hasLength(3));
      expect(trackers[0].status, 2);
      expect(trackers[0].message, 'Tracker status unregistered');
      expect(trackers[0].numPeers, 4);
      expect(trackers[1].status, 1);
      expect(trackers[1].message, 'explicit note');
      expect(trackers[2].status, 0);
    });

    test('tracker_status 含错误关键字时判为红种', () async {
      adapter.ok('core.get_torrent_status', {
        'tracker_host': 'http://t1.example/announce',
        'tracker_status': 'Tracker error: unreachable',
        'trackers': [
          {'url': 'http://t1.example/announce'},
          {'url': 'http://t9.example/announce'},
        ],
      });

      final trackers = await client.getTrackers(_hashA);
      expect(trackers[0].status, 4);
      expect(trackers[1].status, 4);
    });

    test('实机回报的 tracker 字典只有 scrape_* 与 fails/updating', () async {
      // Deluge 2.2.0 单 tracker 的真实字段（本机实例核对）
      adapter.ok('core.get_torrent_status', {
        'tracker_host': 'pandapt.net',
        'tracker_status': 'Announce OK',
        'trackers': [
          <String, dynamic>{
            'url': 'https://tracker.pandapt.net/announce.php?passkey=abc',
            'trackerid': '',
            'tier': 0,
            'fail_limit': 0,
            'source': 1,
            'verified': false,
            'message': '',
            'last_error': {'value': 0, 'category': ''},
            'next_announce': null,
            'scrape_incomplete': 1,
            'scrape_complete': 12,
            'scrape_downloaded': 34,
            'fails': 0,
            'updating': false,
          },
        ],
      });

      final trackers = await client.getTrackers(_hashA);

      expect(trackers.single.seeds, 12);
      expect(trackers.single.leeches, 1);
      expect(trackers.single.numDownloads, 34);
      expect(trackers.single.tier, 0);
      // 逐条 message 为空 → 用种子级 tracker_status 兜底；非错误 → 正常工作
      expect(trackers.single.message, 'Announce OK');
      expect(trackers.single.status, 2);
    });

    test('私站不给 scrape 数据时也认当前 tracker 并显示种子级状态', () async {
      // 本机实例的返回：tracker_host 只给注册域名、scrape_* 全 0、message 空串
      adapter.ok('core.get_torrent_status', {
        'tracker_host': 'pandapt.net',
        'tracker_status': 'Announce OK',
        'trackers': [
          {
            'url': 'https://tracker.pandapt.net/announce.php?passkey=abc',
            'message': '',
            'scrape_complete': 0,
            'scrape_incomplete': 0,
            'scrape_downloaded': 0,
            'fails': 0,
            'updating': false,
          },
          {
            'url': 'https://tracker.other-site.org/announce',
            'message': '',
          },
        ],
      });

      final trackers = await client.getTrackers(_hashA);

      expect(trackers[0].status, 2);
      expect(trackers[0].message, 'Announce OK');
      expect(trackers[0].seeds, 0);
      // 不是当前 tracker：不给兜底消息，判为未联系
      expect(trackers[1].status, 1);
      expect(trackers[1].message, '');
    });

    test('announce 失败次数与 updating 直接决定逐条状态', () async {
      adapter.ok('core.get_torrent_status', {
        'tracker_host': 'other.example',
        'tracker_status': '',
        'trackers': [
          {'url': 'http://t1.example/announce', 'updating': true},
          {'url': 'http://t2.example/announce', 'fails': 2},
        ],
      });

      final trackers = await client.getTrackers(_hashA);
      expect(trackers[0].status, 3);
      expect(trackers[1].status, 4);
    });

    test('没有 trackers 时返回空表', () async {
      adapter.ok('core.get_torrent_status', <String, dynamic>{});
      expect(await client.getTrackers(_hashA), isEmpty);
    });

    test('新增 tracker 追加到最高层，重复则跳过', () async {
      adapter.ok('core.get_torrent_status', {
        'trackers': [
          {'url': 'http://t1.example/announce', 'tier': 0},
          {'url': 'http://t2.example/announce', 'tier': 2},
        ],
      });

      await client.addTracker(_hashA, 'http://t3.example/announce');
      expect(adapter.last.method, 'core.set_torrent_trackers');
      expect(adapter.last.first, _hashA);
      expect(adapter.last[1], [
        {'url': 'http://t1.example/announce', 'tier': 0},
        {'url': 'http://t2.example/announce', 'tier': 2},
        {'url': 'http://t3.example/announce', 'tier': 2},
      ]);

      final callsBefore = adapter.jsonCallCount;
      await client.addTracker(_hashA, 'http://t1.example/announce');
      expect(adapter.jsonCallCount, callsBefore + 1);
      expect(adapter.last.method, 'core.get_torrent_status');
    });

    test('编辑与删除都是整表覆盖', () async {
      adapter.ok('core.get_torrent_status', {
        'trackers': [
          {'url': 'http://t1.example/announce', 'tier': 0},
          {'url': 'http://t2.example/announce', 'tier': 0},
        ],
      });

      await client.editTracker(
        _hashA,
        'http://t1.example/announce',
        'http://t1b.example/announce',
      );
      expect(adapter.last[1], [
        {'url': 'http://t1b.example/announce', 'tier': 0},
        {'url': 'http://t2.example/announce', 'tier': 0},
      ]);

      await client.removeTrackers(_hashA, ['http://t2.example/announce']);
      expect(adapter.last[1], [
        {'url': 'http://t1.example/announce', 'tier': 0},
      ]);

      await client.reannounceTorrents([_hashA]);
      expect(adapter.last.method, 'core.force_reannounce');
      expect(adapter.last.first, [_hashA]);
    });
  });

  group('文件与优先级', () {
    test('files 与 file_progress / file_priorities 按下标配对', () async {
      adapter.ok('core.get_torrent_status', {
        'is_finished': false,
        'files': [
          {'path': 'Show/ep01.mkv', 'size': 100},
          {'name': 'Show/ep02.mkv', 'size': 200},
          {'path': 'Show/ep03.mkv', 'size': 300},
        ],
        'file_progress': [25.0, 1.0],
        // Deluge 直接透出 libtorrent 的 0..7，实机默认档是 4
        'file_priorities': [7, 0],
      });

      final files = await client.getTorrentFiles(_hashA);

      expect(files[0].index, 0);
      expect(files[0].name, 'Show/ep01.mkv');
      expect(files[0].progress, 0.25);
      expect(files[0].priority, FilePriority.maximum);
      expect(files[0].isSeed, isFalse);
      // 0 档在 Deluge 里就是「不下载」
      expect(files[1].priority, FilePriority.skipped);
      expect(files[1].progress, 1.0);
      // 平行数组短于 files 时按下标缺省（进度 0、优先级回到普通档）
      expect(files[2].name, 'Show/ep03.mkv');
      expect(files[2].index, 2);
      expect(files[2].progress, 0);
      expect(files[2].priority, FilePriority.normal);
    });

    test('Deluge 的 4 档展示成「普通」，6/7 档保持高/最高', () async {
      adapter.ok('core.get_torrent_status', {
        'files': [
          {'path': 'a', 'size': 1},
          {'path': 'b', 'size': 1},
        ],
        'file_progress': [0.5, 0.5],
        'file_priorities': [4, 6],
      });

      final files = await client.getTorrentFiles(_hashA);
      expect(files[0].priority, FilePriority.normal);
      expect(files[1].priority, FilePriority.high);
      expect(files[0].selected, isTrue);
    });

    test('setFilePriority 读全表、改目标下标再整体写回', () async {
      adapter.ok('core.get_torrent_status', {'file_priorities': [4, 4, 4, 4]});

      await client.setFilePriority(
        hash: _hashA,
        ids: const [0, 2],
        priority: FilePriority.maximum,
      );

      expect(adapter.last.method, 'core.set_torrent_file_priorities');
      expect(adapter.last.first, _hashA);
      expect(adapter.last[1], [7, 4, 7, 4]);
    });

    test('「普通」写回 Deluge 用默认档 4，跳过用 0', () async {
      // 每次 setFilePriority 都先重新读表，脚本模拟上一轮写回后的真实状态
      adapter.script('core.get_torrent_status', [
        {'file_priorities': [7, 7]},
        {'file_priorities': [4, 7]},
      ]);

      await client.setFilePriority(
        hash: _hashA,
        ids: const [0],
        priority: FilePriority.normal,
      );
      expect(adapter.last[1], [4, 7]);

      await client.setFilePriority(
        hash: _hashA,
        ids: const [1],
        priority: FilePriority.skipped,
      );
      expect(adapter.last[1], [4, 0]);
    });

    test('优先级写回会被夹到 libtorrent 的 0..7', () async {
      adapter.ok('core.get_torrent_status', {'file_priorities': [1, 12, 'x']});

      await client.setFilePriority(
        hash: _hashA,
        ids: const [0],
        priority: 9,
      );

      expect(adapter.last[1], [7, 7, 4]);
    });

    test('种子元数据未就绪（没有优先级列表）时报可读错误', () async {
      adapter.ok('core.get_torrent_status', <String, dynamic>{});

      final error = await captureError(
        () => client.setFilePriority(
          hash: _hashA,
          ids: const [0],
          priority: 1,
        ),
      );
      expect(error.toString(), contains('未返回文件优先级列表'));
      expect(
        adapter.methods.contains('core.set_torrent_file_priorities'),
        isFalse,
      );
    });

    test('节点列表解析，拿不到时按空处理', () async {
      adapter.ok('core.get_torrent_status', {
        'peers': [
          {
            'ip': '10.0.0.8',
            'port': 6881,
            'client': 'qBittorrent/4.6',
            'down_speed': 512,
            'progress': 40.0,
          },
          {'ip': '10.0.0.9'},
        ],
      });

      final peers = await client.getTorrentPeers(_hashA);
      expect(peers, hasLength(2));
      expect(peers[0].peerId, '10.0.0.8:6881');
      expect(peers[0].dlSpeed, 512);
      expect(peers[0].progress, 0.4);
      expect(peers[1].peerId, '10.0.0.9');

      adapter.ok('core.get_torrent_status', const _RpcError(3, 'No such torrent'));
      expect(await client.getTorrentPeers(_hashB), isEmpty);
    });
  });

  group('开关、队列与限速', () {
    test('翻转类开关先读当前值再写回', () async {
      adapter.ok('core.get_torrent_status', {'sequential_download': false});
      await client.toggleSequentialDownload([_hashA]);
      expect(adapter.last.method, 'core.set_torrent_options');
      expect(adapter.last[1], {'sequential_download': true});

      adapter.ok('core.get_torrent_status', {'prioritize_first_last': true});
      await client.toggleFirstLastPiecePrio([_hashA]);
      expect(adapter.last[1], {'prioritize_first_last': false});
    });

    test('超级做种与自动管理直接写值', () async {
      await client.setSuperSeeding([_hashA], true);
      expect(adapter.last[1], {'super_seeding': true});

      await client.setAutoManagement([_hashA, _hashB], false);
      expect(adapter.last.first, [_hashA, _hashB]);
      expect(adapter.last[1], {'auto_managed': false});
    });

    test('队列四个动作映射到 core.queue_*', () async {
      await client.topPriority([_hashA]);
      expect(adapter.last.method, 'core.queue_top');
      await client.bottomPriority([_hashA]);
      expect(adapter.last.method, 'core.queue_bottom');
      await client.increasePriority([_hashA]);
      expect(adapter.last.method, 'core.queue_up');
      await client.decreasePriority([_hashA]);
      expect(adapter.last.method, 'core.queue_down');
    });

    test('全局限速按 KiB/s 原值写进 core.set_config', () async {
      await client.setGlobalDownloadLimit(2048);
      expect(adapter.last.method, 'core.set_config');
      expect(adapter.last.first, {'max_download_speed': 2048});

      await client.setGlobalUploadLimit(-1);
      expect(adapter.last.first, {'max_upload_speed': -1});
    });

    test('偏好读写：core.get_config（无参）/ core.set_config', () async {
      // 实机 2.2.0：core.get_config 带键名列表会报 code 4，只能整表取
      adapter.ok('core.get_config', {
        'max_download_speed': -1.0,
        'max_upload_speed': 512.0,
        'download_location': '/downloads',
        'queue_new_to_top': false,
      });

      final prefs = await client.getGlobalPreferences();
      expect(prefs.dlLimit, -1);
      expect(prefs.upLimit, 512);
      expect(prefs.dlLimitApplied, isFalse);
      expect(prefs.upLimitApplied, isTrue);
      // 定时/备选限速属于插件，core.get_config 里没有对应键
      expect(prefs.schedulerEnabled, isFalse);
      expect(prefs.altDlLimit, -1);
      expect(prefs.altUpLimit, -1);
      expect(prefs.speedLimitMode, 0);
      expect(adapter.callAt(1).params, isEmpty);

      await client.setPreferences({'max_download_speed': 1024});
      expect(adapter.last.method, 'core.set_config');
      expect(adapter.last.first, {'max_download_speed': 1024});

      final before = adapter.jsonCallCount;
      await client.setPreferences(const {});
      expect(adapter.jsonCallCount, before);
    });

    test('不支持的能力用异常挡在门控之外', () async {
      expect(client.capabilities.has(DownloaderFeature.tags), isFalse);
      expect(client.capabilities.has(DownloaderFeature.altSpeedLimits), isFalse);
      expect(client.capabilities.has(DownloaderFeature.forceStart), isFalse);
      expect(
        client.capabilities.has(DownloaderFeature.qbPreferenceSchema),
        isFalse,
      );
      expect(client.capabilities.has(DownloaderFeature.queue), isTrue);
      expect(client.capabilities.has(DownloaderFeature.fileSelection), isTrue);
      expect(client.capabilities.has(DownloaderFeature.trackerWrite), isTrue);
      expect(client.capabilities.has(DownloaderFeature.peers), isTrue);
      // 2.2.0 实机：累计下载/上传能按种子求出来，只是没有缓存与队列指标
      expect(client.capabilities.has(DownloaderFeature.cumulativeStats), isTrue);

      final errors = <String>[
        (await captureError(() => client.addTags([_hashA], ['x'])))
            .toString(),
        (await captureError(() => client.removeTags([_hashA], ['x'])))
            .toString(),
        (await captureError(() => client.createTags(['x']))).toString(),
        (await captureError(() => client.deleteTags(['x']))).toString(),
        (await captureError(() => client.setForceStart([_hashA], true)))
            .toString(),
        (await captureError(() => client.setSpeedLimitsMode(1))).toString(),
      ];

      for (final message in errors) {
        expect(message, contains('当前下载器（Deluge）不支持'));
      }
      expect(errors[0], contains('标签管理'));
      expect(errors[4], contains('强制开始'));
      expect(errors[5], contains('备选限速模式'));
      // 抛错不该先发登录请求
      expect(adapter.askedAuthLogin, isFalse);
    });
  });

  group('分类（Label 插件）', () {
    test('读取分类时忽略内置 No Label', () async {
      adapter.ok('label.get_labels', {
        'No Label': <String, dynamic>{},
        'tv': {'move_completed_path': '/data/tv'},
        'movie': <String, dynamic>{},
      });

      expect(await client.getCategories(), ['movie', 'tv']);
      expect(await client.getCategoryDetails(), {'tv': '/data/tv', 'movie': ''});
    });

    test('Label 插件没启用时读分类退化成空表', () async {
      // 实机：插件关闭后 label.* 是未知方法（本机实例核对）
      adapter.ok(
        'label.get_labels',
        const _RpcError(2, 'No method for "label.get_labels"'),
      );

      expect(await client.getCategories(), isEmpty);
      expect(await client.getCategoryDetails(), isEmpty);
    });

    test('创建分类可附带完成后移动路径', () async {
      await client.createCategory('anime', savePath: '/data/anime');

      expect(adapter.methods, ['auth.login', 'label.add', 'label.set_options']);
      expect(adapter.callAt(1).first, 'anime');
      expect(adapter.last.params, [
        'anime',
        {
          'apply_move_completed': true,
          'move_completed': true,
          'move_completed_path': '/data/anime',
        },
      ]);
    });

    test('不带路径创建时不会多调一次 set_options', () async {
      await client.createCategory('anime');

      expect(adapter.methods, ['auth.login', 'label.add']);
    });

    test('清空保存路径时关掉 move_completed', () async {
      await client.setCategorySavePath('anime', '');

      expect(adapter.last[1], {
        'apply_move_completed': false,
        'move_completed': false,
        'move_completed_path': '',
      });
    });

    test('删除分类与重新校验', () async {
      await client.deleteCategory('anime');
      expect(adapter.last.method, 'label.remove');
      expect(adapter.last.first, 'anime');

      await client.recheckTorrents([_hashA]);
      expect(adapter.last.method, 'core.force_recheck');
      expect(await client.getTags(), isEmpty);
    });

    test('任务里的 label 归一成分类', () async {
      adapter.ok('core.get_torrents_status', {
        _hashA: seed(name: 'a', state: 'Seeding', label: 'No Label'),
        _hashB: seed(name: 'b', state: 'Seeding', label: ''),
        _hashC: seed(name: 'c', state: 'Seeding', label: 'tv'),
      });

      final tasks = await client.getTasks();
      expect(tasks[0].category, '');
      expect(tasks[1].category, '');
      expect(tasks[2].category, 'tv');
      // Deluge 没有标签体系
      expect(tasks[2].tags, isEmpty);
    });
  });

  group('版本与详情', () {
    test('daemon.get_version 读取版本并缓存、回写配置', () async {
      String? saved;
      final probe = build(onConfigUpdated: (c) => saved = c.version);
      adapter.ok('daemon.get_version', '2.2.0');

      expect(await probe.getVersion(), '2.2.0');
      expect(await probe.getVersion(), '2.2.0');
      expect(adapter.methods, ['auth.login', 'daemon.get_version']);
      expect(saved, '2.2.0');
    });

    test('老版本只有 daemon.info 时自动回退', () async {
      String? saved;
      final probe = build(onConfigUpdated: (c) => saved = c.version);
      adapter.script('daemon.get_version', [
        const _RpcError(2, 'No method for "daemon.get_version"'),
      ]);
      adapter.ok('daemon.info', '1.3.15');

      expect(await probe.getVersion(), '1.3.15');
      expect(saved, '1.3.15');
      expect(
        adapter.methods,
        ['auth.login', 'daemon.get_version', 'daemon.info'],
      );
    });

    test('配置已有版本时不再回写', () async {
      String? saved;
      final probe = build(
        version: '2.0.0',
        onConfigUpdated: (c) => saved = c.version,
      );
      adapter.ok('daemon.get_version', '2.2.0');

      expect(await probe.getVersion(), '2.2.0');
      expect(saved, isNull);
    });

    test('getPaths 汇总去重 download_location', () async {
      adapter.ok('core.get_torrents_status', {
        _hashA: seed(name: 'a', state: 'Seeding', downloadLocation: '/data/b'),
        _hashB: seed(name: 'b', state: 'Seeding', downloadLocation: '/data/a'),
        _hashC: seed(name: 'c', state: 'Seeding', downloadLocation: '/data/b'),
      });

      expect(await client.getPaths(), ['/data/a', '/data/b']);
    });

    test('概览页复用 qB 字段名', () async {
      adapter.ok('core.get_torrent_status', seed(
        name: 'Beta.2024',
        state: 'Downloading',
        size: 1000,
        done: 250,
        progress: 25.0,
        addedOn: 100,
        label: 'tv',
        dl: 1024,
        up: 64,
      ));

      final info = await client.getTorrentInfoRaw(_hashA);

      expect(info, isNotNull);
      expect(info!['hash'], _hashA);
      expect(info['size'], 1000);
      expect(info['amount_left'], 750);
      expect(info['dlspeed'], 1024);
      expect(info['added_on'], 100);
      expect(info['time_active'], 300);
      expect(info['category'], 'tv');
      expect(info['tags'], '');
      expect(info['save_path'], '/data/downloads');
      expect(info['content_path'], '/data/downloads/Beta.2024');
      expect(info['num_complete'], 5);
      expect(info['num_incomplete'], 7);
      expect(info['auto_tmm'], isTrue);
      // 原生键同时保留，页面按 qB 别名取值
      expect(info['download_payload_rate'], 1024);

      adapter.ok('core.get_torrent_status', <String, dynamic>{});
      expect(await client.getTorrentInfoRaw(_hashB), isNull);
    });

    test('属性页：完成时间拿不到就留 0', () async {
      adapter.ok('core.get_torrent_status', seed(
        name: 'Beta.2024',
        state: 'Seeding',
        size: 1000,
        done: 1000,
        progress: 100.0,
      ));

      final props = await client.getTorrentProperties(_hashA);
      expect(props.completionOn, 0);
      expect(props.savePath, '/data/downloads');
      expect(props.contentPath, '/data/downloads/Beta.2024');
      expect(props.totalSize, 1000);
      expect(props.seedingTime, 120);
      expect(props.numSeeds, 5);
      // Deluge 的 total_* 是 swarm 规模，num_* 是当前连接数
      expect(props.numLeeches, 7);
      expect(props.numPeers, 3);
      expect(props.dlTotal, 1000);
      expect(props.upTotal, 0);
      expect(props.addedOn, 1000);
    });

    test('testConnection 的成功与失败信息', () async {
      adapter.ok('daemon.get_version', '2.2.0');
      await client.testConnection();
      expect(adapter.methods, ['auth.login', 'daemon.get_version']);

      final failing = _FakeDelugeAdapter()
        ..script('auth.login', [const _RpcError(3, 'Wrong password')]);
      final probe = DelugeClient(
        config: const DelugeConfig(
          id: 'x',
          name: 'x',
          host: '127.0.0.1',
          port: 8112,
          username: '',
          password: 'p',
        ),
        password: 'p',
        dio: Dio()..httpClientAdapter = failing,
      );

      final error = await captureError(probe.testConnection);
      expect(error.toString(), contains('Connection test failed'));
      expect(error.toString(), contains('Deluge 登录失败'));
    });

    test('host 带协议与尾斜杠时 URL 归一到 /json', () async {
      final dio = Dio()..httpClientAdapter = adapter;
      final probe = DelugeClient(
        config: const DelugeConfig(
          id: 'x',
          name: 'x',
          host: 'http://deluge.lan/',
          port: 8112,
          username: '',
          password: 'p',
        ),
        password: 'p',
        dio: dio,
      );
      adapter.ok('core.get_free_space', 1);
      adapter.ok('core.get_torrents_status', {});

      await probe.getServerState();
      expect(adapter.requestUrls, [
        'http://deluge.lan:8112/json',
        'http://deluge.lan:8112/json',
        'http://deluge.lan:8112/json',
      ]);
      expect(adapter.callAt(1).cookie, isNotNull);
    });
  });
}
