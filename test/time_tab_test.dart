import 'package:dmonly/services/profile_store.dart';
import 'package:dmonly/services/progress_store.dart';
import 'package:dmonly/services/usage_summary.dart';
import 'package:dmonly/ui/app_theme.dart';
import 'package:dmonly/ui/mascot.dart';
import 'package:dmonly/ui/time_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _channel = MethodChannel('com.dmonly.app/words');
const _hour = 3600000;
const _min = 60000;

final _png = Uint8List.fromList(const [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, //
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);

/// Eight days of hourly data, each day's time falling in the hour before noon.
List<int> _hourly(List<int> days) => [
  for (final d in days)
    for (var h = 0; h < 24; h++) h == 11 ? d : 0,
];

Map<String, Object> _data({int today = 2 * _hour}) => {
  'granted': true,
  'apps': [
    {
      'package': 'com.instagram.android',
      'label': 'Instagram',
      'category': 'social',
      'todayMs': today,
      'icon': _png,
    },
  ],
  'categories': {'social': today},
  'hourly': _hourly([
    3 * _hour,
    3 * _hour,
    3 * _hour,
    3 * _hour,
    3 * _hour,
    3 * _hour,
    3 * _hour,
    today,
  ]),
  'hasData': [true, true, true, true, true, true, true, true],
};

List<MethodCall> _mock(Object? result) {
  final calls = <MethodCall>[];
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_channel, (call) async {
        calls.add(call);
        return call.method == 'usageSummary' ? result : null;
      });
  addTearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null),
  );
  return calls;
}

Future<void> _open(WidgetTester tester, {double height = 844}) async {
  tester.view.physicalSize = Size(1170, height * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildTheme(Brightness.light),
      // 15:00: halfway through a waking day.
      home: Scaffold(body: TimeTab(now: DateTime(2026, 1, 1, 15))),
    ),
  );
  await tester.pump();
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await ProfileStore.instance.load();
    await ProgressStore.instance.load();
  });

  group('the numbers', () {
    test('2 hours a day adds up as promised', () {
      const c = TimeCost(2 * _hour);
      expect(c.hoursPerMonth, 60);
      expect(c.hoursPerYear, 730);
      expect(c.daysPerYear, closeTo(30.4, 0.1));
      expect(c.yearsOfLife, closeTo(4.2, 0.05));
      expect(c.oneWakingHourIn, 8);
      expect(c.booksPerYear, 91);
    });

    test('formats durations and big numbers', () {
      expect(formatDuration(0), '0m');
      expect(formatDuration(45 * _min), '45m');
      expect(formatDuration(2 * _hour), '2h');
      expect(formatDuration(134 * _min), '2h 14m');
      expect(groupDigits(1095.4), '1,095');
    });

    test('average skips days the phone has no data for', () {
      final s = UsageSummary(
        granted: true,
        hourly: _hourly([0, 0, _hour, 3 * _hour, 0]),
        hasData: const [false, false, true, true, true],
      );
      expect(s.averageMs, 2 * _hour);
      expect(s.finishedDaysWithData, 2);
    });

    test('needs three real days before it has a baseline', () {
      final few = UsageSummary(
        granted: true,
        hourly: _hourly([_hour, _hour, 0]),
        hasData: const [true, true, true],
      );
      expect(few.measureBaseline(DateTime(2026, 1, 8)), isNull);
    });

    test('saved compares with the typical amount by this hour', () {
      final now = DateTime(2026, 1, 8, 15);
      final today = UsageSummary(
        granted: true,
        hourly: _hourly([2 * _hour, 2 * _hour, 2 * _hour, 30 * _min]),
        hasData: const [true, true, true, true],
      );
      final baseline = today.measureBaseline(now)!;
      expect(baseline.totalMs, 2 * _hour);
      // The hour of use is before noon: none typical by 9:00, all by 15:00.
      expect(baseline.at(DateTime(2026, 1, 8, 9)), 0);
      expect(baseline.at(DateTime(2026, 1, 8, 11, 30)), _hour);
      expect(baseline.at(now), 2 * _hour);
      expect(today.savedTodayMs(baseline, DateTime(2026, 1, 8, 9)), 0);
      expect(today.savedTodayMs(baseline, now), 90 * _min);
    });

    test('only days since the baseline count as saved', () {
      final now = DateTime(2026, 1, 8, 23, 59);
      final s = UsageSummary(
        granted: true,
        hourly: _hourly([_hour, _hour, _hour, 2 * _hour]),
        hasData: const [true, true, true, true],
      );
      final curve = List<int>.generate(24, (h) => h < 11 ? 0 : 3 * _hour);
      final taken2DaysAgo = UsageBaseline(
        day: dayNumber(now) - 2,
        curve: curve,
      );
      // Today 1h, plus 2h from each of the two finished days since then.
      expect(s.savedWeekMs(taken2DaysAgo, now), 5 * _hour);
      final takenToday = UsageBaseline(day: dayNumber(now), curve: curve);
      expect(s.savedWeekMs(takenToday, now), _hour);
    });

    test('the baseline is kept once saved', () async {
      final b = UsageBaseline(
        day: 100,
        curve: List<int>.generate(24, (h) => h * 1000),
      );
      await b.save();
      final loaded = await UsageBaseline.load();
      expect(loaded?.day, 100);
      expect(loaded?.curve, b.curve);
    });

    test('projecting today uses the pace, and waits when it is early', () {
      final s = UsageSummary(
        granted: true,
        hourly: _hourly([_hour]),
        hasData: const [true],
      );
      // No baseline: 15:00 is halfway through a waking day.
      expect(s.projectedTodayMs(null, DateTime(2026, 1, 1, 15), 0), 2 * _hour);
      // Before 7:00 it trusts the recent daily figure.
      expect(
        s.projectedTodayMs(null, DateTime(2026, 1, 1, 6), 3 * _hour),
        3 * _hour,
      );
      // Never less than what's already been used.
      final curve = List<int>.filled(24, 2 * _hour);
      expect(
        s.projectedTodayMs(
          UsageBaseline(day: 0, curve: curve),
          DateTime(2026, 1, 1, 15),
          0,
        ),
        _hour,
      );
    });

    test('projection uses real data first, then today, then the estimate', () {
      final noPast = UsageSummary(
        granted: true,
        hourly: _hourly([_hour]),
        hasData: const [true],
      );
      expect(noPast.costDaily(3), (_hour, CostSource.today));
      final nothing = UsageSummary(
        granted: true,
        hourly: _hourly([0]),
        hasData: const [false],
      );
      expect(nothing.costDaily(3), (3 * _hour, CostSource.estimate));
      expect(nothing.costDaily(null), (0, CostSource.none));
      final past = UsageSummary(
        granted: true,
        hourly: _hourly([2 * _hour, _hour]),
        hasData: const [true, true],
      );
      expect(past.costDaily(3), (2 * _hour, CostSource.average));
    });
  });

  testWidgets('no usage access: explains and sends to Settings', (
    tester,
  ) async {
    final calls = _mock({'granted': false});
    await _open(tester);
    expect(find.text('See where your time really goes'), findsOneWidget);
    await tester.tap(find.text('Allow usage access'));
    await tester.pump();
    expect(calls.map((c) => c.method), contains('openUsageAccessSettings'));

    // Back and still off: help for Android's restricted settings.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.scrollUntilVisible(
      find.text('Open App info'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Open App info'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('shows today, real savings, the cost and the next 50 years', (
    tester,
  ) async {
    _mock(_data());
    ProgressStore.instance.addLearning(12 * _min);
    await _open(tester);
    // Usual is the measured 3h, even with no estimate; 3h by 15:00, 2h used.
    expect(find.text('Usual by now '), findsOneWidget);
    expect(find.text('3h'), findsWidgets);
    // 2h by 15:00 with all of a usual day's use already past: 2h a day.
    expect(find.text('Screen time today'), findsOneWidget);
    expect(find.text('2h'), findsWidgets);
    await tester.pump(const Duration(seconds: 5));
    expect(find.textContaining('4.2 yrs in life'), findsOneWidget);
    expect(find.text('Saved today'), findsOneWidget);
    expect(find.text('1h'), findsWidgets);
    expect(find.text('12m'), findsOneWidget);
    expect(await UsageBaseline.load(), isNotNull);
    await tester.scrollUntilVisible(
      find.text('Instagram'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.scrollUntilVisible(
      find.text('What it really costs'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.textContaining('At your recent'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('without enough days, saved waits instead of guessing', (
    tester,
  ) async {
    _mock({
      'granted': true,
      'apps': <Object>[],
      'categories': <String, int>{},
      'hourly': _hourly([_hour, 20 * _min]),
      'hasData': [true, true],
    });
    await ProfileStore.instance.setScrollHoursEstimate(5);
    await _open(tester);
    expect(find.text('--'), findsNWidgets(2));
    expect(find.textContaining('1 of 3 days'), findsOneWidget);
    expect(await UsageBaseline.load(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('minutes under one are hidden, not shown as a full bar', (
    tester,
  ) async {
    _mock({
      ..._data(today: 20000),
      'categories': {'other': 20000},
    });
    await _open(tester);
    expect(find.text('Where it went'), findsNothing);
    expect(find.text('Top apps today'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a heavy day fills the gauge and raises the years', (
    tester,
  ) async {
    _mock(_data(today: 12 * _hour));
    await _open(tester);
    expect(find.text('Screen time today'), findsOneWidget);
    expect(find.text('12h'), findsWidgets);
    await tester.pump(const Duration(seconds: 5));
    expect(find.textContaining('25.0 yrs in life'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the gauge scales to a narrow phone, and animates in', (
    tester,
  ) async {
    _mock(_data());
    tester.view.physicalSize = const Size(320 * 3, 640 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.dark),
        home: Scaffold(body: TimeTab(now: DateTime(2026, 1, 1, 15))),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('Screen time today'), findsOneWidget);
    expect(find.byType(Mascot), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a clean day and no history still lays out', (tester) async {
    _mock({
      'granted': true,
      'apps': <Object>[],
      'categories': <String, int>{},
      'hourly': _hourly([0, 0]),
      'hasData': [false, false],
    });
    await _open(tester, height: 640);
    expect(find.text('0m'), findsWidgets);
    expect(find.text('What it really costs'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
