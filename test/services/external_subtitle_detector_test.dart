import 'package:flutter_test/flutter_test.dart';
import 'package:pt_mate/services/api/external_subtitle_detector.dart';

void main() {
  group('ExternalSubtitleDetector.detectHtml', () {
    test('识别直接指向 srt 文件的下载链接', () {
      const html = '''
        <div id="kdescr">剧情简介</div>
        <table class="subtitle-table">
          <tr><td><a href="/download.php?id=12&amp;type=sub">Movie.chs.srt</a></td></tr>
        </table>
      ''';

      expect(ExternalSubtitleDetector.detectHtml(html), isTrue);
    });

    test('识别字幕专用下载接口', () {
      const html = '''
        <div class="subtitle-box">
          <a href="subtitles.php?action=download&amp;id=88">下载</a>
        </div>
      ''';

      expect(ExternalSubtitleDetector.detectHtml(html), isTrue);
    });

    test('识别字幕数量角标', () {
      const html = '''
        <div class="section-title">字幕(2)</div>
        <div class="empty">暂无内容</div>
      ''';

      expect(ExternalSubtitleDetector.detectHtml(html), isTrue);
    });

    test('字幕区块存在但没有任何附件时判定为无字幕', () {
      const html = '''
        <h2>字幕</h2>
        <div>目前还没有人上传字幕</div>
      ''';

      expect(ExternalSubtitleDetector.detectHtml(html), isFalse);
    });

    test('字幕标题下没有任何内容时判定为无字幕', () {
      const html = '<h2>字幕</h2><div>下一位上传者就是你</div>';

      expect(ExternalSubtitleDetector.detectHtml(html), isFalse);
    });

    test('字幕数量为 0 时判定为无字幕', () {
      const html = '<div class="section-title">字幕(0)</div>';

      expect(ExternalSubtitleDetector.detectHtml(html), isFalse);
    });

    test('按“字幕：2 条”格式显示数量时判定有字幕', () {
      const html = '<div>字幕：2 条</div>';

      expect(ExternalSubtitleDetector.detectHtml(html), isTrue);
    });

    test('明确提示暂无字幕时判定为无字幕', () {
      const html = '''
        <div class="torrent-subtitle-block">
          <span>暂无上传字幕</span>
        </div>
      ''';

      expect(ExternalSubtitleDetector.detectHtml(html), isFalse);
    });

    test('页面没有字幕区块时返回未知', () {
      const html = '''
        <div id="kdescr">这是一段普通简介，没有任何字幕相关区块。</div>
      ''';

      expect(ExternalSubtitleDetector.detectHtml(html), isNull);
    });

    test('简介里出现字幕文件名但没有链接时不误判为外挂字幕', () {
      const html = '''
        <div id="kdescr">
          本资源内封 Movie.chs.srt，播放器可自动加载。
        </div>
      ''';

      expect(ExternalSubtitleDetector.detectHtml(html), isNull);
    });

    test('普通导航字幕链接不误判为外挂字幕', () {
      const html = '''
        <div class="menu"><a href="subtitles.php">字幕</a></div>
      ''';

      expect(ExternalSubtitleDetector.detectHtml(html), isNull);
    });

    test('NexusPHP 字幕插件行内有附件时判定有字幕', () {
      const html = '''
        <table>
          <tr>
            <td class="rowhead" valign="top">字幕</td>
            <td class="rowfollow" valign="top">
              <table>
                <tr>
                  <td class="embedded"><img src="cn.png" title="简体中文"></td>
                  <td class="embedded">
                    <a href="downloadsubs.php?torrentid=621182&amp;subid=2148">
                      <u>[雪飘+白恋] Movie.chs.ass</u>
                    </a>
                  </td>
                </tr>
              </table>
            </td>
          </tr>
        </table>
      ''';

      expect(ExternalSubtitleDetector.detectHtml(html), isTrue);
    });

    test('NexusPHP 字幕插件行内只有上传搜索按钮时判定无字幕', () {
      const html = '''
        <table>
          <tr>
            <td class="rowhead" valign="top">字幕</td>
            <td class="rowfollow" valign="top">
              <a href="javascript:uploadSubtitle(621182);">上传字幕</a>
              <a href="javascript:searchSubtitle(621182);">搜索字幕</a>
            </td>
          </tr>
        </table>
      ''';

      expect(ExternalSubtitleDetector.detectHtml(html), isFalse);
    });

    test('憨憨样式字幕区块内出现附件链接时判定有字幕', () {
      const html = '''
        <div class="font-bold">字幕</div>
        <div class="flex items-center gap-2">
          <a href="/download.php?type=sub&amp;id=99">[字幕组] 简体中文</a>
        </div>
        <div class="font-bold">简介</div>
        <div>剧情简介</div>
      ''';

      expect(ExternalSubtitleDetector.detectHtml(html), isTrue);
    });

    test('憨憨样式字幕区块内只有上传入口时判定无字幕', () {
      const html = '''
        <div class="font-bold">字幕</div>
        <div class="flex items-center gap-2">
          <a href="/upload.php?type=sub">上传字幕</a>
        </div>
        <div class="font-bold">简介</div>
      ''';

      expect(ExternalSubtitleDetector.detectHtml(html), isFalse);
    });

    test('憨憨样式字幕区块内只有上传者资料链接时判定无字幕', () {
      const html = '''
        <div class="font-bold">字幕</div>
        <div><a href="/userdetails.php?id=5">alice</a></div>
        <div class="font-bold">简介</div>
      ''';

      expect(ExternalSubtitleDetector.detectHtml(html), isFalse);
    });

    test('多个字幕行时任意一行有附件即判定有字幕', () {
      const html = '''
        <table>
          <tr>
            <td class="rowhead">字幕</td>
            <td class="rowfollow">简体中文</td>
          </tr>
          <tr>
            <td class="rowhead">字幕</td>
            <td class="rowfollow">
              <a href="downloadsubs.php?torrentid=1&amp;subid=2">简体.ass</a>
            </td>
          </tr>
        </table>
      ''';

      expect(ExternalSubtitleDetector.detectHtml(html), isTrue);
    });

    test('字幕区块为空时不受导航里的字幕库链接影响', () {
      const html = '''
        <div class="menu">
          <a href="subtitles.php?action=download">字幕库</a>
        </div>
        <table>
          <tr>
            <td class="rowhead">字幕</td>
            <td class="rowfollow">暂无字幕</td>
          </tr>
        </table>
      ''';

      expect(ExternalSubtitleDetector.detectHtml(html), isFalse);
    });
  });

  group('ExternalSubtitleDetector.detectRowMarker', () {
    test('列表行出现字幕附件链接时直接判定有字幕', () {
      const html =
          '<td><a href="download.php?id=1&amp;type=sub">字幕.srt</a></td>';

      expect(ExternalSubtitleDetector.detectRowMarker(html), isTrue);
    });

    test('列表行只有中字标签时不误判为外挂字幕', () {
      const html = '<span class="tag">中字</span><span class="tag">4K</span>';

      expect(ExternalSubtitleDetector.detectRowMarker(html), isNull);
    });

    test('列表行出现字幕标签或图标时判定有字幕', () {
      expect(
        ExternalSubtitleDetector.detectRowMarker(
          '<span class="tag">字幕</span>',
        ),
        isTrue,
      );
      expect(
        ExternalSubtitleDetector.detectRowMarker(
          '<i class="subtitle-icon"></i>',
        ),
        isTrue,
      );
    });
  });
}
