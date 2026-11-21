import 'package:dmonly/services/arrest_store.dart';
import 'package:dmonly/services/profile_store.dart';
import 'package:dmonly/services/progress_store.dart';
import 'package:dmonly/ui/app_theme.dart';
import 'package:dmonly/ui/patrol.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

void main() {
  final store = ArrestStore.instance;
  var now = DateTime(2026, 11, 9, 19, 30);

  setUp(() async {
    SharedPreferences.setMockInitialValues({'name': 'Anu'});
    now = DateTime(2026, 11, 9, 19, 30);
    ArrestStore.clock = () => now;
    ProgressStore.clock = () => now;
    store.resetForTest();
    await store.load();
    await ProfileStore.instance.load();
    await ProgressStore.instance.load();
    shellTabRequest.value = null;
  });
  tearDown(() {
    ArrestStore.clock = DateTime.now;
    ProgressStore.clock = DateTime.now;
  });

  group('arrests and bail', () {
    test('a scrolling arrest costs three reels and pays 30 XP', () {
      store.book(offence: Offence.scrolling, app: 'Instagram', minutes: 12);
      expect(store.serving, isTrue);
      expect(store.bailLeft, ArrestStore.bailReels);
      expect(store.bailReward, ArrestStore.bailXp);
      expect(store.onAnswered(), isFalse);
      expect(store.onAnswered(), isFalse);
      expect(store.onAnswered(), isTrue);
      expect(store.serving, isFalse);
      expect(store.current, isNull);
      expect(store.arrests.single.bailPaid, isTrue);
      // Free: answers no longer count towards anything.
      expect(store.onAnswered(), isFalse);
    });

    test('a new charge while serving adds no extra bail', () {
      store.book(offence: Offence.scrolling, app: 'YouTube', minutes: 5);
      store.onAnswered();
      store.book(offence: Offence.scrolling, app: 'Instagram', minutes: 9);
      expect(store.bailLeft, 2);
      store.onAnswered();
      expect(store.onAnswered(), isTrue);
      // Paying bail clears every open charge.
      expect(store.arrests.every((a) => a.bailPaid), isTrue);
    });

    test('a fresh arrest pops up once, and only while recent', () {
      final a = store.book(offence: Offence.scrolling, app: 'X', minutes: 5);
      expect(store.fresh, a);
      store.markSeen(a);
      expect(store.fresh, isNull);
      store.resetForTest();
      store.book(
        offence: Offence.scrolling,
        at: now.subtract(const Duration(hours: 5)),
        app: 'X',
        minutes: 5,
      );
      expect(store.fresh, isNull);
      expect(store.current, isNotNull);
    });

    test('the record survives a restart', () async {
      store.book(offence: Offence.scrolling, app: 'Reddit', minutes: 20);
      store.onAnswered();
      await Future<void>.delayed(Duration.zero);
      store.resetForTest();
      await store.load();
      expect(store.arrests.single.app, 'Reddit');
      expect(store.bailLeft, 2);
      expect(store.bailReward, ArrestStore.bailXp);
    });

    test('the case file sums up the week', () {
      store.book(
        offence: Offence.scrolling,
        at: now.subtract(const Duration(days: 10)),
        app: 'Old',
        minutes: 90,
      );
      store.book(offence: Offence.scrolling, app: 'Instagram', minutes: 12);
      for (var i = 0; i < 3; i++) {
        store.onAnswered();
      }
      store.book(offence: Offence.scrolling, app: 'Instagram', minutes: 25);
      store.book(offence: Offence.scrolling, app: 'YouTube', minutes: 8);
      final file = store.caseFile();
      expect(file.arrests, 3);
      // The first paid bail covered the old one too.
      expect(file.bailPaid, 1);
      expect(file.longestMinutes, 25);
      expect(file.topApp, 'Instagram');
    });
  });

  group('wanted', () {
    test('only in the evening, with the goal missed, once a day', () {
      expect(store.shouldShowWanted(answered: 2, goal: 10), isTrue);
      expect(store.shouldShowWanted(answered: 10, goal: 10), isFalse);
      now = DateTime(2026, 11, 9, 10);
      expect(store.shouldShowWanted(answered: 2, goal: 10), isFalse);
      now = DateTime(2026, 11, 9, 20);
      store.markWantedShown();
      expect(store.shouldShowWanted(answered: 2, goal: 10), isFalse);
      now = DateTime(2026, 11, 10, 20);
      expect(store.shouldShowWanted(answered: 2, goal: 10), isTrue);
      // Not while bail is being served.
      store.book(offence: Offence.scrolling, app: 'X', minutes: 5);
      expect(store.shouldShowWanted(answered: 2, goal: 10), isFalse);
    });

    testWidgets('turning yourself in books a short bail', (tester) async {
      _phone(tester);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(Brightness.light),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) => const WantedPoster(answered: 3, goal: 10),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await _settle(tester);
      expect(find.text('WANTED'), findsOneWidget);
      expect(find.text('ANU'), findsOneWidget);
      expect(
        find.text('For skipping study: 3 of 10 reels today'),
        findsOneWidget,
      );
      await tester.tap(find.text('Turn myself in'));
      await _settle(tester);
      expect(store.current?.offence, Offence.goal);
      expect(store.bailLeft, ArrestStore.maxWantedBail);
      expect(store.bailReward, ArrestStore.wantedXp);
      expect(shellTabRequest.value, 0);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('the arrest screen shows the charge and sends you to pay', (
    tester,
  ) async {
    _phone(tester);
    final arrest = store.book(
      offence: Offence.scrolling,
      app: 'Instagram',
      minutes: 12,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.light),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => ArrestScreen(arrest: arrest),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await _settle(tester);
    expect(find.text('BUSTED!'), findsOneWidget);
    expect(
      find.text('Kept scrolling Instagram after a warning: 12 minutes'),
      findsOneWidget,
    );
    expect(find.text('You’re under arrest!'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (w) => w is Semantics && w.properties.label == 'You, behind bars',
      ),
      findsOneWidget,
    );
    expect(find.text('Answer 3 more reels to walk free'), findsOneWidget);
    // Bail paid while it's open: out of jail.
    for (var i = 0; i < ArrestStore.bailReels; i++) {
      store.onAnswered();
    }
    await _settle(tester);
    expect(find.text('You’re free to go!'), findsOneWidget);
    expect(find.text('RELEASED'), findsOneWidget);
    await tester.tap(find.text('Pay bail now'));
    await _settle(tester);
    expect(find.text('BUSTED!'), findsNothing);
    expect(shellTabRequest.value, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the bail banner counts down, and hides when free', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: BailBanner())),
    );
    expect(find.textContaining('Bail'), findsNothing);
    store.book(offence: Offence.scrolling, app: 'X', minutes: 5);
    await tester.pump();
    expect(find.text('Bail: answer 3 more reels'), findsOneWidget);
    store.onAnswered();
    store.onAnswered();
    await tester.pump();
    expect(find.text('Bail: answer 1 more reel'), findsOneWidget);
    store.onAnswered();
    await tester.pump();
    expect(find.textContaining('Bail'), findsNothing);
  });

  testWidgets('the case file shows the week, or praise when clean', (
    tester,
  ) async {
    _phone(tester);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.light),
        home: const Scaffold(body: CaseFileCard()),
      ),
    );
    expect(find.textContaining('No arrests this week'), findsOneWidget);
    store.book(offence: Offence.scrolling, app: 'Instagram', minutes: 12);
    await tester.pump();
    expect(find.text('Arrests'), findsOneWidget);
    expect(find.text('12m on Instagram'), findsOneWidget);
    expect(find.text('Pending'), findsOneWidget);
    // The ghost has no patrol, unless there is a record to show.
    store.resetForTest();
    await ProfileStore.instance.setMascot(MascotStyle.ghost);
    await tester.pump();
    expect(find.textContaining('case file'), findsNothing);
  });

  test("today's answers count up and reset the next day; bonus XP", () {
    final p = ProgressStore.instance;
    expect(p.answeredToday, 0);
    p.record('math', correct: true);
    p.record('en', correct: false);
    expect(p.answeredToday, 2);
    now = DateTime(2026, 11, 10, 9);
    expect(p.answeredToday, 0);
    final before = p.levelOf('math').xpIntoLevel;
    expect(p.addXp('math', 30).xp, 30);
    expect(p.levelOf('math').xpIntoLevel, before + 30);
  });

  group('record', () {
    test('all-time totals outlive the 100-arrest list', () {
      for (var i = 0; i < 105; i++) {
        store.book(offence: Offence.scrolling, app: 'X', minutes: 5);
      }
      expect(store.arrests.length, 100);
      expect(store.totalArrests, 105);
      for (var i = 0; i < ArrestStore.bailReels; i++) {
        store.onAnswered();
      }
      expect(store.totalPaid, 100);
    });

    test('totals and warnings survive a restart', () async {
      store.book(offence: Offence.scrolling, app: 'X', minutes: 5);
      store.setWarnings(4, 3);
      await Future<void>.delayed(Duration.zero);
      store.resetForTest();
      await store.load();
      expect(store.totalArrests, 1);
      expect(store.warnings, 4);
      expect(store.heeded, 3);
      // Counts from the tracker only ever grow.
      store.setWarnings(2, 1);
      expect(store.warnings, 4);
    });

    test('an older record is counted from its list', () async {
      SharedPreferences.setMockInitialValues({
        'patrol_arrests':
            '[{"at":${now.millisecondsSinceEpoch},"offence":"scrolling",'
            '"app":"X","minutes":5,"bailPaid":true}]',
      });
      store.resetForTest();
      await store.load();
      expect(store.totalArrests, 1);
      expect(store.totalPaid, 1);
    });

    test('days clean count from the last arrest', () {
      expect(store.daysClean, isNull);
      store.book(
        offence: Offence.scrolling,
        at: now.subtract(const Duration(days: 3)),
        app: 'X',
        minutes: 5,
      );
      expect(store.daysClean, 3);
    });

    test('the cloud keeps the larger totals', () {
      store.book(offence: Offence.scrolling, app: 'X', minutes: 5);
      expect(store.toCloud()['arrests'], 1);
      store.mergeCloud({
        'arrests': 7,
        'bailPaid': 5,
        'warnings': 9,
        'stoppedInTime': 4,
      });
      expect(store.totalArrests, 7);
      expect(store.totalPaid, 5);
      expect(store.heeded, 4);
      store.mergeCloud({'arrests': 2});
      expect(store.totalArrests, 7);
    });

    testWidgets('Profile shows the record, and the history behind it', (
      tester,
    ) async {
      _phone(tester);
      var paying = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(Brightness.light),
          home: Scaffold(
            body: PatrolRecordCard(onPayBail: () => paying = true),
          ),
        ),
      );
      expect(find.text('Clean record'), findsOneWidget);
      store.book(offence: Offence.scrolling, app: 'Instagram', minutes: 12);
      store.setWarnings(3, 2);
      await tester.pump();
      expect(find.text('In jail now · 3 reels to bail'), findsOneWidget);
      expect(find.text('Times in jail'), findsOneWidget);
      expect(find.text('Stopped in time'), findsOneWidget);
      await tester.tap(find.text('Pay bail'));
      expect(paying, isTrue);

      await tester.tap(find.text('Arrest record'));
      await _settle(tester);
      expect(find.text('Arrest history'), findsOneWidget);
      expect(
        find.text('1 time in jail · 2 of 3 warnings heeded'),
        findsOneWidget,
      );
      expect(find.text('12 min on Instagram'), findsOneWidget);
      expect(find.text('In jail'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
