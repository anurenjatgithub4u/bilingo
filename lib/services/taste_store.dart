import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Topics a learner can be into, shown as chips and used to tag content.
const kInterestTopics = {
  'travel': 'Travel',
  'food': 'Food',
  'nature': 'Nature',
  'sports': 'Sports',
  'technology': 'Technology',
  'business': 'Work & business',
  'science': 'Science',
  'education': 'Learning',
  'entertainment': 'Movies & music',
  'daily life': 'Daily life',
  'feelings': 'People & feelings',
};

/// Topic for a reading text's heading; unknown ones count as daily life.
String readingTopic(String heading) => switch (heading) {
  'Technology' => 'technology',
  'Food' => 'food',
  'Sports' => 'sports',
  'Feelings' => 'feelings',
  'Work' => 'business',
  'Nature' => 'nature',
  'Education' => 'education',
  'Travel' => 'travel',
  'Science' => 'science',
  'Environment' || 'Weather' => 'nature',
  'Personal Development' => 'feelings',
  'Business' => 'business',
  _ => 'daily life',
};

/// Coding concept a snippet is mainly about.
String codeTopic(String code) {
  if (RegExp(r'\bclass\b').hasMatch(code)) return 'code:classes';
  if (RegExp(r'\b(async|await|Promise|setTimeout)\b').hasMatch(code)) {
    return 'code:async';
  }
  if (RegExp(r'\b(def|function|lambda)\b|=>').hasMatch(code)) {
    return 'code:functions';
  }
  if (RegExp(r'\b(for|while)\b').hasMatch(code)) return 'code:loops';
  if (code.contains('[') || code.contains('{')) return 'code:collections';
  return 'code:basics';
}

const _wordTopics = {
  'travel': [
    'en|journey',
    'en|wander',
    'en|explore',
    'en|ancient',
    'en|yearn',
    'de|Fernweh',
    'de|Wanderlust',
    'de|Reise',
    'de|Zug',
    'de|Ausflug',
    'de|unterwegs',
    'de|Abenteuer',
    'de|Stadt',
    'de|Heimat',
  ],
  'food': [
    'en|delicious',
    'de|Apfel',
    'de|Brot',
    'de|Essen',
    'de|Küche',
    'de|Kummerspeck',
    'de|Schlaraffenland',
  ],
  'nature': [
    'en|petrichor',
    'en|tranquil',
    'en|flourish',
    'en|radiant',
    'en|thrive',
    'en|halcyon',
    'de|Waldeinsamkeit',
    'de|Schmetterling',
    'de|Eichhörnchen',
    'de|Katze',
    'de|Hund',
    'de|Sonne',
    'de|Mond',
    'de|Himmel',
    'de|Blume',
    'de|Baum',
    'de|Regen',
    'de|Wetter',
    'de|Wasser',
    'de|Umwelt',
  ],
  'technology': [
    'en|obsolete',
    'en|versatile',
    'en|redundant',
    'de|Kabelsalat',
    'de|Fortschritt',
  ],
  'business': [
    'en|schedule',
    'en|negotiate',
    'en|opportunity',
    'en|effort',
    'en|diligent',
    'en|reliable',
    'en|feasible',
    'en|persuade',
    'en|pragmatic',
    'en|recommend',
    'en|catalyst',
    'en|meticulous',
    'en|frugal',
    'de|Arbeit',
    'de|Fachkraft',
    'de|Leistung',
    'de|Erfolg',
    'de|Ziel',
    'de|erledigen',
    'de|Herausforderung',
    'de|Pünktlichkeit',
    'de|Gelegenheit',
    'de|Verantwortung',
    'de|Ehrgeiz',
  ],
  'science': [
    'en|paradox',
    'en|hindsight',
    'en|plausible',
    'en|panacea',
    'de|Zusammenhang',
  ],
  'education': [
    'en|improve',
    'en|concise',
    'en|coherent',
    'en|elaborate',
    'en|emphasize',
    'en|convey',
    'en|eloquent',
    'en|lucid',
    'en|verbose',
    'en|esoteric',
    'en|nuance',
    'en|obfuscate',
    'en|curious',
    'en|purpose',
    'de|Schule',
    'de|lernen',
    'de|Wortschatz',
    'de|Ausbildung',
    'de|Gedächtnis',
    'de|Erfahrung',
    'de|Geistesblitz',
    'de|Buch',
    'de|Neugier',
    'de|Zungenbrecher',
  ],
  'entertainment': [
    'en|cacophony',
    'en|mellifluous',
    'en|whimsical',
    'de|Ohrwurm',
    'de|Kopfkino',
    'de|Ohrenschmaus',
  ],
  'daily life': [
    'en|borrow',
    'en|neighbour',
    'en|cozy',
    'en|habit',
    'en|gather',
    'en|quiet',
    'en|celebrate',
    'en|advice',
    'en|decide',
    'en|mundane',
    'en|wholesome',
    'de|Haus',
    'de|Tisch',
    'de|Fenster',
    'de|Tür',
    'de|Wohnzimmer',
    'de|Familie',
    'de|Freund',
    'de|Zeit',
    'de|Morgen',
    'de|Nacht',
    'de|Geschenk',
    'de|Geburtstag',
    'de|Feierabend',
    'de|Bürgersteig',
    'de|Gesundheit',
    'de|gemütlich',
    'de|Gewohnheit',
    'de|Aufwiedersehen',
  ],
};

final Map<String, String> _topicOfWord = {
  for (final e in _wordTopics.entries)
    for (final word in e.value) word: e.key,
};

/// Topic of a word id ("lang|word"). Most of the list is about character and
/// emotion, so that's the default.
String wordTopic(String id) => _topicOfWord[id] ?? 'feelings';

/// What each learner enjoys, learned from what they do and kept only on the
/// phone. It changes the order of a feed, never its level.
class TasteStore {
  TasteStore._();

  static final TasteStore instance = TasteStore._();

  static const _key = 'taste_scores';
  static const _askedKey = 'taste_asked';
  static const _dayKey = 'taste_day';

  /// Scores shrink by this each day, so a feed follows changing interests.
  static const _dailyFade = 0.98;
  static const _maxScore = 20.0;
  static const _minScore = -5.0;

  /// A topic the learner picks themselves starts this high.
  static const _pickedScore = 4.0;

  static const save = 3.0;
  static const share = 3.0;
  static const like = 2.0;
  static const answered = 0.5;
  static const skipped = -0.5;

  @visibleForTesting
  static DateTime Function() clock = DateTime.now;

  SharedPreferences? _prefs;
  bool _loaded = false;
  bool _asked = false;
  final _scores = <String, double>{};

  /// Topics of the reel on screen, for actions that happen deep in a card.
  List<String> current = const [];

  int get _today => clock().difference(DateTime(1970)).inDays;

  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    _scores.clear();
    current = const [];
    _asked = _prefs!.getBool(_askedKey) ?? false;
    try {
      final raw = _prefs!.getString(_key);
      if (raw != null) {
        (jsonDecode(raw) as Map).cast<String, num>().forEach(
          (k, v) => _scores[k] = v.toDouble(),
        );
      }
    } catch (_) {
      // Unreadable: it learns again.
    }
    final last = _prefs!.getInt(_dayKey);
    final today = _today;
    if (last != null && today > last) {
      var fade = 1.0;
      for (var d = last; d < today; d++) {
        fade *= _dailyFade;
      }
      _scores.updateAll((_, v) => v * fade);
    }
    await _prefs!.setInt(_dayKey, today);
    _loaded = true;
  }

  Future<void> ensureLoaded() async {
    if (!_loaded) await load();
  }

  /// Whether the learner has seen the "what are you into" question.
  bool get asked => _asked;

  double score(String topic) => _scores[topic] ?? 0;

  /// The strongest of [topics], for ranking something with several.
  double scoreOf(List<String> topics) {
    var best = double.negativeInfinity;
    for (final t in topics) {
      final s = score(t);
      if (s > best) best = s;
    }
    return best == double.negativeInfinity ? 0 : best;
  }

  void signal(List<String> topics, double delta) {
    for (final t in topics) {
      _scores[t] = (score(t) + delta).clamp(_minScore, _maxScore);
    }
    _save();
  }

  /// Applies a signal to whatever reel is on screen.
  void signalCurrent(double delta) => signal(current, delta);

  /// Topics from [kInterestTopics] the learner clearly likes.
  Set<String> get picked => {
    for (final t in kInterestTopics.keys)
      if (score(t) >= _pickedScore - 0.5) t,
  };

  /// Saves the learner's own choice; unticked topics lose their head start.
  Future<void> setPicked(Set<String> topics) async {
    for (final t in kInterestTopics.keys) {
      if (topics.contains(t)) {
        if (score(t) < _pickedScore) _scores[t] = _pickedScore;
      } else if (score(t) > 0) {
        _scores[t] = 0;
      }
    }
    await markAsked();
    _save();
  }

  Future<void> markAsked() async {
    _asked = true;
    await _prefs?.setBool(_askedKey, true);
  }

  void _save() => _prefs?.setString(_key, jsonEncode(_scores));
}
