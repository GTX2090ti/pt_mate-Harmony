import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../services/downloader/downloader_models.dart';

/// 下载器相关的工具类
class DownloaderUtils {
  DownloaderUtils._();

  /// 获取下载器图标
  static Widget getDownloaderIcon(DownloaderType type, {double? size}) {
    final iconSize = size ?? 24.0;

    if (type == DownloaderType.qbittorrent) {
      return SvgPicture.asset(
        'assets/logo/qBittorrent.svg',
        width: iconSize,
        height: iconSize,
      );
    } else if (type == DownloaderType.transmission) {
      return SvgPicture.asset(
        'assets/logo/Transmission.svg',
        width: iconSize,
        height: iconSize,
      );
    } else if (type == DownloaderType.rutorrent) {
      return Image.asset(
        'assets/logo/ruTorrent.png',
        width: iconSize,
        height: iconSize,
      );
    }

    // 没有随包图标的类型（如 Deluge）用通用图标，避免整页因为一个图标崩掉
    return Icon(Icons.dns_outlined, size: iconSize);
  }

  /// 根据下载器类型获取图标
  static Widget getDownloaderIconByType(DownloaderType type, {double? size}) {
    return getDownloaderIcon(type, size: size);
  }

  /// 获取下载器的默认端口
  static int getDefaultPort(DownloaderType type) {
    if (type == DownloaderType.qbittorrent) {
      return 8080;
    } else if (type == DownloaderType.transmission) {
      return 9091;
    } else if (type == DownloaderType.rutorrent) {
      return 80;
    } else if (type == DownloaderType.deluge) {
      return 8112;
    }

    // 如果将来添加新的下载器类型，这里会处理
    throw UnimplementedError('未实现的下载器类型: ${type.name}');
  }

  /// 检查下载器类型是否需要强制启用本地中转
  static bool requiresLocalRelay(DownloaderType type) {
    switch (type) {
      case DownloaderType.transmission:
        return true;
      case DownloaderType.qbittorrent:
        return false;
      case DownloaderType.rutorrent:
        return true;
      case DownloaderType.deluge:
        // core.add_torrent_url 可用时能直接下发链接；不可用时用户可自行开启中转
        return false;
    }
  }

  /// 获取下载器类型的本地中转说明文字
  static String getLocalRelayDescription(DownloaderType type) {
    if (requiresLocalRelay(type)) {
      return '${type.displayName} 必须启用本地中转（种子文件需要先下载到本地）';
    }
    if (type == DownloaderType.deluge) {
      return 'Deluge 能直接接收种子链接，但下发时不会带上站点 Cookie；PT 站点建议启用本地中转';
    }
    return '启用后，种子文件会先下载到本地，然后再发送给下载器';
  }

  /// 格式化下载器连接信息显示
  static String formatConnectionInfo(String host, int port, String username) {
    return '$host:$port  ·  $username';
  }
}
