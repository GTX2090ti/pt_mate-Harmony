import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pt_mate/models/app_models.dart';
import 'package:pt_mate/services/downloader/torrent_file_downloader_mixin.dart';

class _DownloadHarness with TorrentFileDownloaderMixin {}

class _RecordingHttpClientAdapter implements HttpClientAdapter {
  Map<String, dynamic>? lastHeaders;
  int requestCount = 0;
  int timeoutCount = 0;

  /// 默认回一段最小 bencode（`d3:4`），首字节 'd' 才算合法种子
  List<int> body = const <int>[100, 51, 58, 52];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requestCount++;
    lastHeaders = Map<String, dynamic>.from(options.headers);
    if (requestCount <= timeoutCount) {
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.receiveTimeout,
      );
    }
    return ResponseBody.fromBytes(body, 200);
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  group('TorrentFileDownloaderMixin', () {
    test(
      'attaches a generic Web site cookie to same-origin downloads',
      () async {
        final adapter = _RecordingHttpClientAdapter();
        final dio = Dio()..httpClientAdapter = adapter;
        final harness = _DownloadHarness();

        final result = await harness.downloadTorrentFileCommon(
          dio,
          '##https://jpopsuki.eu/torrents.php?action=download&id=1',
          siteConfig: const SiteConfig(
            id: 'jpopsuki',
            name: 'JPopSuki',
            baseUrl: 'https://jpopsuki.eu/',
            cookie: 'PHPSESSID=fixture',
            siteType: SiteType.web,
          ),
        );

        expect(result, const <int>[100, 51, 58, 52]);
        expect(adapter.lastHeaders?['Cookie'], 'PHPSESSID=fixture');
      },
    );

    test('never sends a site cookie to a third-party download host', () async {
      final adapter = _RecordingHttpClientAdapter();
      final dio = Dio()..httpClientAdapter = adapter;
      final harness = _DownloadHarness();

      await harness.downloadTorrentFileCommon(
        dio,
        'https://cdn.example.net/file.torrent',
        siteConfig: const SiteConfig(
          id: 'web-site',
          name: 'Web Site',
          baseUrl: 'https://tracker.example.org/',
          cookie: 'sid=fixture',
          siteType: SiteType.web,
        ),
      );

      expect(adapter.lastHeaders?.containsKey('Cookie'), isFalse);
    });

    test('retries the torrent request once after a timeout', () async {
      final adapter = _RecordingHttpClientAdapter()..timeoutCount = 1;
      final dio = Dio()..httpClientAdapter = adapter;
      final harness = _DownloadHarness();

      final result = await harness.downloadTorrentFileCommon(
        dio,
        'https://tracker.example.org/download/1',
      );

      expect(result, const <int>[100, 51, 58, 52]);
      expect(adapter.requestCount, 2);
    });

    test('站点回 200 但内容是网页时，不把字节丢给下载器', () async {
      final adapter = _RecordingHttpClientAdapter()
        ..body = '<html><body>please login</body></html>'.codeUnits;
      final dio = Dio()..httpClientAdapter = adapter;
      final harness = _DownloadHarness();

      await expectLater(
        harness.downloadTorrentFileCommon(
          dio,
          'https://tracker.example.org/download.php?id=9',
        ),
        throwsA(
          predicate(
            (e) =>
                e.toString().contains('站点返回的不是种子文件') &&
                e.toString().contains('0x3c') &&
                e.toString().contains('please login'),
          ),
        ),
      );
    });

    test('站点回空内容时单独报错，不和网页内容混成一条', () async {
      final adapter = _RecordingHttpClientAdapter()..body = const <int>[];
      final dio = Dio()..httpClientAdapter = adapter;
      final harness = _DownloadHarness();

      await expectLater(
        harness.downloadTorrentFileCommon(
          dio,
          'https://tracker.example.org/download.php?id=9',
        ),
        throwsA(predicate((e) => e.toString().contains('空内容'))),
      );
    });
  });
}
