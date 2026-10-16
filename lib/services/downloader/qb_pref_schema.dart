import 'package:flutter/material.dart';

/// qBittorrent `/app/preferences` 字段描述。
///
/// 不同 qB 版本的偏好键名并不完全一致（例如 `port` / `listen_port`），
/// 因此每个字段用 `keys` 声明候选键，渲染时只取实际存在于响应中的第一个，
/// 版本里不存在的设置既不会显示也不会被写入。
enum QbPrefKind { boolToggle, number, text, numberEnum, stringEnum, stringList }

class QbPrefOption {
  const QbPrefOption(this.value, this.label);
  final String value;
  final String label;
}

class QbPrefField {
  const QbPrefField({
    required this.keys,
    required this.label,
    required this.kind,
    this.hint,
    this.options,
    this.isBytes = false,
  });

  final List<String> keys;
  final String label;
  final QbPrefKind kind;
  final String? hint;

  /// numberEnum 的候选值为字符串形式的整数，提交时按原值类型回写
  final List<QbPrefOption>? options;

  /// 数值是否按字节/秒展示
  final bool isBytes;
}

class QbPrefGroup {
  const QbPrefGroup({
    required this.id,
    required this.title,
    required this.icon,
    this.fields = const [],
    this.routeHint,
    this.summary,
  });

  final String id;
  final String title;
  final IconData icon;
  final List<QbPrefField> fields;

  /// 非偏好类分组（RSS、分类与标签）由页面自己渲染入口
  final String? routeHint;
  final String? summary;
}

/// 偏好键 + 当前值
class ResolvedQbPrefField {
  const ResolvedQbPrefField(this.field, this.key, this.value);
  final QbPrefField field;
  final String key;
  final dynamic value;
}

const List<QbPrefGroup> qbPrefGroups = [
  QbPrefGroup(
    id: 'download',
    title: '下载',
    summary: '保存路径、TMM、导出与 announce 服务器',
    icon: Icons.download_outlined,
    fields: [
      QbPrefField(keys: ['save_path'], label: '默认保存路径', kind: QbPrefKind.text),
      QbPrefField(keys: ['temp_path'], label: '临时保存路径', kind: QbPrefKind.text),
      QbPrefField(
        keys: ['temp_path_enabled'],
        label: '使用临时保存路径',
        kind: QbPrefKind.boolToggle,
      ),
      QbPrefField(
        keys: ['export_dir'],
        label: '.torrent 导出目录',
        kind: QbPrefKind.text,
      ),
      QbPrefField(
        keys: ['export_dir_enabled', 'use_export_directory'],
        label: '启用导出',
        kind: QbPrefKind.boolToggle,
      ),
      QbPrefField(
        keys: ['incomplete_files_ext'],
        label: '未完成文件加 .!qB 后缀',
        kind: QbPrefKind.boolToggle,
      ),
      QbPrefField(
        keys: ['preallocate_all'],
        label: '预分配磁盘空间',
        kind: QbPrefKind.boolToggle,
      ),
      QbPrefField(
        keys: ['start_paused'],
        label: '添加后暂停下载',
        kind: QbPrefKind.boolToggle,
      ),
      QbPrefField(
        keys: ['auto_tmm_enabled'],
        label: '自动分类管理（TMM）',
        kind: QbPrefKind.boolToggle,
      ),
      QbPrefField(
        keys: ['torrent_changed_tmm_enabled'],
        label: '手动改路径时更新分类',
        kind: QbPrefKind.boolToggle,
      ),
      QbPrefField(
        keys: ['save_path_changed_tmm_enabled'],
        label: '改分类路径时移动种子',
        kind: QbPrefKind.boolToggle,
      ),
      QbPrefField(
        keys: ['category_changed_tmm_enabled'],
        label: '改分类时移动到新路径',
        kind: QbPrefKind.boolToggle,
      ),
      QbPrefField(
        keys: ['use_category'],
        label: '按分类建子目录',
        kind: QbPrefKind.boolToggle,
      ),
      QbPrefField(
        keys: ['use_subcategories'],
        label: '启用子分类',
        kind: QbPrefKind.boolToggle,
      ),
      QbPrefField(
        keys: ['add_trackers_enabled'],
        label: '强制附加 announce 服务器',
        kind: QbPrefKind.boolToggle,
      ),
      QbPrefField(
        keys: ['add_trackers'],
        label: 'announce 服务器列表',
        kind: QbPrefKind.stringList,
        hint: '每行一个 tracker URL',
      ),
    ],
  ),
  QbPrefGroup(
    id: 'connection',
    title: '连接',
    summary: '监听端口、代理与连接上限',
    icon: Icons.settings_ethernet_outlined,
    fields: [
      QbPrefField(
        keys: ['listen_port', 'port'],
        label: '监听端口',
        kind: QbPrefKind.number,
      ),
      QbPrefField(keys: ['upnp'], label: 'UPnP 端口映射', kind: QbPrefKind.boolToggle),
      QbPrefField(
        keys: ['proxy_type'],
        label: '代理类型',
        kind: QbPrefKind.numberEnum,
        options: [
          QbPrefOption('0', '不使用代理'),
          QbPrefOption('1', 'SOCKS4'),
          QbPrefOption('2', 'SOCKS5'),
          QbPrefOption('4', 'HTTP'),
          QbPrefOption('5', 'HTTP（不认证）'),
          QbPrefOption('6', 'SOCKS5（不认证）'),
          QbPrefOption('7', '内置'),
        ],
      ),
      QbPrefField(keys: ['proxy_ip'], label: '代理主机', kind: QbPrefKind.text),
      QbPrefField(keys: ['proxy_port'], label: '代理端口', kind: QbPrefKind.number),
      QbPrefField(
        keys: ['proxy_auth_enabled'],
        label: '代理需要认证',
        kind: QbPrefKind.boolToggle,
      ),
      QbPrefField(
        keys: ['proxy_peer_connections'],
        label: '节点连接走代理',
        kind: QbPrefKind.boolToggle,
      ),
      QbPrefField(
        keys: ['proxy_tracker_connections'],
        label: 'Tracker 走代理',
        kind: QbPrefKind.boolToggle,
      ),
      QbPrefField(keys: ['interface'], label: '网卡绑定', kind: QbPrefKind.text),
      QbPrefField(
        keys: ['interface_address'],
        label: '出站 IP 地址',
        kind: QbPrefKind.text,
      ),
      QbPrefField(
        keys: ['max_connec'],
        label: '全局最大连接数',
        kind: QbPrefKind.number,
        hint: '-1 表示不限',
      ),
      QbPrefField(
        keys: ['max_connec_per_torrent'],
        label: '单种子最大连接数',
        kind: QbPrefKind.number,
        hint: '-1 表示不限',
      ),
      QbPrefField(
        keys: ['max_uploads'],
        label: '全局最大上传数',
        kind: QbPrefKind.number,
        hint: '-1 表示不限',
      ),
      QbPrefField(
        keys: ['max_uploads_per_torrent'],
        label: '单种子最大上传数',
        kind: QbPrefKind.number,
        hint: '-1 表示不限',
      ),
    ],
  ),
  QbPrefGroup(
    id: 'speed',
    title: '速度',
    summary: '限速、定时与磁盘缓存',
    icon: Icons.speed_outlined,
    fields: [
      QbPrefField(
        keys: ['dl_limit'],
        label: '下载限速',
        kind: QbPrefKind.number,
        isBytes: true,
        hint: 'KiB/s，-1 表示不限速',
      ),
      QbPrefField(
        keys: ['up_limit'],
        label: '上传限速',
        kind: QbPrefKind.number,
        isBytes: true,
        hint: 'KiB/s，-1 表示不限速',
      ),
      QbPrefField(
        keys: ['alt_dl_limit'],
        label: '备用下载限速',
        kind: QbPrefKind.number,
        isBytes: true,
        hint: 'KiB/s',
      ),
      QbPrefField(
        keys: ['alt_up_limit'],
        label: '备用上传限速',
        kind: QbPrefKind.number,
        isBytes: true,
        hint: 'KiB/s',
      ),
      QbPrefField(
        keys: ['limit_utp_rate'],
        label: '限速作用于 µTP',
        kind: QbPrefKind.boolToggle,
      ),
      QbPrefField(
        keys: ['limit_tcp_overhead'],
        label: '限速计入协议开销',
        kind: QbPrefKind.boolToggle,
      ),
      QbPrefField(
        keys: ['limit_lan_peers'],
        label: '限速作用于局域网节点',
        kind: QbPrefKind.boolToggle,
      ),
      QbPrefField(
        keys: ['scheduler_enabled'],
        label: '启用定时限速',
        kind: QbPrefKind.boolToggle,
      ),
      QbPrefField(
        keys: ['scheduler_start_time'],
        label: '定时限速开始',
        kind: QbPrefKind.text,
        hint: '如 08:00',
      ),
      QbPrefField(
        keys: ['scheduler_end_time'],
        label: '定时限速结束',
        kind: QbPrefKind.text,
        hint: '如 23:00',
      ),
      QbPrefField(
        keys: ['speed_limit_mode'],
        label: '当前限速模式',
        kind: QbPrefKind.numberEnum,
        options: [
          QbPrefOption('0', '全局'),
          QbPrefOption('1', '备用'),
          QbPrefOption('2', '调度'),
        ],
      ),
      QbPrefField(keys: ['disk_cache'], label: '磁盘缓存', kind: QbPrefKind.number, hint: '-1 为自动'),
      QbPrefField(keys: ['disk_cache_ttl'], label: '缓存 TTL（秒）', kind: QbPrefKind.number),
      QbPrefField(
        keys: ['checking_memory_use'],
        label: '校验内存上限',
        kind: QbPrefKind.number,
      ),
    ],
  ),
  QbPrefGroup(
    id: 'bittorrent',
    title: 'BitTorrent',
    summary: 'DHT/PeX、加密、队列与做种上限',
    icon: Icons.flip_to_back_outlined,
    fields: [
      QbPrefField(keys: ['dht'], label: '启用 DHT', kind: QbPrefKind.boolToggle),
      QbPrefField(keys: ['pex'], label: '启用 PeX', kind: QbPrefKind.boolToggle),
      QbPrefField(keys: ['lsd'], label: '启用本地节点发现', kind: QbPrefKind.boolToggle),
      QbPrefField(
        keys: ['encryption'],
        label: '加密',
        kind: QbPrefKind.stringEnum,
        options: [
          QbPrefOption('enabled', '强制'),
          QbPrefOption('preferEncryption', '优先加密'),
          QbPrefOption('allowPE', '允许'),
        ],
      ),
      QbPrefField(keys: ['anon_mode'], label: '匿名模式', kind: QbPrefKind.boolToggle),
      QbPrefField(keys: ['super_seeding'], label: '超级做种', kind: QbPrefKind.boolToggle),
      QbPrefField(
        keys: ['announce_to_all_tiers'],
        label: '向所有层级 announce',
        kind: QbPrefKind.boolToggle,
      ),
      QbPrefField(
        keys: ['announce_to_all_trackers'],
        label: '向所有 tracker announce',
        kind: QbPrefKind.boolToggle,
      ),
      QbPrefField(keys: ['queueing'], label: '启用下载队列', kind: QbPrefKind.boolToggle),
      QbPrefField(
        keys: ['max_active_downloads'],
        label: '最大活跃下载',
        kind: QbPrefKind.number,
      ),
      QbPrefField(
        keys: ['max_active_uploads'],
        label: '最大活跃做种',
        kind: QbPrefKind.number,
      ),
      QbPrefField(
        keys: ['max_active_torrents'],
        label: '最大活跃种子',
        kind: QbPrefKind.number,
      ),
      QbPrefField(
        keys: ['max_ratio_enabled'],
        label: '分享率限制',
        kind: QbPrefKind.boolToggle,
      ),
      QbPrefField(keys: ['max_ratio'], label: '最大分享率', kind: QbPrefKind.number),
      QbPrefField(
        keys: ['max_ratio_act'],
        label: '达到分享率后',
        kind: QbPrefKind.numberEnum,
        options: [
          QbPrefOption('0', '暂停'),
          QbPrefOption('1', '移除'),
          QbPrefOption('2', '删除种子'),
          QbPrefOption('3', '释放空间'),
          QbPrefOption('4', '自定义动作'),
        ],
      ),
      QbPrefField(
        keys: ['max_seeding_time_enabled'],
        label: '做种时间限制',
        kind: QbPrefKind.boolToggle,
      ),
      QbPrefField(
        keys: ['max_seeding_time'],
        label: '最大做种时长（分钟）',
        kind: QbPrefKind.number,
      ),
      QbPrefField(
        keys: ['max_inactive_seeding_time_enabled'],
        label: '不活跃做种限制',
        kind: QbPrefKind.boolToggle,
      ),
      QbPrefField(
        keys: ['max_inactive_seeding_time'],
        label: '不活跃做种时长（分钟）',
        kind: QbPrefKind.number,
      ),
    ],
  ),
  QbPrefGroup(
    id: 'rss',
    title: 'RSS',
    icon: Icons.rss_feed,
    summary: '订阅源与自动下载规则',
    routeHint: 'rss',
  ),
  QbPrefGroup(
    id: 'categorytag',
    title: '分类与标签',
    summary: '分类保存路径与标签增删',
    icon: Icons.sell_outlined,
    routeHint: 'categorytag',
  ),
];

/// 取该分组在实机偏好里真实存在的字段
List<ResolvedQbPrefField> resolveGroupFields(
  QbPrefGroup group,
  Map<String, dynamic> prefs,
) {
  final result = <ResolvedQbPrefField>[];
  for (final field in group.fields) {
    for (final key in field.keys) {
      if (prefs.containsKey(key)) {
        result.add(ResolvedQbPrefField(field, key, prefs[key]));
        break;
      }
    }
  }
  return result;
}

/// 偏好值 → 输入框初始文本
String prefValueToText(ResolvedQbPrefField resolved) {
  final field = resolved.field;
  final v = resolved.value;
  if (field.kind == QbPrefKind.stringList) {
    if (v is List) return v.map((e) => '$e').join('\n');
    return '$v';
  }
  if (v == null) return '';
  // 字节/秒的限速项按 KiB/s 编辑，与 qBittorrent 客户端一致
  if (field.kind == QbPrefKind.number && field.isBytes && v is num) {
    return v < 0 ? '-1' : (v / 1024).round().toString();
  }
  return '$v';
}

/// 输入文本 → 偏好值（保持原值类型，int 不写成 double）
dynamic prefValueFromInput(ResolvedQbPrefField resolved, String input) {
  switch (resolved.field.kind) {
    case QbPrefKind.boolToggle:
      return input == 'true';
    case QbPrefKind.stringList:
      return input
          .split('\n')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
    case QbPrefKind.text:
    case QbPrefKind.stringEnum:
      return input;
    case QbPrefKind.number:
    case QbPrefKind.numberEnum:
      final origin = resolved.value;
      final trimmed = input.trim();
      if (trimmed.isEmpty) return origin;
      num? parsed = origin is double
          ? double.tryParse(trimmed)
          : int.tryParse(trimmed) ?? double.tryParse(trimmed);
      if (parsed == null) return origin;
      if (resolved.field.kind == QbPrefKind.number &&
          resolved.field.isBytes &&
          parsed >= 0) {
        parsed = parsed * 1024;
      }
      if (origin is int && parsed is double && parsed % 1 == 0) {
        return parsed.toInt();
      }
      return parsed;
  }
}

/// 展示用的当前值（用于分组副标题）
String describePrefValue(QbPrefField field, dynamic value) {
  switch (field.kind) {
    case QbPrefKind.boolToggle:
      return value == true ? '已开启' : '已关闭';
    case QbPrefKind.number:
      if (field.isBytes && value is num) {
        return value < 0 ? '不限' : '${(value / 1024).round()} KiB/s';
      }
      return '$value';
    case QbPrefKind.numberEnum:
    case QbPrefKind.stringEnum:
      final raw = '$value';
      for (final o in field.options ?? const <QbPrefOption>[]) {
        if (o.value == raw) return o.label;
      }
      return raw;
    case QbPrefKind.text:
      return value == null || '$value'.isEmpty ? '未设置' : '$value';
    case QbPrefKind.stringList:
      return value is List ? '${value.length} 条' : '未设置';
  }
}
