import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pt_mate/utils/url_launcher_helper.dart';

/// url_launcher 走独立通道；鸿蒙上该插件没有 ohos 端口，
/// 调用会抛 MissingPluginException，这里用 mock 复现同一情形。
const _urlLauncherChannel = MethodChannel('plugins.flutter.io/url_launcher');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<MethodCall> platformCalls;

  setUp(() {
    platformCalls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          platformCalls.add(call);
          if (call.method == 'Clipboard.setData') return null;
          return null;
        });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_urlLauncherChannel, (call) async {
          throw MissingPluginException(
            'No implementation found for ${call.method} on ohos',
          );
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_urlLauncherChannel, null);
  });

  testWidgets('唤起失败时把链接复制到剪贴板', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SizedBox.shrink())),
    );

    const url = 'https://github.com/GTX2090ti/pt_mate-Harmony';
    await UrlLauncherHelper.launchBrowser(
      tester.element(find.byType(Scaffold)),
      url,
    );
    await tester.pumpAndSettle();

    final clipboardCalls = platformCalls
        .where((c) => c.method == 'Clipboard.setData')
        .toList();
    expect(clipboardCalls, hasLength(1));

    final args = clipboardCalls.first.arguments as Map<Object?, Object?>;
    expect(args['text'], url);

    // 提示条的自动关闭定时器是在 addPostFrameCallback 里创建的，
    // 先 pump 一帧让它起来，再推进时间等它自然结束。
    await tester.pump();
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
  });

  testWidgets('剪贴板写入失败时也不抛异常', (tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          platformCalls.add(call);
          if (call.method == 'Clipboard.setData') {
            throw PlatformException(code: 'unavailable');
          }
          return null;
        });

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SizedBox.shrink())),
    );

    // 不应抛出异常
    await UrlLauncherHelper.launchBrowser(
      tester.element(find.byType(Scaffold)),
      'https://example.com',
    );
    // showError 的自动关闭时长为 4 秒，同样先 pump 一帧再推进时间
    await tester.pump();
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });
}
