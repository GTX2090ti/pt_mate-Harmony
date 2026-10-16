import 'package:flutter_test/flutter_test.dart';
import 'package:pt_mate/services/downloader/qb_pref_schema.dart';

void main() {
  QbPrefGroup groupById(String id) =>
      qbPrefGroups.firstWhere((g) => g.id == id);

  group('qb_pref_schema', () {
    test('每个分组都要么有字段要么有路由标记，且键不重复', () {
      final seen = <String>{};
      for (final group in qbPrefGroups) {
        expect(
          group.fields.isNotEmpty || group.routeHint != null,
          isTrue,
          reason: '${group.id} 既无字段也无路由',
        );
        for (final field in group.fields) {
          expect(field.keys, isNotEmpty);
          for (final key in field.keys) {
            expect(seen.add(key), isTrue, reason: '重复的偏好键：$key');
          }
        }
      }
    });

    test('只命中实机 preferences 里存在的键', () {
      final prefs = <String, dynamic>{
        'save_path': '/downloads',
        'port': 8999,
        'dl_limit': -1,
        'max_ratio': 2.5,
        'queueing': true,
        'add_trackers': ['http://t/announce'],
        'key_from_other_version': 1,
      };

      expect(
        resolveGroupFields(groupById('download'), prefs).map((r) => r.key),
        ['save_path', 'add_trackers'],
      );
      expect(
        resolveGroupFields(groupById('connection'), prefs).map((r) => r.key),
        ['port'],
        reason: 'listen_port 不存在时应回落到别名 port',
      );
      expect(
        resolveGroupFields(groupById('bittorrent'), prefs).map((r) => r.key),
        ['queueing', 'max_ratio'],
      );
      expect(
        resolveGroupFields(groupById('rss'), prefs),
        isEmpty,
        reason: 'RSS 分组不走 preferences',
      );
    });

    test('偏好值按原类型回写', () {
      final prefs = <String, dynamic>{
        'dl_limit': -1,
        'max_ratio': 2.5,
        'queueing': true,
        'encryption': 'enabled',
        'add_trackers': <String>[],
      };
      final dl = resolveGroupFields(groupById('speed'), prefs)
          .firstWhere((r) => r.key == 'dl_limit');
      final ratio = resolveGroupFields(groupById('bittorrent'), prefs)
          .firstWhere((r) => r.key == 'max_ratio');
      final enc = QbPrefField(
        keys: const ['encryption'],
        label: '加密',
        kind: QbPrefKind.stringEnum,
      );

      expect(prefValueFromInput(dl, '1024'), 1048576);
      expect(prefValueFromInput(dl, '1024'), isA<int>(), reason: '字节项按 KiB 输入后回写为字节');
      expect(prefValueFromInput(ratio, '3'), 3.0);
      expect(prefValueFromInput(dl, ''), -1, reason: '清空输入保持原值');
      expect(prefValueToText(dl), '-1', reason: '-1 保持不限速');
      expect(
        prefValueFromInput(
          ResolvedQbPrefField(enc, 'encryption', 'enabled'),
          'preferEncryption',
        ),
        'preferEncryption',
      );
      expect(
        prefValueFromInput(
          ResolvedQbPrefField(
            QbPrefField(
              keys: const ['add_trackers'],
              label: 'trackers',
              kind: QbPrefKind.stringList,
            ),
            'add_trackers',
            <String>[],
          ),
          'http://a\n\nhttp://b\n',
        ),
        ['http://a', 'http://b'],
      );
      expect(
        prefValueFromInput(
          ResolvedQbPrefField(
            QbPrefField(
              keys: const ['queueing'],
              label: 'queueing',
              kind: QbPrefKind.boolToggle,
            ),
            'queueing',
            true,
          ),
          'false',
        ),
        isFalse,
      );
    });

    test('限速值以字节/秒描述，-1 显示不限', () {
      final prefs = <String, dynamic>{'dl_limit': -1, 'up_limit': 1048576};
      final dl = resolveGroupFields(groupById('speed'), prefs)
          .firstWhere((r) => r.key == 'dl_limit');
      final up = resolveGroupFields(groupById('speed'), prefs)
          .firstWhere((r) => r.key == 'up_limit');

      expect(describePrefValue(dl.field, dl.value), '不限');
      expect(describePrefValue(up.field, up.value), '1024 KiB/s');
      expect(prefValueToText(up), '1024');
    });
  });
}
