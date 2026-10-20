import 'package:flutter/material.dart';

import '../services/downloader/deluge_pref_schema.dart';
import '../services/downloader/downloader_config.dart';
import '../services/downloader/downloader_service.dart';
import 'pref_settings_page.dart';

/// Deluge 服务器设置
///
/// 键空间来自实机 `core.get_config`，写回走 `core.set_config`。
class DelugeServerSettingsPage extends StatelessWidget {
  const DelugeServerSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return PrefSettingsPage(
      typeLabel: 'Deluge',
      groups: delugePrefGroups,
      accepts: (config) => config is DelugeConfig,
      loadPreferences:
          (config, password) => DownloaderService.instance.getPreferences(
            config: config,
            password: password,
          ),
      savePreferences:
          (config, password, deltas) => DownloaderService.instance.setPreferences(
            config: config,
            password: password,
            deltas: deltas,
          ),
    );
  }
}
