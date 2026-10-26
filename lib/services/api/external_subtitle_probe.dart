import '../../models/app_models.dart';
import 'api_service.dart';

/// 外挂字幕探测会话缓存。
///
/// 列表页加载后按需读取详情页，字幕状态在本次运行期间缓存，
/// 避免翻页、排序或返回列表时重复请求。
class ExternalSubtitleProbe {
  ExternalSubtitleProbe._();

  static final ExternalSubtitleProbe instance = ExternalSubtitleProbe._();

  final Map<String, bool?> _cache = {};

  String _key(SiteConfig site, String torrentId) => '${site.id}:$torrentId';

  bool contains(SiteConfig site, String torrentId) {
    return _cache.containsKey(_key(site, torrentId));
  }

  bool? cached(SiteConfig site, String torrentId) {
    return _cache[_key(site, torrentId)];
  }

  Future<bool?> probe({
    required SiteConfig site,
    required String torrentId,
    String? detailUrl,
  }) async {
    final key = _key(site, torrentId);
    if (_cache.containsKey(key)) return _cache[key];

    final result = await ApiService.instance.fetchExternalSubtitleStatus(
      torrentId,
      siteConfig: site,
      detailUrl: detailUrl,
    );
    _cache[key] = result;
    return result;
  }

  void clearSite(String siteId) {
    _cache.removeWhere((key, _) => key.startsWith('$siteId:'));
  }
}
