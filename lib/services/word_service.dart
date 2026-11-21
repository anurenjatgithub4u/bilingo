import 'dart:convert';

import 'package:flutter/services.dart';

import 'usage_summary.dart';

/// An app with a launcher icon, for the "which apps eat your time" picker.
class InstalledApp {
  const InstalledApp({
    required this.package,
    required this.label,
    required this.icon,
  });

  final String package;
  final String label;

  /// PNG bytes.
  final Uint8List icon;

  factory InstalledApp.fromMap(Map<Object?, Object?> map) => InstalledApp(
    package: map['package'] as String,
    label: map['label'] as String,
    icon: map['icon'] as Uint8List,
  );
}

/// A word shown (or about to be shown) in a notification.
class ShownWord {
  const ShownWord({
    required this.word,
    required this.meaning,
    required this.lang,
    this.level = 0,
  });

  final String word;
  final String meaning;
  final String lang;

  /// 1 beginner, 2 intermediate, 3 advanced; 0 when the native side did not say.
  final int level;

  /// Stable id for progress tracking.
  String get key => '$lang|$word';

  factory ShownWord.fromMap(Map<Object?, Object?> map) => ShownWord(
    word: map['word'] as String,
    meaning: map['meaning'] as String,
    lang: map['lang'] as String,
    level: (map['level'] as int?) ?? 0,
  );
}

/// What the user decided about a word. Known and hidden words are never shown
/// again until restored. Values match WordDatabase.STATUS_* on the native side.
enum WordStatus { active, known, hidden }

/// Current settings and device state, as reported by the native side.
class WordState {
  const WordState({
    required this.enabled,
    required this.onScreenOn,
    required this.onUnlock,
    required this.languages,
    required this.notificationsGranted,
    required this.batteryUnrestricted,
    required this.usageAccessGranted,
    required this.trackedApps,
    required this.limitMinutes,
    required this.wordCount,
    required this.shownToday,
    required this.totalShown,
    required this.streak,
    required this.learned,
    required this.available,
  });

  final bool enabled;
  final bool onScreenOn;
  final bool onUnlock;
  final Set<String> languages;
  final bool notificationsGranted;

  /// True when the app is exempt from battery optimisation, so the system will not kill the listener.
  final bool batteryUnrestricted;

  /// True when the user has given usage access, so time in scrolling apps can be measured.
  final bool usageAccessGranted;

  /// Packages whose use is timed, and the minutes in a row before the nudge.
  final Set<String> trackedApps;
  final int limitMinutes;
  final int wordCount;
  final int shownToday;
  final int totalShown;

  /// Consecutive days with at least one word shown.
  final int streak;

  /// Distinct words shown at least once, and words in the database, by language code.
  final Map<String, int> learned;
  final Map<String, int> available;

  factory WordState.fromMap(Map<Object?, Object?> map) => WordState(
    enabled: map['enabled'] as bool,
    onScreenOn: map['onScreenOn'] as bool,
    onUnlock: map['onUnlock'] as bool,
    languages: (map['languages'] as List<Object?>).cast<String>().toSet(),
    notificationsGranted: map['notificationsGranted'] as bool,
    batteryUnrestricted: map['batteryUnrestricted'] as bool,
    usageAccessGranted: (map['usageAccessGranted'] as bool?) ?? false,
    trackedApps:
        ((map['trackedApps'] as List<Object?>?) ?? const []).cast<String>().toSet(),
    limitMinutes: (map['limitMinutes'] as int?) ?? 5,
    wordCount: map['wordCount'] as int,
    shownToday: map['shownToday'] as int,
    totalShown: map['totalShown'] as int,
    streak: (map['streak'] as int?) ?? 0,
    learned: (map['learned'] as Map<Object?, Object?>).cast<String, int>(),
    available: (map['available'] as Map<Object?, Object?>).cast<String, int>(),
  );
}

/// Dart face of the native word service (see MainActivity.kt).
class WordService {
  const WordService();

  static const MethodChannel _channel = MethodChannel('com.dmonly.app/words');

  Future<WordState> getState() async => WordState.fromMap(
    await _channel.invokeMethod<Map<Object?, Object?>>('getState') ?? {},
  );

  Future<WordState> update({
    bool? enabled,
    bool? onScreenOn,
    bool? onUnlock,
    Set<String>? languages,
    Set<String>? trackedApps,
    int? limitMinutes,
    String? mascot,
  }) async {
    final result = await _channel.invokeMethod<Map<Object?, Object?>>(
      'setSettings',
      {
        'enabled': ?enabled,
        'onScreenOn': ?onScreenOn,
        'onUnlock': ?onUnlock,
        'languages': ?languages?.toList(),
        'trackedApps': ?trackedApps?.toList(),
        'limitMinutes': ?limitMinutes,
        'mascot': ?mascot,
      },
    );
    return WordState.fromMap(result ?? {});
  }

  Future<bool> requestNotificationPermission() async =>
      await _channel.invokeMethod<bool>('requestNotificationPermission') ??
      false;

  Future<ShownWord?> showWordNow() async {
    final result = await _channel.invokeMethod<Map<Object?, Object?>>(
      'showWordNow',
    );
    return result == null ? null : ShownWord.fromMap(result);
  }

  /// Marks [word] known, hidden, or back to active.
  Future<void> setWordStatus(ShownWord word, WordStatus status) =>
      _channel.invokeMethod<Object?>('setWordStatus', {
        'lang': word.lang,
        'word': word.word,
        'status': status.index,
      });

  /// Every word the user has marked with [status].
  Future<List<ShownWord>> wordsWithStatus(WordStatus status) async {
    final result = await _channel.invokeMethod<List<Object?>>(
      'wordsWithStatus',
      {'status': status.index},
    );
    return [
      for (final m in result ?? const [])
        ShownWord.fromMap(m as Map<Object?, Object?>),
    ];
  }

  /// Words in the user's languages matching [query], best match first.
  Future<List<ShownWord>> lookup(String query) async {
    final result = await _channel.invokeMethod<List<Object?>>('lookup', {
      'query': query,
    });
    return [
      for (final m in result ?? const [])
        ShownWord.fromMap(m as Map<Object?, Object?>),
    ];
  }

  /// Every word in [lang] for the learning path, easiest level first.
  Future<List<ShownWord>> pathWords(String lang) async {
    final result = await _channel.invokeMethod<List<Object?>>('pathWords', {
      'lang': lang,
    });
    return [
      for (final m in result ?? const [])
        ShownWord.fromMap(m as Map<Object?, Object?>),
    ];
  }

  /// A word to explore in the app; does not post a notification or count as shown.
  Future<ShownWord?> randomWord() async {
    final result = await _channel.invokeMethod<Map<Object?, Object?>>(
      'randomWord',
    );
    return result == null ? null : ShownWord.fromMap(result);
  }

  Future<void> requestIgnoreBatteryOptimizations() =>
      _channel.invokeMethod<void>('requestIgnoreBatteryOptimizations');

  /// The word from the notification that launched the app, if any (cleared once read).
  Future<ShownWord?> takeLaunchWord() async {
    final result = await _channel.invokeMethod<Map<Object?, Object?>>(
      'takeLaunchWord',
    );
    return result == null ? null : ShownWord.fromMap(result);
  }

  /// The Scroll Patrol arrest whose notification opened the app, if any:
  /// (app name, minutes).
  Future<(String, int)?> takeLaunchArrest() async {
    final result = await _channel.invokeMethod<Map<Object?, Object?>>(
      'takeLaunchArrest',
    );
    return result == null ? null : _arrestOf(result);
  }

  /// Arrests made in the background since the last call, oldest first, as
  /// (when, app name, minutes).
  Future<List<(DateTime, String, int)>> takeArrests() async {
    final raw = await _channel.invokeMethod<String>('takeArrests');
    final list = raw == null ? const [] : jsonDecode(raw) as List;
    return [
      for (final a in list.cast<Map<String, dynamic>>())
        (
          DateTime.fromMillisecondsSinceEpoch((a['at'] as num).toInt()),
          a['app'] as String? ?? 'an app',
          (a['minutes'] as num?)?.toInt() ?? 0,
        ),
    ];
  }

  /// Scroll Patrol warnings given so far, and how many were heeded.
  Future<(int, int)> patrolCounts() async {
    final m = await _channel.invokeMethod<Map<Object?, Object?>>(
      'patrolCounts',
    );
    return ((m?['warnings'] as int?) ?? 0, (m?['heeded'] as int?) ?? 0);
  }

  static (String, int) _arrestOf(Map<Object?, Object?> m) =>
      (m['app'] as String? ?? 'an app', (m['minutes'] as int?) ?? 0);

  static void Function(ShownWord word)? _onWord;
  static void Function(String app, int minutes)? _onArrest;

  void _listen() => _channel.setMethodCallHandler((call) async {
    final args = call.arguments as Map<Object?, Object?>?;
    if (args == null) return;
    if (call.method == 'openWord') _onWord?.call(ShownWord.fromMap(args));
    if (call.method == 'openArrest') {
      final (app, minutes) = _arrestOf(args);
      _onArrest?.call(app, minutes);
    }
  });

  /// Called when a notification is tapped while the app is already running.
  void onOpenWord(void Function(ShownWord word) handler) {
    _onWord = handler;
    _listen();
  }

  /// Called when a Scroll Patrol notification is tapped while the app runs.
  void onOpenArrest(void Function(String app, int minutes) handler) {
    _onArrest = handler;
    _listen();
  }

  /// The installed version, e.g. ("1.4.0", 6).
  Future<(String, int)> appVersion() async {
    final m = await _channel.invokeMethod<Map<Object?, Object?>>('appVersion');
    return ((m?['name'] as String?) ?? '', (m?['code'] as int?) ?? 0);
  }

  /// Opens [url] in the right app, or [fallback] if nothing can open it.
  /// Returns whether either opened.
  Future<bool> openUrl(String url, {String? fallback}) async =>
      await _channel.invokeMethod<bool>('openUrl', {
        'url': url,
        'fallback': ?fallback,
      }) ??
      false;

  Future<void> openAppSettings() =>
      _channel.invokeMethod<void>('openAppSettings');

  /// Opens the system share sheet with plain [text].
  Future<void> shareText(String text) =>
      _channel.invokeMethod<void>('shareText', {'text': text});

  /// Opens the system share sheet with a PNG picture and a caption.
  Future<void> shareImage(Uint8List png, String text) => _channel
      .invokeMethod<void>('shareImage', {'png': png, 'text': text});

  Future<void> openNotificationSettings() =>
      _channel.invokeMethod<void>('openNotificationSettings');

  /// Every app with a launcher icon, A to Z.
  Future<List<InstalledApp>> installedApps() async {
    final result = await _channel.invokeMethod<List<Object?>>('installedApps');
    return [
      for (final m in result ?? const [])
        InstalledApp.fromMap(m as Map<Object?, Object?>),
    ];
  }

  /// Time on social, video and game apps today and on recent days.
  Future<UsageSummary> usageSummary() async {
    final result = await _channel.invokeMethod<Map<Object?, Object?>>(
      'usageSummary',
    );
    return UsageSummary.fromMap(result ?? const {'granted': false});
  }

  /// Opens the system "Usage access" page; there is no in-app prompt for it.
  Future<void> openUsageAccessSettings() =>
      _channel.invokeMethod<void>('openUsageAccessSettings');
}
