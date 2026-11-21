import 'package:dmonly/services/content_packs.dart';
import 'package:dmonly/services/profile_store.dart';
import 'package:dmonly/services/progress_store.dart';
import 'package:dmonly/services/seen_content.dart';
import 'package:dmonly/services/taste_store.dart';
import 'package:dmonly/services/word_interactions.dart';
import 'package:dmonly/ui/app_theme.dart';
import 'package:dmonly/ui/word_flow_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _channel = MethodChannel('com.dmonly.app/words');

/// The dark feed's backdrop.
const _videoBlack = Color(0xFF0E0F13);

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('the reel feed follows the $brightness theme', (tester) async {
      tester.view.physicalSize = const Size(1170, 844 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues({'language': 'en', 'level': 1});
      await ProfileStore.instance.load();
      await WordInteractions.instance.load();
      await SeenContent.instance.load();
      await ProgressStore.instance.load();
      await ContentPacks.instance.load();
      await TasteStore.instance.load();
      await ProfileStore.instance.setFlowCode('javascript');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_channel, (call) async => null);
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(_channel, null),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(brightness),
          home: const GradientBackground(
            child: Scaffold(body: SafeArea(child: WordFlowTab())),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      final dark = brightness == Brightness.dark;
      // Black backdrop only at night; by day the app's background shows.
      expect(
        find.byWidgetPredicate(
          (w) => w is ColoredBox && w.color == _videoBlack,
        ),
        dark ? findsOneWidget : findsNothing,
      );
      // Status bar icons stay readable on the backdrop.
      final region = tester.widget<AnnotatedRegion<SystemUiOverlayStyle>>(
        find.byType(AnnotatedRegion<SystemUiOverlayStyle>).first,
      );
      expect(
        region.value.statusBarIconBrightness,
        dark ? Brightness.light : Brightness.dark,
      );
      // Reel text uses the theme's ink, not white on white.
      final title = tester.widget<Text>(find.text('JavaScript').first);
      final context = tester.element(find.text('JavaScript').first);
      final color =
          title.style?.color ?? DefaultTextStyle.of(context).style.color!;
      expect(
        color.computeLuminance() > 0.5,
        dark,
        reason: 'text should contrast with the $brightness feed',
      );
      expect(tester.takeException(), isNull);
    });
  }
}
