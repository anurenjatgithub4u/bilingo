import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'like_counts.dart';

/// Like and save state of one word. Independent of whether it is learned.
@immutable
class WordInteraction {
  const WordInteraction(
    this.wordId, {
    this.isLiked = false,
    this.isSaved = false,
  });

  final String wordId;
  final bool isLiked;
  final bool isSaved;

  Map<String, Object> toJson() => {
    'wordId': wordId,
    'isLiked': isLiked,
    'isSaved': isSaved,
  };
}

/// Likes and saved words (bookmarks), per word id ("lang|word"), kept on the
/// phone and copied to Firestore by CloudSync.
class WordInteractions extends ChangeNotifier {
  WordInteractions._();

  static final WordInteractions instance = WordInteractions._();

  static const _likedKey = 'liked_words';
  static const _savedKey = 'saved_words';

  SharedPreferences? _prefs;

  // Insertion-ordered sets: newest last, never a duplicate.
  final Set<String> _liked = {};
  final Set<String> _saved = {};

  Future<void> load() async {
    final prefs = _prefs = await SharedPreferences.getInstance();
    _liked
      ..clear()
      ..addAll(prefs.getStringList(_likedKey) ?? const []);
    _saved
      ..clear()
      ..addAll(prefs.getStringList(_savedKey) ?? const []);
    notifyListeners();
  }

  WordInteraction stateOf(String wordId) => WordInteraction(
    wordId,
    isLiked: _liked.contains(wordId),
    isSaved: _saved.contains(wordId),
  );

  bool isLiked(String wordId) => _liked.contains(wordId);
  bool isSaved(String wordId) => _saved.contains(wordId);

  /// Saved word ids, most recently saved first.
  List<String> get savedIds => _saved.toList().reversed.toList();
  int get likedCount => _liked.length;

  /// Every liked id, oldest first.
  List<String> get likedIds => _liked.toList();

  Future<void> toggleLike(String wordId) =>
      setLiked(wordId, !_liked.contains(wordId));

  Future<void> toggleSave(String wordId) =>
      setSaved(wordId, !_saved.contains(wordId));

  Future<void> setLiked(String wordId, bool value) =>
      _set(_liked, _likedKey, wordId, value);

  Future<void> setSaved(String wordId, bool value) =>
      _set(_saved, _savedKey, wordId, value);

  Future<void> _set(Set<String> set, String key, String id, bool value) async {
    final changed = value ? set.add(id) : set.remove(id);
    if (!changed) return;
    // Everyone's like count follows this learner's likes.
    if (key == _likedKey) LikeCounts.instance.record(id, value);
    // The UI updates first; the write follows.
    notifyListeners();
    await _prefs?.setStringList(key, set.toList());
  }

  /// The state as stored in Firestore (see CloudSync).
  Map<String, Object?> toCloud() => {
    'likedWords': _liked.toList(),
    'savedWords': _saved.toList(),
  };

  /// Adds likes and saves from another phone or a former guest account.
  Future<void> mergeCloud(Map<String, dynamic>? data) async {
    if (data == null) return;
    List<String> strings(Object? v) =>
        v is List ? v.whereType<String>().toList() : const [];
    final liked = strings(data['likedWords']);
    final saved = strings(data['savedWords']);
    if (_liked.containsAll(liked) && _saved.containsAll(saved)) return;
    _liked.addAll(liked);
    _saved.addAll(saved);
    notifyListeners();
    await _prefs?.setStringList(_likedKey, _liked.toList());
    await _prefs?.setStringList(_savedKey, _saved.toList());
  }
}
