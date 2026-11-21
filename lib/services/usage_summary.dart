import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _hourMs = 3600000;
const _hoursPerDay = 24;

/// One app's time today.
class AppUsage {
  const AppUsage({
    required this.package,
    required this.label,
    required this.category,
    required this.todayMs,
    required this.icon,
  });

  final String package;
  final String label;

  /// 'social', 'video', 'games' or 'other' (picked by the learner).
  final String category;
  final int todayMs;
  final Uint8List? icon;

  factory AppUsage.fromMap(Map<Object?, Object?> m) => AppUsage(
    package: m['package']! as String,
    label: m['label']! as String,
    category: m['category']! as String,
    todayMs: (m['todayMs']! as num).toInt(),
    icon: m['icon'] as Uint8List?,
  );
}

/// Whole days since 1970 for [t]'s local date.
int dayNumber(DateTime t) =>
    DateTime.utc(t.year, t.month, t.day).difference(DateTime.utc(1970)).inDays;

/// The learner's measured habit before they started tracking it here: how
/// much they had typically used by each hour of the day. Saved once and kept,
/// so saved time is measured against a fixed "before", not against itself.
class UsageBaseline {
  const UsageBaseline({required this.day, required this.curve});

  static const _key = 'usage_baseline';

  /// Finished days of data needed before saved time means anything.
  static const minDays = 3;

  /// The day this was taken. Only later days can count as saved.
  final int day;

  /// Typical total by the end of each hour, 24 values rising to the day's total.
  final List<int> curve;

  int get totalMs => curve.last;

  /// Typical total by this time of day.
  int at(DateTime now) {
    final before = now.hour == 0 ? 0 : curve[now.hour - 1];
    final part = (now.minute * 60 + now.second) / 3600;
    return (before + (curve[now.hour] - before) * part).round();
  }

  static Future<UsageBaseline?> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null) return null;
      final j = (jsonDecode(raw) as Map).cast<String, dynamic>();
      final curve = (j['curve'] as List).cast<num>();
      if (curve.length != _hoursPerDay) return null;
      return UsageBaseline(
        day: (j['day'] as num).toInt(),
        curve: [for (final c in curve) c.toInt()],
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode({'day': day, 'curve': curve}));
  }
}

/// Where the daily figure behind the yearly numbers came from.
enum CostSource { average, today, estimate, none }

/// Time on social, video and game apps, from the phone's usage data.
class UsageSummary {
  const UsageSummary({
    required this.granted,
    this.apps = const [],
    this.categories = const {},
    this.hourly = const [],
    this.hasData = const [],
  });

  final bool granted;

  /// Today's most-used apps, longest first.
  final List<AppUsage> apps;

  /// Category → today's milliseconds.
  final Map<String, int> categories;

  /// Counted milliseconds for each hour of each day, oldest day first.
  final List<int> hourly;

  /// Per day, whether the phone has any usage data (it keeps only some days).
  final List<bool> hasData;

  factory UsageSummary.fromMap(Map<Object?, Object?> m) {
    if (m['granted'] != true) return const UsageSummary(granted: false);
    return UsageSummary(
      granted: true,
      apps: [
        for (final a in (m['apps'] as List?) ?? const [])
          AppUsage.fromMap((a as Map).cast<Object?, Object?>()),
      ],
      categories: {
        for (final e in ((m['categories'] as Map?) ?? const {}).entries)
          e.key as String: (e.value as num).toInt(),
      },
      hourly: [for (final h in m['hourly']! as List) (h as num).toInt()],
      hasData: [for (final d in m['hasData']! as List) d as bool],
    );
  }

  int get _dayCount => hasData.length;

  int _dayTotal(int day) {
    var total = 0;
    for (var h = 0; h < _hoursPerDay; h++) {
      total += hourly[day * _hoursPerDay + h];
    }
    return total;
  }

  int get todayMs => _dayCount == 0 ? 0 : _dayTotal(_dayCount - 1);

  /// Finished days the phone has data for.
  int get finishedDaysWithData =>
      _dayCount == 0 ? 0 : hasData.take(_dayCount - 1).where((d) => d).length;

  /// Average of the finished days the phone has data for, or null.
  int? get averageMs {
    final count = finishedDaysWithData;
    if (count == 0) return null;
    var total = 0;
    for (var d = 0; d < _dayCount - 1; d++) {
      if (hasData[d]) total += _dayTotal(d);
    }
    return total ~/ count;
  }

  /// The habit so far as a baseline, or null without enough real days.
  UsageBaseline? measureBaseline(DateTime now) {
    final count = finishedDaysWithData;
    if (count < UsageBaseline.minDays) return null;
    final curve = List<int>.filled(_hoursPerDay, 0);
    for (var d = 0; d < _dayCount - 1; d++) {
      if (!hasData[d]) continue;
      var sum = 0;
      for (var h = 0; h < _hoursPerDay; h++) {
        sum += hourly[d * _hoursPerDay + h];
        curve[h] += sum;
      }
    }
    return UsageBaseline(
      day: dayNumber(now),
      curve: [for (final c in curve) c ~/ count],
    );
  }

  /// Under the typical amount for this time of day: real time not spent.
  int savedTodayMs(UsageBaseline baseline, DateTime now) {
    final saved = baseline.at(now) - todayMs;
    return saved > 0 ? saved : 0;
  }

  /// Saved on finished days of this week since the baseline, plus today.
  int savedWeekMs(UsageBaseline baseline, DateTime now) {
    var total = savedTodayMs(baseline, now);
    final today = dayNumber(now);
    for (var d = 0; d < _dayCount - 1; d++) {
      final number = today - (_dayCount - 1 - d);
      if (number < baseline.day || !hasData[d]) continue;
      final saved = baseline.totalMs - _dayTotal(d);
      if (saved > 0) total += saved;
    }
    return total;
  }

  /// How far through a waking day (7:00 to 23:00) [now] is, 0 to 1.
  static double dayFraction(DateTime now) {
    final hours = now.hour + now.minute / 60;
    return ((hours - 7) / 16).clamp(0.0, 1.0);
  }

  /// What today would total at this pace. Too early in a usual day to judge,
  /// it leans on [fallbackMs], the recent daily figure, instead.
  int projectedTodayMs(UsageBaseline? baseline, DateTime now, int fallbackMs) {
    final total = baseline?.totalMs ?? 0;
    final fraction = total > 0 ? baseline!.at(now) / total : dayFraction(now);
    final today = todayMs;
    if (fraction < 0.2) return today > fallbackMs ? today : fallbackMs;
    final projected = (today / fraction).round();
    return projected.clamp(today, 24 * _hourMs);
  }

  /// The daily figure to project from: real use first, then their own guess.
  (int, CostSource) costDaily(int? estimateHours) {
    final average = averageMs;
    if (average != null && average > 0) return (average, CostSource.average);
    if (todayMs > 0) return (todayMs, CostSource.today);
    if (estimateHours != null) {
      return (estimateHours * _hourMs, CostSource.estimate);
    }
    return (0, CostSource.none);
  }
}

/// What a daily habit adds up to. Plain arithmetic on the daily figure.
class TimeCost {
  const TimeCost(this.dailyMs);

  /// The stretch of life the comparison uses.
  static const lifeYears = 50;

  /// Waking hours in a day.
  static const wakingHours = 16;

  /// Rough time to read one book, in hours.
  static const hoursPerBook = 8;

  final int dailyMs;

  double get hoursPerDay => dailyMs / _hourMs;
  double get hoursPerMonth => hoursPerDay * 30;
  double get hoursPerYear => hoursPerDay * 365;
  double get daysPerYear => hoursPerYear / 24;

  /// Whole years of the next [lifeYears] spent on it, counting 24-hour days.
  double get yearsOfLife => hoursPerDay / 24 * lifeYears;

  /// One waking hour in this many goes to it.
  int get oneWakingHourIn =>
      hoursPerDay <= 0 ? 0 : (wakingHours / hoursPerDay).round().clamp(1, 1000);

  int get booksPerYear => (hoursPerYear / hoursPerBook).round();
}

/// "2h 14m", "45m", "0m".
String formatDuration(int ms) {
  final minutes = (ms / 60000).round();
  final h = minutes ~/ 60, m = minutes % 60;
  if (h == 0) return '${m}m';
  return m == 0 ? '${h}h' : '${h}h ${m}m';
}

/// "1,095".
String groupDigits(num n) => n.round().toString().replaceAllMapped(
  RegExp(r'\B(?=(\d{3})+(?!\d))'),
  (_) => ',',
);
