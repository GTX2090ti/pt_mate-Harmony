import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:pt_mate/models/app_models.dart';
import 'package:pt_mate/services/settings/display_settings_manager.dart';
import 'package:pt_mate/services/storage/storage_service.dart';
import 'package:pt_mate/widgets/torrent_list_item.dart';
import 'package:shared_preferences/shared_preferences.dart';

TorrentItem _torrent({
  required String id,
  required String name,
  String smallDescr = '',
  List<TagType> tags = const [],
  bool? hasExternalSubtitle,
  bool collection = false,
  DownloadStatus downloadStatus = DownloadStatus.none,
}) {
  return TorrentItem(
    id: id,
    name: name,
    smallDescr: smallDescr,
    sizeBytes: 1024,
    seeders: 10,
    leechers: 2,
    createdDate: DateTime(2026, 1, 1),
    discountEndTime: null,
    downloadUrl: '',
    imageList: const [],
    cover: '',
    tags: tags,
    hasExternalSubtitle: hasExternalSubtitle,
    collection: collection,
    downloadStatus: downloadStatus,
  );
}

Widget _harness(DisplaySettingsManager settings, TorrentItem torrent) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<DisplaySettingsManager>.value(value: settings),
      Provider<StorageService>.value(value: StorageService.instance),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: TorrentListItem(
          torrent: torrent,
          isSelected: false,
          isSelectionMode: false,
          showCoverSetting: false,
        ),
      ),
    ),
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    StorageService.instance.resetForTest();
  });

  Future<void> pumpTorrent(
    WidgetTester tester,
    TorrentItem torrent, {
    double width = 400,
  }) async {
    tester.view.physicalSize = Size(width, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final settings = DisplaySettingsManager(StorageService.instance);
    addTearDown(settings.dispose);
    await tester.pumpWidget(_harness(settings, torrent));
    await tester.pumpAndSettle();
  }

  testWidgets('探测到外挂字幕时显示有外挂字幕徽章', (tester) async {
    await pumpTorrent(
      tester,
      _torrent(
        id: '1',
        name: 'Movie.2023.1080p.BluRay',
        hasExternalSubtitle: true,
      ),
    );

    expect(find.text('有外挂字幕'), findsOneWidget);
    expect(find.text('无外挂字幕'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('详情页确认没有字幕时显示无外挂字幕徽章', (tester) async {
    await pumpTorrent(
      tester,
      _torrent(
        id: '2',
        name: 'Movie.2023.1080p.BluRay',
        hasExternalSubtitle: false,
      ),
    );

    expect(find.text('无外挂字幕'), findsOneWidget);
    expect(find.text('有外挂字幕'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('尚未探测到字幕状态时不显示字幕徽章', (tester) async {
    await pumpTorrent(
      tester,
      _torrent(id: '3', name: 'Movie.2023.1080p.BluRay'),
    );

    expect(find.text('有外挂字幕'), findsNothing);
    expect(find.text('无外挂字幕'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('收藏红心排在已下载勾之前', (tester) async {
    await pumpTorrent(
      tester,
      _torrent(
        id: '4',
        name: 'Movie.2023.1080p.BluRay',
        collection: true,
        downloadStatus: DownloadStatus.completed,
      ),
    );

    final heart = find.byTooltip('已收藏');
    final downloaded = find.byIcon(Icons.download_done);
    expect(heart, findsOneWidget);
    expect(downloaded, findsOneWidget);
    expect(
      tester.getCenter(heart).dx,
      lessThan(tester.getCenter(downloaded).dx),
    );
    expect(
      (tester.getCenter(heart).dy - tester.getCenter(downloaded).dy).abs(),
      lessThan(1.0),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('窄屏下同时显示红心、已下载和字幕徽章不溢出', (tester) async {
    await pumpTorrent(
      tester,
      _torrent(
        id: '5',
        name: 'Movie.2023.1080p.BluRay.x265.10bit',
        hasExternalSubtitle: true,
        collection: true,
        downloadStatus: DownloadStatus.completed,
      ),
      width: 320,
    );

    expect(find.byTooltip('已收藏'), findsOneWidget);
    expect(find.byIcon(Icons.download_done), findsOneWidget);
    expect(find.text('有外挂字幕'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
