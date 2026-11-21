import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'profile_store.dart';

/// Manages flexible daily screen-time limits:
/// Priority:
/// 1. Today's temporary customized limit (for today's date).
/// 2. Today's scheduled weekday limit (if weekly schedule is enabled).
/// 3. Default daily limit (from onboarding or user preference).
class ScreenTimeStore extends ChangeNotifier {
  ScreenTimeStore._();

  static final ScreenTimeStore instance = ScreenTimeStore._();

  static const _keyDefaultLimit = 'screen_time_default_limit_minutes';
  static const _keyTodayCustomLimit = 'screen_time_today_custom_limit_minutes';
  static const _keyTodayCustomDate = 'screen_time_today_custom_date';
  static const _keyWeeklyScheduleEnabled = 'screen_time_weekly_schedule_enabled';
  static const _keyWeeklySchedule = 'screen_time_weekly_schedule';

  late SharedPreferences _prefs;
  bool _loaded = false;

  int _defaultDailyLimitMinutes = 120; // 2 hours default
  int? _todayCustomLimitMinutes;
  String? _todayCustomDate;
  bool _weeklyScheduleEnabled = false;

  /// Weekday (1 = Monday ... 7 = Sunday) -> limit in minutes.
  Map<int, int> _weeklySchedule = {
    DateTime.monday: 120,
    DateTime.tuesday: 120,
    DateTime.wednesday: 120,
    DateTime.thursday: 120,
    DateTime.friday: 120,
    DateTime.saturday: 120,
    DateTime.sunday: 120,
  };

  int get defaultDailyLimitMinutes => _defaultDailyLimitMinutes;
  int? get todayCustomLimitMinutes => _isTodayCustomValid(DateTime.now()) ? _todayCustomLimitMinutes : null;
  bool get weeklyScheduleEnabled => _weeklyScheduleEnabled;
  Map<int, int> get weeklySchedule => Map.unmodifiable(_weeklySchedule);

  static String _isoDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  bool _isTodayCustomValid(DateTime now) {
    if (_todayCustomLimitMinutes == null || _todayCustomDate == null) return false;
    return _todayCustomDate == _isoDate(now);
  }

  Future<void> ensureLoaded() async {
    if (_loaded) return;
    _prefs = await SharedPreferences.getInstance();

    // Initialize default limit from onboarding scroll estimate if not explicitly configured.
    final storedDefault = _prefs.getInt(_keyDefaultLimit);
    if (storedDefault != null) {
      _defaultDailyLimitMinutes = storedDefault;
    } else {
      final onboardingHours = ProfileStore.instance.scrollHoursEstimate;
      if (onboardingHours != null && onboardingHours > 0) {
        _defaultDailyLimitMinutes = onboardingHours * 60;
      } else {
        _defaultDailyLimitMinutes = 120;
      }
    }

    _todayCustomLimitMinutes = _prefs.getInt(_keyTodayCustomLimit);
    _todayCustomDate = _prefs.getString(_keyTodayCustomDate);
    _weeklyScheduleEnabled = _prefs.getBool(_keyWeeklyScheduleEnabled) ?? false;

    final rawWeekly = _prefs.getString(_keyWeeklySchedule);
    if (rawWeekly != null) {
      try {
        final decoded = jsonDecode(rawWeekly) as Map<String, dynamic>;
        _weeklySchedule = {
          for (final e in decoded.entries) int.parse(e.key): (e.value as num).toInt(),
        };
      } catch (_) {}
    }

    _loaded = true;
    notifyListeners();
  }

  /// The effective limit that applies right now.
  int effectiveLimitMinutes(DateTime now) {
    // 1. Temporary custom limit for today
    if (_isTodayCustomValid(now)) {
      return _todayCustomLimitMinutes!;
    }
    // 2. Scheduled weekday limit if weekly schedule is active
    if (_weeklyScheduleEnabled && _weeklySchedule.containsKey(now.weekday)) {
      return _weeklySchedule[now.weekday]!;
    }
    // 3. Default daily limit
    return _defaultDailyLimitMinutes;
  }

  /// Temporary customized limit for today only.
  Future<void> setTodayCustomLimit(int? minutes, DateTime now) async {
    _todayCustomLimitMinutes = minutes;
    _todayCustomDate = minutes != null ? _isoDate(now) : null;

    if (minutes != null) {
      await _prefs.setInt(_keyTodayCustomLimit, minutes);
      await _prefs.setString(_keyTodayCustomDate, _todayCustomDate!);
    } else {
      await _prefs.remove(_keyTodayCustomLimit);
      await _prefs.remove(_keyTodayCustomDate);
    }
    notifyListeners();
  }

  /// Change default daily limit.
  Future<void> setDefaultDailyLimit(int minutes) async {
    _defaultDailyLimitMinutes = minutes.clamp(15, 1440);
    await _prefs.setInt(_keyDefaultLimit, _defaultDailyLimitMinutes);
    notifyListeners();
  }

  /// Toggle weekly schedule on/off.
  Future<void> setWeeklyScheduleEnabled(bool enabled) async {
    _weeklyScheduleEnabled = enabled;
    await _prefs.setBool(_keyWeeklyScheduleEnabled, enabled);
    notifyListeners();
  }

  /// Update schedule for a specific weekday (1 = Monday ... 7 = Sunday).
  Future<void> setWeekdayLimit(int weekday, int minutes) async {
    _weeklySchedule[weekday] = minutes.clamp(15, 1440);
    await _prefs.setString(
      _keyWeeklySchedule,
      jsonEncode({for (final e in _weeklySchedule.entries) e.key.toString(): e.value}),
    );
    notifyListeners();
  }
}
