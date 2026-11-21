import 'package:dmonly/services/profile_store.dart';
import 'package:dmonly/services/progress_store.dart';
import 'package:dmonly/ui/app_theme.dart';
import 'package:dmonly/ui/mascot.dart';
import 'package:dmonly/ui/path_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({'language': 'en', 'level': 1});
    await ProfileStore.instance.load();
    await ProgressStore.instance.load();
  });

  test('the officer is the default character, and a pick is kept', () async {
    final store = ProfileStore.instance;
    expect(store.mascot, MascotStyle.police);
    await store.setMascot(MascotStyle.ghost);
    await store.load();
    expect(store.mascot, MascotStyle.ghost);
    expect((store.toCloud()['settings'] as Map)['mascot'], 'ghost');
  });

  testWidgets('both characters draw every mood', (tester) async {
    for (final style in MascotStyle.values) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Wrap(
              children: [
                for (final m in <GhostMood?>[null, ...GhostMood.values])
                  Mascot(size: 80, mood: m, style: style),
              ],
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 1500));
      expect(tester.takeException(), isNull, reason: style.name);
    }
  });

  testWidgets('the profile setting switches the character', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: Mascot(size: 100))),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await ProfileStore.instance.setMascot(MascotStyle.ghost);
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
  });

  test('a word answered right on schedule counts as known', () {
    var now = DateTime(2026, 3, 1);
    ProgressStore.clock = () => now;
    addTearDown(() => ProgressStore.clock = DateTime.now);
    final p = ProgressStore.instance;
    expect(p.isKnown('en|keen'), isFalse);
    p.record('en', correct: true, wordId: 'en|keen');
    now = DateTime(2026, 3, 2);
    p.record('en', correct: true, wordId: 'en|keen');
    expect(p.isKnown('en|keen'), isTrue);
  });

  testWidgets('coding learners get their level road, not English words', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await ProfileStore.instance.setFlowCode('javascript');
    for (var i = 0; i < 12; i++) {
      ProgressStore.instance.record('javascript', correct: true);
    }
    var practised = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.light),
        home: Scaffold(body: PathTab(onPractise: () => practised = true)),
      ),
    );
    await _settle(tester);

    expect(find.text('Everyday words'), findsNothing);
    expect(find.text('JavaScript'), findsOneWidget);
    expect(find.text('LEVEL 2 · BEGINNER'), findsOneWidget);
    expect(find.text('20 / 115 XP to level 3'), findsOneWidget);
    expect(find.text('12'), findsOneWidget); // questions solved

    // The current stop sends the learner off to practise.
    await tester.tap(find.byKey(const ValueKey('level2')));
    await _settle(tester);
    expect(find.text('PRACTISE'), findsOneWidget);
    await tester.tap(find.text('PRACTISE'));
    await _settle(tester);
    expect(practised, isTrue);
    expect(tester.takeException(), isNull);
  });

  test('every screen shares one streak', () {
    expect(sharedStreak(4), 4);
    ProgressStore.instance.record('math', correct: true);
    expect(sharedStreak(0), 1);
    expect(subjectName('javascript'), 'JavaScript');
    expect(subjectName('math'), 'Maths');
    expect(subjectName('de'), 'German');
  });
}
