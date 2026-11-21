import 'dart:math' as math;

import 'package:dmonly/services/content_packs.dart';
import 'package:dmonly/services/profile_store.dart';
import 'package:dmonly/services/progress_store.dart';
import 'package:dmonly/services/reels.dart';
import 'package:dmonly/services/seen_content.dart';
import 'package:dmonly/services/taste_store.dart';
import 'package:dmonly/services/vocab.dart';
import 'package:dmonly/services/word_interactions.dart';
import 'package:dmonly/services/word_service.dart';
import 'package:dmonly/ui/app_theme.dart';
import 'package:dmonly/ui/word_flow_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _channel = MethodChannel('com.dmonly.app/words');

VocabWord _word(String word, int level) => VocabWord(
  ShownWord(word: word, meaning: 'm $word', lang: 'en', level: level),
);

void main() {
  group('XP by difficulty', () {
    test('harder content earns more, right or wrong', () {
      expect(xpFor(correct: true), kXpCorrect);
      expect(xpFor(correct: true, difficulty: 2), 15);
      expect(xpFor(correct: true, difficulty: 3), 20);
      expect(xpFor(correct: false), kXpTried);
      expect(xpFor(correct: false, difficulty: 2), 5);
      expect(xpFor(correct: false, difficulty: 3), 6);
      // A bonus grows with the difficulty too.
      expect(xpFor(correct: true, bonus: 20, difficulty: 3), 60);
      expect(kDifficultyNames.values, ['Easy', 'Medium', 'Hard']);
    });
  });

  group('picked difficulty', () {
    late ProgressStore p;
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      p = ProgressStore.instance;
      await p.load();
      p.startTier = 1;
    });

    test('Auto by default; a pick sets the feed and is kept', () async {
      expect(p.chosenTier('en'), isNull);
      expect(p.feedTier('en'), 1);
      await p.setDifficulty('en', 3);
      expect(p.chosenTier('en'), 3);
      expect(p.feedTier('en'), 3);
      // Per subject.
      expect(p.chosenTier('de'), isNull);
      // Survives a restart and goes to the cloud with the subject.
      await p.load();
      expect(p.chosenTier('en'), 3);
      final cloud = p.toCloud()['subjects'] as Map;
      expect((cloud['en'] as Map)['choice'], 3);
      await p.setDifficulty('en', null);
      expect(p.chosenTier('en'), isNull);
      expect(((p.toCloud()['subjects'] as Map)['en'] as Map)['choice'], isNull);
    });

    test('out-of-range picks mean Auto', () async {
      await p.setDifficulty('en', 7);
      expect(p.chosenTier('en'), isNull);
    });

    test('answers at a picked difficulty leave Auto where it was', () async {
      await p.setDifficulty('math', 1);
      for (var i = 0; i < 10; i++) {
        p.record('math', correct: true);
      }
      // Ten right in a row would move Auto up; at a pick they don't.
      expect(p.tierOf('math'), 1);
      expect(p.feedTier('math'), 1);
      await p.setDifficulty('math', null);
      for (var i = 0; i < 20; i++) {
        p.record('math', correct: true);
      }
      // Auto moves again once it is back on.
      expect(p.tierOf('math'), 2);
    });

    test('record uses the difficulty for XP', () {
      expect(p.record('en', correct: true, difficulty: 3).xp, 20);
      expect(p.levelOf('en').xpIntoLevel, 20);
    });

    test('a bad cloud choice is ignored', () async {
      await p.mergeCloud({
        'subjects': {
          'en': {'xp': 50, 'stage': 1, 'choice': 9},
        },
      });
      expect(p.chosenTier('en'), isNull);
      expect(p.levelOf('en').xpIntoLevel, 50);
    });
  });

  group('feed at a picked difficulty', () {
    test('reel difficulty: unknown word levels count as medium', () {
      expect(reelLevel(LearnReel(_word('keen', 1))), 1);
      expect(reelLevel(SpellReel(_word('brave', 3), const [])), 3);
      expect(reelLevel(LearnReel(_word('calm', 0))), 2);
    });

    test('no stretch: the tier above waits until the end', () async {
      SharedPreferences.setMockInitialValues({});
      final seen = SeenContent.instance;
      await seen.load();
      final items = [
        for (var i = 0; i < 30; i++) ('a$i', 1),
        for (var i = 0; i < 30; i++) ('b$i', 2),
      ];
      final out = levelledFeed<(String, int)>(
        items,
        levelOf: (i) => i.$2,
        keyOf: (i) => i.$1,
        tier: 1,
        seen: seen,
        random: math.Random(3),
        stretch: false,
      );
      expect(out.take(30).every((i) => i.$2 == 1), isTrue);
      expect(out.skip(30).every((i) => i.$2 == 2), isTrue);
      expect(out, hasLength(60));
    });

    test('maths without stretch stays on its level', () {
      final reels = buildMathReels(2, math.Random(5), stretch: false);
      expect(reels.every((r) => reelLevel(r) == 2), isTrue);
      final auto = buildMathReels(2, math.Random(5));
      expect(auto.any((r) => reelLevel(r) == 3), isTrue);
    });
  });

  testWidgets('pick a difficulty from the subject sheet or a reel pill', (
    tester,
  ) async {
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
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          _channel,
          (call) async => switch (call.method) {
            'pathWords' => [
              for (final w in ['keen', 'brave', 'calm', 'proud', 'quiet'])
                {'word': w, 'meaning': 'm $w', 'lang': 'en', 'level': 1},
            ],
            _ => null,
          },
        );
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_channel, null),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.light),
        home: const GradientBackground(
          child: Scaffold(body: SafeArea(child: WordFlowTab())),
        ),
      ),
    );
    Future<void> settle() async {
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    await tester.pump(const Duration(milliseconds: 100));
    // The word card says how hard it is, and the pill opens the picker.
    final pill = find.bySemanticsLabel('Easy. Change difficulty');
    expect(pill, findsWidgets);

    // From "What to practise": the difficulty row on top.
    await tester.tap(find.bySemanticsLabel(RegExp('^Change what to practise')));
    await settle();
    expect(find.text('Difficulty: Auto'), findsOneWidget);
    await tester.tap(find.text('Difficulty: Auto'));
    await settle();
    expect(find.text('How hard?'), findsOneWidget);
    expect(find.text('Auto (recommended)'), findsOneWidget);
    expect(find.textContaining('×1.5 XP'), findsOneWidget);
    expect(find.textContaining('×2 XP'), findsOneWidget);
    await tester.tap(find.text('Hard'));
    await settle();

    expect(ProgressStore.instance.chosenTier('en'), 3);
    // Only easy words exist, so the learner is told others fill in.
    expect(find.textContaining('No new Hard ones'), findsOneWidget);

    // From a reel pill: back to Auto.
    await tester.tap(pill.hitTestable().first);
    await settle();
    expect(find.text('How hard?'), findsOneWidget);
    await tester.tap(find.text('Auto (recommended)'));
    await settle();
    expect(ProgressStore.instance.chosenTier('en'), isNull);
    expect(tester.takeException(), isNull);
  });
}
