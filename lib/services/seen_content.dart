import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// What WordFlow has already shown: words, questions, puzzles and texts, by
/// content key (see `contentKey` in reels.dart), with when each was last
/// seen. Feeds show unseen content first and bring seen content back
/// oldest first, only once there is nothing new left. Kept on the phone.
class SeenContent {
  SeenContent._();

  static final SeenContent instance = SeenContent._();

  static const _key = 'seen_content';

  /// Oldest entries are dropped beyond this, so storage stays small.
  static const _limit = 4000;

  SharedPreferences? _prefs;
  bool _loaded = false;

  /// Content key → milliseconds since epoch; insertion order is oldest first.
  final Map<String, int> _seen = {};

  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    _seen.clear();
    try {
      final raw = _prefs!.getString(_key);
      if (raw != null) {
        final map = (jsonDecode(raw) as Map).cast<String, int>();
        final entries = map.entries.toList()
          ..sort((a, b) => a.value.compareTo(b.value));
        _seen.addEntries(entries);
      }
    } catch (_) {
      // Unreadable: start afresh rather than block the feed.
    }
    _loaded = true;
  }

  /// Loads once; later calls keep what is in memory.
  Future<void> ensureLoaded() async {
    if (!_loaded) await load();
  }

  bool has(String key) => _seen.containsKey(key);

  /// When [key] was last shown, or null if never.
  int? seenAt(String key) => _seen[key];

  Set<String> get keys => _seen.keys.toSet();

  int get count => _seen.length;

  void mark(String key) {
    _seen.remove(key);
    _seen[key] = DateTime.now().millisecondsSinceEpoch;
    while (_seen.length > _limit) {
      _seen.remove(_seen.keys.first);
    }
    _prefs?.setString(_key, jsonEncode(_seen));
  }

  /// [items] with never-seen ones first, in their given order, then seen ones
  /// from longest ago to most recent.
  List<T> unseenFirst<T>(List<T> items, String Function(T) keyOf) {
    final fresh = <T>[], old = <T>[];
    for (final item in items) {
      (has(keyOf(item)) ? old : fresh).add(item);
    }
    old.sort((a, b) => _seen[keyOf(a)]!.compareTo(_seen[keyOf(b)]!));
    return [...fresh, ...old];
  }
}
