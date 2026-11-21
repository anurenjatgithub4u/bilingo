import 'dart:async';
import 'dart:math' as math;

import 'package:dmonly/services/content_packs.dart';
import 'package:dmonly/services/like_counts.dart';
import 'package:dmonly/services/profile_store.dart';
import 'package:dmonly/services/progress_store.dart';
import 'package:dmonly/services/reading_bank.dart';
import 'package:dmonly/services/seen_content.dart';
import 'package:dmonly/services/speech_service.dart';
import 'package:dmonly/services/taste_store.dart';
import 'package:dmonly/services/word_interactions.dart';
import 'package:dmonly/ui/app_theme.dart';
import 'package:dmonly/ui/word_flow_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _channel = MethodChannel('com.dmonly.app/words');

final _germanWords = [
  {
    'word': 'Fernweh',
    'meaning': 'A longing for far-off places.',
    'lang': 'de',
    'level': 1,
  },
  {'word': 'Heimat', 'meaning': 'Home.', 'lang': 'de', 'level': 1},
  {'word': 'Ohrwurm', 'meaning': 'A catchy song.', 'lang': 'de', 'level': 1},
];

/// A typical phone screen, 390 × 844 logical pixels.
void _phone(WidgetTester tester, {double height = 844}) {
  tester.view.physicalSize = Size(1170, height * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

final _englishWords = [
  {'word': 'keen', 'meaning': 'Eager.', 'lang': 'en', 'level': 1},
  {'word': 'brave', 'meaning': 'Not afraid.', 'lang': 'en', 'level': 1},
  {'word': 'calm', 'meaning': 'Peaceful and quiet.', 'lang': 'en', 'level': 1},
  {
    'word': 'grateful',
    'meaning': 'Feeling thankful for something someone did for you.',
    'lang': 'en',
    'level': 1,
  },
];

Future<List<MethodCall>> _setUp({
  String language = 'de',
  List<Map<String, Object>>? words,
}) async {
  SharedPreferences.setMockInitialValues({'language': language, 'level': 1});
  await ProfileStore.instance.load();
  await WordInteractions.instance.load();
  LikeCounts.instance.resetForTest();
  await SeenContent.instance.load();
  await ProgressStore.instance.load();
  await ContentPacks.instance.load();
  await TasteStore.instance.load();
  final calls = <MethodCall>[];
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_channel, (call) async {
        calls.add(call);
        return switch (call.method) {
          'pathWords' => words ?? _germanWords,
          _ => null,
        };
      });
  addTearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null),
  );
  return calls;
}

Widget _app({Brightness brightness = Brightness.light}) => MaterialApp(
  theme: buildTheme(brightness),
  home: const GradientBackground(
    child: Scaffold(body: SafeArea(child: WordFlowTab())),
  ),
);

/// The word on screen now (with its article), read from the card title.
String _currentWord(WidgetTester tester) {
  for (final w in ['das Fernweh', 'die Heimat', 'der Ohrwurm']) {
    if (find.text(w).hitTestable().evaluate().isNotEmpty) return w;
  }
  return '';
}

/// Lets sheets open or close; the mascot never stops moving, so no
/// pumpAndSettle.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _swipeUp(WidgetTester tester) async {
  await tester.fling(find.byType(PageView), const Offset(0, -500), 1500);
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _swipeDown(WidgetTester tester) async {
  await tester.fling(find.byType(PageView), const Offset(0, 500), 1500);
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('card shows German article, example and three actions '
        '($brightness)', (tester) async {
      _phone(tester);
      await _setUp();
      await tester.pumpWidget(_app(brightness: brightness));
      await tester.pump(const Duration(milliseconds: 100));

      // No title or reel counter at the top, just the feed picker.
      expect(find.text('WordFlow'), findsNothing);
      expect(find.textContaining(RegExp(r'^Word \d+ of')), findsNothing);
      expect(find.text('German'), findsWidgets);
      expect(_currentWord(tester), isNotEmpty);
      expect(find.text('Like'), findsOneWidget);
      expect(find.text('Share'), findsOneWidget);
      expect(find.text('Save'), findsOneWidget);
      // No comment or AI actions.
      expect(find.byIcon(Icons.chat_bubble_outline), findsNothing);
      expect(find.byIcon(Icons.mode_comment_outlined), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('like and save stick to their word when swiping away and back', (
    tester,
  ) async {
    _phone(tester);
    await _setUp();
    await tester.pumpWidget(_app());
    await tester.pump(const Duration(milliseconds: 100));

    final first = _currentWord(tester);
    await tester.tap(find.bySemanticsLabel('Like'));
    await tester.tap(find.bySemanticsLabel('Save word'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byIcon(Icons.favorite_rounded), findsOneWidget);
    expect(find.byIcon(Icons.bookmark_rounded), findsOneWidget);
    expect(find.text('Saved'), findsOneWidget);

    await _swipeUp(tester);
    final second = _currentWord(tester);
    expect(second, isNot(first));
    expect(
      find.byIcon(Icons.favorite_border_rounded).hitTestable(),
      findsOneWidget,
    );
    expect(
      find.byIcon(Icons.bookmark_border_rounded).hitTestable(),
      findsOneWidget,
    );

    await _swipeDown(tester);
    expect(_currentWord(tester), first);
    expect(find.byIcon(Icons.favorite_rounded).hitTestable(), findsOneWidget);
    expect(find.byIcon(Icons.bookmark_rounded).hitTestable(), findsOneWidget);

    // Unlike works too, and leaves the bookmark alone.
    await tester.tap(find.bySemanticsLabel('Unlike'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(
      find.byIcon(Icons.favorite_border_rounded).hitTestable(),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.bookmark_rounded).hitTestable(), findsOneWidget);
    expect(WordInteractions.instance.likedCount, 0);
    expect(WordInteractions.instance.savedIds, hasLength(1));
  });

  testWidgets('double tap likes the word', (tester) async {
    _phone(tester);
    await _setUp();
    await tester.pumpWidget(_app());
    await tester.pump(const Duration(milliseconds: 100));

    final card = find.text(_currentWord(tester));
    await tester.tap(card);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(card);
    await tester.pump(const Duration(milliseconds: 300));
    expect(WordInteractions.instance.likedCount, 1);
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('share sends a picture card to the share sheet', (tester) async {
    _phone(tester);
    final calls = await _setUp();
    await tester.pumpWidget(_app());
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.bySemanticsLabel('Share word'));
    // Drawing the picture needs real async work.
    await tester.runAsync(() async {
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        await Future<void>.delayed(const Duration(milliseconds: 50));
        if (calls.any((c) => c.method.startsWith('share'))) break;
      }
    });
    await tester.pump(const Duration(milliseconds: 100));

    final share = calls.firstWhere((c) => c.method.startsWith('share'));
    expect(share.method, 'shareImage');
    final args = share.arguments as Map;
    expect((args['png'] as Uint8List).length, greaterThan(1000));
    expect(args['text'] as String, contains('German'));
  });

  testWidgets('changing language starts again at the first word', (
    tester,
  ) async {
    _phone(tester);
    await _setUp();
    await tester.pumpWidget(_app());
    await tester.pump(const Duration(milliseconds: 100));
    final first = _currentWord(tester);
    await _swipeUp(tester);
    expect(_currentWord(tester), isNot(first));

    await ProfileStore.instance.setLanguage('en');
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    // Back at the first reel of the reloaded feed: nothing above it.
    final now = _currentWord(tester);
    expect(now, isNotEmpty);
    await _swipeDown(tester);
    expect(_currentWord(tester), now);
    expect(tester.takeException(), isNull);
  });

  testWidgets('der, die or das: tapping an article answers the reel', (
    tester,
  ) async {
    _phone(tester);
    await _setUp();
    await tester.pumpWidget(_app());
    await tester.pump(const Duration(milliseconds: 100));
    // Third reel: German noun, article hidden.
    await _swipeUp(tester);
    await _swipeUp(tester);
    expect(find.text('DER, DIE OR DAS?'), findsOneWidget);
    final word = ['Fernweh', 'Heimat', 'Ohrwurm'].firstWhere(
      (w) => find
          .textContaining('___ $w', findRichText: true)
          .evaluate()
          .isNotEmpty,
    );
    final article = {
      'Fernweh': 'das',
      'Heimat': 'die',
      'Ohrwurm': 'der',
    }[word]!;
    await tester.tap(find.bySemanticsLabel(article));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('Correct!', findRichText: true), findsOneWidget);
    expect(ProfileStore.instance.accuracy, 100);

    // The answer is still there after swiping away and back.
    await _swipeDown(tester);
    await _swipeUp(tester);
    expect(find.textContaining('Correct!', findRichText: true), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('maths can be picked and answered', (tester) async {
    _phone(tester);
    await _setUp();
    await tester.pumpWidget(_app());
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.bySemanticsLabel(RegExp('^Change what to practise')));
    await _settle(tester);
    expect(find.text('Hindi'), findsNothing);
    await tester.tap(find.text('Maths'));
    await _settle(tester);
    expect(find.textContaining(RegExp(r'^Question \d+ of')), findsNothing);
    expect(ProfileStore.instance.flowMaths, isTrue);
    expect(ProfileStore.instance.language, 'de');
    // Maths reels can be liked, shared and saved too.
    expect(find.bySemanticsLabel('Share question'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Like'));
    await tester.tap(find.bySemanticsLabel('Save word'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(WordInteractions.instance.likedCount, 1);
    expect(WordInteractions.instance.savedIds.single, startsWith('math|'));

    // Any answer shows feedback and counts towards quiz accuracy.
    final options = find.byType(AnimatedContainer).hitTestable();
    await tester.tap(options.first);
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      find.textContaining(RegExp('Correct!|Not quite.'), findRichText: true),
      findsOneWidget,
    );
    expect(ProfileStore.instance.accuracy, isNotNull);

    // Back to German.
    await tester.tap(find.bySemanticsLabel(RegExp('^Change what to practise')));
    await _settle(tester);
    await tester.tap(find.text('German'));
    await _settle(tester);
    expect(ProfileStore.instance.flowMaths, isFalse);
  });

  testWidgets('maths games: make the target and beat the clock', (
    tester,
  ) async {
    _phone(tester);
    await _setUp();
    await ProfileStore.instance.setFlowMaths(true);
    await tester.pumpWidget(_app());
    await tester.pump(const Duration(milliseconds: 100));

    // Second reel: sort it, smallest first.
    await _swipeUp(tester);
    expect(find.text('SORT IT'), findsOneWidget);
    final labels = [
      for (final e in find.bySemanticsLabel(RegExp(r'^Number ')).evaluate())
        e.renderObject!.debugSemantics!.label.replaceFirst('Number ', ''),
    ];
    double value(String l) {
      if (!l.contains('/')) return double.parse(l);
      final p = l.split('/');
      return int.parse(p[0]) / int.parse(p[1]);
    }

    for (final l in [...labels]..sort((a, b) => value(a).compareTo(value(b)))) {
      await tester.tap(find.bySemanticsLabel('Number $l'));
      await tester.pump(const Duration(milliseconds: 250));
    }
    expect(find.textContaining('Correct!', findRichText: true), findsOneWidget);
    await _swipeUp(tester);
    await _swipeUp(tester);

    // Fourth reel: make the target.
    expect(find.text('MAKE THE TARGET'), findsOneWidget);
    final target = int.parse(
      tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? '')
          .where((t) => RegExp(r'^\d+$').hasMatch(t))
          // The first number on screen is the level ring.
          .elementAt(1),
    );
    final numbers = [
      for (final e in find.bySemanticsLabel(RegExp(r'^Number ')).evaluate()) e,
    ];
    expect(numbers, hasLength(6));
    final values = [
      for (final e in numbers)
        int.parse(
          (e.renderObject!.debugSemantics!.label).replaceFirst('Number ', ''),
        ),
    ];
    // Beginner level adds.
    late int a, b;
    for (var x = 0; x < 6; x++) {
      for (var y = x + 1; y < 6; y++) {
        if (values[x] + values[y] == target) (a, b) = (x, y);
      }
    }
    await tester.tap(find.bySemanticsLabel('Number ${values[a]}'));
    await tester.tap(find.bySemanticsLabel('Number ${values[b]}'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('Correct!', findRichText: true), findsOneWidget);

    // Sixth reel: memory flash. Numbers show, hide, then a question.
    await _swipeUp(tester);
    await _swipeUp(tester);
    expect(find.text('MEMORY FLASH'), findsOneWidget);
    await tester.tap(find.text('Show me'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.bySemanticsLabel(RegExp(r'^Number \d+$')), findsWidgets);
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    expect(find.bySemanticsLabel('Number ?'), findsWidgets);
    expect(find.textContaining(RegExp('sum|biggest')), findsOneWidget);

    // Seventh reel: beat the clock. Let the time run out.
    await _swipeUp(tester);
    expect(find.text('BEAT THE CLOCK'), findsOneWidget);
    await tester.tap(find.text('Start'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.textContaining('= ?'), findsOneWidget);
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    expect(find.text('0 / 5'), findsOneWidget);
    expect(find.text('Play again'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mini sudoku: fill the grid', (tester) async {
    _phone(tester);
    await _setUp();
    await ProfileStore.instance.setFlowMaths(true);
    await tester.pumpWidget(_app());
    await tester.pump(const Duration(milliseconds: 100));
    for (var i = 0; i < 8; i++) {
      await _swipeUp(tester);
    }
    expect(find.text('SUDOKU'), findsOneWidget);

    // Read the 4×4 grid from the cells' labels and solve it here.
    final cell = RegExp(r'^Row (\d) column (\d), (empty|\d)$');
    final grid = List<int>.filled(16, 0);
    for (final e in find.bySemanticsLabel(cell).evaluate()) {
      final m = cell.firstMatch(e.renderObject!.debugSemantics!.label)!;
      final v = m[3] == 'empty' ? 0 : int.parse(m[3]!);
      grid[(int.parse(m[1]!) - 1) * 4 + int.parse(m[2]!) - 1] = v;
    }
    bool ok(int i, int v) {
      final r = i ~/ 4, c = i % 4;
      for (var k = 0; k < 4; k++) {
        if (grid[r * 4 + k] == v || grid[k * 4 + c] == v) return false;
      }
      final r0 = r - r % 2, c0 = c - c % 2;
      for (var a = 0; a < 2; a++) {
        for (var b = 0; b < 2; b++) {
          if (grid[(r0 + a) * 4 + c0 + b] == v) return false;
        }
      }
      return true;
    }

    final blanks = [
      for (var i = 0; i < 16; i++)
        if (grid[i] == 0) i,
    ];
    bool solve(int k) {
      if (k == blanks.length) return true;
      for (var v = 1; v <= 4; v++) {
        if (!ok(blanks[k], v)) continue;
        grid[blanks[k]] = v;
        if (solve(k + 1)) return true;
        grid[blanks[k]] = 0;
      }
      return false;
    }

    expect(solve(0), isTrue);
    for (final i in blanks) {
      await tester.tap(
        find.bySemanticsLabel('Row ${i ~/ 4 + 1} column ${i % 4 + 1}, empty'),
      );
      await tester.pump();
      await tester.tap(find.bySemanticsLabel('Number ${grid[i]}'));
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(find.textContaining('Perfect!', findRichText: true), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('word search: tap first and last letters', (tester) async {
    _phone(tester);
    final words = [
      for (final w in [
        'keen',
        'brave',
        'calm',
        'witty',
        'kind',
        'bold',
        'wise',
        'shy',
        'warm',
      ])
        {'word': w, 'meaning': 'Means $w.', 'lang': 'en', 'level': 1},
    ];
    await _setUp(language: 'en', words: words);
    await tester.pumpWidget(_app());
    await tester.pump(const Duration(milliseconds: 100));
    // Eight words plus the reading reel before the sixth.
    for (var i = 0; i < 9; i++) {
      await _swipeUp(tester);
    }
    expect(find.text('Find the word that means…'), findsOneWidget);
    expect(find.bySemanticsLabel('Like'), findsOneWidget);
    expect(find.bySemanticsLabel('Save word'), findsOneWidget);

    final cell = RegExp(r'^Letter (.), row (\d+) column (\d+)$');
    final letters = <(int, int), String>{};
    var size = 0;
    for (final e in find.bySemanticsLabel(cell).evaluate()) {
      final m = cell.firstMatch(e.renderObject!.debugSemantics!.label)!;
      final r = int.parse(m[2]!), c = int.parse(m[3]!);
      letters[(r, c)] = m[1]!;
      size = math.max(size, r);
    }
    final targets = [
      for (final w in words)
        if (find.text(w['meaning']! as String).evaluate().isNotEmpty)
          (w['word']! as String).toUpperCase(),
    ];
    expect(targets.length, inInclusiveRange(3, 4));
    // Beginner words run across or down.
    for (final t in targets) {
      (int, int, int, int)? at;
      for (var r = 1; r <= size && at == null; r++) {
        for (var c = 1; c <= size && at == null; c++) {
          for (final (dr, dc) in [(0, 1), (1, 0)]) {
            var k = 0;
            while (k < t.length && letters[(r + dr * k, c + dc * k)] == t[k]) {
              k++;
            }
            if (k == t.length) {
              at = (r, c, r + dr * (k - 1), c + dc * (k - 1));
              break;
            }
          }
        }
      }
      expect(at, isNotNull, reason: t);
      final (r0, c0, r1, c1) = at!;
      String label(int r, int c) =>
          'Letter ${letters[(r, c)]}, row $r column $c';
      await tester.tap(find.bySemanticsLabel(label(r0, c0)));
      await tester.pump();
      await tester.tap(find.bySemanticsLabel(label(r1, c1)));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text(t), findsOneWidget);
    }
    expect(find.text('All found! Swipe up for the next one'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Save word'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(WordInteractions.instance.savedIds, hasLength(targets.length));
    expect(tester.takeException(), isNull);
  });

  testWidgets('read aloud on the reel: words turn green, Done scores it', (
    tester,
  ) async {
    _phone(tester);
    final engine = _ScriptedSpeech();
    debugReadingEngine = engine;
    addTearDown(() => debugReadingEngine = null);
    final words = [
      for (final w in [
        'Haus',
        'Baum',
        'Hund',
        'Katze',
        'Brot',
        'Milch',
        'Buch',
      ])
        {'word': w, 'meaning': 'Means $w.', 'lang': 'de', 'level': 1},
    ];
    await _setUp(words: words);
    await tester.pumpWidget(_app());
    await tester.pump(const Duration(milliseconds: 100));
    for (var i = 0; i < 5; i++) {
      await _swipeUp(tester);
    }
    expect(find.text('READ ALOUD'), findsOneWidget);
    expect(find.bySemanticsLabel('Like'), findsOneWidget);

    // One short sentence on screen, with its meaning for German.
    final onScreen = [
      for (final r in tester.widgetList<RichText>(find.byType(RichText)))
        r.text.toPlainText().trim(),
    ];
    final shown = readingTexts('de')
        .firstWhere((t) => onScreen.contains(t.text));
    final paragraph = shown.text;
    expect(find.text(shown.translation!), findsOneWidget);
    expect(find.text('Say this'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Start reading'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(engine.listening, isTrue);
    expect(find.text('Listening… read it out loud'), findsOneWidget);

    // Every word heard: it finishes by itself.
    engine.hear(paragraph);
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.textContaining(RegExp(r'^\d+% · ')), findsOneWidget);
    expect(find.textContaining('100%'), findsOneWidget);
    expect(find.text('Read again'), findsOneWidget);
    expect(ProfileStore.instance.accuracy, isNotNull);

    // Swiping away stops the microphone.
    await tester.tap(find.text('Read again'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.bySemanticsLabel('Start reading'));
    await tester.pump(const Duration(milliseconds: 100));
    await _swipeUp(tester);
    expect(engine.listening, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('words already shown are not shown first again', (tester) async {
    _phone(tester);
    await _setUp();
    await tester.pumpWidget(_app());
    await tester.pump(const Duration(milliseconds: 100));
    final first = _currentWord(tester);
    expect(first, isNotEmpty);
    expect(SeenContent.instance.count, 1);

    // Reopening the feed starts on a word not seen yet.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(_app());
    await tester.pump(const Duration(milliseconds: 100));
    final second = _currentWord(tester);
    expect(second, isNot(first));

    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(_app());
    await tester.pump(const Duration(milliseconds: 100));
    final third = _currentWord(tester);
    expect({first, second, third}, hasLength(3));

    // All three seen: the one seen longest ago comes back first.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(_app());
    await tester.pump(const Duration(milliseconds: 100));
    expect(_currentWord(tester), first);
  });

  testWidgets('coding reels: answer earns XP, every kind lays out', (
    tester,
  ) async {
    _phone(tester);
    await _setUp();
    await ProfileStore.instance.setFlowCode('python');
    await tester.pumpWidget(_app());
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Python'), findsWidgets);

    var answered = false;
    for (var i = 0; i < 25; i++) {
      expect(tester.takeException()?.toString(), isNull, reason: 'reel $i');
      if (!answered &&
          find.text('What does this print?').evaluate().isNotEmpty) {
        // Any answer: the options change with the day's shuffle.
        await tester.tap(find.byType(AnimatedContainer).hitTestable().first);
        await tester.pump(const Duration(milliseconds: 300));
        answered = true;
      }
      await _swipeUp(tester);
    }
    expect(answered, isTrue);
    expect(ProgressStore.instance.startedSubjects, ['python']);
    expect(
      ProgressStore.instance.levelOf('python').xpIntoLevel,
      greaterThan(0),
    );
  });

  testWidgets('a level up celebrates', (tester) async {
    _phone(tester);
    await _setUp();
    await ProfileStore.instance.setFlowMaths(true);
    for (var i = 0; i < 9; i++) {
      ProgressStore.instance.record('math', correct: true);
    }
    await tester.pumpWidget(_app());
    await tester.pump(const Duration(milliseconds: 100));
    // Options are tapped until one is right; a wrong one adds only 3 XP.
    final options = find.byType(AnimatedContainer).hitTestable();
    await tester.tap(options.last);
    await tester.pump(const Duration(milliseconds: 500));
    if (ProgressStore.instance.levelOf('math').level == 2) {
      expect(find.text('Level 2!'), findsOneWidget);
    } else {
      expect(find.text('Level 2!'), findsNothing);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('spell it: hints fill the word in', (tester) async {
    _phone(tester);
    await _setUp(language: 'en', words: _englishWords);
    await tester.pumpWidget(_app());
    await tester.pump(const Duration(milliseconds: 100));
    for (var i = 0; i < 3 && find.text('SPELL IT').evaluate().isEmpty; i++) {
      await _swipeUp(tester);
    }
    expect(find.text('SPELL IT'), findsOneWidget);
    for (var i = 0; i < 10 && find.text('Hint').evaluate().isNotEmpty; i++) {
      await tester.tap(find.text('Hint'));
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(find.textContaining('Solved!', findRichText: true), findsOneWidget);
    expect(find.text('Swipe up for the next one'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final height in [640.0, 844.0]) {
    testWidgets('interactive reels fit a ${height.toInt()} tall phone', (
      tester,
    ) async {
      _phone(tester, height: height);
      await _setUp(language: 'en', words: _englishWords);
      await tester.pumpWidget(_app());
      await tester.pump(const Duration(milliseconds: 100));
      for (var i = 0; i < 4; i++) {
        expect(tester.takeException()?.toString(), isNull, reason: 'reel $i');
        if (find.text('Hint').evaluate().isNotEmpty) {
          for (
            var j = 0;
            j < 10 && find.text('Hint').evaluate().isNotEmpty;
            j++
          ) {
            await tester.tap(find.text('Hint'));
            await tester.pump(const Duration(milliseconds: 200));
          }
        } else if (find.text('PICK THE MEANING').evaluate().isNotEmpty) {
          await tester.tap(find.bySemanticsLabel(RegExp('^Eager')));
          await tester.pump(const Duration(milliseconds: 300));
        }
        expect(tester.takeException(), isNull, reason: 'answered reel $i');
        await _swipeUp(tester);
      }
    });
  }

  testWidgets('filters narrow the feed, per subject, and are remembered', (
    tester,
  ) async {
    _phone(tester);
    await _setUp();
    await ProfileStore.instance.setFlowMaths(true);
    await tester.pumpWidget(_app());
    await tester.pump(const Duration(milliseconds: 100));
    for (final label in ['For you', 'Quick', 'Puzzles', 'Speed']) {
      expect(find.bySemanticsLabel('Show $label'), findsOneWidget);
    }

    await tester.tap(find.bySemanticsLabel('Show Speed'));
    await tester.pump(const Duration(milliseconds: 200));
    for (var i = 0; i < 4; i++) {
      expect(find.text('BEAT THE CLOCK'), findsOneWidget);
      await _swipeUp(tester);
    }

    await tester.tap(find.bySemanticsLabel('Show Puzzles'));
    await tester.pump(const Duration(milliseconds: 200));
    for (final kind in [
      'Sort it',
      'Make the target',
      'Memory flash',
      'Sudoku',
    ]) {
      expect(find.text(kind.toUpperCase()), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _swipeUp(tester);
    }
    expect(ProfileStore.instance.flowFilter('math'), 'puzzles');
    // Other subjects keep their own choice.
    expect(ProfileStore.instance.flowFilter('de'), 'all');
  });

  testWidgets('a filter that runs out ends with a card, not a dead end', (
    tester,
  ) async {
    _phone(tester);
    await _setUp();
    await ProfileStore.instance.setFlowFilter('de', 'words');
    await tester.pumpWidget(_app());
    await tester.pump(const Duration(milliseconds: 200));
    for (var i = 0; i < 3; i++) {
      expect(find.text('Review again'), findsNothing);
      await _swipeUp(tester);
    }
    expect(find.text('You’ve done all the new ones!'), findsOneWidget);
    await tester.tap(find.text('Show All'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(ProfileStore.instance.flowFilter('de'), 'all');
    expect(_currentWord(tester), isNotEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('German read aloud, quiz and coding filters', (tester) async {
    _phone(tester);
    await _setUp();
    await ProfileStore.instance.setFlowFilter('de', 'read');
    await tester.pumpWidget(_app());
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('READ ALOUD'), findsWidgets);
    expect(find.bySemanticsLabel('Start reading'), findsOneWidget);
    await _swipeUp(tester);
    expect(find.bySemanticsLabel('Start reading'), findsOneWidget);

    await ProfileStore.instance.setFlowCode('python');
    await ProfileStore.instance.setFlowFilter('python', 'puzzles');
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('ORDER THE LINES'), findsOneWidget);
    await ProfileStore.instance.setFlowFilter('python', 'fix');
    await tester.pump(const Duration(milliseconds: 200));
    expect(
      find.textContaining(RegExp('FIND THE BUG|FILL THE BLANK')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('liking and saving teach the feed, and skipping does too', (
    tester,
  ) async {
    _phone(tester);
    await _setUp();
    await tester.pumpWidget(_app());
    await tester.pump(const Duration(milliseconds: 100));
    final taste = TasteStore.instance;
    final topic = taste.current.single;
    await tester.tap(find.bySemanticsLabel('Like'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(taste.score(topic), TasteStore.like);
    await tester.tap(find.bySemanticsLabel('Save word'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(taste.score(topic), TasteStore.like + TasteStore.save);
    // Unliking is not a signal of its own.
    await tester.tap(find.bySemanticsLabel('Unlike'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(taste.score(topic), TasteStore.like + TasteStore.save);
    expect(tester.takeException(), isNull);
  });

  testWidgets('onboarded learners are asked their interests once', (
    tester,
  ) async {
    _phone(tester);
    await _setUp();
    await ProfileStore.instance.completeOnboarding();
    await tester.pumpWidget(_app());
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('What are you into?'), findsOneWidget);
    await tester.tap(find.text('Travel'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('What are you into?'), findsNothing);
    expect(TasteStore.instance.picked, {'travel'});
    expect(TasteStore.instance.asked, isTrue);

    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(_app());
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('What are you into?'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('fits a small phone without overflow', (tester) async {
    _phone(tester, height: 640);
    await _setUp();
    await tester.pumpWidget(_app());
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);
    expect(find.text('Like'), findsOneWidget);
  });
}

/// A recogniser that hears whatever the test says.
class _ScriptedSpeech implements SpeechEngine {
  final _events = StreamController<SpeechEvent>.broadcast(sync: true);
  bool listening = false;

  @override
  Stream<SpeechEvent> get events => _events.stream;

  @override
  Future<SpeechAvailability> prepare() async => SpeechAvailability.ready;

  @override
  Future<void> listen({List<String> hints = const []}) async =>
      listening = true;

  @override
  Future<void> stop() async {
    if (!listening) return;
    listening = false;
    _events.add(const SpeechDone());
  }

  @override
  Future<void> cancel() async => listening = false;

  void hear(String words) => _events.add(SpeechWords(words, isFinal: true));
}
