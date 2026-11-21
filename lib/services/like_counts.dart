import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// How many people like each reel, shared by everyone.
///
/// Firestore keeps `reelStats/{id}` with a `likes` count, and
/// `reelStats/{id}/likes/{uid}` for each learner who liked it, so a learner
/// counts once however often they tap. The rules in `firestore.rules` only
/// let the count move by one, together with the learner's own like.
///
/// A like shows at once; the write follows. One made offline is kept and
/// sent when the app is next online.
class LikeCounts extends ChangeNotifier {
  LikeCounts._();

  static final LikeCounts instance = LikeCounts._();

  static const _pendingKey = 'like_pending';
  static const _backfilledKey = 'like_backfilled';

  /// Count as last read from Firestore, per like key.
  final _server = <String, int>{};

  /// This phone's likes not yet reflected in [_server].
  final _delta = <String, int>{};

  /// Likes still to send: key → liked.
  final _pending = <String, bool>{};

  /// Open listeners and how many buttons use each.
  final _subs = <String, StreamSubscription<DocumentSnapshot>>{};
  final _refs = <String, int>{};

  SharedPreferences? _prefs;
  StreamSubscription<User?>? _userSub;
  bool _flushing = false;

  /// The like being sent right now, so a tap meanwhile is sent after it.
  String? _sending;

  static bool get _ready {
    try {
      return Firebase.apps.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  FirebaseFirestore get _db => FirebaseFirestore.instance;

  /// A Firestore-safe id for [key]; keys hold '/' and can be long.
  @visibleForTesting
  static String docId(String key) {
    // FNV-1a, 64 bit.
    var hash = 0xcbf29ce484222325;
    for (final byte in utf8.encode(key)) {
      hash ^= byte;
      hash = (hash * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF;
    }
    return 'r${hash.toUnsigned(64).toRadixString(16).padLeft(16, '0')}';
  }

  /// "1.2K" style, as feeds show it.
  static String format(int n) {
    String short(double v) {
      final s = v < 10 ? v.toStringAsFixed(1) : v.toStringAsFixed(0);
      return s.endsWith('.0') ? s.substring(0, s.length - 2) : s;
    }

    if (n < 1000) return '$n';
    if (n < 1000000) return '${short(n / 1000)}K';
    return '${short(n / 1000000)}M';
  }

  /// Likes on [key] including this phone's own, or null before it is known.
  /// Never below one while [likedHere].
  int? countOf(String key, {required bool likedHere}) {
    final server = _server[key];
    final delta = _delta[key] ?? 0;
    if (server == null && delta == 0) return likedHere ? 1 : null;
    final n = math.max(0, (server ?? 0) + delta);
    return likedHere ? math.max(1, n) : n;
  }

  /// Sends what is waiting once there is a user, and once ever counts the
  /// likes made before counts existed.
  Future<void> start({Iterable<String> earlierLikes = const []}) async {
    _prefs ??= await SharedPreferences.getInstance();
    _loadPending();
    if (!(_prefs!.getBool(_backfilledKey) ?? false)) {
      for (final key in earlierLikes) {
        _pending.putIfAbsent(key, () => true);
      }
      await _savePending();
      await _prefs!.setBool(_backfilledKey, true);
    }
    if (!_ready || _userSub != null) return;
    _userSub = FirebaseAuth.instance.userChanges().listen((user) {
      if (user != null) unawaited(_flush());
    });
  }

  /// The learner liked or unliked [key]: shown now, sent next.
  void record(String key, bool liked) {
    final was = _pending[key];
    // Undoing a like that was never sent: nothing to send.
    if (was != null && was != liked && _sending != key) {
      _pending.remove(key);
    } else {
      _pending[key] = liked;
    }
    _delta[key] = (_delta[key] ?? 0) + (liked ? 1 : -1);
    notifyListeners();
    unawaited(_savePending());
    unawaited(_flush());
  }

  /// Starts following [key]'s count; pair with [unwatch].
  void watch(String key) {
    _refs[key] = (_refs[key] ?? 0) + 1;
    if (_subs.containsKey(key) || !_ready) return;
    _subs[key] = _db.collection('reelStats').doc(docId(key)).snapshots().listen(
      (snap) {
        final likes = (snap.data()?['likes'] as num?)?.toInt() ?? 0;
        // A pending like is already in the count once the server has it.
        if (!_pending.containsKey(key)) _delta.remove(key);
        if (_server[key] != likes || _delta[key] == null) {
          _server[key] = likes;
          notifyListeners();
        }
      },
      // Offline with nothing cached, or rules not published yet: the
      // button shows "Like" without a number.
      onError: (Object e) => debugPrint('LikeCounts: $key: $e'),
    );
  }

  void unwatch(String key) {
    final left = (_refs[key] ?? 1) - 1;
    if (left > 0) {
      _refs[key] = left;
      return;
    }
    _refs.remove(key);
    unawaited(_subs.remove(key)?.cancel());
  }

  Future<void> _flush() async {
    if (_flushing || !_ready || _pending.isEmpty) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    _flushing = true;
    try {
      for (final key in _pending.keys.toList()) {
        final liked = _pending[key];
        if (liked == null) continue;
        final int count;
        _sending = key;
        try {
          count = await _send(uid, key, liked);
        } catch (e) {
          // Offline: kept for the next try.
          debugPrint('LikeCounts: could not send $key: $e');
          break;
        } finally {
          _sending = null;
        }
        // Tapped again meanwhile: that newer state is still to send.
        if (_pending[key] == liked) {
          _pending.remove(key);
          // The count now includes this like, so it isn't added twice.
          _delta.remove(key);
          _server[key] = count;
          notifyListeners();
        }
        await _savePending();
      }
    } finally {
      _flushing = false;
    }
  }

  /// One like or unlike, counted only if it changes this learner's like.
  /// Returns the count afterwards.
  Future<int> _send(String uid, String key, bool liked) async {
    final stats = _db.collection('reelStats').doc(docId(key));
    final mine = stats.collection('likes').doc(uid);
    return _db.runTransaction((tx) async {
      final had = (await tx.get(mine)).exists;
      final snap = await tx.get(stats);
      final now = (snap.data()?['likes'] as num?)?.toInt() ?? 0;
      // Already so, or a count that can't go lower: nothing to change.
      if (had == liked || (!liked && now == 0)) return now;
      if (liked) {
        tx.set(mine, {'at': FieldValue.serverTimestamp()});
      } else {
        tx.delete(mine);
      }
      tx.set(stats, {
        'likes': now + (liked ? 1 : -1),
        // What was liked, readable in the console; ids are hashes.
        'key': key.length > 300 ? key.substring(0, 300) : key,
      });
      return now + (liked ? 1 : -1);
    });
  }

  void _loadPending() {
    _pending.clear();
    try {
      final raw = _prefs?.getString(_pendingKey);
      if (raw != null) {
        (jsonDecode(raw) as Map).cast<String, bool>().forEach(
          (k, v) => _pending[k] = v,
        );
      }
    } catch (_) {
      // Unreadable: those likes stay on the phone uncounted.
    }
  }

  Future<void> _savePending() async =>
      _prefs?.setString(_pendingKey, jsonEncode(_pending));

  @visibleForTesting
  void resetForTest() {
    _server.clear();
    _delta.clear();
    _pending.clear();
    _refs.clear();
    for (final s in _subs.values) {
      unawaited(s.cancel());
    }
    _subs.clear();
    _prefs = null;
  }
}
