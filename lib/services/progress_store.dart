import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// XP for answering a reel, right or wrong.
const kXpCorrect = 10;
const kXpTried = 3;

/// What content difficulty 1, 2 and 3 are called on reels and in the picker.
const kDifficultyNames = {1: 'Easy', 2: 'Medium', 3: 'Hard'};

/// Harder content earns more, so picking Easy is never the quick way to XP.
double xpMultiplier(int difficulty) => switch (difficulty) {
  3 => 2.0,
  2 => 1.5,
  _ => 1.0,
};

/// XP for one answer to content of [difficulty] (1–3), bonus included.
int xpFor({required bool correct, int bonus = 0, int difficulty = 1}) =>
    (((correct ? kXpCorrect : kXpTried) + bonus) * xpMultiplier(difficulty))
        .round();

/// XP needed to go from level [level] to the next. Grows, then stops growing,
/// so a regular learner keeps levelling up every few days at any level.
int xpForLevel(int level) => math.min(100 + 15 * (level - 1), 600);

/// The name for a level. Levels themselves never end.
String rankName(int level) => switch (level) {
  < 10 => 'Beginner',
  < 25 => 'Explorer',
  < 50 => 'Achiever',
  < 100 => 'Expert',
  < 200 => 'Master',
  _ => 'Legend',
};

/// What one answer earned.
class Reward {
  const Reward({
    required this.subject,
    required this.xp,
    required this.level,
    required this.leveledUp,
  });

  final String subject;
  final int xp;

  /// The level after this answer.
  final int level;
  final bool leveledUp;
}

/// One subject's level as the screens show it.
class SubjectLevel {
  const SubjectLevel(this.level, this.xpIntoLevel, this.xpNeeded, this.tier);

  final int level;
  final int xpIntoLevel;
  final int xpNeeded;

  /// Content difficulty: 1 beginner, 2 intermediate, 3 advanced.
  final int tier;

  String get rank => rankName(level);
  double get fraction => xpIntoLevel / xpNeeded;
}

class _Subject {
  _Subject({required this.stage});

  int xp = 0;
  int stage;
  int answered = 0;

  /// The difficulty the learner picked (1–3), or null for Auto.
  int? choice;

  /// For accuracy: answers counted, and how many of them were right.
  int judged = 0;
  int correct = 0;
  final recent = <bool>[];

  Map<String, Object> toJson() => {
    'xp': xp,
    'stage': stage,
    'answered': answered,
    'judged': judged,
    'correct': correct,
    'recent': recent,
    'choice': ?choice,
  };

  factory _Subject.fromJson(Map<String, dynamic> j) =>
      _Subject(stage: (j['stage'] as num?)?.toInt() ?? 1)
        ..xp = (j['xp'] as num?)?.toInt() ?? 0
        ..answered = (j['answered'] as num?)?.toInt() ?? 0
        ..judged = (j['judged'] as num?)?.toInt() ?? 0
        ..correct = (j['correct'] as num?)?.toInt() ?? 0
        ..recent.addAll(((j['recent'] as List?) ?? const []).cast<bool>())
        ..choice = switch ((j['choice'] as num?)?.toInt()) {
          final int c when c >= 1 && c <= 3 => c,
          _ => null,
        };
}

/// Levels and word mastery, kept on the phone and copied to Firestore by
/// CloudSync.
///
/// Two separate numbers per subject: the **level** comes from XP, never goes
/// down and never ends. The hidden **stage** (1–30, ten per tier) picks how
/// hard the content is and follows recent results up and down.
class ProgressStore extends ChangeNotifier {
  ProgressStore._();

  static final ProgressStore instance = ProgressStore._();

  static const _subjectsKey = 'reel_progress';
  static const _masteryKey = 'word_mastery';
  static const _streakKey = 'practice_streak';
  static const _learningKey = 'learning_time';
  static const _answeredKey = 'answered_today';
  static const _hardKey = 'hard_today';

  /// Credit per step, so a reel left open doesn't count as study.
  static const _maxStepMs = 60000;

  /// A longer gap than this means they stopped; the time isn't counted at all.
  static const _idleMs = 180000;

  /// Days until a word is due again, by mastery box.
  static const _intervals = [1, 3, 7, 30, 90];

  /// Box at which a word counts as known or mastered.
  static const _knownBox = 2;
  static const _masteredBox = 4;

  @visibleForTesting
  static DateTime Function() clock = DateTime.now;

  SharedPreferences? _prefs;
  bool _loaded = false;
  final _subjects = <String, _Subject>{};
  int _practiceStreak = 0;

  /// Today's real learning time, and which day it belongs to.
  int _learningMs = 0;
  int _learningDay = -1;
  DateTime? _lastActive;
  int _lastPracticeDay = -10;

  /// Reels answered today, any subject, and which day that count is for.
  int _answeredToday = 0;
  int _answeredDay = -1;

  /// Reels answered today while playing at a picked Hard difficulty.
  int _hardToday = 0;
  int _hardDay = -1;

  /// Word id → (box, day it is next due).
  final _mastery = <String, (int, int)>{};

  /// Tier a subject starts on the first time it is opened.
  int startTier = 1;

  int get _today => clock().difference(DateTime(1970)).inDays;

  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    _subjects.clear();
    _mastery.clear();
    final learning = _prefs!.getStringList(_learningKey);
    _learningDay = int.tryParse(learning?.first ?? '') ?? -1;
    _learningMs = int.tryParse(learning?.last ?? '') ?? 0;
    _lastActive = null;
    final hard = _prefs!.getStringList(_hardKey);
    _hardDay = int.tryParse(hard?.first ?? '') ?? -1;
    _hardToday = int.tryParse(hard?.last ?? '') ?? 0;
    final answered = _prefs!.getStringList(_answeredKey);
    _answeredDay = int.tryParse(answered?.first ?? '') ?? -1;
    _answeredToday = int.tryParse(answered?.last ?? '') ?? 0;
    final streak = _prefs!.getStringList(_streakKey);
    _practiceStreak = int.tryParse(streak?.first ?? '') ?? 0;
    _lastPracticeDay = int.tryParse(streak?.last ?? '') ?? -10;
    try {
      final raw = _prefs!.getString(_subjectsKey);
      if (raw != null) {
        (jsonDecode(raw) as Map).cast<String, dynamic>().forEach((k, v) {
          _subjects[k] = _Subject.fromJson((v as Map).cast<String, dynamic>());
        });
      }
      final words = _prefs!.getString(_masteryKey);
      if (words != null) {
        (jsonDecode(words) as Map).cast<String, dynamic>().forEach((k, v) {
          final pair = (v as List).cast<num>();
          _mastery[k] = (pair[0].toInt(), pair[1].toInt());
        });
      }
    } catch (_) {
      // Unreadable: start afresh rather than block the app.
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> ensureLoaded() async {
    if (!_loaded) await load();
  }

  _Subject _subject(String code) => _subjects.putIfAbsent(
    code,
    () => _Subject(stage: (startTier - 1) * 10 + 1),
  );

  /// Subjects with at least one answer.
  List<String> get startedSubjects => [
    for (final e in _subjects.entries)
      if (e.value.answered > 0) e.key,
  ];

  SubjectLevel levelOf(String code) {
    final s = _subject(code);
    var level = 1;
    var left = s.xp;
    while (left >= xpForLevel(level)) {
      left -= xpForLevel(level);
      level++;
    }
    return SubjectLevel(level, left, xpForLevel(level), tierOf(code));
  }

  /// The difficulty Auto would pick for [code] from recent results.
  int tierOf(String code) => (_subject(code).stage - 1) ~/ 10 + 1;

  /// The difficulty the learner picked for [code], or null for Auto.
  int? chosenTier(String code) => _subjects[code]?.choice;

  /// The difficulty a feed for [code] is built at: the learner's pick, else
  /// Auto's.
  int feedTier(String code) => chosenTier(code) ?? tierOf(code);

  /// Picks the difficulty for [code]: 1–3, or null to follow results again.
  Future<void> setDifficulty(String code, int? tier) async {
    final s = _subject(code);
    final value = tier != null && tier >= 1 && tier <= 3 ? tier : null;
    if (s.choice == value) return;
    s.choice = value;
    // Answers given at a picked difficulty don't move Auto's stage.
    s.recent.clear();
    await _save();
  }

  /// Reels answered today in any subject, for the daily goal.
  int get answeredToday => _answeredDay == _today ? _answeredToday : 0;

  /// Reels answered today with Hard picked, any subject (free: a few a day).
  int get hardAnsweredToday => _hardDay == _today ? _hardToday : 0;

  /// Milliseconds of active learning today.
  int get learningTodayMs => _learningDay == _today ? _learningMs : 0;

  /// Marks a moment of real activity: a swipe, an answer. The time since the
  /// last one counts as learning, up to a limit.
  void touchLearning() {
    final now = clock();
    final last = _lastActive;
    _lastActive = now;
    if (last == null) return;
    final gap = now.difference(last).inMilliseconds;
    if (gap <= 0 || gap > _idleMs) return;
    addLearning(math.min(gap, _maxStepMs));
  }

  /// Adds measured learning, such as a timed lesson or reading.
  void addLearning(int ms) {
    final today = _today;
    if (_learningDay != today) {
      _learningDay = today;
      _learningMs = 0;
    }
    _learningMs += ms;
    _prefs?.setStringList(_learningKey, ['$_learningDay', '$_learningMs']);
  }

  /// Questions answered correctly in this subject.
  int correctIn(String code) => _subject(code).correct;

  /// Whole percent right in this subject, or null before any answer.
  int? accuracyIn(String code) {
    final s = _subject(code);
    return s.judged == 0 ? null : (s.correct * 100 / s.judged).round();
  }

  /// Days in a row with at least one reel answered, counting today or
  /// yesterday; any subject counts.
  int get practiceStreak =>
      _today - _lastPracticeDay <= 1 ? _practiceStreak : 0;

  void _touchStreak() {
    final today = _today;
    if (_lastPracticeDay == today) return;
    _practiceStreak = today - _lastPracticeDay == 1 ? _practiceStreak + 1 : 1;
    _lastPracticeDay = today;
  }

  /// Records one answered reel of [difficulty] (1–3), which sets the XP.
  /// [wordId] also moves that word's mastery.
  Reward record(
    String code, {
    required bool correct,
    int bonus = 0,
    String? wordId,
    int difficulty = 1,
  }) {
    final s = _subject(code);
    final before = levelOf(code).level;
    final xp = xpFor(correct: correct, bonus: bonus, difficulty: difficulty);
    s
      ..xp += xp
      ..answered += 1
      ..judged += 1
      ..correct += correct ? 1 : 0;
    _touchStreak();
    _answeredToday = answeredToday + 1;
    _answeredDay = _today;
    if (s.choice == 3) {
      _hardToday = hardAnsweredToday + 1;
      _hardDay = _today;
    }
    // Auto follows results; a picked difficulty stays where it was put.
    if (s.choice == null) {
      s.recent.add(correct);
      _adapt(s);
    }
    if (wordId != null) _reviewWord(wordId, correct);
    final after = levelOf(code).level;
    _save();
    return Reward(
      subject: code,
      xp: xp,
      level: after,
      leveledUp: after > before,
    );
  }

  /// Early answers decide quickly, standing in for a placement test; after
  /// that each group of 20 can move the stage one step.
  void _adapt(_Subject s) {
    final early = s.answered <= 30;
    final window = early ? 10 : 20;
    if (s.recent.length < window) return;
    final rate = s.recent.where((r) => r).length / s.recent.length;
    final step = rate >= 0.85
        ? (early ? 5 : 1)
        : rate < 0.55
        ? -1
        : 0;
    s
      ..stage = (s.stage + step).clamp(1, 30)
      ..recent.clear();
  }

  void _reviewWord(String id, bool correct) {
    final today = _today;
    final (box, due) = _mastery[id] ?? (0, today);
    if (!correct) {
      // Falls back and returns tomorrow.
      _mastery[id] = (math.max(0, box - 2), today + 1);
    } else if (due <= today) {
      // Right answers only count when due, so repeats in a day don't farm it.
      final next = math.min(box + 1, _intervals.length);
      _mastery[id] = (next, today + _intervals[next - 1]);
    }
  }

  /// Word ids in [lang] that are due for review, most overdue first.
  List<String> dueWords(String lang) {
    final today = _today;
    final due = [
      for (final e in _mastery.entries)
        if (e.key.startsWith('$lang|') && e.value.$2 <= today) e,
    ]..sort((a, b) => a.value.$2.compareTo(b.value.$2));
    return [for (final e in due) e.key];
  }

  /// Whether the reels show the learner knows word [id] ("lang|word").
  bool isKnown(String id) => (_mastery[id]?.$1 ?? 0) >= _knownBox;

  int masteredCount(String lang) => _countAtLeast(lang, _masteredBox);
  int knownCount(String lang) => _countAtLeast(lang, _knownBox);

  int _countAtLeast(String lang, int box) => _mastery.entries
      .where((e) => e.key.startsWith('$lang|') && e.value.$1 >= box)
      .length;

  /// Bonus XP that no answer earned, such as for paying Scroll Patrol bail.
  Reward addXp(String code, int xp) {
    final s = _subject(code);
    final before = levelOf(code).level;
    s.xp += xp;
    final after = levelOf(code).level;
    _save();
    return Reward(
      subject: code,
      xp: xp,
      level: after,
      leveledUp: after > before,
    );
  }

  Future<void> _save() async {
    notifyListeners();
    await _prefs?.setStringList(_hardKey, ['$_hardDay', '$_hardToday']);
    await _prefs?.setStringList(_answeredKey, [
      '$_answeredDay',
      '$_answeredToday',
    ]);
    await _prefs?.setStringList(_streakKey, [
      '$_practiceStreak',
      '$_lastPracticeDay',
    ]);
    await _prefs?.setString(
      _subjectsKey,
      jsonEncode(_subjects.map((k, v) => MapEntry(k, v.toJson()))),
    );
    await _prefs?.setString(
      _masteryKey,
      jsonEncode(_mastery.map((k, v) => MapEntry(k, [v.$1, v.$2]))),
    );
  }

  Map<String, Object?> toCloud() => {
    'subjects': _subjects.map((k, v) => MapEntry(k, v.toJson())),
    // Firestore keys can't contain every word safely, so a list of triples.
    'mastery': [
      for (final e in _mastery.entries)
        {'id': e.key, 'box': e.value.$1, 'due': e.value.$2},
    ],
  };

  /// Keeps the higher XP and mastery of the phone and the cloud.
  Future<void> mergeCloud(Map<String, dynamic>? data) async {
    if (data == null) return;
    final subjects = (data['subjects'] as Map?)?.cast<String, dynamic>();
    subjects?.forEach((k, v) {
      final cloud = _Subject.fromJson((v as Map).cast<String, dynamic>());
      final mine = _subjects[k];
      if (mine == null || cloud.xp > mine.xp) _subjects[k] = cloud;
    });
    for (final m in (data['mastery'] as List?) ?? const []) {
      final e = (m as Map).cast<String, dynamic>();
      final id = e['id'] as String;
      final box = (e['box'] as num).toInt();
      if ((_mastery[id]?.$1 ?? -1) < box) {
        _mastery[id] = (box, (e['due'] as num).toInt());
      }
    }
    await _save();
  }
}
