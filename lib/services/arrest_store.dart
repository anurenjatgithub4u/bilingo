import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// What Scroll Patrol arrested the learner for.
enum Offence {
  /// Past their limit in a tracked app (booked by the native tracker).
  scrolling,

  /// Turned themselves in on a Wanted poster for missing the daily goal.
  goal,
}

/// One arrest. Bail is paid in answered reels; paying it covers every
/// charge still open.
class Arrest {
  Arrest({
    required this.at,
    required this.offence,
    this.app = '',
    this.minutes = 0,
    this.bailPaid = false,
    this.seen = false,
  });

  final DateTime at;
  final Offence offence;

  /// The app and the minutes in a row, for scrolling arrests.
  final String app;
  final int minutes;

  bool bailPaid;

  /// Shown on the arrest screen already, so it doesn't pop up again.
  bool seen;

  Map<String, Object> toJson() => {
    'at': at.millisecondsSinceEpoch,
    'offence': offence.name,
    'app': app,
    'minutes': minutes,
    'bailPaid': bailPaid,
    'seen': seen,
  };

  factory Arrest.fromJson(Map<String, dynamic> j) => Arrest(
    at: DateTime.fromMillisecondsSinceEpoch((j['at'] as num).toInt()),
    offence: Offence.values.asNameMap()[j['offence']] ?? Offence.scrolling,
    app: j['app'] as String? ?? '',
    minutes: (j['minutes'] as num?)?.toInt() ?? 0,
    bailPaid: j['bailPaid'] as bool? ?? false,
    seen: j['seen'] as bool? ?? false,
  );
}

/// A week of arrests, for the case file in Your Time.
class CaseFile {
  const CaseFile({
    required this.arrests,
    required this.bailPaid,
    required this.longestMinutes,
    required this.topApp,
  });

  final int arrests;
  final int bailPaid;
  final int longestMinutes;

  /// The app with the most scrolling arrests, or null with none.
  final String? topApp;
}

/// Scroll Patrol: arrests, the bail being served, and the evening Wanted
/// poster. It never takes away XP or a streak; every arrest ends in a quick
/// win. Kept on the phone.
class ArrestStore extends ChangeNotifier {
  ArrestStore._();

  static final ArrestStore instance = ArrestStore._();

  /// Reels to answer to pay bail for scrolling.
  static const bailReels = 3;

  /// XP for paying bail, and for turning yourself in on a Wanted poster.
  static const bailXp = 30;
  static const wantedXp = 20;

  /// Most reels a Wanted poster asks for.
  static const maxWantedBail = 5;

  /// From this hour a missed daily goal makes the learner Wanted.
  static const wantedHour = 18;

  /// An unseen arrest older than this is too late to pop up about.
  static const _freshFor = Duration(hours: 3);

  static const _keep = 100;
  static const _key = 'patrol_arrests';
  static const _bailKey = 'patrol_bail';
  static const _wantedKey = 'patrol_wanted_day';
  static const _totalsKey = 'patrol_totals';

  @visibleForTesting
  static DateTime Function() clock = DateTime.now;

  SharedPreferences? _prefs;
  bool _loaded = false;
  final _arrests = <Arrest>[];
  int _bailLeft = 0;
  int _bailTotal = 0;
  int _bailReward = 0;
  String? _wantedDay;

  /// All-time totals: the list above only keeps the latest arrests.
  int _totalArrests = 0;
  int _totalPaid = 0;

  /// Scroll Patrol warnings, and those the learner stopped in time for.
  int _warnings = 0;
  int _heeded = 0;

  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    _arrests.clear();
    try {
      final raw = _prefs!.getString(_key);
      if (raw != null) {
        _arrests.addAll([
          for (final a in jsonDecode(raw) as List)
            Arrest.fromJson((a as Map).cast<String, dynamic>()),
        ]);
      }
    } catch (_) {
      // Unreadable: a clean record.
    }
    final bail = _prefs!.getStringList(_bailKey);
    _bailLeft = int.tryParse(bail?.elementAtOrNull(0) ?? '') ?? 0;
    _bailTotal = int.tryParse(bail?.elementAtOrNull(1) ?? '') ?? 0;
    _bailReward = int.tryParse(bail?.elementAtOrNull(2) ?? '') ?? 0;
    _wantedDay = _prefs!.getString(_wantedKey);
    final totals = _prefs!.getStringList(_totalsKey);
    int at(int i) => int.tryParse(totals?.elementAtOrNull(i) ?? '') ?? 0;
    // Records from before the totals existed count what the list holds.
    _totalArrests = totals == null ? _arrests.length : at(0);
    _totalPaid = totals == null
        ? _arrests.where((a) => a.bailPaid).length
        : at(1);
    _warnings = at(2);
    _heeded = at(3);
    _loaded = true;
    notifyListeners();
  }

  Future<void> ensureLoaded() async {
    if (!_loaded) await load();
  }

  List<Arrest> get arrests => List.unmodifiable(_arrests);

  /// Every arrest ever, and how many of them ended with bail paid.
  int get totalArrests => _totalArrests;
  int get totalPaid => _totalPaid;

  /// Warnings given, and how many the learner stopped scrolling for.
  int get warnings => _warnings;
  int get heeded => _heeded;

  /// Whole days since the last arrest, or null with a clean record.
  int? get daysClean {
    if (_arrests.isEmpty) return null;
    final last = _arrests.last.at;
    final now = clock();
    return DateTime(
      now.year,
      now.month,
      now.day,
    ).difference(DateTime(last.year, last.month, last.day)).inDays;
  }

  /// The warning counts as the background tracker keeps them; they only
  /// ever grow, so the larger of the two wins.
  void setWarnings(int warnings, int heeded) {
    if (warnings <= _warnings && heeded <= _heeded) return;
    _warnings = math.max(_warnings, warnings);
    _heeded = math.max(_heeded, heeded);
    _save();
  }

  /// Reels still to answer before release; 0 when free.
  int get bailLeft => _bailLeft;
  int get bailTotal => _bailTotal;

  /// XP the learner gets when released.
  int get bailReward => _bailReward;
  bool get serving => _bailLeft > 0;

  /// The most recent arrest whose bail isn't paid yet.
  Arrest? get current => _arrests.lastWhereOrNull((a) => !a.bailPaid);

  /// The arrest to show now: open, not shown yet, and recent.
  Arrest? get fresh {
    final a = current;
    if (a == null || a.seen) return null;
    return clock().difference(a.at) <= _freshFor ? a : null;
  }

  /// Books an arrest. A new charge while bail is already being served adds
  /// no extra bail: paying it covers everything.
  Arrest book({
    required Offence offence,
    DateTime? at,
    String app = '',
    int minutes = 0,
    int? bail,
  }) {
    final arrest = Arrest(
      at: at ?? clock(),
      offence: offence,
      app: app,
      minutes: minutes,
    );
    _arrests.add(arrest);
    _totalArrests++;
    while (_arrests.length > _keep) {
      _arrests.removeAt(0);
    }
    if (!serving) {
      _bailTotal = _bailLeft = math.max(1, bail ?? bailReels);
      _bailReward = offence == Offence.goal ? wantedXp : bailXp;
    }
    _save();
    return arrest;
  }

  void markSeen(Arrest arrest) {
    if (arrest.seen) return;
    arrest.seen = true;
    _save();
  }

  /// One reel answered. Returns true when that pays the last of the bail;
  /// the caller hands out [bailReward] (read it before the next arrest).
  bool onAnswered() {
    if (!serving) return false;
    _bailLeft--;
    if (_bailLeft == 0) {
      for (final a in _arrests) {
        if (!a.bailPaid) _totalPaid++;
        a.bailPaid = true;
      }
    }
    _save();
    return _bailLeft == 0;
  }

  static String _day(DateTime d) => '${d.year}-${d.month}-${d.day}';

  /// Evening, the goal not met, not shown today and nothing being served.
  bool shouldShowWanted({required int answered, required int goal}) {
    final now = clock();
    return now.hour >= wantedHour &&
        answered < goal &&
        _wantedDay != _day(now) &&
        !serving;
  }

  void markWantedShown() {
    _wantedDay = _day(clock());
    _prefs?.setString(_wantedKey, _wantedDay!);
  }

  /// The last seven days.
  CaseFile caseFile() {
    final since = clock().subtract(const Duration(days: 7));
    final week = [
      for (final a in _arrests)
        if (a.at.isAfter(since)) a,
    ];
    final byApp = <String, int>{};
    for (final a in week) {
      if (a.offence == Offence.scrolling && a.app.isNotEmpty) {
        byApp[a.app] = (byApp[a.app] ?? 0) + 1;
      }
    }
    final top = byApp.entries.fold<MapEntry<String, int>?>(
      null,
      (best, e) => best == null || e.value > best.value ? e : best,
    );
    return CaseFile(
      arrests: week.length,
      bailPaid: week.where((a) => a.bailPaid).length,
      longestMinutes: week.fold(0, (m, a) => math.max(m, a.minutes)),
      topApp: top?.key,
    );
  }

  /// The record as kept with the learner's profile in Firestore.
  Map<String, Object> toCloud() => {
    'arrests': _totalArrests,
    'bailPaid': _totalPaid,
    'warnings': _warnings,
    'stoppedInTime': _heeded,
    if (_arrests.isNotEmpty)
      'lastArrestAt': _arrests.last.at.millisecondsSinceEpoch,
  };

  /// From another phone or a reinstall: totals only grow, so keep the larger.
  void mergeCloud(Map<String, dynamic>? data) {
    if (data == null) return;
    int n(String k) => (data[k] as num?)?.toInt() ?? 0;
    final arrests = math.max(_totalArrests, n('arrests'));
    final paid = math.max(_totalPaid, n('bailPaid'));
    final warnings = math.max(_warnings, n('warnings'));
    final heeded = math.max(_heeded, n('stoppedInTime'));
    if (arrests == _totalArrests &&
        paid == _totalPaid &&
        warnings == _warnings &&
        heeded == _heeded) {
      return;
    }
    _totalArrests = arrests;
    _totalPaid = paid;
    _warnings = warnings;
    _heeded = heeded;
    _save();
  }

  void _save() {
    notifyListeners();
    _prefs?.setStringList(_totalsKey, [
      '$_totalArrests',
      '$_totalPaid',
      '$_warnings',
      '$_heeded',
    ]);
    _prefs?.setString(_key, jsonEncode([for (final a in _arrests) a.toJson()]));
    _prefs?.setStringList(_bailKey, [
      '$_bailLeft',
      '$_bailTotal',
      '$_bailReward',
    ]);
  }

  @visibleForTesting
  void resetForTest() {
    _arrests.clear();
    _bailLeft = _bailTotal = _bailReward = 0;
    _totalArrests = _totalPaid = _warnings = _heeded = 0;
    _wantedDay = null;
    _loaded = false;
  }
}

extension<T> on List<T> {
  T? lastWhereOrNull(bool Function(T) test) {
    for (var i = length - 1; i >= 0; i--) {
      if (test(this[i])) return this[i];
    }
    return null;
  }
}
