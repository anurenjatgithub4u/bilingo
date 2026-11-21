import 'dart:math' as math;

import 'package:dmonly/services/content_packs.dart';
import 'package:dmonly/services/progress_store.dart';
import 'package:dmonly/services/reading_bank.dart';
import 'package:dmonly/services/reels.dart';
import 'package:dmonly/services/seen_content.dart';
import 'package:dmonly/services/taste_store.dart';
import 'package:dmonly/services/vocab.dart';
import 'package:dmonly/services/word_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

VocabWord _word(String lang, String word, [String meaning = 'm']) =>
    VocabWord(ShownWord(word: word, meaning: '$meaning $word', lang: lang));

void main() {
  test('word feed mixes learn, meaning, article and spelling reels', () {
    final words = [
      for (final w in [
        'Fernweh',
        'Heimat',
        'Ohrwurm',
        'Freundschaft',
        'Augenblick',
        'Hilfsbereit',
        'Aufwiedersehen',
        'Gemütlichkeit',
      ])
        _word('de', w),
    ];
    final reels = buildWordReels(words, math.Random(1));
    expect(reels.where((r) => r is! WordSearchReel), hasLength(words.length));
    expect(reels.first, isA<LearnReel>());
    expect(reels.whereType<MeaningReel>(), isNotEmpty);
    expect(reels.whereType<ArticleReel>(), isNotEmpty);
    expect(reels.map((r) => r.id).toSet(), hasLength(reels.length));
    for (final r in reels.whereType<ArticleReel>()) {
      expect(r.options[r.answer], r.word.article);
    }
    for (final r in reels.whereType<MeaningReel>()) {
      expect(r.options, hasLength(4));
      expect(r.options[r.answer], r.word.meaning);
      expect(r.options.toSet(), hasLength(4));
    }
  });

  test('spelling reels use only the word’s own letters', () {
    final words = [
      for (final w in ['keen', 'brave', 'calm', 'eager', 'joyful'])
        _word('en', w),
    ];
    final spell = buildWordReels(
      words,
      math.Random(2),
    ).whereType<SpellReel>().toList();
    expect(spell, isNotEmpty);
    for (final r in spell) {
      expect([...r.letters]..sort(), r.target.split('')..sort());
    }
    expect(canSpell(_word('de', 'Aufwiedersehen')), isFalse);
    expect(canSpell(_word('de', 'Straße')), isFalse);
  });

  test('maths questions always have exactly one right answer', () {
    for (final level in [1, 2, 3]) {
      final all = buildMathReels(level, math.Random(level));
      expect(all, hasLength(120));
      expect(
        all.take(60).every((r) => (r as MathsItem).level == level),
        isTrue,
      );
      expect(all.map((r) => r.id).toSet(), hasLength(120));
      expect(all.whereType<TargetReel>(), isNotEmpty);
      expect(all.whereType<BlitzReel>(), isNotEmpty);
      final reels = [
        ...all.whereType<MathReel>(),
        for (final b in all.whereType<BlitzReel>()) ...b.questions,
      ];
      for (final r in reels) {
        expect(r.answer, inInclusiveRange(0, r.options.length - 1));
        expect(
          r.options.toSet(),
          hasLength(r.options.length),
          reason: r.prompt,
        );
        expect(r.options.length, anyOf(2, 3, 4));
      }
    }
  });

  test('simple maths answers are right', () {
    final gen = MathGenerator(math.Random(7));
    final ops = RegExp(r'^(\d+) ([+−×÷]) (\d+) = \?$');
    var checked = 0;
    for (var i = 0; i < 400; i++) {
      final r = gen.question(1 + i % 3, 'q$i');
      final m = ops.firstMatch(r.prompt);
      if (m == null) continue;
      final a = int.parse(m[1]!), b = int.parse(m[3]!);
      final expected = switch (m[2]) {
        '+' => a + b,
        '−' => a - b,
        '×' => a * b,
        _ => a ~/ b,
      };
      expect(r.options[r.answer], '$expected', reason: r.prompt);
      checked++;
    }
    expect(checked, greaterThan(50));
  });

  test('make the target has exactly one pair', () {
    final gen = MathGenerator(math.Random(3));
    for (var i = 0; i < 300; i++) {
      final t = gen.target(1 + i % 3);
      expect(t.numbers.toSet(), hasLength(6));
      var pairs = 0;
      for (var a = 0; a < 6; a++) {
        for (var b = a + 1; b < 6; b++) {
          if (t.apply(t.numbers[a], t.numbers[b]) == t.target) pairs++;
        }
      }
      expect(pairs, 1, reason: t.title);
      expect(t.apply(t.numbers[t.pair.$1], t.numbers[t.pair.$2]), t.target);
    }
  });

  test('new question kinds have one right answer', () {
    final gen = MathGenerator(math.Random(5));
    final kinds = <String>{};
    for (var i = 0; i < 900; i++) {
      final r = gen.question(1 + i % 3);
      kinds.add(r.kind);
      final m = RegExp(r'^(\d+) \? (\d+) = (\d+)$').firstMatch(r.prompt);
      if (r.kind == 'Pick the sign' && m != null) {
        final a = int.parse(m[1]!), b = int.parse(m[2]!), c = int.parse(m[3]!);
        final ok = {
          '+': a + b == c,
          '−': a - b == c,
          '×': a * b == c,
          '÷': a % b == 0 && a ~/ b == c,
        };
        expect(ok.values.where((v) => v), hasLength(1), reason: r.prompt);
        expect(ok[r.solution], isTrue, reason: r.prompt);
      }
      if (r.kind == 'Odd one out') {
        expect(r.options.toSet(), hasLength(4));
      }
    }
    expect(
      kinds,
      containsAll(['Pick the sign', 'Which is bigger?', 'Odd one out']),
    );
  });

  test('maths save ids round-trip', () {
    final id = mathsSaveId('2x + 5 = 17\nx = ?', '6');
    expect(id, 'math|2x + 5 = 17 x = ?|6');
    expect(parseMathsId(id), (title: '2x + 5 = 17 x = ?', solution: '6'));
    expect(parseMathsId('de|Fernweh'), isNull);
  });

  test('sort and memory games', () {
    final gen = MathGenerator(math.Random(9));
    for (var i = 0; i < 300; i++) {
      final level = 1 + i % 3;
      final sort = gen.sort(level);
      expect(sort.labels, hasLength(5));
      expect(sort.values.toSet(), hasLength(5));
      final sorted = [for (final k in sort.order) sort.values[k]];
      expect(sorted, [...sorted]..sort());

      final memory = gen.memory(level);
      expect(memory.options.toSet(), hasLength(4));
      expect(
        int.parse(memory.solution),
        memory.question.contains('sum')
            ? memory.numbers.reduce((a, b) => a + b)
            : memory.numbers.reduce(math.max),
      );
    }
  });

  test('balance, shop, clock and estimate questions', () {
    final gen = MathGenerator(math.Random(11));
    final kinds = <String>{};
    for (var i = 0; i < 1500; i++) {
      final r = gen.question(1 + i % 3);
      kinds.add(r.kind);
      expect(r.options.toSet(), hasLength(r.options.length), reason: r.prompt);
      final m = RegExp(r'^(\d+) \+ \? = (\d+) \+ (\d+)$').firstMatch(r.prompt);
      if (m != null) {
        expect(
          int.parse(m[1]!) + int.parse(r.solution),
          int.parse(m[2]!) + int.parse(m[3]!),
        );
      }
    }
    expect(
      kinds,
      containsAll(['Balance it ⚖️', 'Clock ⏰', 'Estimate 🤔', 'Shopping 🛒']),
    );
  });

  test('mini sudoku has exactly one solution and a valid grid', () {
    final gen = MathGenerator(math.Random(21));
    for (var i = 0; i < 60; i++) {
      final level = 1 + i % 3;
      final s = gen.sudoku(level);
      final n = s.size;
      expect(n, level == 1 ? 4 : 6);
      // The solution is a valid Sudoku.
      for (var k = 0; k < n; k++) {
        final row = {for (var c = 0; c < n; c++) s.grid[k * n + c]};
        final col = {for (var r = 0; r < n; r++) s.grid[r * n + k]};
        expect(row, hasLength(n));
        expect(col, hasLength(n));
        final r0 = k ~/ (n ~/ s.boxCols) * s.boxRows;
        final c0 = k % (n ~/ s.boxCols) * s.boxCols;
        final box = {
          for (var a = 0; a < s.boxRows; a++)
            for (var b = 0; b < s.boxCols; b++) s.grid[(r0 + a) * n + c0 + b],
        };
        expect(box, hasLength(n));
      }
      // Givens agree with the solution, and there are blanks to fill.
      for (var c = 0; c < n * n; c++) {
        if (s.puzzle[c] != 0) expect(s.puzzle[c], s.grid[c]);
      }
      expect(s.blanks, greaterThanOrEqualTo(n == 4 ? 8 : 16));
      expect(_count(s.puzzle, n, s.boxRows, s.boxCols), 1);
    }
  });

  test('word search hides each word exactly once', () {
    final random = math.Random(4);
    final en = [
      for (final w in ['keen', 'brave', 'calm', 'eager', 'joyful', 'witty'])
        _word('en', w),
    ];
    final de = [
      for (final w in ['Heimat', 'Fernweh', 'Ohrwurm', 'Kuchen', 'Brücke'])
        _word('de', w),
    ];
    for (var i = 0; i < 40; i++) {
      final s = makeWordSearch(i.isEven ? en : de, random)!;
      expect(s.words.length, inInclusiveRange(3, 4));
      expect(s.letters, hasLength(s.size * s.size));
      for (var w = 0; w < s.words.length; w++) {
        final text = s.words[w].word.toUpperCase();
        final path = s.paths[w];
        expect(path.map((c) => s.letters[c]).join(), text);
        expect(s.match(path), w);
        expect(s.match(path.reversed.toList()), w);
      }
      expect(s.match([0, 1]), isNull);
    }
    // Too few short words: no puzzle.
    expect(
      makeWordSearch([
        _word('de', 'Aufwiedersehen'),
        _word('en', 'ok'),
      ], random),
      isNull,
    );
  });

  test('word feed gets a word search every eight words', () {
    final words = [
      for (var i = 0; i < 17; i++)
        _word('en', ['keen', 'brave', 'calm', 'witty'][i % 4] + 'x' * (i ~/ 4)),
    ];
    final reels = buildWordReels(words, math.Random(5));
    expect(reels.whereType<WordSearchReel>(), hasLength(2));
    expect(reels[8], isA<WordSearchReel>());
  });

  test('reading texts: German and English, every level, findable by id', () {
    for (final lang in ['en', 'de']) {
      final texts = readingTexts(lang);
      for (final level in [1, 2, 3]) {
        expect(texts.where((t) => t.level == level).length, greaterThan(4));
      }
      expect(texts.map((t) => t.id).toSet(), hasLength(texts.length));
      for (final t in texts) {
        expect(readingById(t.id)?.text, t.text);
        expect(t.text.split(' ').length, inInclusiveRange(3, 12));
        expect(t.translation != null, lang == 'de');
      }
    }
    expect(readingById('read|fr|x'), isNull);
    final words = [for (var i = 0; i < 12; i++) _word('en', 'calm$i')];
    final reels = buildWordReels(
      words,
      math.Random(1),
      readings: readingTexts('en'),
    );
    expect(reels.whereType<ReadingReel>(), hasLength(2));
    expect(reels[5], isA<ReadingReel>());
  });

  test('maths feed skips questions already shown', () {
    final first = buildMathReels(1, math.Random(7));
    final avoid = {for (final r in first) r.id};
    final next = buildMathReels(1, math.Random(7), avoid: avoid);
    expect(next, hasLength(120));
    expect(next.map((r) => r.id).toSet(), hasLength(120));
    final repeats = next.where((r) => avoid.contains(r.id)).length;
    // A few tiny question spaces may run dry; nearly all are new.
    expect(repeats, lessThan(6));
  });

  test('seen content: unseen first, then oldest seen first', () async {
    SharedPreferences.setMockInitialValues({});
    final seen = SeenContent.instance;
    await seen.load();
    seen.mark('b');
    await Future<void>.delayed(const Duration(milliseconds: 5));
    seen.mark('a');
    expect(seen.unseenFirst(['a', 'b', 'c', 'd'], (x) => x), [
      'c',
      'd',
      'b',
      'a',
    ]);
    // Kept on the phone.
    await seen.load();
    expect(seen.has('a'), isTrue);
    expect(seen.has('c'), isFalse);
    expect(
      contentKey(MeaningReel(_word('de', 'Heimat'), const ['x'], 0)),
      contentKey(LearnReel(_word('de', 'Heimat'))),
    );
  });

  group('levels and mastery', () {
    late ProgressStore p;
    var now = DateTime(2026, 1, 1);
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      now = DateTime(2026, 1, 1);
      ProgressStore.clock = () => now;
      p = ProgressStore.instance;
      await p.load();
      p.startTier = 1;
    });
    tearDown(() => ProgressStore.clock = DateTime.now);

    test('levels never end and the XP per level stops growing', () {
      expect(xpForLevel(1), 100);
      expect(xpForLevel(1000), xpForLevel(5000));
      expect(rankName(1), 'Beginner');
      expect(rankName(500), 'Legend');
      for (var i = 0; i < 9; i++) {
        expect(p.record('en', correct: true).leveledUp, isFalse);
      }
      final up = p.record('en', correct: true);
      expect(up.leveledUp, isTrue);
      expect(up.level, 2);
      // Each subject is separate; wrong answers still earn a little.
      expect(p.levelOf('de').level, 1);
      expect(p.record('de', correct: false).xp, kXpTried);
    });

    test('difficulty follows results, and the level never drops', () {
      for (var i = 0; i < 20; i++) {
        p.record('math', correct: true);
      }
      // Strong early answers move up fast: stage 11 is Intermediate.
      expect(p.tierOf('math'), 2);
      final level = p.levelOf('math').level;
      for (var i = 0; i < 300; i++) {
        p.record('math', correct: false);
      }
      expect(p.tierOf('math'), 1);
      expect(p.levelOf('math').level, greaterThanOrEqualTo(level));
    });

    test('words come back on schedule, and a miss drops them back', () {
      const id = 'de|Heimat';
      void day(int d) => now = DateTime(2026, 1, 1 + d);
      p.record('de', correct: true, wordId: id);
      expect(p.dueWords('de'), isEmpty);
      day(1);
      expect(p.dueWords('de'), [id]);
      p.record('de', correct: true, wordId: id);
      day(4);
      p.record('de', correct: true, wordId: id);
      expect(p.knownCount('de'), 1);
      expect(p.masteredCount('de'), 0);
      day(11);
      p.record('de', correct: true, wordId: id);
      expect(p.masteredCount('de'), 1);
      day(12);
      p.record('de', correct: false, wordId: id);
      expect(p.masteredCount('de'), 0);
      day(13);
      expect(p.dueWords('de'), [id]);
    });

    test('accuracy is per subject, and any subject keeps the streak', () {
      void day(int d) => now = DateTime(2026, 1, 1 + d);
      expect(p.accuracyIn('python'), isNull);
      expect(p.practiceStreak, 0);
      p.record('python', correct: true);
      p.record('python', correct: false);
      p.record('math', correct: true);
      expect(p.accuracyIn('python'), 50);
      expect(p.correctIn('python'), 1);
      expect(p.accuracyIn('math'), 100);
      expect(p.practiceStreak, 1);
      day(1);
      expect(p.practiceStreak, 1);
      p.record('de', correct: true);
      expect(p.practiceStreak, 2);
      day(4);
      expect(p.practiceStreak, 0);
      p.record('de', correct: true);
      expect(p.practiceStreak, 1);
    });

    test('learning counts active time only, not an app left open', () {
      void at(int s) => now = DateTime(2026, 1, 1, 10, 0, s);
      expect(p.learningTodayMs, 0);
      at(0);
      p.touchLearning();
      expect(p.learningTodayMs, 0);
      at(20);
      p.touchLearning();
      expect(p.learningTodayMs, 20000);
      // A long look at one reel counts only so much.
      now = DateTime(2026, 1, 1, 10, 2, 20);
      p.touchLearning();
      expect(p.learningTodayMs, 80000);
      // Walking away isn't learning at all.
      now = DateTime(2026, 1, 1, 12);
      p.touchLearning();
      expect(p.learningTodayMs, 80000);
      p.addLearning(30000);
      expect(p.learningTodayMs, 110000);
      // A new day starts again.
      now = DateTime(2026, 1, 2, 9);
      expect(p.learningTodayMs, 0);
    });

    test('cloud merge keeps the higher progress', () async {
      p.record('en', correct: true);
      await p.mergeCloud({
        'subjects': {
          'en': {'xp': 500, 'stage': 12, 'answered': 50, 'recent': <bool>[]},
        },
        'mastery': [
          {'id': 'en|calm', 'box': 4, 'due': 1},
        ],
      });
      expect(p.levelOf('en').level, greaterThan(1));
      expect(p.tierOf('en'), 2);
      expect(p.masteredCount('en'), 1);
    });
  });

  test(
    'feed: tier first, review and stretch mixed in, nothing far off',
    () async {
      SharedPreferences.setMockInitialValues({});
      final seen = SeenContent.instance;
      await seen.load();
      final items = [
        for (var i = 0; i < 40; i++) ('a$i', 1),
        for (var i = 0; i < 40; i++) ('b$i', 2),
        for (var i = 0; i < 40; i++) ('c$i', 3),
      ];
      seen.mark('a0');
      final out = levelledFeed<(String, int)>(
        items,
        levelOf: (i) => i.$2,
        keyOf: (i) => i.$1,
        tier: 1,
        seen: seen,
        random: math.Random(1),
        review: [('a1', 1), ('a2', 1)],
      );
      expect(out.where((i) => i.$2 == 3), isEmpty);
      expect(out[4], ('a1', 1));
      expect(out[9].$2, 2);
      expect(out.map((i) => i.$1).toSet(), hasLength(out.length));
      // The seen one waits until the new ones are done.
      expect(out.indexWhere((i) => i.$1 == 'a0'), greaterThan(30));
    },
  );

  test(
    'strict mode: picked difficulty shows only that tier',
    () async {
      SharedPreferences.setMockInitialValues({});
      final seen = SeenContent.instance;
      await seen.load();
      final items = [
        for (var i = 0; i < 30; i++) ('e$i', 1), // Easy
        for (var i = 0; i < 30; i++) ('m$i', 2), // Medium
        for (var i = 0; i < 30; i++) ('h$i', 3), // Hard
      ];
      // Pick Easy (stretch: false): only tier-1 items.
      final easy = levelledFeed<(String, int)>(
        items,
        levelOf: (i) => i.$2,
        keyOf: (i) => i.$1,
        tier: 1,
        seen: seen,
        random: math.Random(1),
        stretch: false,
      );
      expect(easy.every((i) => i.$2 == 1), isTrue,
          reason: 'Easy should show only Easy');
      // Pick Medium (stretch: false): only tier-2 items.
      final medium = levelledFeed<(String, int)>(
        items,
        levelOf: (i) => i.$2,
        keyOf: (i) => i.$1,
        tier: 2,
        seen: seen,
        random: math.Random(2),
        stretch: false,
      );
      expect(medium.every((i) => i.$2 == 2), isTrue,
          reason: 'Medium should show only Medium');
      // Pick Hard (stretch: false): only tier-3 items.
      final hard = levelledFeed<(String, int)>(
        items,
        levelOf: (i) => i.$2,
        keyOf: (i) => i.$1,
        tier: 3,
        seen: seen,
        random: math.Random(3),
        stretch: false,
      );
      expect(hard.every((i) => i.$2 == 3), isTrue,
          reason: 'Hard should show only Hard');
    },
  );

  test(
    'strict mode falls back when chosen tier is empty',
    () async {
      SharedPreferences.setMockInitialValues({});
      final seen = SeenContent.instance;
      await seen.load();
      // Only tier-1 and tier-2 content, none at tier 3.
      final items = [
        for (var i = 0; i < 20; i++) ('a$i', 1),
        for (var i = 0; i < 20; i++) ('b$i', 2),
      ];
      final out = levelledFeed<(String, int)>(
        items,
        levelOf: (i) => i.$2,
        keyOf: (i) => i.$1,
        tier: 3,
        seen: seen,
        random: math.Random(1),
        stretch: false,
      );
      // Falls back to all content rather than returning empty.
      expect(out, isNotEmpty);
    },
  );

  test('content items: bad ones are refused, good ones become reels', () {
    expect(
      ContentItem.tryParse({
        'subject': 'en',
        'difficulty': 1,
        'kind': 'Quiz',
        'prompt': 'x',
        'options': ['a', 'a'],
        'answer': 0,
      }),
      isNull,
    );
    expect(
      ContentItem.tryParse({'subject': 'en', 'difficulty': 9, 'kind': 'k'}),
      isNull,
    );
    final code = reelFromItem(
      const ContentItem(
        subject: 'python',
        difficulty: 2,
        kind: 'Quiz',
        prompt: 'p',
        code: 'print(1)',
        options: ['1', '2'],
      ),
      math.Random(1),
    ) as CodeReel;
    expect(code.options[code.answer], '1');
    expect(code.id, startsWith('code|Python: print(1)|'));
    expect(parseMathsId(code.id)?.solution, '1');
    final order = reelFromItem(
      const ContentItem(
        subject: 'python',
        difficulty: 1,
        kind: 'k',
        prompt: 'p',
        lines: ['a', 'b', 'c'],
      ),
      math.Random(1),
    );
    expect((order as OrderLinesReel).shuffled.join(), isNot('abc'));
  });

  test('filters build only their kind of reel', () {
    final random = math.Random(3);
    for (final (filter, ok) in [
      ('quick', (Reel r) => r is MathReel),
      ('speed', (Reel r) => r is BlitzReel),
      (
        'puzzles',
        (Reel r) =>
            r is SortReel ||
            r is TargetReel ||
            r is MemoryReel ||
            r is SudokuReel,
      ),
    ]) {
      final reels = buildMathReels(1, random, filter: filter);
      expect(reels.every(ok), isTrue, reason: filter);
      expect(reels.every((r) => matchesFilter(r, filter)), isTrue);
      expect(reels.map((r) => r.id).toSet(), hasLength(reels.length));
    }
    final words = [
      for (final w in [
        'Heimat',
        'Fernweh',
        'Ohrwurm',
        'Kuchen',
        'Brücke',
        'Haus',
        'Baum',
        'Tisch',
      ])
        _word('de', w),
    ];
    for (final filter in ['words', 'quiz', 'puzzles', 'read']) {
      final reels = buildWordReels(
        words,
        random,
        filter: filter,
        readings: readingTexts('de'),
      );
      expect(reels, isNotEmpty, reason: filter);
      expect(
        reels.every((r) => matchesFilter(r, filter)),
        isTrue,
        reason: filter,
      );
    }
    expect(filtersFor('math').first.$1, kFilterAll);
    expect(filtersFor('python').map((f) => f.$1), contains('fix'));
    expect(filtersFor('de').map((f) => f.$1), contains('read'));
  });

  group('taste', () {
    late TasteStore t;
    var now = DateTime(2026, 1, 1);
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      now = DateTime(2026, 1, 1);
      TasteStore.clock = () => now;
      t = TasteStore.instance;
      await t.load();
    });
    tearDown(() => TasteStore.clock = DateTime.now);

    test(
      'actions move scores, they are kept, and they fade with time',
      () async {
        t.signal(['travel'], TasteStore.save);
        t.signal(['travel'], TasteStore.like);
        t.signal(['food'], TasteStore.skipped);
        expect(t.score('travel'), 5);
        expect(t.score('food'), -0.5);
        await t.load();
        expect(t.score('travel'), 5);
        now = DateTime(2026, 1, 11);
        await t.load();
        expect(t.score('travel'), closeTo(5 * 0.817, 0.01));
      },
    );

    test('picked interests start high and can be unpicked', () async {
      await t.setPicked({'travel', 'sports'});
      expect(t.asked, isTrue);
      expect(t.picked, {'travel', 'sports'});
      await t.setPicked({'sports'});
      expect(t.picked, {'sports'});
      expect(t.score('travel'), 0);
    });

    test('tags cover words, texts, code and maths', () {
      expect(wordTopic('de|Fernweh'), 'travel');
      expect(wordTopic('de|Küche'), 'food');
      expect(wordTopic('en|keen'), 'feelings');
      expect(readingTopic('Environment'), 'nature');
      expect(readingTopic('Something new'), 'daily life');
      expect(codeTopic('for i in x:'), 'code:loops');
      expect(codeTopic('class A:'), 'code:classes');
      expect(codeTopic('x = 1'), 'code:basics');
      final gen = MathGenerator(math.Random(1));
      expect(reelTopics(gen.sudoku(1)), ['math:sudoku']);
      expect(reelTopics(LearnReel(_word('de', 'Fernweh'))), ['travel']);
    });

    test('feed: liked topics lead, about a third stays varied', () async {
      await SeenContent.instance.load();
      final items = [
        for (var i = 0; i < 20; i++) ('t$i', 'travel'),
        for (var i = 0; i < 20; i++) ('f$i', 'food'),
      ];
      final out = levelledFeed<(String, String)>(
        items,
        levelOf: (_) => 1,
        keyOf: (i) => i.$1,
        tier: 1,
        seen: SeenContent.instance,
        random: math.Random(2),
        tasteOf: (i) => i.$2 == 'travel' ? 4 : 0,
      );
      final first = out.take(12).toList();
      expect(first.where((i) => i.$2 == 'travel').length, 8);
      expect(first.where((i) => i.$2 == 'food').length, 4);
      // Everything still shows; nothing is hidden by taste.
      expect(out, hasLength(40));
    });

    test('no liked topics leaves the order alone', () async {
      await SeenContent.instance.load();
      final items = [for (var i = 0; i < 8; i++) ('x$i', 'food')];
      List<(String, String)> feed(double Function((String, String))? w) =>
          levelledFeed<(String, String)>(
            items,
            levelOf: (_) => 1,
            keyOf: (i) => i.$1,
            tier: 1,
            seen: SeenContent.instance,
            random: math.Random(3),
            tasteOf: w,
          );
      expect(feed((_) => 0), feed(null));
    });

    test('a liked maths game shows up more, at the same level', () {
      int count(List<String> favourites) => buildMathReels(
        1,
        math.Random(4),
        favourites: favourites,
      ).whereType<SudokuReel>().length;
      expect(count(['math:sudoku']), greaterThan(count(const [])));
      t.signal(['math:sudoku'], 2);
      expect(favouriteMathKinds(t), ['math:sudoku']);
    });
  });
}

/// Solutions of a Sudoku, counting up to two.
int _count(List<int> cells, int n, int br, int bc) {
  final g = [...cells];
  var found = 0;
  bool ok(int i, int v) {
    final r = i ~/ n, c = i % n;
    for (var k = 0; k < n; k++) {
      if (g[r * n + k] == v || g[k * n + c] == v) return false;
    }
    final r0 = r - r % br, c0 = c - c % bc;
    for (var a = 0; a < br; a++) {
      for (var b = 0; b < bc; b++) {
        if (g[(r0 + a) * n + c0 + b] == v) return false;
      }
    }
    return true;
  }

  void solve() {
    if (found > 1) return;
    final i = g.indexOf(0);
    if (i < 0) {
      found++;
      return;
    }
    for (var v = 1; v <= n; v++) {
      if (ok(i, v)) {
        g[i] = v;
        solve();
        g[i] = 0;
      }
    }
  }

  solve();
  return found;
}
