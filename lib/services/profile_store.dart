import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../ui/topics.dart';

/// Skill levels a learner can pick; words in words.json carry the same numbers.
const kLevelNames = {1: 'Beginner', 2: 'Intermediate', 3: 'Advanced'};

/// The app's character: the Scroll Patrol officer or the original ghost.
enum MascotStyle { police, ghost }

/// Daily word goals offered in onboarding and Profile.
const kDailyGoals = [10, 20, 50];

/// Locally stored learner profile, filled in during onboarding.
class ProfileStore extends ChangeNotifier {
  ProfileStore._();

  static final ProfileStore instance = ProfileStore._();

  late SharedPreferences _prefs;

  String _name = '';
  Set<String> _topics = {};
  bool _onboarded = false;
  bool _darkTheme = false;
  MascotStyle _mascot = MascotStyle.police;
  bool _flowMaths = false;
  String? _flowCode;
  int? _scrollHours;
  Map<String, Object?> _setup = const {};
  int _answered = 0;
  int _correct = 0;

  String _language = 'en';
  int _level = 1;
  int _dailyGoal = 10;
  Set<String> _learned = {};
  Set<String> _checkpoints = {};
  int _learnedToday = 0;
  int _todayKey = 0;
  int _streak = 0;
  int _lastLearnDay = 0;

  String get name => _name;
  Set<String> get topics => _topics;
  bool get onboarded => _onboarded;

  /// Light is the default; the user's explicit choice is remembered.
  bool get darkTheme => _darkTheme;

  /// Which character shows across the app.
  MascotStyle get mascot => _mascot;

  String get firstName => _name.trim().split(' ').first;

  /// The one language the learning path follows.
  String get language => _language;

  /// The learner's own guess at daily scrolling, 1–8 hours, from onboarding.
  /// Not measured usage.
  int? get scrollHoursEstimate => _scrollHours;

  /// What was switched on in onboarding's setup step (see [saveSetup]).
  Map<String, Object?> get onboardingSetup => _setup;

  /// WordFlow shows maths questions instead of [language] words.
  bool get flowMaths => _flowMaths;

  /// WordFlow shows this coding language ('python' or 'javascript') instead.
  String? get flowCode => _flowCode;

  /// Starting skill level, 1–3 (see [kLevelNames]).
  int get level => _level;
  String get levelName => kLevelNames[_level]!;

  /// Words to learn per day.
  int get dailyGoal => _dailyGoal;

  /// Words finished in a lesson today (resets at midnight).
  int get learnedToday =>
      _todayKey == _dayKey(DateTime.now()) ? _learnedToday : 0;

  /// Consecutive days with at least one word learned, counting today or yesterday.
  int get streak {
    final today = _dayKey(DateTime.now());
    final yesterday = _dayKey(DateTime.now().subtract(const Duration(days: 1)));
    return _lastLearnDay == today || _lastLearnDay == yesterday ? _streak : 0;
  }

  bool isLearned(String wordKey) => _learned.contains(wordKey);

  /// Words learned in [lang] through the path.
  int learnedIn(String lang) =>
      _learned.where((k) => k.startsWith('$lang|')).length;

  bool checkpointPassed(String lang, int level) =>
      _checkpoints.contains('$lang:$level');

  /// Quiz accuracy as a whole percent, or null until a question has been answered.
  int? get accuracy =>
      _answered == 0 ? null : (_correct * 100 / _answered).round();

  static int _dayKey(DateTime d) => d.year * 10000 + d.month * 100 + d.day;

  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    _name = _prefs.getString('name') ?? '';
    _topics = (_prefs.getStringList('topics') ?? const []).toSet();
    _onboarded = _prefs.getBool('onboarded') ?? false;
    _darkTheme = _prefs.getBool('dark_theme') ?? false;
    _mascot =
        MascotStyle.values.asNameMap()[_prefs.getString('mascot')] ??
        MascotStyle.police;
    _flowMaths = _prefs.getBool('flow_maths') ?? false;
    _flowCode = _prefs.getString('flow_code');
    _scrollHours = _prefs.getInt('scroll_hours_estimate');
    try {
      final raw = _prefs.getString('onboarding_setup');
      _setup = raw == null
          ? const {}
          : (jsonDecode(raw) as Map).cast<String, Object?>();
    } catch (_) {
      _setup = const {};
    }
    _answered = _prefs.getInt('answered') ?? 0;
    _correct = _prefs.getInt('correct') ?? 0;
    // Profiles from before single-language onboarding fall back to their first topic.
    _language =
        _prefs.getString('language') ??
        (_topics.isEmpty || _topics.contains('en') ? 'en' : _topics.first);
    // Hindi was removed; its learners move to English.
    if (!kWordLanguageCodes.contains(_language)) {
      _language = 'en';
      _topics = {'en'};
    }
    _level = _prefs.getInt('level') ?? 1;
    _dailyGoal = _prefs.getInt('daily_goal') ?? 10;
    _learned = (_prefs.getStringList('learned_words') ?? const []).toSet();
    _checkpoints = (_prefs.getStringList('checkpoints') ?? const []).toSet();
    _learnedToday = _prefs.getInt('learned_today') ?? 0;
    _todayKey = _prefs.getInt('learned_today_key') ?? 0;
    _streak = _prefs.getInt('learn_streak') ?? 0;
    _lastLearnDay = _prefs.getInt('last_learn_day') ?? 0;
  }

  Future<void> setName(String value) async {
    _name = value.trim();
    await _prefs.setString('name', _name);
    notifyListeners();
  }

  Future<void> setTopics(Set<String> value) async {
    _topics = Set.of(value);
    await _prefs.setStringList('topics', _topics.toList());
    notifyListeners();
  }

  /// Picks the path language; topics follow so older screens stay in sync.
  Future<void> setLanguage(String code) async {
    _language = code;
    await _prefs.setString('language', code);
    await setTopics({code, if (_topics.contains(kMathsCode)) kMathsCode});
  }

  Future<void> setScrollHoursEstimate(int hours) async {
    _scrollHours = hours.clamp(1, 8);
    await _prefs.setInt('scroll_hours_estimate', _scrollHours!);
    notifyListeners();
  }

  /// Records onboarding's setup choices and the permission states at the end.
  Future<void> saveSetup(Map<String, Object?> setup) async {
    _setup = Map.unmodifiable(setup);
    await _prefs.setString('onboarding_setup', jsonEncode(setup));
    notifyListeners();
  }

  Future<void> setFlowMaths(bool value) async {
    _flowMaths = value;
    _flowCode = null;
    await _prefs.setBool('flow_maths', value);
    await _prefs.remove('flow_code');
    notifyListeners();
  }

  /// The WordFlow filter chip chosen for [feed], remembered per subject.
  String flowFilter(String feed) =>
      _prefs.getString('flow_filter_$feed') ?? 'all';

  Future<void> setFlowFilter(String feed, String filter) async {
    await _prefs.setString('flow_filter_$feed', filter);
    notifyListeners();
  }

  Future<void> setFlowCode(String code) async {
    _flowMaths = false;
    _flowCode = code;
    await _prefs.setBool('flow_maths', false);
    await _prefs.setString('flow_code', code);
    notifyListeners();
  }

  Future<void> setLevel(int value) async {
    _level = value.clamp(1, 3);
    await _prefs.setInt('level', _level);
    notifyListeners();
  }

  Future<void> setDailyGoal(int value) async {
    _dailyGoal = value;
    await _prefs.setInt('daily_goal', value);
    notifyListeners();
  }

  Future<void> setDarkTheme(bool value) async {
    _darkTheme = value;
    await _prefs.setBool('dark_theme', value);
    notifyListeners();
  }

  Future<void> setMascot(MascotStyle value) async {
    _mascot = value;
    await _prefs.setString('mascot', value.name);
    notifyListeners();
  }

  /// For the quiz feature: records one answered question.
  Future<void> recordAnswer({required bool correct}) async {
    _answered++;
    if (correct) _correct++;
    await _prefs.setInt('answered', _answered);
    await _prefs.setInt('correct', _correct);
    notifyListeners();
  }

  /// Marks the words of a finished lesson learned and moves today's count and the streak.
  Future<void> markLearned(Iterable<String> wordKeys) async {
    final fresh = wordKeys.where((k) => !_learned.contains(k)).toList();
    if (fresh.isEmpty) return;
    _learned.addAll(fresh);

    final now = DateTime.now();
    final today = _dayKey(now);
    _learnedToday = learnedToday + fresh.length;
    _todayKey = today;
    if (_lastLearnDay != today) {
      final yesterday = _dayKey(now.subtract(const Duration(days: 1)));
      _streak = _lastLearnDay == yesterday ? _streak + 1 : 1;
      _lastLearnDay = today;
    }

    await _prefs.setStringList('learned_words', _learned.toList());
    await _prefs.setInt('learned_today', _learnedToday);
    await _prefs.setInt('learned_today_key', _todayKey);
    await _prefs.setInt('learn_streak', _streak);
    await _prefs.setInt('last_learn_day', _lastLearnDay);
    notifyListeners();
  }

  Future<void> passCheckpoint(String lang, int level) async {
    _checkpoints.add('$lang:$level');
    await _prefs.setStringList('checkpoints', _checkpoints.toList());
    notifyListeners();
  }

  Future<void> completeOnboarding() async {
    _onboarded = true;
    await _prefs.setBool('onboarded', true);
    notifyListeners();
  }

  /// The profile as stored in Firestore (see CloudSync).
  Map<String, Object?> toCloud() => {
    'name': _name,
    'settings': {
      'language': _language,
      'level': _level,
      'levelName': levelName,
      'dailyGoal': _dailyGoal,
      'topics': _topics.toList(),
      'darkTheme': _darkTheme,
      'mascot': _mascot.name,
      'flowMaths': _flowMaths,
      'scrollHoursEstimate': _scrollHours,
      'onboarding': _setup,
      'onboarded': _onboarded,
    },
    'progress': {
      'learnedWords': _learned.toList(),
      'learnedCount': _learned.length,
      'checkpoints': _checkpoints.toList(),
      'learnedToday': learnedToday,
      'learnedTodayKey': _todayKey,
      'streak': streak,
      'streakCount': _streak,
      'lastLearnDay': _lastLearnDay,
      'quizAnswered': _answered,
      'quizCorrect': _correct,
      'quizAccuracy': accuracy,
    },
  };

  /// Folds progress saved in Firestore into this phone's, keeping the best of
  /// both: learned words and checkpoints are combined, counters keep the
  /// higher value. Settings chosen on this phone stay; only an empty name is
  /// filled in.
  Future<void> mergeCloud(Map<String, dynamic> data) async {
    final progress = (data['progress'] as Map?)?.cast<String, dynamic>();
    final cloudName = data['name'] as String?;
    var changed = false;

    if (_name.isEmpty && cloudName != null && cloudName.isNotEmpty) {
      _name = cloudName;
      await _prefs.setString('name', _name);
      changed = true;
    }
    if (progress != null) {
      List<String> strings(Object? v) =>
          v is List ? v.whereType<String>().toList() : const [];
      int number(Object? v) => v is num ? v.toInt() : 0;

      final learned = strings(progress['learnedWords']);
      final checkpoints = strings(progress['checkpoints']);
      if (!_learned.containsAll(learned) ||
          !_checkpoints.containsAll(checkpoints)) {
        _learned.addAll(learned);
        _checkpoints.addAll(checkpoints);
        await _prefs.setStringList('learned_words', _learned.toList());
        await _prefs.setStringList('checkpoints', _checkpoints.toList());
        changed = true;
      }

      final answered = number(progress['quizAnswered']);
      if (answered > _answered) {
        _answered = answered;
        _correct = number(progress['quizCorrect']);
        await _prefs.setInt('answered', _answered);
        await _prefs.setInt('correct', _correct);
        changed = true;
      }

      // The streak that was moved most recently wins; on the same day, the longer one.
      final lastDay = number(progress['lastLearnDay']);
      final cloudStreak = number(progress['streakCount']);
      if (lastDay > _lastLearnDay ||
          (lastDay == _lastLearnDay && cloudStreak > _streak)) {
        _lastLearnDay = lastDay;
        _streak = cloudStreak;
        await _prefs.setInt('learn_streak', _streak);
        await _prefs.setInt('last_learn_day', _lastLearnDay);
        changed = true;
      }

      final todayKey = number(progress['learnedTodayKey']);
      final today = number(progress['learnedToday']);
      if (todayKey > _todayKey ||
          (todayKey == _todayKey && today > _learnedToday)) {
        _todayKey = todayKey;
        _learnedToday = today;
        await _prefs.setInt('learned_today', _learnedToday);
        await _prefs.setInt('learned_today_key', _todayKey);
        changed = true;
      }
    }
    if (changed) notifyListeners();
  }
}
