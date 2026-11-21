import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Represents a single blocked application session.
class BlockedApp {
  const BlockedApp({
    required this.packageName,
    required this.label,
    required this.startTime,
    required this.endTime,
    this.blockType = 'manual',
    this.isActive = true,
  });

  final String packageName;
  final String label;
  final int startTime; // epoch ms
  final int endTime; // epoch ms
  final String blockType; // 'manual', 'limit_exceeded', 'schedule'
  final bool isActive;

  bool get isExpired => DateTime.now().millisecondsSinceEpoch >= endTime;

  Duration get remainingDuration {
    final now = DateTime.now().millisecondsSinceEpoch;
    final diff = endTime - now;
    return diff > 0 ? Duration(milliseconds: diff) : Duration.zero;
  }

  String get formattedRemaining {
    final rem = remainingDuration;
    if (rem.inMinutes <= 0) return 'Ending soon';
    if (rem.inHours > 0) {
      final mins = rem.inMinutes % 60;
      return mins > 0 ? '${rem.inHours}h ${mins}m left' : '${rem.inHours}h left';
    }
    return '${rem.inMinutes}m left';
  }

  Map<String, dynamic> toMap() => {
    'packageName': packageName,
    'label': label,
    'startTime': startTime,
    'endTime': endTime,
    'blockType': blockType,
    'isActive': isActive,
  };

  factory BlockedApp.fromMap(Map<dynamic, dynamic> map) => BlockedApp(
    packageName: (map['packageName'] ?? map['package']) as String,
    label: (map['label'] ?? '') as String,
    startTime: (map['startTime'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch,
    endTime: (map['endTime'] as num?)?.toInt() ?? (DateTime.now().millisecondsSinceEpoch + 3600000),
    blockType: (map['blockType'] as String?) ?? 'manual',
    isActive: (map['isActive'] as bool?) ?? true,
  );
}

/// Manages blocked applications, communication with native Android, and
/// intelligent usage-based blocking recommendations.
class AppBlockStore extends ChangeNotifier {
  AppBlockStore._() {
    _startTicker();
  }

  static final AppBlockStore instance = AppBlockStore._();

  static const MethodChannel _channel = MethodChannel('com.dmonly.app/words');
  static const _keyDismissedRecDate = 'dismissed_block_recommendation_date';
  static const _keyDismissedRecApp = 'dismissed_block_recommendation_app';

  List<BlockedApp> _blockedApps = [];
  Timer? _ticker;
  bool _loaded = false;

  List<BlockedApp> get blockedApps => List.unmodifiable(_blockedApps.where((b) => !b.isExpired && b.isActive));

  bool isBlocked(String packageName) =>
      _blockedApps.any((b) => b.packageName == packageName && !b.isExpired && b.isActive);

  BlockedApp? getBlock(String packageName) {
    try {
      return _blockedApps.firstWhere((b) => b.packageName == packageName && !b.isExpired && b.isActive);
    } catch (_) {
      return null;
    }
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 15), (_) {
      // Clean up expired blocks automatically
      final before = _blockedApps.length;
      _blockedApps.removeWhere((b) => b.isExpired);
      if (_blockedApps.length != before) {
        _syncToNative();
        notifyListeners();
      } else if (_blockedApps.isNotEmpty) {
        notifyListeners();
      }
    });
  }

  Future<void> ensureLoaded() async {
    if (_loaded) return;
    await _loadFromNative();
    _loaded = true;
  }

  Future<void> _loadFromNative() async {
    try {
      final result = await _channel.invokeMethod<List<dynamic>>('getBlockedApps');
      if (result != null) {
        _blockedApps = [
          for (final item in result)
            if (item is Map) BlockedApp.fromMap(item),
        ];
        _blockedApps.removeWhere((b) => b.isExpired);
      }
    } catch (_) {
      // Fallback: load from local prefs
      try {
        final prefs = await SharedPreferences.getInstance();
        final raw = prefs.getString('bilingo_blocked_apps');
        if (raw != null) {
          final list = jsonDecode(raw) as List;
          _blockedApps = [
            for (final item in list)
              if (item is Map) BlockedApp.fromMap(item),
          ];
          _blockedApps.removeWhere((b) => b.isExpired);
        }
      } catch (_) {}
    }
    notifyListeners();
  }

  Future<void> _syncToNative() async {
    _blockedApps.removeWhere((b) => b.isExpired);
    final list = _blockedApps.map((b) => b.toMap()).toList();
    try {
      await _channel.invokeMethod('setBlockedApps', {'apps': list});
    } catch (_) {}

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('bilingo_blocked_apps', jsonEncode(list));
    } catch (_) {}
  }

  /// Block one or more apps for [duration].
  Future<void> blockApps({
    required List<(String package, String label)> apps,
    required Duration duration,
    String blockType = 'manual',
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final end = now + duration.inMilliseconds;

    for (final (pkg, lbl) in apps) {
      _blockedApps.removeWhere((b) => b.packageName == pkg);
      _blockedApps.add(
        BlockedApp(
          packageName: pkg,
          label: lbl,
          startTime: now,
          endTime: end,
          blockType: blockType,
          isActive: true,
        ),
      );
    }
    await _syncToNative();
    notifyListeners();
  }

  /// Unblock an app immediately.
  Future<void> unblockApp(String packageName) async {
    _blockedApps.removeWhere((b) => b.packageName == packageName);
    try {
      await _channel.invokeMethod('unblockApp', {'package': packageName});
    } catch (_) {}
    await _syncToNative();
    notifyListeners();
  }

  /// Extend blocking duration by [extra].
  Future<void> extendBlock(String packageName, Duration extra) async {
    final idx = _blockedApps.indexWhere((b) => b.packageName == packageName);
    if (idx >= 0) {
      final cur = _blockedApps[idx];
      final newEnd = cur.endTime + extra.inMilliseconds;
      _blockedApps[idx] = BlockedApp(
        packageName: cur.packageName,
        label: cur.label,
        startTime: cur.startTime,
        endTime: newEnd,
        blockType: cur.blockType,
        isActive: true,
      );
      await _syncToNative();
      notifyListeners();
    }
  }

  /// Change blocking duration to [newDuration] from now.
  Future<void> changeDuration(String packageName, Duration newDuration) async {
    final idx = _blockedApps.indexWhere((b) => b.packageName == packageName);
    if (idx >= 0) {
      final cur = _blockedApps[idx];
      final now = DateTime.now().millisecondsSinceEpoch;
      _blockedApps[idx] = BlockedApp(
        packageName: cur.packageName,
        label: cur.label,
        startTime: now,
        endTime: now + newDuration.inMilliseconds,
        blockType: cur.blockType,
        isActive: true,
      );
      await _syncToNative();
      notifyListeners();
    }
  }

  // --- Recommendation Logic ---

  /// Checks if the user has dismissed today's recommendation for [appPackage].
  Future<bool> isRecommendationDismissed(String appPackage) async {
    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final savedDate = prefs.getString(_keyDismissedRecDate);
    final savedApp = prefs.getString(_keyDismissedRecApp);
    return savedDate == today && savedApp == appPackage;
  }

  /// Dismiss recommendation for today.
  Future<void> dismissRecommendation(String appPackage) async {
    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now().toIso8601String().substring(0, 10);
    await prefs.setString(_keyDismissedRecDate, today);
    await prefs.setString(_keyDismissedRecApp, appPackage);
  }
}
