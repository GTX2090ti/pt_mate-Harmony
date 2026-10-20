import 'package:flutter/material.dart';

/// 下载器自身偏好的字段描述（qBittorrent 与 Deluge 共用）。
///
/// 各下载器的偏好键名并不完全一致，同义项也可能换名（例如 qB 的 `port` /
/// `listen_port`），因此每个字段用 `keys` 声明候选键，渲染时只取实际存在于
/// 响应中的第一个，版本里不存在的设置既不会显示也不会被写入。
enum PrefKind { boolToggle, number, text, numberEnum, stringEnum, stringList }

class PrefOption {
  const PrefOption(this.value, this.label);
  final String value;
  final String label;
}

class PrefField {
  const PrefField({
    required this.keys,
    required this.label,
    required this.kind,
    this.hint,
    this.options,
    this.isBytes = false,
  });

  final List<String> keys;
  final String label;
  final PrefKind kind;
  final String? hint;

  /// numberEnum 的候选值为字符串形式的整数，提交时按原值类型回写
  final List<PrefOption>? options;

  /// 数值是否按字节/秒存储（qB 的限速项）；Deluge 的限速本身就是 KiB/s，不置位
  final bool isBytes;
}

class PrefGroup {
  const PrefGroup({
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
  final List<PrefField> fields;

  /// 非偏好类分组（RSS、分类与标签）由页面自己渲染入口
  final String? routeHint;
  final String? summary;
}

/// 偏好键 + 当前值
class ResolvedPrefField {
  const ResolvedPrefField(this.field, this.key, this.value);
  final PrefField field;
  final String key;
  final dynamic value;
}

/// 取该分组在实机偏好里真实存在的字段
List<ResolvedPrefField> resolveGroupFields(
  PrefGroup group,
  Map<String, dynamic> prefs,
) {
  final result = <ResolvedPrefField>[];
  for (final field in group.fields) {
    for (final key in field.keys) {
      if (prefs.containsKey(key)) {
        result.add(ResolvedPrefField(field, key, prefs[key]));
        break;
      }
    }
  }
  return result;
}

/// 偏好值 → 输入框初始文本
String prefValueToText(ResolvedPrefField resolved) {
  final field = resolved.field;
  final v = resolved.value;
  if (field.kind == PrefKind.stringList) {
    if (v is List) return v.map((e) => '$e').join('\n');
    return '$v';
  }
  if (v == null) return '';
  // 字节/秒的限速项按 KiB/s 编辑，与 qBittorrent 客户端一致
  if (field.kind == PrefKind.number && field.isBytes && v is num) {
    return v < 0 ? '-1' : (v / 1024).round().toString();
  }
  return '$v';
}

/// 输入文本 → 偏好值（保持原值类型，int 不写成 double）
dynamic prefValueFromInput(ResolvedPrefField resolved, String input) {
  switch (resolved.field.kind) {
    case PrefKind.boolToggle:
      return input == 'true';
    case PrefKind.stringList:
      return input
          .split('\n')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
    case PrefKind.text:
    case PrefKind.stringEnum:
      return input;
    case PrefKind.number:
    case PrefKind.numberEnum:
      final origin = resolved.value;
      final trimmed = input.trim();
      if (trimmed.isEmpty) return origin;
      num? parsed = origin is double
          ? double.tryParse(trimmed)
          : int.tryParse(trimmed) ?? double.tryParse(trimmed);
      if (parsed == null) return origin;
      if (resolved.field.kind == PrefKind.number &&
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
String describePrefValue(PrefField field, dynamic value) {
  switch (field.kind) {
    case PrefKind.boolToggle:
      return value == true ? '已开启' : '已关闭';
    case PrefKind.number:
      if (field.isBytes && value is num) {
        return value < 0 ? '不限' : '${(value / 1024).round()} KiB/s';
      }
      return '$value';
    case PrefKind.numberEnum:
    case PrefKind.stringEnum:
      final raw = '$value';
      for (final o in field.options ?? const <PrefOption>[]) {
        if (o.value == raw) return o.label;
      }
      return raw;
    case PrefKind.text:
      return value == null || '$value'.isEmpty ? '未设置' : '$value';
    case PrefKind.stringList:
      return value is List ? '${value.length} 条' : '未设置';
  }
}
