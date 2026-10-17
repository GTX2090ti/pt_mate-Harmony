/*
 * [移植适配-OHOS] shared_preferences 鸿蒙实现
 *
 * 上游 shared_preferences 无 ohos 实现，Dart 侧 SharedPreferences.getInstance()
 * 同样会挂起。站点配置、显示设置、更新检查等都依赖它。
 *
 * 底层使用 @kit.ArkData 的 preferences（键值持久化），语义对齐
 * shared_preferences 2.x 的 channel 协议。
 *
 * channel: plugins.flutter.io/shared_preferences
 *
 * ArkTS 约束备忘：
 *  - 禁止用 obj[key] 做动态字段访问（arkts-no-props-by-index）
 *  - 禁止 any/unknown（arkts-no-any-unknown）
 *  故此处统一用 Map 承载中间数据，读写时显式取值。
 */

import common from '@ohos.app.ability.common';
import { preferences } from '@kit.ArkData';
import { MethodChannel, MethodCall, MethodResult, Any } from '@ohos/flutter_ohos';
import { FlutterPlugin, FlutterPluginBinding } from '@ohos/flutter_ohos';
import Log from '@ohos/flutter_ohos/src/main/ets/util/Log';

const TAG = 'SharedPreferencesOhos';
const CHANNEL_NAME = 'plugins.flutter.io/shared_preferences';
const PREFIX = 'flutter.';
const STORE_NAME = 'ptmate_prefs';
/**
 * 降级存储的字符串列表前缀。
 *
 * 见 setStringList：只有「原生数组写入被设备拒绝」时才会走 JSON 文本分支，
 * 加上这个前缀让 getAll 能无歧义地认出它是列表，不必再靠内容猜测。
 */
const LIST_TEXT_PREFIX = '\u0001';

export default class SharedPreferencesOhos implements FlutterPlugin {
  private channel: MethodChannel | null = null;
  private context: common.Context | null = null;
  private store: preferences.Preferences | null = null;

  getUniqueClassName(): string {
    return 'SharedPreferencesOhos';
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.context = binding.getApplicationContext();
    this.channel = new MethodChannel(binding.getBinaryMessenger(), CHANNEL_NAME);
    this.channel.setMethodCallHandler({
      onMethodCall: (call: MethodCall, result: MethodResult): void => {
        try {
          this.handle(call, result);
        } catch (e) {
          const msg = e instanceof Error ? (e.message ?? '') : String(e);
          Log.e(TAG, `${call.method} failed: ${msg}`);
          result.error('shared_preferences_error', msg, null);
        }
      },
    });
    Log.i(TAG, 'shared_preferences ohos implementation attached');
  }

  onDetachedFromEngine(binding: FlutterPluginBinding): void {
    if (this.channel != null) {
      this.channel.setMethodCallHandler(null);
      this.channel = null;
    }
    this.store = null;
    this.context = null;
  }

  private prefs(): preferences.Preferences {
    if (this.store != null) {
      return this.store;
    }
    const ctx = this.context;
    if (ctx == null) {
      throw new Error('application context unavailable');
    }
    const options: preferences.Options = { name: STORE_NAME };
    this.store = preferences.getPreferencesSync(ctx, options);
    return this.store;
  }

  private handle(call: MethodCall, result: MethodResult): void {
    const store = this.prefs();

    switch (call.method) {
      case 'getAll': {
        // 协议要求：返回去掉 flutter. 前缀后的键值对
        const out: Map<string, Object> = new Map<string, Object>();
        const all = store.getAllSync() as Record<string, Object>;
        for (const k of Object.keys(all)) {
          if (k.startsWith(PREFIX)) {
            // 列表值必须还原成真正的数组，否则 Dart 侧强转失败（见
            // restoreStringList 的说明）。
            out.set(
              k.substring(PREFIX.length),
              SharedPreferencesOhos.restoreStringList(all[k]),
            );
          }
        }
        result.success(this.mapToObject(out));
        break;
      }

      case 'setBool': {
        const v: Any = this.optArg(call, 'value');
        store.putSync(PREFIX + this.strArg(call, 'key'), v === true);
        store.flushSync();
        result.success(true);
        break;
      }

      case 'setString':
        store.putSync(PREFIX + this.strArg(call, 'key'), this.strArg(call, 'value'));
        store.flushSync();
        result.success(true);
        break;

      case 'setInt': {
        const v: Any = this.optArg(call, 'value');
        store.putSync(PREFIX + this.strArg(call, 'key'), Math.trunc(Number(v)));
        store.flushSync();
        result.success(true);
        break;
      }

      case 'setDouble': {
        const v: Any = this.optArg(call, 'value');
        store.putSync(PREFIX + this.strArg(call, 'key'), Number(v));
        store.flushSync();
        result.success(true);
        break;
      }

      case 'setStringList': {
        const arr: Array<string> = [];
        const rawList: Any = this.optArg(call, 'value');
        if (rawList instanceof Array) {
          const typed = rawList as Array<Object>;
          for (let i = 0; i < typed.length; i++) {
            arr.push(String(typed[i]));
          }
        }
        const listKey = PREFIX + this.strArg(call, 'key');
        let storedAsArray = false;
        try {
          // preferences 原生支持 Array<string>，以数组形态写入，getAll 才能
          // 原样返回数组（见 restoreStringList）。
          store.putSync(listKey, arr);
          // 必须回读确认它真的是数组：putSync 在部分版本上不抛异常却静默把
          // 数组降级成字符串，那样 getAll 回来的就是字符串，Dart 侧
          // getStringList() 会反向崩溃。
          storedAsArray = store.getSync(listKey, '') instanceof Array;
        } catch (e) {
          storedAsArray = false;
        }
        if (!storedAsArray) {
          // 设备不接受数组值，降级为带标记前缀的 JSON 文本；
          // 读取时由 restoreStringList 还原，对 Dart 侧表现一致。
          // 加前缀而不是直接存 JSON，是为了和「业务自己 setString 的 JSON 集合」
          // 区分开——后者必须原样以字符串回传，否则 Dart 的 getString 会强转崩溃。
          store.putSync(listKey, LIST_TEXT_PREFIX + JSON.stringify(arr));
        }
        store.flushSync();
        result.success(true);
        break;
      }

      case 'remove':
        store.deleteSync(PREFIX + this.strArg(call, 'key'));
        store.flushSync();
        result.success(true);
        break;

      case 'clear': {
        // 只清 flutter. 前缀的数据，避免误删宿主应用的偏好项
        const all = store.getAllSync() as Record<string, Object>;
        for (const k of Object.keys(all)) {
          if (k.startsWith(PREFIX)) {
            store.deleteSync(k);
          }
        }
        store.flushSync();
        result.success(true);
        break;
      }

      case 'commit':
        store.flushSync();
        result.success(true);
        break;

      default:
        Log.w(TAG, `unhandled method ${call.method}`);
        result.notImplemented();
        break;
    }
  }

  /**
   * [移植适配-OHOS] 还原被降级存储的「字符串列表」。
   *
   * shared_preferences 的 Dart 侧对 getAll() 的返回值直接做强转
   * （`_preferenceCache[key] as List<dynamic>`）。早期实现为规避 preferences
   * 对数组值的兼容问题，把列表 `JSON.stringify` 后以字符串写入，导致：
   *  - 所有 `getStringList()` 调用点抛
   *    `type 'String' is not a subtype of type 'List<dynamic>?' in type cast`
   *  - 备份导出在收集「默认下载标签 / 代理绕过规则」阶段直接中断
   *
   * 这里在读出时把 JSON 数组文本还原成真正的 Array<string>：
   *  - 已是数组：原样返回（新写入路径）
   *  - 带 LIST_TEXT_PREFIX 标记：按列表解析（允许空列表）
   *  - 无标记的历史数据：解析结果必须是**非空扁平字符串数组**才还原。
   *    对象数组（站点列表、WebDAV 配置历史）和 `"[]"` 都必须原样返回字符串，
   *    否则这些键在 Dart 侧 `getString()` 时会反向崩溃。
   */
  private static restoreStringList(value: Object): Object {
    if (value instanceof Array) {
      return value;
    }
    if (typeof value !== 'string') {
      return value;
    }
    const text: string = value as string;
    if (text.startsWith(LIST_TEXT_PREFIX)) {
      const body: string = text.substring(LIST_TEXT_PREFIX.length);
      return SharedPreferencesOhos.parseStringArray(body, true) ?? body;
    }
    // 兼容早期无标记的降级存储：只能按内容形态猜。
    const legacy: string = text.trim();
    if (legacy.length < 2 || !legacy.startsWith('[') || !legacy.endsWith(']')) {
      return value;
    }
    return SharedPreferencesOhos.parseStringArray(legacy, false) ?? value;
  }

  /**
   * 把 JSON 文本解析成扁平字符串数组；不符合返回 null（保留原值）。
   *
   * 【为什么空数组不能算列表】`jsonEncode([])` 落到 setString 也是 `"[]"`，
   * 与「空字符串列表」在文本上完全同形，内容无法区分。而 Dart 侧
   * `SharedPreferences.getString()` 是裸强转（`_preferenceCache[key] as String?`），
   * 一旦把这种值改写成数组，读它的键就会抛
   * 「type 'List<Object?>' is not a subtype of type 'String?'」——
   * 实机表现是「导出备份失败」，因为备份链路会用 getString 读
   * webdav_config_history / siteConfigs / downloaderConfigs 这些 JSON 集合。
   * 所以带 LIST_TEXT_PREFIX 的新格式允许空数组，无标记的旧格式只认非空数组。
   */
  private static parseStringArray(text: string, allowEmpty: boolean): Array<string> | null {
    try {
      const parsed: Object = JSON.parse(text) as Object;
      if (!(parsed instanceof Array)) {
        return null;
      }
      const items = parsed as Array<Object>;
      if (items.length === 0 && !allowEmpty) {
        return null;
      }
      const out: Array<string> = [];
      for (let i = 0; i < items.length; i++) {
        const item: Object = items[i];
        if (typeof item !== 'string') {
          return null;
        }
        out.push(item as string);
      }
      return out;
    } catch (e) {
      return null;
    }
  }

  private mapToObject(src: Map<string, Object>): Record<string, Object> {
    const out: Record<string, Object> = {};
    src.forEach((v: Object, k: string) => {
      out[k] = v;
    });
    return out;
  }

  /**
   * 【必须走 call.argument()】引擎 StandardMessageCodec 把 Dart 的 Map 解码为
   * ArkTS 原生 Map（readValueOfType 的 `new Map()` 分支），不是普通对象：
   *  - `Object.keys(map)` 恒为空数组
   *  - `map['key']` 索引访问恒为 undefined
   * 引擎的 argument() 内部已兼容 Map / Object 两种情况。
   */
  private strArg(call: MethodCall, name: string): string {
    const v: Any = call.argument(name);
    if (v === null || v === undefined) {
      throw new Error(`missing argument "${name}"`);
    }
    return String(v);
  }

  private optArg(call: MethodCall, name: string): Any {
    return call.argument(name);
  }
}
