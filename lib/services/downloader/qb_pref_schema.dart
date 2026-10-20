import 'package:flutter/material.dart';

import 'pref_schema.dart';

/// qBittorrent `/app/preferences` 字段表。
///
/// 键名以实机响应为准，字段模型与解析规则见 [pref_schema]（Deluge 共用）。
const List<PrefGroup> qbPrefGroups = [
  PrefGroup(
    id: 'download',
    title: '下载',
    summary: '保存路径、TMM、导出与 announce 服务器',
    icon: Icons.download_outlined,
    fields: [
      PrefField(keys: ['save_path'], label: '默认保存路径', kind: PrefKind.text),
      PrefField(keys: ['temp_path'], label: '临时保存路径', kind: PrefKind.text),
      PrefField(
        keys: ['temp_path_enabled'],
        label: '使用临时保存路径',
        kind: PrefKind.boolToggle,
      ),
      PrefField(
        keys: ['export_dir'],
        label: '.torrent 导出目录',
        kind: PrefKind.text,
      ),
      PrefField(
        keys: ['export_dir_enabled', 'use_export_directory'],
        label: '启用导出',
        kind: PrefKind.boolToggle,
      ),
      PrefField(
        keys: ['incomplete_files_ext'],
        label: '未完成文件加 .!qB 后缀',
        kind: PrefKind.boolToggle,
      ),
      PrefField(
        keys: ['preallocate_all'],
        label: '预分配磁盘空间',
        kind: PrefKind.boolToggle,
      ),
      PrefField(
        keys: ['start_paused'],
        label: '添加后暂停下载',
        kind: PrefKind.boolToggle,
      ),
      PrefField(
        keys: ['auto_tmm_enabled'],
        label: '自动分类管理（TMM）',
        kind: PrefKind.boolToggle,
      ),
      PrefField(
        keys: ['torrent_changed_tmm_enabled'],
        label: '手动改路径时更新分类',
        kind: PrefKind.boolToggle,
      ),
      PrefField(
        keys: ['save_path_changed_tmm_enabled'],
        label: '改分类路径时移动种子',
        kind: PrefKind.boolToggle,
      ),
      PrefField(
        keys: ['category_changed_tmm_enabled'],
        label: '改分类时移动到新路径',
        kind: PrefKind.boolToggle,
      ),
      PrefField(
        keys: ['use_category'],
        label: '按分类建子目录',
        kind: PrefKind.boolToggle,
      ),
      PrefField(
        keys: ['use_subcategories'],
        label: '启用子分类',
        kind: PrefKind.boolToggle,
      ),
      PrefField(
        keys: ['add_trackers_enabled'],
        label: '强制附加 announce 服务器',
        kind: PrefKind.boolToggle,
      ),
      PrefField(
        keys: ['add_trackers'],
        label: 'announce 服务器列表',
        kind: PrefKind.stringList,
        hint: '每行一个 tracker URL',
      ),
    ],
  ),
  PrefGroup(
    id: 'connection',
    title: '连接',
    summary: '监听端口、代理与连接上限',
    icon: Icons.settings_ethernet_outlined,
    fields: [
      PrefField(
        keys: ['listen_port', 'port'],
        label: '监听端口',
        kind: PrefKind.number,
      ),
      PrefField(keys: ['upnp'], label: 'UPnP 端口映射', kind: PrefKind.boolToggle),
      PrefField(
        keys: ['proxy_type'],
        label: '代理类型',
        kind: PrefKind.numberEnum,
        options: [
          PrefOption('0', '不使用代理'),
          PrefOption('1', 'SOCKS4'),
          PrefOption('2', 'SOCKS5'),
          PrefOption('4', 'HTTP'),
          PrefOption('5', 'HTTP（不认证）'),
          PrefOption('6', 'SOCKS5（不认证）'),
          PrefOption('7', '内置'),
        ],
      ),
      PrefField(keys: ['proxy_ip'], label: '代理主机', kind: PrefKind.text),
      PrefField(keys: ['proxy_port'], label: '代理端口', kind: PrefKind.number),
      PrefField(
        keys: ['proxy_auth_enabled'],
        label: '代理需要认证',
        kind: PrefKind.boolToggle,
      ),
      PrefField(
        keys: ['proxy_peer_connections'],
        label: '节点连接走代理',
        kind: PrefKind.boolToggle,
      ),
      PrefField(
        keys: ['proxy_tracker_connections'],
        label: 'Tracker 走代理',
        kind: PrefKind.boolToggle,
      ),
      PrefField(keys: ['interface'], label: '网卡绑定', kind: PrefKind.text),
      PrefField(
        keys: ['interface_address'],
        label: '出站 IP 地址',
        kind: PrefKind.text,
      ),
      PrefField(
        keys: ['max_connec'],
        label: '全局最大连接数',
        kind: PrefKind.number,
        hint: '-1 表示不限',
      ),
      PrefField(
        keys: ['max_connec_per_torrent'],
        label: '单种子最大连接数',
        kind: PrefKind.number,
        hint: '-1 表示不限',
      ),
      PrefField(
        keys: ['max_uploads'],
        label: '全局最大上传数',
        kind: PrefKind.number,
        hint: '-1 表示不限',
      ),
      PrefField(
        keys: ['max_uploads_per_torrent'],
        label: '单种子最大上传数',
        kind: PrefKind.number,
        hint: '-1 表示不限',
      ),
    ],
  ),
  PrefGroup(
    id: 'speed',
    title: '速度',
    summary: '限速、定时与磁盘缓存',
    icon: Icons.speed_outlined,
    fields: [
      PrefField(
        keys: ['dl_limit'],
        label: '下载限速',
        kind: PrefKind.number,
        isBytes: true,
        hint: 'KiB/s，-1 表示不限速',
      ),
      PrefField(
        keys: ['up_limit'],
        label: '上传限速',
        kind: PrefKind.number,
        isBytes: true,
        hint: 'KiB/s，-1 表示不限速',
      ),
      PrefField(
        keys: ['alt_dl_limit'],
        label: '备用下载限速',
        kind: PrefKind.number,
        isBytes: true,
        hint: 'KiB/s',
      ),
      PrefField(
        keys: ['alt_up_limit'],
        label: '备用上传限速',
        kind: PrefKind.number,
        isBytes: true,
        hint: 'KiB/s',
      ),
      PrefField(
        keys: ['limit_utp_rate'],
        label: '限速作用于 µTP',
        kind: PrefKind.boolToggle,
      ),
      PrefField(
        keys: ['limit_tcp_overhead'],
        label: '限速计入协议开销',
        kind: PrefKind.boolToggle,
      ),
      PrefField(
        keys: ['limit_lan_peers'],
        label: '限速作用于局域网节点',
        kind: PrefKind.boolToggle,
      ),
      PrefField(
        keys: ['scheduler_enabled'],
        label: '启用定时限速',
        kind: PrefKind.boolToggle,
      ),
      PrefField(
        keys: ['scheduler_start_time'],
        label: '定时限速开始',
        kind: PrefKind.text,
        hint: '如 08:00',
      ),
      PrefField(
        keys: ['scheduler_end_time'],
        label: '定时限速结束',
        kind: PrefKind.text,
        hint: '如 23:00',
      ),
      PrefField(
        keys: ['speed_limit_mode'],
        label: '当前限速模式',
        kind: PrefKind.numberEnum,
        options: [
          PrefOption('0', '全局'),
          PrefOption('1', '备用'),
          PrefOption('2', '调度'),
        ],
      ),
      PrefField(keys: ['disk_cache'], label: '磁盘缓存', kind: PrefKind.number, hint: '-1 为自动'),
      PrefField(keys: ['disk_cache_ttl'], label: '缓存 TTL（秒）', kind: PrefKind.number),
      PrefField(
        keys: ['checking_memory_use'],
        label: '校验内存上限',
        kind: PrefKind.number,
      ),
    ],
  ),
  PrefGroup(
    id: 'bittorrent',
    title: 'BitTorrent',
    summary: 'DHT/PeX、加密、队列与做种上限',
    icon: Icons.flip_to_back_outlined,
    fields: [
      PrefField(keys: ['dht'], label: '启用 DHT', kind: PrefKind.boolToggle),
      PrefField(keys: ['pex'], label: '启用 PeX', kind: PrefKind.boolToggle),
      PrefField(keys: ['lsd'], label: '启用本地节点发现', kind: PrefKind.boolToggle),
      PrefField(
        keys: ['encryption'],
        label: '加密',
        kind: PrefKind.stringEnum,
        options: [
          PrefOption('enabled', '强制'),
          PrefOption('preferEncryption', '优先加密'),
          PrefOption('allowPE', '允许'),
        ],
      ),
      PrefField(keys: ['anon_mode'], label: '匿名模式', kind: PrefKind.boolToggle),
      PrefField(keys: ['super_seeding'], label: '超级做种', kind: PrefKind.boolToggle),
      PrefField(
        keys: ['announce_to_all_tiers'],
        label: '向所有层级 announce',
        kind: PrefKind.boolToggle,
      ),
      PrefField(
        keys: ['announce_to_all_trackers'],
        label: '向所有 tracker announce',
        kind: PrefKind.boolToggle,
      ),
      PrefField(keys: ['queueing'], label: '启用下载队列', kind: PrefKind.boolToggle),
      PrefField(
        keys: ['max_active_downloads'],
        label: '最大活跃下载',
        kind: PrefKind.number,
      ),
      PrefField(
        keys: ['max_active_uploads'],
        label: '最大活跃做种',
        kind: PrefKind.number,
      ),
      PrefField(
        keys: ['max_active_torrents'],
        label: '最大活跃种子',
        kind: PrefKind.number,
      ),
      PrefField(
        keys: ['max_ratio_enabled'],
        label: '分享率限制',
        kind: PrefKind.boolToggle,
      ),
      PrefField(keys: ['max_ratio'], label: '最大分享率', kind: PrefKind.number),
      PrefField(
        keys: ['max_ratio_act'],
        label: '达到分享率后',
        kind: PrefKind.numberEnum,
        options: [
          PrefOption('0', '暂停'),
          PrefOption('1', '移除'),
          PrefOption('2', '删除种子'),
          PrefOption('3', '释放空间'),
          PrefOption('4', '自定义动作'),
        ],
      ),
      PrefField(
        keys: ['max_seeding_time_enabled'],
        label: '做种时间限制',
        kind: PrefKind.boolToggle,
      ),
      PrefField(
        keys: ['max_seeding_time'],
        label: '最大做种时长（分钟）',
        kind: PrefKind.number,
      ),
      PrefField(
        keys: ['max_inactive_seeding_time_enabled'],
        label: '不活跃做种限制',
        kind: PrefKind.boolToggle,
      ),
      PrefField(
        keys: ['max_inactive_seeding_time'],
        label: '不活跃做种时长（分钟）',
        kind: PrefKind.number,
      ),
    ],
  ),
  PrefGroup(
    id: 'rss',
    title: 'RSS',
    icon: Icons.rss_feed,
    summary: '订阅源与自动下载规则',
    routeHint: 'rss',
  ),
  PrefGroup(
    id: 'categorytag',
    title: '分类与标签',
    summary: '分类保存路径与标签增删',
    icon: Icons.sell_outlined,
    routeHint: 'categorytag',
  ),
];
