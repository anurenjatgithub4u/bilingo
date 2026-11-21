import 'dart:math' as math;

import 'content_packs.dart';
import 'reading_bank.dart';
import 'seen_content.dart';
import 'taste_store.dart';
import 'vocab.dart';

/// One screen of the WordFlow feed. Most reels ask the learner to do
/// something; a few just teach the word.
sealed class Reel {
  const Reel();

  /// Stable within a feed, so answers survive swiping away and back.
  String get id;
}

/// The plain word card: word, meaning, example.
class LearnReel extends Reel {
  const LearnReel(this.word);
  final VocabWord word;
  @override
  String get id => 'learn|${word.id}';
}

/// A question with a few tappable answers.
abstract class ChoiceReel extends Reel {
  const ChoiceReel();

  /// Small label over the question, e.g. "Pick the meaning".
  String get kind;
  String get prompt;
  List<String> get options;
  int get answer;

  /// Shown once answered.
  String get explanation;
}

/// Word shown, four meanings to choose from.
class MeaningReel extends ChoiceReel {
  const MeaningReel(this.word, this.options, this.answer);
  final VocabWord word;
  @override
  final List<String> options;
  @override
  final int answer;
  @override
  String get id => 'meaning|${word.id}';
  @override
  String get kind => 'Pick the meaning';
  @override
  String get prompt => word.headword;
  @override
  String get explanation => word.example ?? word.meaning;
}

/// German noun without its article: der, die or das?
class ArticleReel extends ChoiceReel {
  const ArticleReel(this.word);
  final VocabWord word;
  @override
  String get id => 'article|${word.id}';
  @override
  String get kind => 'der, die or das?';
  @override
  String get prompt => word.word;
  @override
  List<String> get options => const ['der', 'die', 'das'];
  @override
  int get answer => options.indexOf(word.article!);
  @override
  String get explanation => '${word.headwordWithPlural} — ${word.meaning}';
}

/// Meaning shown; tap scrambled letters to build the word.
class SpellReel extends Reel {
  const SpellReel(this.word, this.letters);
  final VocabWord word;

  /// The word's letters, upper case, shuffled.
  final List<String> letters;

  String get target => word.word.toUpperCase();
  @override
  String get id => 'spell|${word.id}';
}

/// Any maths reel. Likes and saves are keyed by the question itself, so a
/// question keeps them on another day, when the feed is shuffled again.
mixin MathsItem on Reel {
  int get level;

  /// The question as it reads in Saved Words.
  String get title;

  /// Its answer, shown under it in Saved Words.
  String get solution;

  String get shareText;

  String get saveId => mathsSaveId(title, solution);
}

/// "math|question|answer", the like/save id of a maths reel.
String mathsSaveId(String title, String solution, [String prefix = 'math']) {
  String clean(String s) => s.replaceAll('\n', ' ').replaceAll('|', '/');
  return '$prefix|${clean(title)}|${clean(solution)}';
}

/// The question and answer in a [mathsSaveId], or null for word ids.
({String title, String solution})? parseMathsId(String id) {
  final parts = id.split('|');
  if (parts.length != 3 || !const {'math', 'code', 'quiz'}.contains(parts[0])) {
    return null;
  }
  return (title: parts[1], solution: parts[2]);
}

/// A mental-maths question.
class MathReel extends ChoiceReel with MathsItem {
  const MathReel({
    required this.kind,
    required this.prompt,
    required this.options,
    required this.answer,
    required this.explanation,
    required this.level,
  });
  @override
  String get id => saveId;
  @override
  final String kind;
  @override
  final String prompt;
  @override
  final List<String> options;
  @override
  final int answer;
  @override
  final String explanation;
  @override
  final int level;

  @override
  String get title => prompt;
  @override
  String get solution => options[answer];

  @override
  String get shareText =>
      'Can you solve this? 🧠\n\n$prompt\n\n'
      '${[for (var i = 0; i < options.length; i++) '${'ABCD'[i]}) ${options[i]}'].join('   ')}'
      '\n\nPractising with BiLingo';
}

/// Make the target: tap the two numbers that add (or multiply) to it.
class TargetReel extends Reel with MathsItem {
  const TargetReel({
    required this.numbers,
    required this.target,
    required this.op,
    required this.pair,
    required this.level,
  });

  final List<int> numbers;
  final int target;

  /// '+' or '×'.
  final String op;

  /// Indexes of the one pair in [numbers] that makes [target].
  final (int, int) pair;
  @override
  final int level;

  int apply(int a, int b) => op == '+' ? a + b : a * b;

  @override
  String get id => saveId;
  @override
  String get title => 'Make $target from ${numbers.join(', ')}';
  @override
  String get solution => '${numbers[pair.$1]} $op ${numbers[pair.$2]}';
  @override
  String get shareText =>
      'Can you make $target? 🎯\n\n'
      'Pick two of: ${numbers.join(', ')} '
      '(${op == '+' ? 'add' : 'multiply'} them)\n\nPractising with BiLingo';
}

/// Beat the clock: a few quick questions against a countdown.
class BlitzReel extends Reel with MathsItem {
  const BlitzReel({
    required this.questions,
    required this.seconds,
    required this.level,
  });

  final List<MathReel> questions;
  final int seconds;
  @override
  final int level;

  @override
  String get id => saveId;
  @override
  String get title =>
      'Beat the clock: ${questions.map((q) => q.prompt).join(' · ')}';
  @override
  String get solution => questions.map((q) => q.solution).join(' · ');
  @override
  String get shareText =>
      'Beat the clock ⏱️ ${questions.length} quick questions in $seconds '
      'seconds. Can you get them all?\n\nPractising with BiLingo';
}

/// Sort it: tap the numbers from smallest to largest.
class SortReel extends Reel with MathsItem {
  const SortReel({
    required this.labels,
    required this.values,
    required this.level,
  });

  /// As shown: "7", "-3", "0.5", "3/4".
  final List<String> labels;
  final List<double> values;
  @override
  final int level;

  /// Indexes of [labels] from smallest to largest.
  List<int> get order =>
      [for (var i = 0; i < values.length; i++) i]
        ..sort((a, b) => values[a].compareTo(values[b]));

  @override
  String get id => saveId;
  @override
  String get title => 'Sort: ${labels.join(', ')}';
  @override
  String get solution => order.map((i) => labels[i]).join(' < ');
  @override
  String get shareText =>
      'Put these in order, smallest first 🔢\n\n${labels.join('   ')}'
      '\n\nPractising with BiLingo';
}

/// Memory flash: numbers show for a few seconds, then a question about them.
class MemoryReel extends Reel with MathsItem {
  const MemoryReel({
    required this.numbers,
    required this.seconds,
    required this.question,
    required this.options,
    required this.answer,
    required this.level,
  });

  final List<int> numbers;
  final int seconds;

  /// Asked once the numbers are hidden.
  final String question;
  final List<String> options;
  final int answer;
  @override
  final int level;

  @override
  String get id => saveId;
  @override
  String get title => 'Remember ${numbers.join(', ')}: $question';
  @override
  String get solution => options[answer];
  @override
  String get shareText =>
      'Memory test 🧠 Look at these for $seconds seconds, then cover them:'
      '\n\n${numbers.join('   ')}\n\n$question\n\nPractising with BiLingo';
}

/// Mini Sudoku: 4×4 for beginners, 6×6 above. Every row, column and box
/// holds each number once.
class SudokuReel extends Reel with MathsItem {
  const SudokuReel({
    required this.size,
    required this.boxRows,
    required this.boxCols,
    required this.puzzle,
    required this.grid,
    required this.level,
  });

  final int size;
  final int boxRows;
  final int boxCols;

  /// Row by row; 0 is an empty cell.
  final List<int> puzzle;

  /// The one solution, row by row.
  final List<int> grid;
  @override
  final int level;

  int get blanks => puzzle.where((v) => v == 0).length;

  String _rows(List<int> cells) => [
    for (var r = 0; r < size; r++)
      cells
          .sublist(r * size, r * size + size)
          .map((v) => v == 0 ? '·' : '$v')
          .join(' '),
  ].join(' / ');

  @override
  String get id => saveId;
  @override
  String get title => 'Sudoku $size×$size: ${_rows(puzzle)}';
  @override
  String get solution => _rows(grid);
  @override
  String get shareText =>
      'Mini Sudoku 🧩 Fill in 1–$size so every row, column and box has '
      'each number once:\n\n'
      '${[for (var r = 0; r < size; r++) puzzle.sublist(r * size, r * size + size).map((v) => v == 0 ? '·' : '$v').join(' ')].join('\n')}'
      '\n\nPractising with BiLingo';
}

/// Word search: a few words from the feed hidden in a grid of letters.
class WordSearchReel extends Reel {
  const WordSearchReel({
    required this.words,
    required this.size,
    required this.letters,
    required this.paths,
  });

  final List<VocabWord> words;
  final int size;

  /// Row by row, upper case.
  final List<String> letters;

  /// For each of [words], the cell indexes it covers, first letter first.
  final List<List<int>> paths;

  int get level => words.first.level;
  String get lang => words.first.lang;

  /// The word whose path is [cells] (either way round), or null.
  int? match(List<int> cells) {
    for (var i = 0; i < paths.length; i++) {
      final p = paths[i];
      if (p.length != cells.length) continue;
      var forward = true, backward = true;
      for (var k = 0; k < p.length; k++) {
        if (p[k] != cells[k]) forward = false;
        if (p[k] != cells[cells.length - 1 - k]) backward = false;
      }
      if (forward || backward) return i;
    }
    return null;
  }

  @override
  String get id => 'search|${words.map((w) => w.id).join(',')}';

  String get shareText {
    final clues = [
      for (var i = 0; i < words.length; i++)
        '${i + 1}. ${words[i].meaning} '
            '(${words[i].word.length} letters, starts with '
            '${words[i].word[0].toUpperCase()})',
    ];
    final grid = [
      for (var r = 0; r < size; r++)
        letters.sublist(r * size, r * size + size).join(' '),
    ];
    return 'Word search 🔍 Find the ${words.first.languageName} word for:\n\n'
        '${clues.join('\n')}\n\n${grid.join('\n')}\n\nPractising with BiLingo';
  }
}

/// Hides [words] (3–4, upper-case spellable) in a square grid; null when
/// fewer than three fit.
WordSearchReel? makeWordSearch(List<VocabWord> words, math.Random random) {
  final picked = [
    for (final w in words)
      if (canSpell(w) && w.word.length <= 8) w,
  ].take(4).toList();
  if (picked.length < 3) return null;
  final size = math.max(7, picked.map((w) => w.word.length).reduce(math.max));
  // Beginners: across and down. Later: diagonals too.
  final dirs = [(0, 1), (1, 0), if (picked.first.level > 1) (1, 1)];
  final alphabet = picked.first.lang == 'de'
      ? 'ABCDEFGHIJKLMNOPRSTUVWZEEINSTRAÄÖÜ'
      : 'ABCDEFGHIJKLMNOPRSTUVWYEEAIOSTRN';
  for (var attempt = 0; attempt < 30; attempt++) {
    final grid = List<String?>.filled(size * size, null);
    final placed = <VocabWord>[];
    final paths = <List<int>>[];
    final order = [...picked]
      ..sort((a, b) => b.word.length.compareTo(a.word.length));
    for (final w in order) {
      final text = w.word.toUpperCase();
      for (var tries = 0; tries < 200; tries++) {
        final (dr, dc) = dirs[random.nextInt(dirs.length)];
        final r0 = random.nextInt(size - dr * (text.length - 1));
        final c0 = random.nextInt(size - dc * (text.length - 1));
        final path = [
          for (var k = 0; k < text.length; k++)
            (r0 + dr * k) * size + c0 + dc * k,
        ];
        var fits = true;
        for (var k = 0; k < text.length && fits; k++) {
          final cur = grid[path[k]];
          if (cur != null && cur != text[k]) fits = false;
        }
        if (!fits) continue;
        for (var k = 0; k < text.length; k++) {
          grid[path[k]] = text[k];
        }
        placed.add(w);
        paths.add(path);
        break;
      }
    }
    if (placed.length < 3) continue;
    final letters = [
      for (final c in grid) c ?? alphabet[random.nextInt(alphabet.length)],
    ];
    // Each word must appear only where it was hidden.
    if (placed.any(
      (w) => _occurrences(letters, size, w.word.toUpperCase()) != 1,
    )) {
      continue;
    }
    return WordSearchReel(
      words: placed,
      size: size,
      letters: letters,
      paths: paths,
    );
  }
  return null;
}

/// How often [word] reads in [letters] in any of the eight directions.
int _occurrences(List<String> letters, int size, String word) {
  var count = 0;
  const dirs = [
    (0, 1),
    (1, 0),
    (1, 1),
    (1, -1),
    (0, -1),
    (-1, 0),
    (-1, -1),
    (-1, 1),
  ];
  for (var r = 0; r < size; r++) {
    for (var c = 0; c < size; c++) {
      for (final (dr, dc) in dirs) {
        var k = 0;
        while (k < word.length) {
          final rr = r + dr * k, cc = c + dc * k;
          if (rr < 0 || cc < 0 || rr >= size || cc >= size) break;
          if (letters[rr * size + cc] != word[k]) break;
          k++;
        }
        if (k == word.length) count++;
      }
    }
  }
  // A palindrome reads twice from the same cells.
  return word == word.split('').reversed.join() ? count ~/ 2 : count;
}

/// Read a short paragraph aloud; the reel listens and marks each word.
class ReadingReel extends Reel {
  const ReadingReel(this.text);
  final ReadingText text;
  @override
  String get id => text.id;
}

/// A code snippet with a question about it: output, fill the blank, find the
/// bug.
class CodeReel extends ChoiceReel with MathsItem {
  const CodeReel({
    required this.subject,
    required this.kind,
    required this.prompt,
    required this.code,
    required this.options,
    required this.answer,
    required this.explanation,
    required this.level,
  });

  /// 'python' or 'javascript'.
  final String subject;
  final String code;
  @override
  final String kind;
  @override
  final String prompt;
  @override
  final List<String> options;
  @override
  final int answer;
  @override
  final String explanation;
  @override
  final int level;

  String get languageName => kCodeNames[subject] ?? subject;

  @override
  String get saveId => mathsSaveId(title, solution, 'code');
  @override
  String get id => saveId;
  @override
  String get title => '$languageName: $code';
  @override
  String get solution => options[answer];
  @override
  String get shareText =>
      'Can you solve this? 💻\n\n$prompt\n\n$code\n\n'
      '${[for (var i = 0; i < options.length; i++) '${'ABCD'[i]}) ${options[i]}'].join('   ')}'
      '\n\nPractising with BiLingo';
}

/// Order the lines: tap a program's shuffled lines into the right order.
class OrderLinesReel extends Reel with MathsItem {
  const OrderLinesReel({
    required this.subject,
    required this.prompt,
    required this.lines,
    required this.shuffled,
    required this.level,
  });

  final String subject;
  final String prompt;

  /// The right order.
  final List<String> lines;

  /// The same lines as shown to tap.
  final List<String> shuffled;
  @override
  final int level;

  String get languageName => kCodeNames[subject] ?? subject;

  @override
  String get saveId => mathsSaveId(title, solution, 'code');
  @override
  String get id => saveId;
  @override
  String get title => '$languageName: order ${lines.first}';
  @override
  String get solution => lines.join('\n');
  @override
  String get shareText =>
      'Put these lines in order 💻\n\n${shuffled.join('\n')}'
      '\n\nPractising with BiLingo';
}

/// A generated language question, such as fill the blank or a grammar check.
class QuizReel extends ChoiceReel with MathsItem {
  const QuizReel({
    required this.subject,
    required this.kind,
    required this.prompt,
    required this.options,
    required this.answer,
    required this.explanation,
    required this.level,
    this.topic = 'daily life',
  });

  final String subject;

  /// What it's about, for matching a learner's taste.
  final String topic;
  @override
  final String kind;
  @override
  final String prompt;
  @override
  final List<String> options;
  @override
  final int answer;
  @override
  final String explanation;
  @override
  final int level;

  @override
  String get saveId => mathsSaveId(title, solution, 'quiz');
  @override
  String get id => saveId;
  @override
  String get title => prompt;
  @override
  String get solution => options[answer];
  @override
  String get shareText =>
      'Can you answer this? 🧠\n\n$prompt\n\n'
      '${[for (var i = 0; i < options.length; i++) '${'ABCD'[i]}) ${options[i]}'].join('   ')}'
      '\n\nPractising with BiLingo';
}

const kCodeNames = {'coding': 'Coding', 'python': 'Python', 'javascript': 'JavaScript'};

/// The reel for a checked item; answers are shuffled here, ids don't change.
Reel reelFromItem(ContentItem item, math.Random random) {
  if (item.isOrder) {
    final shuffled = [...item.lines];
    for (var tries = 0; tries < 10; tries++) {
      shuffled.shuffle(random);
      if (shuffled.join() != item.lines.join()) break;
    }
    return OrderLinesReel(
      subject: item.subject,
      prompt: item.prompt,
      lines: item.lines,
      shuffled: shuffled,
      level: item.difficulty,
    );
  }
  final right = item.options[item.answer];
  final options = [...item.options]..shuffle(random);
  final code = item.code;
  if (code != null) {
    return CodeReel(
      subject: item.subject,
      kind: item.kind,
      prompt: item.prompt,
      code: code,
      options: options,
      answer: options.indexOf(right),
      explanation: item.explanation,
      level: item.difficulty,
    );
  }
  return QuizReel(
    subject: item.subject,
    kind: item.kind,
    prompt: item.prompt,
    options: options,
    answer: options.indexOf(right),
    explanation: item.explanation,
    level: item.difficulty,
    topic: item.topic ?? 'daily life',
  );
}

/// What a reel is about, for taste. Maths has no topics, so its own kinds of
/// puzzle stand in for them.
List<String> reelTopics(Reel reel) => switch (reel) {
  LearnReel(:final word) ||
  MeaningReel(:final word) ||
  ArticleReel(:final word) ||
  SpellReel(:final word) => [wordTopic(word.id)],
  WordSearchReel(:final words) => {
    for (final w in words) wordTopic(w.id),
  }.toList(),
  ReadingReel(:final text) => [readingTopic(text.topic)],
  QuizReel(:final topic) => [topic],
  CodeReel(:final code) => [codeTopic(code)],
  OrderLinesReel(:final lines) => [codeTopic(lines.join('\n'))],
  MathReel() => const ['math:quick'],
  SortReel() => const ['math:sort'],
  TargetReel() => const ['math:target'],
  MemoryReel() => const ['math:memory'],
  BlitzReel() => const ['math:blitz'],
  SudokuReel() => const ['math:sudoku'],
  _ => const [],
};

/// How hard a reel is, 1 easy to 3 hard. Words without a level count as
/// medium.
int reelLevel(Reel reel) {
  final level = switch (reel) {
    LearnReel(:final word) ||
    MeaningReel(:final word) ||
    ArticleReel(:final word) ||
    SpellReel(:final word) => word.level,
    WordSearchReel() => reel.level,
    ReadingReel(:final text) => text.level,
    MathsItem() => reel.level,
    _ => 2,
  };
  return level >= 1 && level <= 3 ? level : 2;
}

/// Maths kinds with a positive taste score, strongest first.
List<String> favouriteMathKinds(TasteStore taste) {
  const kinds = [
    'math:sort',
    'math:target',
    'math:memory',
    'math:blitz',
    'math:sudoku',
  ];
  final liked = kinds.where((k) => taste.score(k) > 0).toList()
    ..sort((a, b) => taste.score(b).compareTo(taste.score(a)));
  return liked;
}

/// Puts what a learner likes first, but keeps every third item from elsewhere,
/// so a feed still teaches useful things and can discover new interests.
/// [items] keeps its order without any liked topics.
List<T> _byTaste<T>(List<T> items, double Function(T)? tasteOf) {
  if (tasteOf == null) return items;
  final liked = items.where((i) => tasteOf(i) > 0).toList();
  if (liked.isEmpty) return items;
  // Stable: equal scores keep their shuffled order.
  final order = {for (var n = 0; n < liked.length; n++) liked[n]: n};
  liked.sort((a, b) {
    final byScore = tasteOf(b).compareTo(tasteOf(a));
    return byScore != 0 ? byScore : order[a]!.compareTo(order[b]!);
  });
  final others = items.where((i) => tasteOf(i) <= 0).toList();
  final out = <T>[];
  var l = 0, o = 0;
  while (l < liked.length || o < others.length) {
    final wantOther = out.length % 3 == 2;
    if ((wantOther && o < others.length) || l >= liked.length) {
      out.add(others[o++]);
    } else {
      out.add(liked[l++]);
    }
  }
  return out;
}

/// Orders content for a feed at difficulty [tier]: mostly new items at this
/// tier, every fifth one a [review] due again, every tenth a new one from the
/// tier above as a stretch. After that, seen items at this tier and below,
/// longest ago first. Nothing further than one tier above ever shows, unless
/// there is nothing else.
///
/// Without [stretch] (a difficulty the learner picked), only items at exactly
/// [tier] are returned — the feed never mixes in easier or harder content.
/// Items from other tiers appear only when the chosen tier is completely empty.
List<T> levelledFeed<T>(
  List<T> items, {
  required int Function(T) levelOf,
  required String Function(T) keyOf,
  required int tier,
  required SeenContent seen,
  required math.Random random,
  List<T> review = const [],
  double Function(T)? tasteOf,
  bool stretch = true,
}) {
  final shuffled = [...items]..shuffle(random);
  final reviewKeys = {for (final r in review) keyOf(r)};
  final rest = shuffled.where((i) => !reviewKeys.contains(keyOf(i)));
  final fresh = _byTaste(
    rest.where((i) => levelOf(i) == tier && !seen.has(keyOf(i))).toList(),
    tasteOf,
  );

  // ── Strict mode: when the learner picked a difficulty (!stretch), keep
  // only items at exactly that tier. Other tiers appear only when this
  // tier has zero content at all.
  if (!stretch) {
    final sameTierSeen = seen.unseenFirst(
      rest.where((i) => levelOf(i) == tier && seen.has(keyOf(i))).toList(),
      keyOf,
    );
    final sameTierReview = [
      for (final r in review) if (levelOf(r) == tier) r,
    ];
    final out = <T>[];
    var f = 0, r = 0;
    while (f < fresh.length) {
      if (out.length % 5 == 4 && r < sameTierReview.length) {
        out.add(sameTierReview[r++]);
      } else {
        out.add(fresh[f++]);
      }
    }
    out
      ..addAll(sameTierReview.skip(r))
      ..addAll(sameTierSeen);
    // Only fall back to everything when the chosen tier is truly empty.
    return out.isEmpty ? shuffled : out;
  }

  // ── Auto mode: mix in stretch items from the tier above.
  final above = rest
      .where((i) => levelOf(i) == tier + 1 && !seen.has(keyOf(i)))
      .toList();
  final older = seen.unseenFirst(
    rest.where((i) {
      final level = levelOf(i);
      return level < tier || (level == tier && seen.has(keyOf(i)));
    }).toList(),
    keyOf,
  );

  final out = <T>[];
  var f = 0, r = 0, s = 0;
  while (f < fresh.length) {
    final at = out.length % 10;
    if (at == 9 && s < above.length) {
      out.add(above[s++]);
    } else if (at % 5 == 4 && r < review.length) {
      out.add(review[r++]);
    } else {
      out.add(fresh[f++]);
    }
  }
  out
    ..addAll(review.skip(r))
    ..addAll(older)
    ..addAll(above.skip(s));
  return out.isEmpty ? shuffled : out;
}

/// The filter showing every kind of reel.
const kFilterAll = 'all';

/// The filter chips for a feed, as (code, label).
List<(String, String)> filtersFor(String feed) => [
  (kFilterAll, 'For you'),
  ...switch (feed) {
    'math' => const [
      ('quick', 'Quick'),
      ('puzzles', 'Puzzles'),
      ('speed', 'Speed'),
    ],
    'coding' || 'python' || 'javascript' => const [
      ('output', 'Output'),
      ('fix', 'Fix code'),
      ('puzzles', 'Puzzles'),
    ],
    _ => const [
      ('words', 'Words'),
      ('quiz', 'Quiz'),
      ('puzzles', 'Puzzles'),
      ('read', 'Read aloud'),
    ],
  },
];

/// Whether [reel] belongs under the chip [filter].
bool matchesFilter(Reel reel, String filter) {
  if (filter == kFilterAll) return true;
  return filter ==
      switch (reel) {
        LearnReel() => 'words',
        MeaningReel() || ArticleReel() || QuizReel() => 'quiz',
        SpellReel() || WordSearchReel() => 'puzzles',
        ReadingReel() => 'read',
        MathReel() => 'quick',
        SortReel() || TargetReel() || MemoryReel() || SudokuReel() => 'puzzles',
        BlitzReel() => 'speed',
        OrderLinesReel() => 'puzzles',
        CodeReel(:final kind) =>
          kind.startsWith('What does') ? 'output' : 'fix',
        _ => '',
      };
}

/// What a reel shows, for not showing it again: the word for every word
/// reel type (so a word seen as a card is not quizzed as new), otherwise the
/// question, puzzle or text itself.
String contentKey(Reel reel) => switch (reel) {
  LearnReel(:final word) ||
  MeaningReel(:final word) ||
  ArticleReel(:final word) ||
  SpellReel(:final word) => 'w|${word.id}',
  _ => reel.id,
};

/// Words that can be spelled from tiles: one token, 3–9 letters.
bool canSpell(VocabWord w) {
  final s = w.word;
  return s.length >= 3 &&
      s.length <= 9 &&
      !s.contains(' ') &&
      !s.contains('-') &&
      !s.contains('ß') &&
      s.toUpperCase().length == s.length;
}

/// Turns an ordered word list into a mixed feed: learn, pick the meaning,
/// der/die/das (German nouns) and spell-it reels, taking turns, with a word
/// search of the last eight words every eight words and a paragraph from
/// [readings] to read aloud every six.
List<Reel> buildWordReels(
  List<VocabWord> words,
  math.Random random, {
  List<ReadingText> readings = const [],
  List<Reel> quizzes = const [],
  String filter = kFilterAll,
}) {
  if (filter != kFilterAll) {
    return _focusedWordReels(words, random, filter, readings, quizzes);
  }
  final reels = <Reel>[];
  var read = 0, quiz = 0;
  for (var i = 0; i < words.length; i++) {
    // Generated questions, once any have been downloaded.
    if (i % 7 == 3 && quiz < quizzes.length) reels.add(quizzes[quiz++]);
    // Every sixth reel or so, a paragraph to read aloud.
    if (i % 6 == 5 && read < readings.length) {
      reels.add(ReadingReel(readings[read++]));
    }
    // After every eight words, a word search with some of them.
    if (i > 0 && i % 8 == 0) {
      final search = makeWordSearch(words.sublist(i - 8, i), random);
      if (search != null) reels.add(search);
    }
    final w = words[i];
    final slot = i % 4;
    if (slot == 2 && w.article != null) {
      reels.add(ArticleReel(w));
    } else if ((slot == 2 || slot == 3) && canSpell(w)) {
      reels.add(SpellReel(w, _scramble(w.word.toUpperCase(), random)));
    } else if (slot != 0 && words.length >= 4) {
      reels.add(_meaning(w, words, random));
    } else {
      reels.add(LearnReel(w));
    }
  }
  return reels;
}

/// A word feed of one kind only, one reel per word where it can.
List<Reel> _focusedWordReels(
  List<VocabWord> words,
  math.Random random,
  String filter,
  List<ReadingText> readings,
  List<Reel> quizzes,
) {
  if (filter == 'read') return [for (final t in readings) ReadingReel(t)];
  if (filter == 'words') return [for (final w in words) LearnReel(w)];
  final reels = <Reel>[];
  if (filter == 'quiz') {
    var quiz = 0;
    for (var i = 0; i < words.length; i++) {
      if (i % 3 == 2 && quiz < quizzes.length) reels.add(quizzes[quiz++]);
      final w = words[i];
      if (w.article != null && (words.length < 4 || random.nextBool())) {
        reels.add(ArticleReel(w));
      } else if (words.length >= 4) {
        reels.add(_meaning(w, words, random));
      }
    }
    return [...reels, ...quizzes.skip(quiz)];
  }
  // Puzzles: spelling, with a word search of the last eight words now and then.
  for (var i = 0; i < words.length; i++) {
    if (i > 0 && i % 6 == 0) {
      final from = math.max(0, i - 8);
      final search = makeWordSearch(words.sublist(from, i), random);
      if (search != null) reels.add(search);
    }
    final w = words[i];
    if (canSpell(w)) {
      reels.add(SpellReel(w, _scramble(w.word.toUpperCase(), random)));
    }
  }
  return reels;
}

MeaningReel _meaning(VocabWord w, List<VocabWord> all, math.Random random) {
  final others = [
    for (final o in all)
      if (o.id != w.id && o.meaning != w.meaning) o.meaning,
  ]..shuffle(random);
  final options = {w.meaning, ...others}.take(4).toList()..shuffle(random);
  return MeaningReel(w, options, options.indexOf(w.meaning));
}

List<String> _scramble(String word, math.Random random) {
  final letters = word.split('');
  for (var tries = 0; tries < 10; tries++) {
    letters.shuffle(random);
    if (letters.join() != word) break;
  }
  return letters;
}

/// Mental-maths reels, the learner's level first, then the others. Most
/// reels are games (sort it, make the target, memory flash, beat the
/// clock, mini Sudoku) between quick questions.
/// Questions in [avoid] (already shown) are made again where possible.
/// Without [stretch] (a level the learner picked), only [level] shows.
List<Reel> buildMathReels(
  int level,
  math.Random random, {
  Set<String> avoid = const {},
  String filter = kFilterAll,
  List<String> favourites = const [],
  bool stretch = true,
}) {
  final gen = MathGenerator(random);
  final reels = <Reel>[];
  final seen = <String>{};
  bool fresh(Reel r) => !avoid.contains(r.id) && seen.add(r.id);
  Reel favourite(int lvl) =>
      switch (favourites[random.nextInt(favourites.length)]) {
        'math:sort' => gen.sort(lvl),
        'math:target' => gen.target(lvl),
        'math:memory' => gen.memory(lvl),
        'math:blitz' => gen.blitz(lvl),
        _ => gen.sudoku(lvl),
      };
  // Some plain question slots become the games a learner enjoys.
  Reel mixed(int lvl, int i) => switch (i % 9) {
    2 || 7 when favourites.isNotEmpty => favourite(lvl),
    1 => gen.sort(lvl),
    3 => gen.target(lvl),
    5 => gen.memory(lvl),
    6 => gen.blitz(lvl),
    8 => gen.sudoku(lvl),
    _ => gen.question(lvl),
  };
  void add(int lvl, int count) {
    for (var i = 0; i < count; i++) {
      Reel next() => switch (filter) {
        'quick' => gen.question(lvl),
        'speed' => gen.blitz(lvl),
        'puzzles' => switch (i % 4) {
          0 => gen.sort(lvl),
          1 => gen.target(lvl),
          2 => gen.memory(lvl),
          _ => gen.sudoku(lvl),
        },
        _ => mixed(lvl, i),
      };
      // Ids must be unique in a feed, and seen questions are skipped; a
      // repeat is made again. After many tries an old one is allowed back.
      var reel = next();
      var tries = 0;
      while (!fresh(reel) && tries++ < 30) {
        reel = next();
      }
      // Out of new ones: anything not already in this feed.
      while (tries > 30 && !seen.add(reel.id) && tries++ < 60) {
        reel = next();
      }
      reels.add(reel);
    }
  }

  add(level, level < 3 ? 100 : 120);
  // A stretch: the next level up. Lower or far-off levels never show.
  if (stretch && level < 3) add(level + 1, 20);
  return reels;
}

/// Makes level-appropriate arithmetic questions with plausible wrong answers.
class MathGenerator {
  MathGenerator(this._r);
  final math.Random _r;

  int _n(int min, int max) => min + _r.nextInt(max - min + 1);

  MathReel question(int level, [String id = '']) {
    final makers = switch (level) {
      1 => [
        _add,
        _subtract,
        _times,
        _missingAdd,
        _pattern,
        _trueFalse,
        _whichSign,
        _bigger,
        _oddOneOut,
        _balance,
        _shop,
        _clock,
        _estimate,
      ],
      2 => [
        _times,
        _divide,
        _missingTimes,
        _percent,
        _orderOfOps,
        _pattern,
        _whichSign,
        _bigger,
        _oddOneOut,
        _balance,
        _shop,
        _clock,
        _estimate,
      ],
      _ => [
        _percent,
        _square,
        _orderOfOps,
        _equation,
        _negative,
        _pattern,
        _whichSign,
        _bigger,
        _oddOneOut,
        _balance,
        _shop,
        _clock,
        _estimate,
      ],
    };
    return makers[_r.nextInt(makers.length)](level, id);
  }

  /// Six numbers; exactly one pair adds (beginner) or multiplies to the target.
  TargetReel target(int level) {
    final op = level == 1 ? '+' : '×';
    final (lo, hi) = switch (level) {
      1 => (2, 20),
      2 => (2, 12),
      _ => (3, 15),
    };
    int apply(int a, int b) => op == '+' ? a + b : a * b;
    while (true) {
      final a = _n(lo, hi), b = _n(lo, hi);
      if (a == b) continue;
      final goal = apply(a, b);
      final numbers = [a, b];
      var tries = 0;
      while (numbers.length < 6 && tries++ < 200) {
        final c = _n(lo, hi);
        if (numbers.contains(c)) continue;
        if (numbers.any((x) => apply(x, c) == goal)) continue;
        numbers.add(c);
      }
      if (numbers.length < 6) continue;
      numbers.shuffle(_r);
      return TargetReel(
        numbers: numbers,
        target: goal,
        op: op,
        pair: (numbers.indexOf(a), numbers.indexOf(b)),
        level: level,
      );
    }
  }

  /// Five numbers to put in order; harder levels mix in negatives,
  /// decimals and fractions.
  SortReel sort(int level) {
    final labels = <String>[];
    final values = <double>[];
    void add(String label, double value) {
      if (values.contains(value)) return;
      labels.add(label);
      values.add(value);
    }

    while (labels.length < 5) {
      switch (level == 1 ? 0 : _r.nextInt(level == 2 ? 2 : 3)) {
        case 0:
          final n = level == 1 ? _n(1, 99) : _n(-20, 99);
          add('$n', n.toDouble());
        case 1:
          final tenths = _n(1, 49);
          add((tenths / 10).toString(), tenths / 10);
        default:
          final den = [2, 3, 4, 5, 8][_r.nextInt(5)];
          final num = _n(1, den * 2 - 1);
          if (num % den == 0) continue;
          add('$num/$den', num / den);
      }
    }
    return SortReel(labels: labels, values: values, level: level);
  }

  /// A few numbers to remember, then: what was their sum? (or the biggest).
  MemoryReel memory(int level) {
    final count = level == 1 ? 3 : 4;
    final numbers = <int>[];
    while (numbers.length < count) {
      final n = level == 3 ? _n(11, 49) : _n(2, level == 1 ? 9 : 19);
      if (!numbers.contains(n)) numbers.add(n);
    }
    final askSum = level == 1 || _r.nextInt(3) > 0;
    final int answer;
    final String question;
    final List<int> options;
    if (askSum) {
      answer = numbers.reduce((a, b) => a + b);
      question = 'What was their sum?';
      final wrong = {
        answer + 1,
        answer - 1,
        answer + 2,
        answer - 2,
        answer + 10,
      }..remove(answer);
      options = [answer, ...wrong.take(3)];
    } else {
      answer = numbers.reduce(math.max);
      question = 'Which was the biggest?';
      final wrong = <int>{
        for (final n in numbers)
          if (n != answer) n,
      };
      while (wrong.length < 3) {
        wrong.add(answer + wrong.length + 1);
      }
      options = [answer, ...wrong.take(3)];
    }
    options.shuffle(_r);
    return MemoryReel(
      numbers: numbers,
      seconds: level == 3 ? 4 : 3,
      question: question,
      options: [for (final o in options) '$o'],
      answer: options.indexOf(answer),
      level: level,
    );
  }

  /// A mini Sudoku with exactly one solution: 4×4 (2×2 boxes) at level 1,
  /// 6×6 (2×3 boxes) above, with fewer clues at level 3.
  SudokuReel sudoku(int level) {
    final (n, br, bc) = level == 1 ? (4, 2, 2) : (6, 2, 3);
    // A valid grid from the standard pattern, then shuffled in ways that
    // keep it valid: digits, rows within a band, columns within a stack,
    // whole bands and whole stacks.
    List<int> shuffled(int groups, int per) {
      final g = [for (var i = 0; i < groups; i++) i]..shuffle(_r);
      return [
        for (final b in g)
          ...([for (var i = 0; i < per; i++) b * per + i]..shuffle(_r)),
      ];
    }

    final rows = shuffled(n ~/ br, br);
    final cols = shuffled(n ~/ bc, bc);
    final digits = [for (var d = 1; d <= n; d++) d]..shuffle(_r);
    int base(int r, int c) => (bc * (r % br) + r ~/ br + c) % n;
    final grid = [
      for (var r = 0; r < n; r++)
        for (var c = 0; c < n; c++) digits[base(rows[r], cols[c])],
    ];

    final keep = switch (level) {
      1 => 6,
      2 => 16,
      _ => 13,
    };
    final puzzle = [...grid];
    final cells = [for (var i = 0; i < n * n; i++) i]..shuffle(_r);
    var givens = n * n;
    for (final i in cells) {
      if (givens <= keep) break;
      final v = puzzle[i];
      puzzle[i] = 0;
      if (_solutions(puzzle, n, br, bc, 2) == 1) {
        givens--;
      } else {
        puzzle[i] = v;
      }
    }
    return SudokuReel(
      size: n,
      boxRows: br,
      boxCols: bc,
      puzzle: puzzle,
      grid: grid,
      level: level,
    );
  }

  /// Number of solutions of [cells], counting no further than [limit].
  static int _solutions(List<int> cells, int n, int br, int bc, int limit) {
    final grid = [...cells];
    var found = 0;
    bool ok(int i, int v) {
      final r = i ~/ n, c = i % n;
      for (var k = 0; k < n; k++) {
        if (grid[r * n + k] == v || grid[k * n + c] == v) return false;
      }
      final r0 = r - r % br, c0 = c - c % bc;
      for (var a = 0; a < br; a++) {
        for (var b = 0; b < bc; b++) {
          if (grid[(r0 + a) * n + c0 + b] == v) return false;
        }
      }
      return true;
    }

    void solve(int from) {
      if (found >= limit) return;
      var i = from;
      while (i < n * n && grid[i] != 0) {
        i++;
      }
      if (i == n * n) {
        found++;
        return;
      }
      for (var v = 1; v <= n; v++) {
        if (!ok(i, v)) continue;
        grid[i] = v;
        solve(i + 1);
        grid[i] = 0;
      }
    }

    solve(0);
    return found;
  }

  /// Five quick questions with three answers each, against the clock.
  BlitzReel blitz(int level) {
    MathReel quick() {
      final a = _n(2, level == 1 ? 12 : 20), b = _n(2, 9);
      return switch (_r.nextInt(level == 1 ? 2 : 3)) {
        0 => _choice(level, '', 'Sum', '$a + $b', a + b, '', count: 3),
        1 => _choice(level, '', 'Difference', '${a + b} − $b', a, '', count: 3),
        _ => _choice(level, '', 'Product', '$a × $b', a * b, '', count: 3),
      };
    }

    return BlitzReel(
      questions: [for (var i = 0; i < 5; i++) quick()],
      seconds: level == 1 ? 25 : 20,
      level: level,
    );
  }

  MathReel _choice(
    int level,
    String id,
    String kind,
    String prompt,
    int answer,
    String explanation, {
    List<int> near = const [],
    int count = 4,
  }) {
    final wrong = <int>{};
    for (final d in [...near, 1, -1, 2, -2, 10, -10, 3, -3, 5, -5]) {
      if (wrong.length == count - 1) break;
      final v = answer + d;
      if (v != answer && (answer < 0 || v >= 0)) wrong.add(v);
    }
    final options = [answer, ...wrong]..shuffle(_r);
    return MathReel(
      kind: kind,
      prompt: prompt,
      options: [for (final o in options) '$o'],
      answer: options.indexOf(answer),
      explanation: explanation,
      level: level,
    );
  }

  MathReel _add(int level, String id) {
    final a = _n(5, 60), b = _n(5, 40);
    return _choice(
      level,
      id,
      'Quick sum',
      '$a + $b = ?',
      a + b,
      '$a + $b = ${a + b}',
    );
  }

  MathReel _subtract(int level, String id) {
    final a = _n(20, 99), b = _n(3, a - 5);
    return _choice(
      level,
      id,
      'Quick difference',
      '$a − $b = ?',
      a - b,
      '$a − $b = ${a - b}',
    );
  }

  MathReel _times(int level, String id) {
    final a = level == 1 ? _n(2, 10) : _n(11, 25), b = _n(3, 9);
    return _choice(
      level,
      id,
      'Times table',
      '$a × $b = ?',
      a * b,
      '$a × $b = ${a * b}',
      near: [a, -a, b, -b],
    );
  }

  MathReel _divide(int level, String id) {
    final b = _n(3, 12), q = _n(4, 15);
    return _choice(
      level,
      id,
      'Share it out',
      '${b * q} ÷ $b = ?',
      q,
      '$b × $q = ${b * q}',
    );
  }

  MathReel _missingAdd(int level, String id) {
    final a = _n(4, 40), x = _n(3, 30);
    return _choice(
      level,
      id,
      'Missing number',
      '$a + ? = ${a + x}',
      x,
      '${a + x} − $a = $x',
    );
  }

  MathReel _missingTimes(int level, String id) {
    final a = _n(3, 12), x = _n(3, 12);
    return _choice(
      level,
      id,
      'Missing number',
      '$a × ? = ${a * x}',
      x,
      '${a * x} ÷ $a = $x',
    );
  }

  MathReel _percent(int level, String id) {
    final pct = level == 2
        ? [10, 25, 50][_r.nextInt(3)]
        : [5, 15, 20, 30, 75][_r.nextInt(5)];
    final base = _n(2, 20) * 20;
    final ans = base * pct ~/ 100;
    return _choice(
      level,
      id,
      'Percent',
      '$pct% of $base = ?',
      ans,
      '$base × $pct ÷ 100 = $ans',
      near: [ans ~/ 2, ans],
    );
  }

  MathReel _orderOfOps(int level, String id) {
    final a = _n(2, 20), b = _n(2, 9), c = _n(2, 9);
    if (level >= 3) {
      final ans = (a + b) * c;
      return _choice(
        level,
        id,
        'Brackets first',
        '($a + $b) × $c = ?',
        ans,
        '$a + $b = ${a + b}, then × $c = $ans',
        near: [a + b * c - ans],
      );
    }
    final ans = a + b * c;
    return _choice(
      level,
      id,
      'Order of operations',
      '$a + $b × $c = ?',
      ans,
      'Multiply first: $b × $c = ${b * c}, then + $a = $ans',
      near: [(a + b) * c - ans],
    );
  }

  MathReel _square(int level, String id) {
    final n = _n(4, 19);
    if (_r.nextBool()) {
      return _choice(
        level,
        id,
        'Square it',
        '$n² = ?',
        n * n,
        '$n × $n = ${n * n}',
        near: [n, -n],
      );
    }
    return _choice(
      level,
      id,
      'Square root',
      '√${n * n} = ?',
      n,
      '$n × $n = ${n * n}',
    );
  }

  MathReel _equation(int level, String id) {
    final a = _n(2, 9), x = _n(2, 12), b = _n(1, 20);
    return _choice(
      level,
      id,
      'Solve for x',
      '${a}x + $b = ${a * x + b}\nx = ?',
      x,
      '${a}x = ${a * x + b} − $b = ${a * x}, so x = $x',
    );
  }

  MathReel _negative(int level, String id) {
    final a = _n(3, 20), b = _n(a + 2, 40);
    return _choice(
      level,
      id,
      'Below zero',
      '$a − $b = ?',
      a - b,
      '$a − $b = ${a - b}',
      near: [b - a - (a - b)],
    );
  }

  MathReel _pattern(int level, String id) {
    final List<int> seq;
    final String rule;
    switch (level == 1 ? 0 : _r.nextInt(level == 2 ? 2 : 3)) {
      case 0:
        final start = _n(1, 20), step = _n(2, level == 1 ? 5 : 12);
        seq = [for (var i = 0; i < 5; i++) start + step * i];
        rule = 'add $step each time';
      case 1:
        final start = _n(1, 5), k = _n(2, 3);
        seq = [for (var i = 0, v = start; i < 5; i++, v *= k) v];
        rule = 'multiply by $k each time';
      default:
        final s = _n(1, 6);
        seq = [for (var i = s; i < s + 5; i++) i * i];
        rule = 'square numbers: ${s + 4} × ${s + 4}';
    }
    final shown = seq.take(4).join(', ');
    return _choice(
      level,
      id,
      'What comes next?',
      '$shown, ?',
      seq[4],
      'Pattern: $rule',
    );
  }

  /// Which sign makes it true: + − × ÷ (only one does).
  MathReel _whichSign(int level, String id) {
    const signs = ['+', '−', '×', '÷'];
    int? apply(String s, int a, int b) => switch (s) {
      '+' => a + b,
      '−' => a - b,
      '×' => a * b,
      _ => a % b == 0 ? a ~/ b : null,
    };
    while (true) {
      final a = _n(level == 1 ? 3 : 6, level == 1 ? 12 : 48);
      final b = _n(2, level == 1 ? 6 : 12);
      final sign = signs[_r.nextInt(level == 1 ? 3 : 4)];
      final result = apply(sign, a, b);
      if (result == null || result < 0) continue;
      if (signs.where((s) => apply(s, a, b) == result).length != 1) continue;
      return MathReel(
        kind: 'Pick the sign',
        prompt: '$a ? $b = $result',
        options: signs,
        answer: signs.indexOf(sign),
        explanation: '$a $sign $b = $result',
        level: level,
      );
    }
  }

  /// Two expressions; tap the bigger one.
  MathReel _bigger(int level, String id) {
    (String, int) make() {
      final a = _n(2, level == 1 ? 15 : 12), b = _n(2, level == 1 ? 15 : 12);
      return switch (level) {
        1 => ('$a + $b', a + b),
        2 => ('$a × $b', a * b),
        _ =>
          _r.nextBool()
              ? ('${a + 3}²', (a + 3) * (a + 3))
              : ('$a × ${b + 8}', a * (b + 8)),
      };
    }

    while (true) {
      final one = make(), two = make();
      if (one.$2 == two.$2 || one.$1 == two.$1) continue;
      return MathReel(
        kind: 'Which is bigger?',
        prompt: 'Tap the bigger one',
        options: [one.$1, two.$1],
        answer: one.$2 > two.$2 ? 0 : 1,
        explanation: '${one.$1} = ${one.$2}, ${two.$1} = ${two.$2}',
        level: level,
      );
    }
  }

  /// Four numbers; three share a property, one does not.
  MathReel _oddOneOut(int level, String id) {
    final String rule;
    final bool Function(int) fits;
    final int Function() pick;
    switch (level == 1 ? _r.nextInt(2) : 1 + _r.nextInt(2)) {
      case 0:
        rule = 'even';
        fits = (n) => n.isEven;
        pick = () => _n(2, 60);
      case 1:
        final k = _n(3, level == 1 ? 5 : 9);
        rule = 'multiples of $k';
        fits = (n) => n % k == 0;
        pick = () => _n(2, 12) * k + (_r.nextInt(3) == 0 ? _n(1, k - 1) : 0);
      default:
        rule = 'square numbers';
        fits = (n) {
          final root = math.sqrt(n).round();
          return root * root == n;
        };
        pick = () =>
            _r.nextBool() ? math.pow(_n(2, 12), 2).toInt() : _n(5, 140);
    }
    final ins = <int>{}, outs = <int>{};
    while (ins.length < 3 || outs.isEmpty) {
      final n = pick();
      (fits(n) ? ins : outs).add(n);
    }
    final odd = outs.first;
    final options = [...ins.take(3), odd]..shuffle(_r);
    return MathReel(
      kind: 'Odd one out',
      prompt: 'Which one does not fit?',
      options: [for (final o in options) '$o'],
      answer: options.indexOf(odd),
      explanation: 'The others are all $rule; $odd is not.',
      level: level,
    );
  }

  /// Balance it: both sides must come out equal.
  MathReel _balance(int level, String id) {
    switch (level) {
      case 1:
        final a = _n(2, 12), b = _n(2, 12), c = _n(1, a + b - 1);
        final x = a + b - c;
        return _choice(
          level,
          id,
          'Balance it ⚖️',
          '$c + ? = $a + $b',
          x,
          '$a + $b = ${a + b}, and $c + $x = ${a + b}',
        );
      case 2:
        final a = _n(2, 6), b = _n(2, 12), c = [2, 3, 4, 6][_r.nextInt(4)];
        if ((a * b) % c != 0) return _balance(level, id);
        final x = a * b ~/ c;
        return _choice(
          level,
          id,
          'Balance it ⚖️',
          '$c × ? = $a × $b',
          x,
          '$a × $b = ${a * b}, and $c × $x = ${a * b}',
        );
      default:
        final x = _n(3, 12), k = _n(3, 9), d = _n(5, 40);
        return _choice(
          level,
          id,
          'Balance it ⚖️',
          '? × $k = ${x * k + d} − $d',
          x,
          '${x * k + d} − $d = ${x * k}, and ${x * k} ÷ $k = $x',
        );
    }
  }

  /// A shopping question in rupees.
  MathReel _shop(int level, String id) {
    switch (level) {
      case 1:
        final n = _n(2, 6), price = _n(2, 15) * 2;
        return _choice(
          level,
          id,
          'Shopping 🛒',
          '$n pens at ₹$price each.\nTotal?',
          n * price,
          '$n × ₹$price = ₹${n * price}',
          near: [price, -price],
        );
      case 2:
        final a = _n(12, 45), b = _n(10, 40);
        final paid = a + b > 50 ? 100 : 50;
        final change = paid - a - b;
        return _choice(
          level,
          id,
          'Shopping 🛒',
          'Items cost ₹$a and ₹$b.\nYou pay ₹$paid. Change?',
          change,
          '₹$paid − ₹${a + b} = ₹$change',
        );
      default:
        final price = _n(4, 30) * 50, off = [10, 20, 25, 40][_r.nextInt(4)];
        final pay = price - price * off ~/ 100;
        return _choice(
          level,
          id,
          'Sale 🏷️',
          '$off% off ₹$price.\nYou pay?',
          pay,
          '$off% of ₹$price is ₹${price * off ~/ 100}, so ₹$pay',
          near: [price * off ~/ 100 - pay, 50, -50],
        );
    }
  }

  /// Time arithmetic on a 12-hour clock.
  MathReel _clock(int level, String id) {
    String fmt(int minutes) {
      final m = minutes % (12 * 60);
      final h = m ~/ 60;
      return '${h == 0 ? 12 : h}:${(m % 60).toString().padLeft(2, '0')}';
    }

    final start = _n(1, 11) * 60 + _n(0, 11) * 5;
    final add = level == 1 ? [15, 30, 45, 60][_r.nextInt(4)] : _n(4, 30) * 5;
    final end = start + add;
    final options = <int>{end};
    for (final d in [10, -10, 60, -60, 5, -5]) {
      if (options.length == 4) break;
      options.add(end + d);
    }
    final list = options.toList()..shuffle(_r);
    return MathReel(
      kind: 'Clock ⏰',
      prompt: 'It is ${fmt(start)}.\nWhat time in $add min?',
      options: [for (final o in list) fmt(o)],
      answer: list.indexOf(end),
      explanation: '${fmt(start)} + $add min = ${fmt(end)}',
      level: level,
    );
  }

  /// Estimate: which power of ten is closest?
  MathReel _estimate(int level, String id) {
    while (true) {
      final a = _n(level == 1 ? 8 : 15, level == 1 ? 60 : 99);
      final b = _n(level == 1 ? 8 : 15, level == 3 ? 999 : 99);
      final p = a * b;
      final log = math.log(p) / math.ln10;
      final k = log.round();
      // Only clear-cut cases, never halfway between two answers.
      if ((log - k).abs() > 0.25 || k < 2) continue;
      final options = [
        for (var e = k - 1; e <= k + 2; e++) math.pow(10, e).toInt(),
      ]..shuffle(_r);
      String group(int n) => n.toString().replaceAllMapped(
        RegExp(r'\B(?=(\d{3})+(?!\d))'),
        (_) => ',',
      );
      final answer = math.pow(10, k).toInt();
      return MathReel(
        kind: 'Estimate 🤔',
        prompt: '$a × $b ≈ ?',
        options: [for (final o in options) group(o)],
        answer: options.indexOf(answer),
        explanation: '$a × $b = ${group(p)}, closest to ${group(answer)}',
        level: level,
      );
    }
  }

  MathReel _trueFalse(int level, String id) {
    final a = _n(2, 10), b = _n(2, 10);
    final honest = _r.nextBool();
    final shown = honest ? a * b : a * b + [-2, -1, 1, 2][_r.nextInt(4)];
    return MathReel(
      kind: 'True or false?',
      prompt: '$a × $b = $shown',
      options: const ['True', 'False'],
      answer: honest ? 0 : 1,
      explanation: '$a × $b = ${a * b}',
      level: level,
    );
  }
}
