/// 外挂字幕识别工具。
///
/// 站点详情页里的“字幕”区块由用户上传，常见形态包括：
/// - 字幕附件链接（`download.php?...`、`subtitles.php?action=download` 等）；
/// - 直接指向 `.srt/.ass/.ssa/.sup/.sub/.vtt` 文件的链接；
/// - 标题为“字幕”/“外挂字幕”的表格或折叠区块，并以“字幕(3)”形式显示数量。
///
/// 这里只做保守判断：没有找到任何字幕区块时返回 `null`（未知），
/// 避免把“没有字幕功能”误显示成“无外挂字幕”。
class ExternalSubtitleDetector {
  ExternalSubtitleDetector._();

  static final RegExp _anchorRegExp = RegExp(
    r'<a\b([^>]*)>([\s\S]{0,400}?)</a>',
    caseSensitive: false,
  );
  static final RegExp _hrefRegExp = RegExp(
    r'''href\s*=\s*["']([^"']+)["']''',
    caseSensitive: false,
  );
  static final RegExp _subtitleFileRegExp = RegExp(
    r'''\.(?:srt|ass|ssa|sup|sub|vtt)(?:$|[?#&"'\s>])''',
    caseSensitive: false,
  );
  static final RegExp _subtitleHrefRegExp = RegExp(
    r'subtitles?|subs(?:\.php|/)|zimu',
    caseSensitive: false,
  );
  static final RegExp _attachmentHintRegExp = RegExp(
    r'download|attach|file|getfile|dl',
    caseSensitive: false,
  );
  static final RegExp _explicitEmptyRegExp = RegExp(
    r'暂无(?:上传|人上传)?字幕|暫無(?:上傳|人上傳)?字幕|'
    r'(?:还|還)没有(?:人)?上传字幕|尚未(?:有人)?上传字幕|'
    r'字幕[^\d]{0,8}0\s*(?:条|個|个)|'
    r'字幕\s*[\(（\[【]\s*0\s*[\)）\]】]',
  );
  static final RegExp _subtitleCountRegExp = RegExp(
    r'字幕\s*[\(（\[【]\s*[1-9]\d*\s*[\)）\]】]|'
    r'字幕[：:]?\s*[1-9]\d*\s*(?:条|個|个)',
  );
  static final RegExp _subtitleSectionRegExp = RegExp(
    r'字幕下载|字幕下載|外挂字幕|外掛字幕|上传字幕|上傳字幕|字幕文件|字幕檔案|字幕列表',
  );
  static final RegExp _headingElementRegExp = RegExp(
    r'<\s*(?:h[1-6]|legend|th)[^>]*>([\s\S]{0,80}?)'
    r'<\s*/\s*(?:h[1-6]|legend|th)\s*>',
    caseSensitive: false,
  );
  static final RegExp _subtitleLabelAttrRegExp = RegExp(
    r'''(?:alt|title)\s*=\s*["'][^"']*'''
    r'''(?:有字幕|外挂字幕|外掛字幕|字幕下载|字幕下載|下载字幕|下載字幕|字幕文件)'''
    r'''[^"']*["']''',
    caseSensitive: false,
  );
  static final RegExp _subtitleIconClassRegExp = RegExp(
    r'''<(?:span|div|i|em|b|label)\b[^>]*(?:class|id)\s*=\s*["']'''
    r'''[^"']*(?:has-subtitle|subtitle-(?:icon|badge|tag|mark|label|flag)|'''
    r'''subs-(?:icon|badge|tag|mark)|subtitles?(?:-icon|-badge|-tag))'''
    r'''[^"']*["'][^>]*>(?:[\s\S]{0,80}?)</''',
    caseSensitive: false,
  );
  static final RegExp _subtitleTagTextRegExp = RegExp(
    r'''<(?:span|div|i|em|b|label)\b[^>]*(?:class|id)\s*=\s*["']'''
    r'''[^"']*(?:tag|label|badge|chip)'''
    r'''[^"']*["'][^>]*>\s*字幕\s*<''',
    caseSensitive: false,
  );
  /// NexusPHP 字幕插件把区块标题放在 `rowhead` 单元格里。
  static final RegExp _subtitleRowHeadRegExp = RegExp(
    r'''<td\b[^>]*\bclass\s*=\s*["'][^"']*\b(?:rowhead|colhead)\b[^"']*["']'''
    r'''[^>]*>\s*字幕\s*</td>''',
    caseSensitive: false,
  );
  /// 憨憨等站点用 `<div class="font-bold">字幕</div>` 作为区块标题。
  static final RegExp _subtitleBoldDivRegExp = RegExp(
    r'''<div\b[^>]*\bclass\s*=\s*["'][^"']*\bfont-bold\b[^"']*["']'''
    r'''[^>]*>\s*字幕\s*</div>''',
    caseSensitive: false,
  );
  /// 区块内容到下一个标题或表格结束为止。
  static final RegExp _subtitleSectionEndRegExp = RegExp(
    r'''\bclass\s*=\s*["'][^"']*\b(?:rowhead|colhead|font-bold)\b[^"']*["']'''
    r'''|</table>''',
    caseSensitive: false,
  );
  /// 上传/搜索按钮不是用户已上传的字幕。
  static final RegExp _uploadOnlyHintRegExp = RegExp(
    r'upload|search|submit|rules?|help|faq|上传|上傳|搜索|搜尋|规则|規則|说明|說明',
    caseSensitive: false,
  );

  /// 识别详情页 HTML 中的外挂字幕状态。
  ///
  /// 返回 `true` 表示存在用户上传的字幕，`false` 表示站点有字幕区块但
  /// 当前种子没有字幕，`null` 表示页面里没有可识别的字幕信息。
  static bool? detectHtml(String html) {
    if (html.trim().isEmpty) return null;

    // 详情页可能同时有“字幕语言”信息行和字幕插件行，逐个区块检查，
    // 任意一个区块里有附件即判定有外挂字幕。
    final sections = _subtitleSections(html);
    if (sections.isNotEmpty) {
      return sections.any(_sectionHasAttachment);
    }

    final plain = _plainText(html);
    if (_explicitEmptyRegExp.hasMatch(plain)) return false;
    if (_hasSubtitleAttachment(html)) return true;
    if (_subtitleCountRegExp.hasMatch(plain)) return true;
    if (_subtitleSectionRegExp.hasMatch(plain)) return false;
    if (_hasSubtitleHeading(html)) return false;
    return null;
  }

  /// 列表行里若已经带有字幕链接或图标，直接返回 `true`。
  /// 没有则返回 `null`，由详情页探测补全。
  static bool? detectRowMarker(String html) {
    if (html.trim().isEmpty) return null;
    if (_hasSubtitleAttachment(html)) return true;
    if (_subtitleLabelAttrRegExp.hasMatch(html)) return true;
    if (_subtitleIconClassRegExp.hasMatch(html)) return true;
    if (_subtitleTagTextRegExp.hasMatch(html)) return true;
    return null;
  }

  /// 找到所有“字幕”区块并截取区块内容。
  static List<String> _subtitleSections(String html) {
    final markers = <RegExpMatch>[
      ..._subtitleRowHeadRegExp.allMatches(html),
      ..._subtitleBoldDivRegExp.allMatches(html),
    ]..sort((a, b) => a.start.compareTo(b.start));

    final sections = <String>[];
    for (final marker in markers) {
      var rest = html.substring(marker.end);
      final end = _subtitleSectionEndRegExp.firstMatch(rest);
      if (end != null) {
        rest = rest.substring(0, end.start);
      }
      sections.add(rest.length > 8000 ? rest.substring(0, 8000) : rest);
    }
    return sections;
  }

  /// 字幕区块内出现可下载的附件链接才算“有外挂字幕”。
  /// 只有上传/搜索按钮或空区块时返回 `false`。
  static bool _sectionHasAttachment(String section) {
    if (_hasSubtitleAttachment(section)) return true;
    if (_subtitleCountRegExp.hasMatch(_plainText(section))) return true;

    for (final match in _anchorRegExp.allMatches(section)) {
      final attrs = match.group(1) ?? '';
      final text = _plainText(match.group(2) ?? '');
      final href = _hrefRegExp.firstMatch(attrs)?.group(1) ?? '';
      final lowerHref = href.toLowerCase();
      if (lowerHref.isEmpty || lowerHref.startsWith('javascript')) continue;

      // 区块里的“上传字幕/搜索字幕/查看规则”等入口不是已上传字幕。
      if (_uploadOnlyHintRegExp.hasMatch(lowerHref) ||
          _uploadOnlyHintRegExp.hasMatch(text) ||
          _uploadOnlyHintRegExp.hasMatch(attrs)) {
        continue;
      }

      // 既不指向字幕接口也没有下载/附件特征时，可能只是上传者资料等无关链接。
      if (!_subtitleHrefRegExp.hasMatch(lowerHref) &&
          !_attachmentHintRegExp.hasMatch(lowerHref) &&
          !_subtitleFileRegExp.hasMatch(text)) {
        continue;
      }

      return true;
    }
    return false;
  }

  static bool _hasSubtitleAttachment(String html) {
    for (final match in _anchorRegExp.allMatches(html)) {
      final attrs = match.group(1) ?? '';
      final text = _plainText(match.group(2) ?? '');
      final href = _hrefRegExp.firstMatch(attrs)?.group(1) ?? '';
      final lowerHref = href.toLowerCase();

      // 直接指向字幕文件，或链接文字就是字幕文件名。
      if (_subtitleFileRegExp.hasMatch(lowerHref) ||
          _subtitleFileRegExp.hasMatch(text)) {
        return true;
      }

      // 字幕专用下载接口，例如 subtitles.php?action=download&id=...
      if (_subtitleHrefRegExp.hasMatch(lowerHref) &&
          _attachmentHintRegExp.hasMatch(lowerHref) &&
          !lowerHref.startsWith('javascript')) {
        return true;
      }

      // 图标链接或按钮只写“下载字幕”的情况。
      if ((text.contains('下载字幕') ||
              text.contains('下載字幕') ||
              text.contains('字幕下载') ||
              text.contains('字幕下載') ||
              attrs.contains('下载字幕') ||
              attrs.contains('下載字幕')) &&
          href.isNotEmpty &&
          !lowerHref.startsWith('javascript')) {
        return true;
      }
    }
    return false;
  }

  static bool _hasSubtitleHeading(String html) {
    for (final match in _headingElementRegExp.allMatches(html)) {
      final text = _plainText(match.group(1) ?? '').trim();
      if (text.isEmpty) continue;
      if (text == '字幕' ||
          text == '外挂字幕' ||
          text == '外掛字幕' ||
          text == '字幕下载' ||
          text == '字幕下載') {
        return true;
      }
    }
    return false;
  }

  static String _plainText(String html) {
    return html
        .replaceAll(RegExp(r'<[^>]+>'), ' ')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}
