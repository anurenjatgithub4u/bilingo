import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app_info.dart';
import '../ui/rating_sheet.dart';
import 'word_service.dart';

/// Tracks learner milestones and prompts for a Play Store rating only after
/// positive "Good News" achievements (e.g. 10 reels completed, daily goal hit,
/// level up, or arrest bail paid).
class RatingService extends ChangeNotifier {
  RatingService._();

  static final RatingService instance = RatingService._();

  static const _hasRatedKey = 'rating_has_rated';
  static const _dontAskKey = 'rating_dont_ask';
  static const _lastPromptKey = 'rating_last_prompt_epoch';
  static const _totalReelsKey = 'rating_total_reels';

  /// Minimum answered reels before first prompt.
  static const minReelsBeforePrompt = 10;

  /// Minimum time between snoozed prompts.
  static const snoozeDuration = Duration(days: 14);

  SharedPreferences? _prefs;
  bool _hasRated = false;
  bool _dontAskAgain = false;
  int _lastPromptEpoch = 0;
  int _totalReelsAnswered = 0;
  bool _promptedThisSession = false;

  bool get hasRated => _hasRated;
  bool get dontAskAgain => _dontAskAgain;
  int get totalReelsAnswered => _totalReelsAnswered;

  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    _hasRated = _prefs?.getBool(_hasRatedKey) ?? false;
    _dontAskAgain = _prefs?.getBool(_dontAskKey) ?? false;
    _lastPromptEpoch = _prefs?.getInt(_lastPromptKey) ?? 0;
    _totalReelsAnswered = _prefs?.getInt(_totalReelsKey) ?? 0;
    notifyListeners();
  }

  /// Increments total reels answered counter.
  Future<void> recordReelAnswered() async {
    _totalReelsAnswered++;
    await _prefs?.setInt(_totalReelsKey, _totalReelsAnswered);
    notifyListeners();
  }

  /// Whether the app should present a rating prompt right now.
  bool shouldPrompt() {
    if (_hasRated || _dontAskAgain || _promptedThisSession) return false;
    if (_totalReelsAnswered < minReelsBeforePrompt) return false;
    if (_lastPromptEpoch > 0) {
      final lastPrompt = DateTime.fromMillisecondsSinceEpoch(_lastPromptEpoch);
      if (DateTime.now().difference(lastPrompt) < snoozeDuration) return false;
    }
    return true;
  }

  /// Checks eligibility and shows the celebratory rating sheet if appropriate.
  Future<void> promptIfEligible(
    BuildContext context, {
    required RatingTrigger trigger,
  }) async {
    if (!shouldPrompt()) return;
    _promptedThisSession = true;
    _lastPromptEpoch = DateTime.now().millisecondsSinceEpoch;
    await _prefs?.setInt(_lastPromptKey, _lastPromptEpoch);

    if (!context.mounted) return;
    await showRatingSheet(context, trigger: trigger);
  }

  /// Opens the Play Store page and marks the user as rated (never prompts again).
  Future<void> markRated() async {
    _hasRated = true;
    await _prefs?.setBool(_hasRatedKey, true);
    notifyListeners();
    try {
      await const WordService().openUrl(
        kPlayStoreAppUrl,
        fallback: kPlayStoreUrl,
      );
    } catch (_) {
      // Native side fallback.
    }
  }

  /// Snoozes rating prompts for [snoozeDuration].
  Future<void> snooze() async {
    _promptedThisSession = true;
    _lastPromptEpoch = DateTime.now().millisecondsSinceEpoch;
    await _prefs?.setInt(_lastPromptKey, _lastPromptEpoch);
    notifyListeners();
  }

  /// User declined permanently; never ask again.
  Future<void> optOut() async {
    _dontAskAgain = true;
    await _prefs?.setBool(_dontAskKey, true);
    notifyListeners();
  }

  @visibleForTesting
  void resetForTest({
    bool hasRated = false,
    bool dontAsk = false,
    int lastPromptEpoch = 0,
    int totalReels = 0,
  }) {
    _hasRated = hasRated;
    _dontAskAgain = dontAsk;
    _lastPromptEpoch = lastPromptEpoch;
    _totalReelsAnswered = totalReels;
    _promptedThisSession = false;
  }
}
