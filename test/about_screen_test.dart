import 'dart:io';
import 'dart:ui' as ui;

import 'package:dmonly/app_info.dart';
import 'package:dmonly/ui/about_screen.dart';
import 'package:dmonly/ui/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _channel = MethodChannel('com.dmonly.app/words');

/// Set to a folder to save a picture of the screen.
const _out = String.fromEnvironment('OUT');

void main() {
  testWidgets('About shows the version, what it does, data and actions', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
          calls.add(call);
          return switch (call.method) {
            'appVersion' => {'name': '1.4.0', 'code': 6},
            'openUrl' => true,
            _ => null,
          };
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_channel, null),
    );

    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.light),
        home: RepaintBoundary(key: key, child: const AboutScreen()),
      ),
    );
    for (var i = 0; i < 15; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.text('Version 1.4.0 (6)'), findsOneWidget);
    expect(find.text('A word every unlock'), findsOneWidget);
    expect(find.text('Scroll Stop'), findsOneWidget);
    if (_out.isNotEmpty) {
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await boundary.toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        File('$_out/about.png').writeAsBytesSync(bytes!.buffer.asUint8List());
      });
    }

    await tester.scrollUntilVisible(find.text('Your data'), 300);
    expect(find.text('Your data'), findsOneWidget);
    // Not shown until a URL and an email are set in app_info.dart.
    expect(
      find.text('Privacy policy'),
      kPrivacyPolicyUrl.isEmpty ? findsNothing : findsOneWidget,
    );
    expect(
      find.text('Send feedback'),
      kSupportEmail.isEmpty ? findsNothing : findsOneWidget,
    );

    await tester.scrollUntilVisible(find.text('Rate BiLingo'), 300);
    await tester.tap(find.text('Rate BiLingo'));
    await tester.pump();
    final open = calls.lastWhere((c) => c.method == 'openUrl');
    expect((open.arguments as Map)['url'], kPlayStoreAppUrl);
    expect((open.arguments as Map)['fallback'], kPlayStoreUrl);

    await tester.tap(find.text('Share with a friend'));
    await tester.pump();
    final share = calls.lastWhere((c) => c.method == 'shareText');
    expect((share.arguments as Map)['text'], contains(kPlayStoreUrl));
    expect(tester.takeException(), isNull);
  });
}
