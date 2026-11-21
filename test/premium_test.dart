import 'package:dmonly/services/content_packs.dart';
import 'package:dmonly/services/premium_store.dart';
import 'package:dmonly/services/profile_store.dart';
import 'package:dmonly/services/progress_store.dart';
import 'package:dmonly/services/seen_content.dart';
import 'package:dmonly/services/taste_store.dart';
import 'package:dmonly/services/word_interactions.dart';
import 'package:dmonly/ui/app_theme.dart';
import 'package:dmonly/ui/premium_screen.dart';
import 'package:dmonly/ui/tracked_apps_screen.dart';
import 'package:dmonly/ui/word_flow_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _channel = MethodChannel('com.dmonly.app/words');

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

Future<void> _settle(WidgetTester tester, [int steps = 10]) async {
  for (var i = 0; i < steps; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Map<String, Object> _state(List<String> tracked) => {
  'enabled': true,
  'onScreenOn': false,
  'onUnlock': true,
  'languages': ['en'],
  'notificationsGranted': true,
  'batteryUnrestricted': true,
  'usageAccessGranted': true,
  'trackedApps': tracked,
  'limitMinutes': 5,
  'wordCount': 10,
  'shownToday': 0,
  'totalShown': 0,
  'streak': 0,
  'learned': <String, int>{},
  'available': <String, int>{},
};

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({'language': 'en', 'level': 1});
    await ProfileStore.instance.load();
    await ProgressStore.instance.load();
    await PremiumStore.instance.load();
    PremiumStore.instance.resetForTest();
  });

  test('free by default; the developer switch turns Premium on', () async {
    final store = PremiumStore.instance;
    expect(store.isPremium, isFalse);
    await store.setTestPremium(true);
    expect(store.isPremium, isTrue);
    await store.setTestPremium(false);
    expect(store.isPremium, isFalse);
    expect(store.toCloud(), {'active': false, 'product': null});
  });

  test('only answers at a picked Hard count towards the free five', () async {
    final p = ProgressStore.instance;
    p.record('en', correct: true);
    expect(p.hardAnsweredToday, 0);
    await p.setDifficulty('en', 3);
    p.record('en', correct: true, difficulty: 3);
    p.record('en', correct: false, difficulty: 2);
    expect(p.hardAnsweredToday, 2);
  });

  testWidgets('the Premium screen lists the benefits and, before Play is '
      'set up, says it isn’t on sale', (tester) async {
    _phone(tester);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.light),
        home: const PremiumScreen(reason: 'Free covers up to 3 tracked apps.'),
      ),
    );
    await _settle(tester);
    expect(find.text('BiLingo Premium'), findsOneWidget);
    expect(find.text('Free covers up to 3 tracked apps.'), findsOneWidget);
    expect(find.text('No ads'), findsOneWidget);
    expect(find.text('Unlimited tracked apps'), findsOneWidget);
    expect(find.text('Unlimited Hard reels'), findsOneWidget);
    expect(find.textContaining('can’t be bought here'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  group('tracked apps', () {
    late List<MethodCall> calls;

    Future<void> open(WidgetTester tester, List<String> tracked) async {
      _phone(tester);
      calls = [];
      final icon = Uint8List(0);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_channel, (call) async {
            calls.add(call);
            return switch (call.method) {
              'getState' => _state(tracked),
              'setSettings' => _state(
                ((call.arguments as Map)['trackedApps'] as List?)
                        ?.cast<String>() ??
                    tracked,
              ),
              'installedApps' => [
                for (final n in ['Alpha', 'Bravo', 'Charlie', 'Delta'])
                  {'package': 'app.$n', 'label': n, 'icon': icon},
              ],
              _ => null,
            };
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(_channel, null),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(Brightness.light),
          home: const TrackedAppsScreen(),
        ),
      );
      await _settle(tester);
    }

    testWidgets('free stops at three and offers Premium', (tester) async {
      await open(tester, ['app.Alpha', 'app.Bravo', 'app.Charlie']);
      expect(find.text('3 of 3 free apps'), findsOneWidget);
      await tester.tap(find.text('Delta'));
      await _settle(tester);
      expect(find.text('Free covers up to 3 tracked apps.'), findsOneWidget);
      expect(calls.where((c) => c.method == 'setSettings'), isEmpty);
    });

    testWidgets('Premium tracks as many as you like', (tester) async {
      PremiumStore.instance.resetForTest(premium: true);
      await open(tester, ['app.Alpha', 'app.Bravo', 'app.Charlie']);
      expect(find.text('3 apps tracked'), findsOneWidget);
      await tester.tap(find.text('Delta'));
      await _settle(tester);
      final saved = calls.lastWhere((c) => c.method == 'setSettings');
      expect((saved.arguments as Map)['trackedApps'], hasLength(4));
      expect(find.text('4 apps tracked'), findsOneWidget);
    });

    testWidgets('removing an app is always allowed', (tester) async {
      await open(tester, ['app.Alpha', 'app.Bravo', 'app.Charlie']);
      await tester.tap(find.text('Alpha'));
      await _settle(tester);
      final saved = calls.lastWhere((c) => c.method == 'setSettings');
      expect((saved.arguments as Map)['trackedApps'], hasLength(2));
    });
  });

  testWidgets('after five Hard reels a free learner goes back to Auto', (
    tester,
  ) async {
    _phone(tester);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async => null);
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_channel, null),
    );
    await WordInteractions.instance.load();
    await SeenContent.instance.load();
    await ContentPacks.instance.load();
    await TasteStore.instance.load();
    await ProfileStore.instance.setFlowMaths(true);
    final p = ProgressStore.instance;
    await p.setDifficulty('math', 3);
    for (var i = 0; i < kFreeHardPerDay - 1; i++) {
      p.record('math', correct: true, difficulty: 3);
    }
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.light),
        home: const GradientBackground(
          child: Scaffold(body: SafeArea(child: WordFlowTab())),
        ),
      ),
    );
    await _settle(tester, 3);
    // The fifth: any answer to the maths question on screen.
    await tester.tap(find.byType(AnimatedContainer).hitTestable().first);
    await _settle(tester, 30);

    expect(p.hardAnsweredToday, kFreeHardPerDay);
    expect(p.chosenTier('math'), isNull);
    expect(find.text('That’s today’s 5 free Hard reels'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
