import 'dart:math' as math;
import 'dart:typed_data';

/// How a single word of the passage is shown while the learner reads.
enum WordMark {
  /// Not reached yet.
  unread,

  /// Probably being said right now, or missed but not confirmed yet.
  pending,

  /// The recogniser heard this word.
  matched,

  /// Skipped or heard as a different word, confirmed by later words.
  missed,
}

/// One word of the passage: [display] keeps the punctuation the learner
/// sees, [key] is the normalised form used for matching.
class RefWord {
  const RefWord(this.display, this.key, this.sentence);

  final String display;
  final String key;

  /// Index into [ReferenceText.sentences].
  final int sentence;
}

/// The passage being read, split into words and sentences once.
class ReferenceText {
  factory ReferenceText(String text) {
    final words = <RefWord>[];
    final sentences = <String>[];
    var current = <String>[];
    for (final token in text.trim().split(RegExp(r'\s+'))) {
      if (token.isEmpty) continue;
      final key = normalizeWord(token);
      if (key.isEmpty) {
        // A lone dash or symbol: show it with the previous word, nothing to say.
        if (words.isNotEmpty) {
          final last = words.removeLast();
          words.add(RefWord('${last.display} $token', last.key, last.sentence));
        }
        current.add(token);
        continue;
      }
      words.add(RefWord(token, key, sentences.length));
      current.add(token);
      if (RegExp(r'''[.!?]["'”’)]*$''').hasMatch(token)) {
        sentences.add(current.join(' '));
        current = [];
      }
    }
    if (current.isNotEmpty) sentences.add(current.join(' '));
    return ReferenceText._(text, words, sentences);
  }

  ReferenceText._(this.text, this.words, this.sentences);

  final String text;
  final List<RefWord> words;
  final List<String> sentences;
}

const _numbers = {
  'zero': '0', 'one': '1', 'two': '2', 'three': '3', 'four': '4', //
  'five': '5', 'six': '6', 'seven': '7', 'eight': '8', 'nine': '9',
  'ten': '10', 'eleven': '11', 'twelve': '12', 'thirteen': '13',
  'fourteen': '14', 'fifteen': '15', 'sixteen': '16', 'seventeen': '17',
  'eighteen': '18', 'nineteen': '19', 'twenty': '20', 'thirty': '30',
  'forty': '40', 'fifty': '50', 'sixty': '60', 'seventy': '70',
  'eighty': '80', 'ninety': '90', 'hundred': '100',
  '1st': 'first', '2nd': 'second', '3rd': 'third',
};

/// Lowercase, straight apostrophes, letters/digits only, number words as digits.
/// "Well-known," → "wellknown", "Don’t" → "don't", "Five" → "5".
String normalizeWord(String word) {
  final s = word
      .toLowerCase()
      .replaceAll(RegExp('[’‘`´]'), "'")
      // Keeps German letters, so "für" and "fünf" stay different words.
      .replaceAll(RegExp(r"[^a-z0-9'äöüß]"), '')
      .replaceAll(RegExp(r"^'+|'+$"), '');
  return _numbers[s] ?? s;
}

/// Splits a recogniser transcript into normalised words.
List<String> transcriptWords(String transcript) => [
  for (final t in transcript.split(RegExp(r'\s+')))
    if (normalizeWord(t) case final k when k.isNotEmpty) k,
];

/// Words a recogniser cannot tell apart; any spelling counts as the word.
const _homophoneGroups = [
  ['there', 'their', "they're"],
  ['to', 'too', '2'],
  ['for', 'four', '4'],
  ['your', "you're"],
  ['its', "it's"],
  ['here', 'hear'],
  ['know', 'no'],
  ['knew', 'new'],
  ['write', 'right'],
  ['by', 'buy', 'bye'],
  ['weather', 'whether'],
  ['whole', 'hole'],
  ['one', '1', 'won'],
  ['eight', '8', 'ate'],
  ['week', 'weak'],
  ['meet', 'meat'],
  ['see', 'sea'],
  ['piece', 'peace'],
  ['road', 'rode'],
  ['wait', 'weight'],
  ['ok', 'okay'],
  ['percent', '%'],
];

final Map<String, int> _homophoneOf = {
  for (var g = 0; g < _homophoneGroups.length; g++)
    for (final w in _homophoneGroups[g]) normalizeWord(w): g,
};

/// Alignment scores (higher is better).
const _exact = 4;
const _close = 3;
const _wrong = -2;
const _gap = -2;

/// Result of matching a transcript against the passage.
class WordAlignment {
  const WordAlignment(this.marks, this.matched, this.frontier);

  final List<WordMark> marks;

  /// Passage words the recogniser heard.
  final Set<int> matched;

  /// Index of the furthest matched word, -1 before the first one.
  final int frontier;

  int get matchedCount => matched.length;
}

/// Lines a speech transcript up with the passage and marks each word.
///
/// Uses a sequence alignment (Needleman–Wunsch with a free tail on the
/// passage, since the learner has only read part of it) instead of comparing
/// positions, so a skipped, extra or repeated word shifts nothing after it.
/// Words match exactly, as homophones, or within a small edit distance for
/// longer words ("colour"/"color"). Two heard words may also match one
/// passage word ("well known" → "well-known").
class WordAligner {
  WordAligner(this.reference)
    : _keys = [for (final w in reference.words) w.key];

  final ReferenceText reference;
  final List<String> _keys;

  /// Cached word-pair scores: they repeat across the many partial results.
  final _fitCache = <String, int>{};

  /// A missed word turns red only after this many later words were heard.
  static const confirmAfter = 2;

  /// How far back a re-read word may be picked up again.
  static const rereadWindow = 40;

  int _fit(String ref, String heard) {
    if (ref == heard) return _exact;
    final cacheKey = '$ref|$heard';
    final cached = _fitCache[cacheKey];
    if (cached != null) return cached;
    var score = _wrong;
    final hr = _homophoneOf[ref];
    if (hr != null && hr == _homophoneOf[heard]) {
      score = _exact;
    } else if (ref.length >= 4) {
      final allowed = ref.length >= 8 ? 2 : 1;
      if ((ref.length - heard.length).abs() <= allowed &&
          _levenshtein(ref, heard, allowed) <= allowed) {
        score = _close;
      }
    }
    _fitCache[cacheKey] = score;
    return score;
  }

  /// Marks every passage word for the words heard so far.
  ///
  /// [locked] holds words matched in earlier, settled results; they stay
  /// green even if a later partial result lines up differently. Pass
  /// [finished] once reading has stopped so pending words become missed.
  WordAlignment align(
    List<String> heard, {
    Set<int> locked = const {},
    bool finished = false,
  }) {
    final n = _keys.length;
    final m = heard.length;
    final matched = <int>{...locked};
    var trailingUnmatched = false;

    if (m > 0 && n > 0) {
      final w = m + 1;
      final score = Int32List((n + 1) * w);
      // 0 = diagonal, 1 = skip passage word, 2 = extra heard word,
      // 3 = two heard words for one passage word.
      final move = Uint8List((n + 1) * w);
      for (var j = 1; j <= m; j++) {
        score[j] = j * _gap;
        move[j] = 2;
      }
      for (var i = 1; i <= n; i++) {
        score[i * w] = i * _gap;
        move[i * w] = 1;
        final ref = _keys[i - 1];
        for (var j = 1; j <= m; j++) {
          var best = score[(i - 1) * w + j - 1] + _fit(ref, heard[j - 1]);
          var how = 0;
          final skip = score[(i - 1) * w + j] + _gap;
          if (skip > best) {
            best = skip;
            how = 1;
          }
          final extra = score[i * w + j - 1] + _gap;
          if (extra > best) {
            best = extra;
            how = 2;
          }
          if (j >= 2 && ref.length >= 4 && ref == heard[j - 2] + heard[j - 1]) {
            final joined = score[(i - 1) * w + j - 2] + _exact;
            if (joined > best) {
              best = joined;
              how = 3;
            }
          }
          score[i * w + j] = best;
          move[i * w + j] = how;
        }
      }

      // The learner has read a prefix of the passage: end wherever scores best.
      var endI = 0;
      for (var i = 1; i <= n; i++) {
        if (score[i * w + m] > score[endI * w + m]) endI = i;
      }

      final heardUsed = List<bool>.filled(m, false);
      var lastHeardMatch = -1;
      var i = endI, j = m;
      while (i > 0 || j > 0) {
        final how = move[i * w + j];
        if (i > 0 && j > 0 && how == 0) {
          if (_fit(_keys[i - 1], heard[j - 1]) > 0) {
            matched.add(i - 1);
            heardUsed[j - 1] = true;
            lastHeardMatch = math.max(lastHeardMatch, j - 1);
          }
          i--;
          j--;
        } else if (i > 0 && j > 1 && how == 3) {
          matched.add(i - 1);
          heardUsed[j - 1] = heardUsed[j - 2] = true;
          lastHeardMatch = math.max(lastHeardMatch, j - 1);
          i--;
          j -= 2;
        } else if (i > 0 && (how == 1 || j == 0)) {
          i--;
        } else {
          j--;
        }
      }
      trailingUnmatched = lastHeardMatch < m - 1;
      _recoverRereads(heard, heardUsed, matched);
    }

    final frontier = matched.isEmpty ? -1 : matched.reduce(math.max);
    final marks = List<WordMark>.filled(n, WordMark.unread);
    var laterMatches = 0;
    for (var k = frontier; k >= 0; k--) {
      if (matched.contains(k)) {
        marks[k] = WordMark.matched;
        laterMatches++;
      } else {
        marks[k] = finished || laterMatches >= confirmAfter
            ? WordMark.missed
            : WordMark.pending;
      }
    }
    // Something was said after the last match: the next word may be on its way.
    if (!finished && trailingUnmatched && frontier + 1 < n) {
      marks[frontier + 1] = WordMark.pending;
    }
    return WordAlignment(marks, matched, frontier);
  }

  /// The alignment only moves forward, so going back to re-read a missed
  /// word leaves the heard words unused. Pick those up again when two
  /// neighbouring words agree, so a lone "the" cannot match at random.
  void _recoverRereads(
    List<String> heard,
    List<bool> heardUsed,
    Set<int> matched,
  ) {
    if (matched.isEmpty) return;
    final frontier = matched.reduce(math.max);
    final from = math.max(0, frontier - rereadWindow);
    for (var j = 0; j < heard.length; j++) {
      if (heardUsed[j]) continue;
      for (var k = frontier - 1; k >= from; k--) {
        if (matched.contains(k) || _fit(_keys[k], heard[j]) <= 0) continue;
        final before = j > 0 && k > 0 && _fit(_keys[k - 1], heard[j - 1]) > 0;
        final after =
            j + 1 < heard.length &&
            k + 1 < _keys.length &&
            _fit(_keys[k + 1], heard[j + 1]) > 0;
        if (before || after) {
          matched.add(k);
          heardUsed[j] = true;
          break;
        }
      }
    }
  }
}

/// Edit distance between [a] and [b], giving up early once it exceeds [limit].
int _levenshtein(String a, String b, int limit) {
  var prev = List<int>.generate(b.length + 1, (i) => i);
  var curr = List<int>.filled(b.length + 1, 0);
  for (var i = 1; i <= a.length; i++) {
    curr[0] = i;
    var rowMin = i;
    for (var j = 1; j <= b.length; j++) {
      final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
      curr[j] = math.min(
        math.min(curr[j - 1] + 1, prev[j] + 1),
        prev[j - 1] + cost,
      );
      rowMin = math.min(rowMin, curr[j]);
    }
    if (rowMin > limit) return limit + 1;
    final t = prev;
    prev = curr;
    curr = t;
  }
  return prev[b.length];
}
