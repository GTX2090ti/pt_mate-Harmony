import 'package:flutter/material.dart';

import 'pref_schema.dart';

/// Deluge `core.get_config` 字段表。
///
/// 键名与取值形态取自 Deluge 2.2.0 实机转储，实机没返回的键不显示也不写入。
/// 与 qBittorrent 有两处实质差别，直接影响这里不能照抄字段表：
/// 1. `max_download_speed` / `max_upload_speed` 的单位本来就是 KiB/s（qB 存字节/秒），
///    所以限速项一律不置 `isBytes`，否则页面上会再乘一次 1024。
/// 2. 监听/出站端口是 `[起, 止]` 数组、代理是嵌套字典，编辑语义与单值不同，
///    这里不提供，避免把列表当文本写回。
const List<PrefGroup> delugePrefGroups = [
  PrefGroup(
    id: 'download',
    title: '下载',
    summary: '默认下载目录、种子文件与完成后移动',
    icon: Icons.download_outlined,
    fields: [
      PrefField(
        keys: ['download_location'],
        label: '默认下载位置',
        kind: PrefKind.text,
      ),
      PrefField(
        keys: ['torrentfiles_location'],
        label: '.torrent 存放位置',
        kind: PrefKind.text,
      ),
      PrefField(
        keys: ['copy_torrent_file'],
        label: '添加时复制 .torrent',
        kind: PrefKind.boolToggle,
      ),
      PrefField(
        keys: ['del_copy_torrent_file'],
        label: '下载完成后删除副本',
        kind: PrefKind.boolToggle,
        hint: '需同时开启「添加时复制 .torrent」',
      ),
      PrefField(
        keys: ['pre_allocate_storage'],
        label: '预分配磁盘空间',
        kind: PrefKind.boolToggle,
      ),
      PrefField(
        keys: ['add_paused'],
        label: '添加后暂停',
        kind: PrefKind.boolToggle,
      ),
      PrefField(
        keys: ['move_completed'],
        label: '完成后移动到目录',
        kind: PrefKind.boolToggle,
      ),
      PrefField(
        keys: ['move_completed_path'],
        label: '完成后的目标目录',
        kind: PrefKind.text,
        hint: 'Deluge 是下载完成后移动，不是直接落盘',
      ),
    ],
  ),
  PrefGroup(
    id: 'queue',
    title: '队列与做种',
    summary: '活跃上限、排队顺序与停种条件',
    icon: Icons.playlist_play,
    fields: [
      PrefField(
        keys: ['max_active_downloading'],
        label: '最大活跃下载',
        kind: PrefKind.number,
      ),
      PrefField(
        keys: ['max_active_seeding'],
        label: '最大活跃做种',
        kind: PrefKind.number,
      ),
      PrefField(
        keys: ['max_active_limit'],
        label: '最大活跃种子总数',
        kind: PrefKind.number,
      ),
      PrefField(
        keys: ['queue_new_to_top'],
        label: '新任务排到队首',
        kind: PrefKind.boolToggle,
      ),
      PrefField(
        keys: ['dont_count_slow_torrents'],
        label: '慢速种子不计入上限',
        kind: PrefKind.boolToggle,
      ),
      PrefField(
        keys: ['auto_managed'],
        label: '新任务自动管理',
        kind: PrefKind.boolToggle,
      ),
      PrefField(
        keys: ['prioritize_first_last_pieces'],
        label: '首尾分块优先',
        kind: PrefKind.boolToggle,
      ),
      PrefField(
        keys: ['sequential_download'],
        label: '顺序下载',
        kind: PrefKind.boolToggle,
      ),
      PrefField(
        keys: ['super_seeding'],
        label: '超级做种',
        kind: PrefKind.boolToggle,
      ),
      PrefField(
        keys: ['shared'],
        label: '默认标记为共享种子',
        kind: PrefKind.boolToggle,
      ),
      PrefField(
        keys: ['auto_manage_prefer_seeds'],
        label: '共享种子优先管理',
        kind: PrefKind.boolToggle,
      ),
      PrefField(
        keys: ['stop_seed_at_ratio'],
        label: '达到分享率后停止做种',
        kind: PrefKind.boolToggle,
      ),
      PrefField(
        keys: ['remove_seed_at_ratio'],
        label: '达到分享率后移除种子',
        kind: PrefKind.boolToggle,
      ),
      PrefField(
        keys: ['stop_seed_ratio'],
        label: '停种分享率',
        kind: PrefKind.number,
        hint: '仅在「达到分享率后停止做种」开启时生效',
      ),
      PrefField(
        keys: ['share_ratio_limit'],
        label: '分享率上限',
        kind: PrefKind.number,
        hint: '0 表示不限',
      ),
      PrefField(
        keys: ['seed_time_ratio_limit'],
        label: '做种时间比上限',
        kind: PrefKind.number,
        hint: '做种时长 ÷ 下载时长，0 表示不限',
      ),
      PrefField(
        keys: ['seed_time_limit'],
        label: '做种时长上限',
        kind: PrefKind.number,
        hint: '0 表示不限',
      ),
    ],
  ),
  PrefGroup(
    id: 'speed',
    title: '速度',
    summary: '全局限速、连接上限与磁盘缓存',
    icon: Icons.speed_outlined,
    fields: [
      PrefField(
        keys: ['max_download_speed'],
        label: '下载限速',
        kind: PrefKind.number,
        hint: 'KiB/s，-1 表示不限速',
      ),
      PrefField(
        keys: ['max_upload_speed'],
        label: '上传限速',
        kind: PrefKind.number,
        hint: 'KiB/s，-1 表示不限速',
      ),
      PrefField(
        keys: ['rate_limit_ip_overhead'],
        label: '限速计入协议开销',
        kind: PrefKind.boolToggle,
      ),
      PrefField(
        keys: ['max_upload_slots_global'],
        label: '全局上传槽位',
        kind: PrefKind.number,
        hint: '-1 表示不限',
      ),
      PrefField(
        keys: ['max_connections_global'],
        label: '全局最大连接数',
        kind: PrefKind.number,
        hint: '-1 表示不限',
      ),
      PrefField(
        keys: ['max_half_open_connections'],
        label: '半开连接上限',
        kind: PrefKind.number,
      ),
      PrefField(
        keys: ['max_connections_per_second'],
        label: '每秒新建连接上限',
        kind: PrefKind.number,
      ),
      PrefField(
        keys: ['ignore_limits_on_local_network'],
        label: '局域网不计入连接上限',
        kind: PrefKind.boolToggle,
      ),
      PrefField(
        keys: ['max_download_speed_per_torrent'],
        label: '单种子下载限速',
        kind: PrefKind.number,
        hint: 'KiB/s，-1 表示沿用全局',
      ),
      PrefField(
        keys: ['max_upload_speed_per_torrent'],
        label: '单种子上传限速',
        kind: PrefKind.number,
        hint: 'KiB/s，-1 表示沿用全局',
      ),
      PrefField(
        keys: ['max_connections_per_torrent'],
        label: '单种子最大连接数',
        kind: PrefKind.number,
        hint: '-1 表示沿用全局',
      ),
      PrefField(
        keys: ['max_upload_slots_per_torrent'],
        label: '单种子上传槽位',
        kind: PrefKind.number,
        hint: '-1 表示沿用全局',
      ),
      PrefField(
        keys: ['cache_size'],
        label: 'libtorrent 缓存',
        kind: PrefKind.number,
      ),
      PrefField(
        keys: ['cache_expiry'],
        label: '缓存过期时间',
        kind: PrefKind.number,
        hint: '秒',
      ),
    ],
  ),
  PrefGroup(
    id: 'connection',
    title: '连接',
    summary: '端口、网卡绑定与协议开关',
    icon: Icons.settings_ethernet_outlined,
    fields: [
      PrefField(
        keys: ['random_port'],
        label: '随机监听端口',
        kind: PrefKind.boolToggle,
      ),
      PrefField(
        keys: ['listen_reuse_port'],
        label: '允许端口复用',
        kind: PrefKind.boolToggle,
      ),
      PrefField(
        keys: ['random_outgoing_ports'],
        label: '随机出站端口',
        kind: PrefKind.boolToggle,
      ),
      PrefField(
        keys: ['listen_interface'],
        label: '监听网卡',
        kind: PrefKind.text,
        hint: '留空为自动',
      ),
      PrefField(
        keys: ['outgoing_interface'],
        label: '出站网卡',
        kind: PrefKind.text,
        hint: '留空为自动',
      ),
      PrefField(keys: ['dht'], label: '启用 DHT', kind: PrefKind.boolToggle),
      PrefField(keys: ['utpex'], label: '启用 PeX', kind: PrefKind.boolToggle),
      PrefField(keys: ['lsd'], label: '启用本地节点发现', kind: PrefKind.boolToggle),
      PrefField(keys: ['upnp'], label: 'UPnP 端口映射', kind: PrefKind.boolToggle),
      PrefField(keys: ['natpmp'], label: 'NAT-PMP 端口映射', kind: PrefKind.boolToggle),
      PrefField(
        keys: ['peer_tos'],
        label: '连接服务类型（TOS）',
        kind: PrefKind.text,
        hint: '如 0x00',
      ),
    ],
  ),
  PrefGroup(
    id: 'misc',
    title: '其它',
    summary: '路径补全、插件目录与更新检查',
    icon: Icons.tune,
    fields: [
      PrefField(
        keys: ['new_release_check'],
        label: '检查新版本',
        kind: PrefKind.boolToggle,
      ),
      PrefField(
        keys: ['send_info'],
        label: '上报使用信息',
        kind: PrefKind.boolToggle,
      ),
      PrefField(
        keys: ['plugins_location'],
        label: '插件目录',
        kind: PrefKind.text,
      ),
      PrefField(
        keys: ['geoip_db_location'],
        label: 'GeoIP 数据库路径',
        kind: PrefKind.text,
      ),
      PrefField(
        keys: ['path_chooser_auto_complete_enabled'],
        label: '路径输入自动补全',
        kind: PrefKind.boolToggle,
      ),
      PrefField(
        keys: ['path_chooser_show_hidden_files'],
        label: '路径选择显示隐藏文件',
        kind: PrefKind.boolToggle,
      ),
      PrefField(
        keys: ['path_chooser_max_popup_rows'],
        label: '路径补全下拉行数',
        kind: PrefKind.number,
      ),
    ],
  ),
];
