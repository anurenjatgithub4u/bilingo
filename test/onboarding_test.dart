import 'package:dmonly/services/profile_store.dart';
import 'package:dmonly/ui/app_theme.dart';
import 'package:dmonly/ui/onboarding_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _channel = MethodChannel('com.dmonly.app/words');

/// A 1×1 transparent PNG, for app icons.
final _icon = Uint8List.fromList(const [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, //
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);

Map<String, Object> _state({bool notifications = false}) => {
  'enabled': false,
  'onScreenOn': false,
  'onUnlock': true,
  'languages': <String>['en'],
  'notificationsGranted': notifications,
  'batteryUnrestricted': false,
  'usageAccessGranted': false,
  'wordCount': 0,
  'shownToday': 0,
  'totalShown': 0,
  'learned': <String, int>{},
  'available': <String, int>{},
};

Future<List<MethodCall>> _setUp({List<Map<String, Object>>? apps}) async {
  SharedPreferences.setMockInitialValues({});
  await ProfileStore.instance.load();
  final calls = <MethodCall>[];
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_channel, (call) async {
        calls.add(call);
        return switch (call.method) {
          'getState' => _state(notifications: true),
          'installedApps' =>
            apps ??
                [
                  {
                    'package': 'com.instagram.android',
                    'label': 'Instagram',
                    'icon': _icon,
                  },
                  {
                    'package': 'com.example.notes',
                    'label': 'Notes',
                    'icon': _icon,
                  },
                ],
          _ => null,
        };
      });
  addTearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null),
  );
  return calls;
}

void _phone(WidgetTester tester, {double height = 844}) {
  tester.view.physicalSize = Size(1170, height * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

Widget _app() => MaterialApp(
  theme: buildTheme(Brightness.light),
  home: const OnboardingScreen(),
);

/// The ghost never stops moving, so no pumpAndSettle.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Finder get _continue => find.widgetWithText(FilledButton, 'Continue');

Future<void> _tapContinue(WidgetTester tester) async {
  await tester.tap(_continue);
  await _settle(tester);
}

/// Taps Get started. Home needs Firebase, which tests don't have, so its
/// build errors are ignored; onboarding's own work is done by then.
Future<void> _getStarted(WidgetTester tester) async {
  final original = FlutterError.onError;
  FlutterError.onError = (details) {
    if (!'${details.exception}'.contains('Firebase')) original?.call(details);
  };
  addTearDown(() => FlutterError.onError = original);
  await tester.tap(find.widgetWithText(FilledButton, 'Get started'));
  await _settle(tester);
  await tester.pumpWidget(const SizedBox());
  FlutterError.onError = original;
}

bool _enabled(WidgetTester tester, Finder button) =>
    tester.widget<FilledButton>(button).onPressed != null;

void main() {
  testWidgets('six steps: welcome, name, subjects, usage, how, setup', (
    tester,
  ) async {
    _phone(tester);
    final calls = await _setUp();
    await tester.pumpWidget(_app());
    await _settle(tester);

    // 1. Welcome
    expect(find.text('Focus, uninterrupted.'), findsOneWidget);
    expect(find.text('SCROLLING'), findsOneWidget);
    expect(find.text('BILINGO'), findsOneWidget);
    await _tapContinue(tester);

    // 2. Name: required.
    expect(find.text('What should I call you?'), findsOneWidget);
    expect(_enabled(tester, _continue), isFalse);
    await tester.enterText(find.byType(TextField), '  ');
    await tester.pump();
    expect(_enabled(tester, _continue), isFalse);
    await tester.enterText(find.byType(TextField), 'Anu');
    await tester.pump();
    expect(_enabled(tester, _continue), isTrue);
    await _tapContinue(tester);

    // 3. Subjects: several allowed, at least one, no Hindi.
    expect(find.text('What would you like to learn?'), findsOneWidget);
    expect(find.text('Hindi'), findsNothing);
    expect(_enabled(tester, _continue), isFalse);
    await tester.tap(find.text('German'));
    await tester.tap(find.text('Mathematics'));
    await tester.pump();
    expect(_enabled(tester, _continue), isTrue);
    await tester.tap(find.text('German'));
    await tester.pump();
    expect(_enabled(tester, _continue), isTrue); // Maths still picked.
    await _tapContinue(tester);

    // 4. Usage awareness: auto-detect prompt by default; user can estimate manually.
    expect(find.text('Track actual time automatically'), findsOneWidget);
    expect(find.text("I'd rather estimate manually"), findsOneWidget);
    await tester.tap(find.text("I'd rather estimate manually"));
    await _settle(tester);

    expect(find.text('3 hours a day'), findsOneWidget);
    expect(find.text('21 h'), findsOneWidget);
    expect(
      find.text('That’s 21 hours every week. Imagine what you could learn!'),
      findsOneWidget,
    );
    final slider = find.byType(Slider);
    final box = tester.getRect(slider);
    // Far right: 8 hours.
    await tester.tapAt(Offset(box.right - 26, box.center.dy));
    await _settle(tester);
    expect(find.text('8 hours a day'), findsOneWidget);
    expect(find.text('56 h'), findsOneWidget);
    expect(find.text('2,920 h'), findsOneWidget);
    expect(find.textContaining('We need a little change.'), findsOneWidget);
    // Far left: 1 hour.
    await tester.tapAt(Offset(box.left + 26, box.center.dy));
    await _settle(tester);
    expect(find.text('1 hour a day'), findsOneWidget);
    expect(find.textContaining("Let's make them count!"), findsOneWidget);
    await _tapContinue(tester);

    // 5. How it works
    expect(find.text('Scrolling reminders'), findsOneWidget);
    expect(find.text('Unlock learning'), findsOneWidget);
    expect(find.text('WordFlow'), findsOneWidget);
    expect(find.textContaining('does not read your messages'), findsOneWidget);
    await _tapContinue(tester);

    // 6. Apps: Instagram is preselected.
    expect(find.text('Which apps eat your time?'), findsOneWidget);
    expect(find.text('1 app picked'), findsOneWidget);
    expect(find.text('Notifications'), findsNothing);
    await _tapContinue(tester);

    // 7. Reminder limit, on its own screen, fully visible.
    expect(find.text('How long before I step in?'), findsOneWidget);
    expect(find.text('5 minutes').hitTestable(), findsOneWidget);
    expect(find.byType(Slider).hitTestable(), findsOneWidget);
    expect(
      find.text("Enough scrolling! Let's learn something new").hitTestable(),
      findsOneWidget,
    );
    // Any time works: one minute at a time, or by dragging.
    await tester.tap(find.byIcon(Icons.add_rounded));
    await tester.pump();
    expect(find.text('6 minutes'), findsOneWidget);
    final limitBar = tester.getRect(find.byType(Slider));
    await tester.tapAt(Offset(limitBar.left + 26, limitBar.center.dy));
    await tester.pump();
    expect(find.text('1 minute'), findsOneWidget);
    await tester.tapAt(Offset(limitBar.right - 26, limitBar.center.dy));
    await tester.pump();
    expect(find.text('60 minutes'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.remove_rounded));
    await tester.pump();
    expect(find.text('59 minutes'), findsOneWidget);
    await _tapContinue(tester);

    // 8. Permissions, on their own screen; usage access since apps are picked.
    expect(find.text('Let me in'), findsOneWidget);
    expect(find.text('Notifications'), findsOneWidget);
    expect(find.text('Usage access'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Get started'), findsOneWidget);
    // Back and forth keeps every answer.
    for (var i = 0; i < 4; i++) {
      await tester.tap(find.byIcon(Icons.arrow_back));
      await _settle(tester);
    }
    expect(find.text('1 hour a day'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.arrow_back));
    await _settle(tester);
    expect(_enabled(tester, _continue), isTrue);
    await _tapContinue(tester);
    await _tapContinue(tester);
    await _tapContinue(tester);

    // Skip app monitoring: the limit step and usage access go away.
    await tester.tap(find.text('Instagram'));
    await _settle(tester);
    await _tapContinue(tester);
    expect(find.text('How long before I step in?').hitTestable(), findsNothing);
    expect(find.text('Let me in'), findsOneWidget);
    expect(find.text('Usage access'), findsNothing);
    // Back skips the limit step too.
    await tester.tap(find.byIcon(Icons.arrow_back));
    await _settle(tester);
    expect(
      find.text('Which apps eat your time?').hitTestable(),
      findsOneWidget,
    );
    await _tapContinue(tester);
    expect(find.text('Notifications'), findsOneWidget);

    await _getStarted(tester);

    final store = ProfileStore.instance;
    expect(store.onboarded, isTrue);
    expect(store.name, 'Anu');
    expect(store.topics, {'math'});
    expect(store.flowMaths, isTrue);
    expect(store.scrollHoursEstimate, 1);
    expect(store.onboardingSetup['appMonitoring'], isFalse);
    expect(store.onboardingSetup['unlockLearning'], isTrue);
    expect(store.onboardingSetup['notificationsGranted'], isTrue);
    final settings = calls.lastWhere((c) => c.method == 'setSettings');
    final args = settings.arguments as Map;
    expect(args['enabled'], isTrue);
    expect(args['onUnlock'], isTrue);
    expect(args['trackedApps'], isEmpty);
  });

  testWidgets('onboarding shows language, maths and coding without sub-languages', (
    tester,
  ) async {
    _phone(tester);
    await _setUp(apps: const []);
    await tester.pumpWidget(_app());
    await _settle(tester);
    await _tapContinue(tester);
    await tester.enterText(find.byType(TextField), 'Sam');
    await tester.pump();
    await _tapContinue(tester);
    expect(find.text('English'), findsOneWidget);
    expect(find.text('German'), findsOneWidget);
    expect(find.text('Mathematics'), findsOneWidget);
    expect(find.text('Coding'), findsOneWidget);
    expect(find.text('Python'), findsNothing);
    expect(find.text('JavaScript'), findsNothing);
    await tester.tap(find.text('Coding'));
    await tester.pump();
    expect(_enabled(tester, _continue), isTrue);
    for (var i = 0; i < 4; i++) {
      await _tapContinue(tester);
    }
    await _getStarted(tester);
    final store = ProfileStore.instance;
    expect(store.topics, {'coding'});
    expect(store.flowCode, 'coding');
  });

  testWidgets('a double tap on Continue moves one step only', (tester) async {
    _phone(tester);
    await _setUp();
    await tester.pumpWidget(_app());
    await _settle(tester);
    await tester.tap(_continue);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(_continue, warnIfMissed: false);
    await _settle(tester);
    expect(find.text('What should I call you?'), findsOneWidget);
    expect(
      find.text('What would you like to learn?').hitTestable(),
      findsNothing,
    );
  });

  testWidgets('setup with no reminders needs no permissions', (tester) async {
    _phone(tester, height: 640);
    await _setUp(apps: const []);
    await tester.pumpWidget(_app());
    await _settle(tester);
    await _tapContinue(tester);
    await tester.enterText(find.byType(TextField), 'Sam');
    await tester.pump();
    await _tapContinue(tester);
    await tester.tap(find.text('English'));
    await tester.pump();
    await _tapContinue(tester);
    await _tapContinue(tester);
    await _tapContinue(tester);
    expect(tester.takeException(), isNull);
    await _tapContinue(tester);
    expect(tester.takeException(), isNull);

    await tester.ensureVisible(find.byType(Switch));
    await tester.pump();
    await tester.tap(find.byType(Switch));
    await _settle(tester);
    expect(find.text('Notifications'), findsNothing);
    expect(find.textContaining('I need no permissions'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _getStarted(tester);
    final store = ProfileStore.instance;
    expect(store.language, 'en');
    expect(store.topics, {'en'});
    expect(store.flowMaths, isFalse);
    expect(store.scrollHoursEstimate, 3);
    expect(store.onboardingSetup['unlockLearning'], isFalse);
  });
}
