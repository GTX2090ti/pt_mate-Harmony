import 'package:flutter_test/flutter_test.dart';
import 'package:pt_mate/services/downloader/deluge_pref_schema.dart';
import 'package:pt_mate/services/downloader/pref_schema.dart';

void main() {
  PrefGroup groupById(String id) =>
      delugePrefGroups.firstWhere((g) => g.id == id);

  final allKeys = [
    for (final group in delugePrefGroups)
      for (final field in group.fields) ...field.keys,
  ];

  /// Deluge 2.2.0 实机 `core.get_config` 回报的键（含本字段表未暴露的那些）。
  const liveKeys = <String>{
    'add_paused',
    'allow_remote',
    'anonymous_mode',
    'auto_manage_prefer_seeds',
    'auto_managed',
    'cache_expiry',
    'cache_size',
    'copy_torrent_file',
    'daemon_port',
    'del_copy_torrent_file',
    'dht',
    'dont_count_slow_torrents',
    'download_location',
    'download_location_paths_list',
    'enabled_plugins',
    'enc_in_policy',
    'enc_level',
    'enc_out_policy',
    'force_proxy',
    'geoip_db_location',
    'hostname',
    'ignore_limits_on_local_network',
    'info_sent',
    'listen_interface',
    'listen_ports',
    'listen_random_port',
    'listen_reuse_port',
    'listen_use_sys_port',
    'lsd',
    'max_active_downloading',
    'max_active_limit',
    'max_active_seeding',
    'max_connections_global',
    'max_connections_per_second',
    'max_connections_per_torrent',
    'max_download_speed',
    'max_download_speed_per_torrent',
    'max_half_open_connections',
    'max_upload_slots_global',
    'max_upload_slots_per_torrent',
    'max_upload_speed',
    'max_upload_speed_per_torrent',
    'move_completed',
    'move_completed_path',
    'move_completed_paths_list',
    'natpmp',
    'new_release_check',
    'outgoing_interface',
    'outgoing_ports',
    'password',
    'path_chooser_accelerator_string',
    'path_chooser_auto_complete_enabled',
    'path_chooser_max_popup_rows',
    'path_chooser_show_chooser_button_on_localhost',
    'path_chooser_show_hidden_files',
    'peer_tos',
    'plugins_location',
    'port',
    'pre_allocate_storage',
    'prioritize_first_last_pieces',
    'proxy',
    'proxy_hostnames',
    'proxy_peer_connections',
    'proxy_tracker_connections',
    'queue_new_to_top',
    'random_outgoing_ports',
    'random_port',
    'rate_limit_ip_overhead',
    'remove_seed_at_ratio',
    'seed_time_limit',
    'seed_time_ratio_limit',
    'send_info',
    'sequential_download',
    'share_ratio_limit',
    'shared',
    'stop_seed_at_ratio',
    'stop_seed_ratio',
    'super_seeding',
    'torrentfiles_location',
    'type',
    'upnp',
    'username',
    'utpex',
  };

  group('deluge_pref_schema', () {
    test('分组都要有字段、键不重复，且都在实机键空间内', () {
      expect(delugePrefGroups, isNotEmpty);
      expect(allKeys.toSet().length, allKeys.length, reason: '存在重复的偏好键');
      for (final group in delugePrefGroups) {
        expect(
          group.fields,
          isNotEmpty,
          reason: '${group.id} Deluge 侧没有非偏好分组',
        );
        expect(group.routeHint, isNull);
      }
      expect(
        allKeys.where((k) => !liveKeys.contains(k)),
        isEmpty,
        reason: '字段表引用了实机不存在的键',
      );
    });

    test('数组与嵌套字典键不暴露', () {
      // listen_ports / outgoing_ports 是 [起, 止] 区间，proxy 是嵌套字典，
      // *_paths_list 与 enabled_plugins 是列表：写成单值文本会破坏配置
      for (final key in [
        'listen_ports',
        'outgoing_ports',
        'proxy',
        'enabled_plugins',
        'download_location_paths_list',
        'move_completed_paths_list',
        'password',
        'username',
      ]) {
        expect(allKeys, isNot(contains(key)), reason: '$key 不该出现在字段表里');
      }
    });

    test('限速键按 KiB/s 原样读写，不做字节换算', () {
      final prefs = <String, dynamic>{
        'max_download_speed': -1,
        'max_upload_speed': 1024,
        'max_upload_slots_global': 8,
      };
      final speed = resolveGroupFields(groupById('speed'), prefs)
          .firstWhere((r) => r.key == 'max_upload_speed');

      expect(speed.field.isBytes, isFalse);
      expect(prefValueToText(speed), '1024');
      expect(prefValueFromInput(speed, '2048'), 2048);
      expect(prefValueFromInput(speed, '2048'), isA<int>(), reason: '不换算成字节');
      expect(describePrefValue(speed.field, speed.value), '1024');

      final unlimited = resolveGroupFields(groupById('speed'), prefs)
          .firstWhere((r) => r.key == 'max_download_speed');
      expect(prefValueToText(unlimited), '-1');
      expect(
        unlimited.field.hint,
        contains('不限速'),
        reason: '-1 的语义靠 hint 说明，不做通用转换（qB 的 -2 才是无限）',
      );

      final slots = resolveGroupFields(groupById('speed'), prefs)
          .firstWhere((r) => r.key == 'max_upload_slots_global');
      expect(prefValueFromInput(slots, '16'), 16);
    });

    test('只命中实机偏好里存在的键', () {
      final prefs = <String, dynamic>{
        'download_location': '/downloads',
        'max_active_seeding': 10,
        'dht': false,
        'key_from_other_version': 1,
      };
      expect(
        resolveGroupFields(groupById('download'), prefs).map((r) => r.key),
        ['download_location'],
      );
      expect(
        resolveGroupFields(groupById('queue'), prefs).map((r) => r.key),
        ['max_active_seeding'],
      );
      expect(
        resolveGroupFields(groupById('connection'), prefs).map((r) => r.key),
        ['dht'],
      );
      expect(resolveGroupFields(groupById('misc'), prefs), isEmpty);
    });

    test('布尔项回写为 bool，文本项保持字符串', () {
      final prefs = <String, dynamic>{
        'move_completed': true,
        'move_completed_path': '/done',
      };
      final toggle = resolveGroupFields(groupById('download'), prefs)
          .firstWhere((r) => r.key == 'move_completed');
      final path = resolveGroupFields(groupById('download'), prefs)
          .firstWhere((r) => r.key == 'move_completed_path');

      expect(prefValueFromInput(toggle, 'false'), isFalse);
      expect(describePrefValue(toggle.field, toggle.value), '已开启');
      expect(prefValueFromInput(path, '/srv/done'), '/srv/done');
      expect(
        path.field.hint,
        contains('移动'),
        reason: 'Deluge 的完成路径是下载后移动，文案要区别于 qB 的直接落盘',
      );
    });
  });
}
