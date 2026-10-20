import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pt_mate/services/downloader/downloader_models.dart';
import 'package:pt_mate/utils/downloader_utils.dart';

Widget _wrap(Widget child) => MaterialApp(
  home: Scaffold(body: Center(child: child)),
);

void main() {
  group('DownloaderUtils.getDownloaderIcon', () {
    testWidgets('每种下载器都有图标且不抛异常', (tester) async {
      for (final type in DownloaderType.values) {
        await tester.pumpWidget(_wrap(DownloaderUtils.getDownloaderIcon(type)));
        await tester.pump();
        expect(tester.takeException(), isNull, reason: type.name);
        final drawn =
            find.byType(SvgPicture).evaluate().length +
            find.byType(Image).evaluate().length +
            find.byType(Icon).evaluate().length;
        expect(drawn, 1, reason: '${type.name} 应恰好渲染一个图标');
      }
    });

    testWidgets('Deluge 用随包的官方 SVG 而不是通用图标', (tester) async {
      await tester.pumpWidget(
        _wrap(DownloaderUtils.getDownloaderIcon(DownloaderType.deluge, size: 48)),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.byType(SvgPicture), findsOneWidget);
      expect(find.byType(Icon), findsNothing);

      final source = await rootBundle.loadString('assets/logo/Deluge.svg');
      expect(source, contains('<svg'));
      expect(source, contains('viewBox'), reason: '无 viewBox 时 flutter_svg 无法定标');
    });

    test('Deluge 的默认端口与本地中转说明', () {
      expect(DownloaderUtils.getDefaultPort(DownloaderType.deluge), 8112);
      expect(DownloaderUtils.requiresLocalRelay(DownloaderType.deluge), isFalse);
      expect(
        DownloaderUtils.getLocalRelayDescription(DownloaderType.deluge),
        contains('Cookie'),
      );
    });
  });
}
