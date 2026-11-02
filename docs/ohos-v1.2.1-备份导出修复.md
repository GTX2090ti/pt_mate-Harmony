# ohos-v1.2.1：鸿蒙导出备份失败修复

对应提交 `4db2f43`、标签 `ohos-v1.2.1`、应用版本 `2.29.3+201`。

## 现象

「备份与恢复」页点击**导出备份**直接失败：

```
BackupException: 导出备份失败: type 'List<Object?>' is not a subtype of type 'String?' in type cast
```

**导入备份正常。**

## 根因链

1. 导入备份时，WebDAV 配置历史 `webdav_config_history` 以 JSON **文本**（值可能是 `"[]"`）通过 `setString` 写入偏好。
2. 本仓库手写的鸿蒙 `shared_preferences` 实现 `ohos/entry/src/main/ets/plugins/SharedPreferencesOhos.ets`，其 `getAll` 对**每一个**返回值套用「内容形如 JSON 数组就还原成列表」的启发式。这条本来是字符串的配置因此被改写成原生 Array，经 StandardMethodCodec 回传成 Dart 的 `List<Object?>`。
   - 定位依据：`List<Object?>` 是平台通道解码产物的运行时类型指纹，`jsonDecode` 产出的是 `List<dynamic>`，所以嫌疑在插件侧而不是业务 JSON 解析。
3. `shared_preferences` 的 `getString()` 是裸强转（`_preferenceCache[key] as String?`），拿到 `List<Object?>` 立即抛类型转换异常。
4. 备份链路 `BackupService._createBackupInCurrentEpoch()` 组装备份内容时调用 `WebDAVService.loadConfigHistory()`，命中上述异常 → 导出在**打开保存文件对话框之前**中止。
5. 导入不受影响：该路径在选中文件之前完全不读这个键。

## 修复

### 权威层：ArkTS 插件不再按内容形态猜

`SharedPreferencesOhos.ets`

- 列表降级存储时写入 `\u0001` 标记前缀；`restoreStringList` **只对有标记的值**做还原，普通字符串（哪怕内容就是 `[]`）原样回传。加标记而不是直接存 JSON，是为了和业务自己 `setString` 的 JSON 集合区分——后者必须原样以字符串回传。
- `setStringList` 写完数组后**回读校验**它真的是数组：部分系统版本的 `putSync` 不抛异常却静默把数组降级成字符串，那种情况才走带标记的 JSON 文本降级路径；反向校验同时保证 `getStringList()` 不会拿到字符串而崩溃。
- 保留对**无标记历史数据**的兼容还原（非空且元素全为字符串才认定为降级列表），存量数据无需清理或重导。

### 兜底层：Dart 侧读 JSON 配置不强转

`lib/services/webdav_service.dart`

- 新增 `_readJsonPreference()`，走无强转的 `prefs.get()`，把 `String` 与 `List` 两种形态统一归一成 JSON 字符串；`loadConfig()` 与 `loadConfigHistory()` 改用它。即使平台侧将来再出现同类偏差，也只是形态归一，不抛异常。

## 影响面

- 改动集中在鸿蒙专属的手写插件与 WebDAV 配置读取，不影响其它平台的 `shared_preferences` 行为。
- 行为变化：以前「内容恰好是扁平字符串数组的 JSON 文本」会被转成列表（即本 bug），现在保持字符串；真正用 `setStringList` 写入的值仍按列表回传。

## 验证

- `dart analyze lib/services/webdav_service.dart` → No issues found!
- Dart 侧产物新鲜度：包内 `libapp.so` 的 head_sha 由 `ba44d53f5f10f08a` 变为 `c1fac81551ef1157`；`module.json` 为 `versionCode=201`、`versionName=2.29.3`。
- ArkTS 侧产物新鲜度（与 Dart 独立）：包内 `ets/modules.abc` 含本轮新增的方法名 `parseStringArray`，且 `modules.abc` 构建时间新于 `.ets` 源码修改时间。只校验 `libapp.so` 证明不了 ArkTS 改动进了包。
- 未签名产物：`PTMate-201-unsigned.hap`，35,251,038 字节，sha256 `e8ba1bd8faa01b89d2d82863a631f2bc384b453f75d91d3a258934aad4f96636`（需自行签名后安装）。
