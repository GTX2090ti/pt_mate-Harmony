import 'package:flutter_test/flutter_test.dart';
import 'package:pt_mate/services/downloader/downloader_capabilities.dart';
import 'package:pt_mate/services/downloader/downloader_models.dart';

void main() {
  group('DownloaderCapabilities.forType', () {
    test('只有 qB 与 Deluge 有服务器设置与累计统计', () {
      for (final type in [DownloaderType.qbittorrent, DownloaderType.deluge]) {
        final caps = DownloaderCapabilities.forType(type);
        expect(caps.has(DownloaderFeature.serverPreferences), isTrue, reason: type.name);
        expect(caps.has(DownloaderFeature.cumulativeStats), isTrue, reason: type.name);
      }
      for (final type in [DownloaderType.transmission, DownloaderType.rutorrent]) {
        expect(
          DownloaderCapabilities.forType(type),
          same(DownloaderCapabilities.none),
          reason: '${type.name} 只实现基础契约，设置页要整块隐藏',
        );
      }
    });

    test('类型映射与客户端声明的能力集合同源', () {
      expect(
        DownloaderCapabilities.forType(DownloaderType.qbittorrent),
        same(DownloaderCapabilities.qbittorrent),
      );
      expect(
        DownloaderCapabilities.forType(DownloaderType.deluge),
        same(DownloaderCapabilities.deluge),
      );
    });

    test('Deluge 相对 qB 缺标签、强制开始与备选速率', () {
      const missing = {
        DownloaderFeature.tags,
        DownloaderFeature.forceStart,
        DownloaderFeature.altSpeedLimits,
      };
      final qb = DownloaderCapabilities.qbittorrent.features;
      final deluge = DownloaderCapabilities.deluge.features;
      for (final feature in missing) {
        expect(qb, contains(feature));
        expect(deluge, isNot(contains(feature)));
      }
      // qB 独有的能力位之外，Deluge 不该有 qB 没有的
      expect(deluge.difference(qb), isEmpty);
    });
  });
}
