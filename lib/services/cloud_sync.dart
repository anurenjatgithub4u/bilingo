import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import 'arrest_store.dart';
import 'auth_service.dart';
import 'passage_service.dart';
import 'premium_store.dart';
import 'profile_store.dart';
import 'progress_store.dart';
import 'reading_session.dart';
import 'word_interactions.dart';
import 'word_service.dart';

/// Keeps the learner's details and progress in Firestore.
///
/// Every install has a Firebase user (anonymous until the learner signs in),
/// so progress is stored from the first session. Layout:
///
/// * `users/{uid}`: profile, settings, lesson progress, reading totals and
///   WordFlow likes and saved words.
/// * `users/{uid}/readingSessions/{id}`: one document per Read & Speak attempt.
/// * `users/{uid}/daily/{yyyy-MM-dd}`: reading totals per day.
///
/// Writes go through Firestore's offline queue, so nothing waits on the
/// network and results reach the server once the phone is back online.
class CloudSync {
  CloudSync._();

  static final CloudSync instance = CloudSync._();

  Timer? _debounce;
  StreamSubscription<User?>? _userSub;
  String? _uid;

  /// False in tests and anywhere Firebase was not initialised.
  bool get _ready => Firebase.apps.isNotEmpty;

  FirebaseFirestore get _db => FirebaseFirestore.instance;

  /// True while the learner has not signed in (anonymous or no user yet).
  bool get isGuest =>
      _ready && (FirebaseAuth.instance.currentUser?.isAnonymous ?? true);

  /// Starts syncing: makes sure there is a user, then follows profile changes.
  Future<void> start() async {
    if (!_ready || _userSub != null) return;
    ProfileStore.instance.addListener(_schedulePush);
    WordInteractions.instance.addListener(_schedulePush);
    ProgressStore.instance.addListener(_schedulePush);
    ArrestStore.instance.addListener(_schedulePush);
    PremiumStore.instance.addListener(_schedulePush);
    _userSub = FirebaseAuth.instance.userChanges().listen(_onUser);
    await AuthService.instance.ensureUser();
  }

  Future<void> _onUser(User? user) async {
    if (user == null) return;
    if (user.uid != _uid) {
      _uid = user.uid;
      // A different account (new install, or signed in to an existing one):
      // bring its saved progress onto this phone before writing ours back.
      await _pullProfile(user.uid);
    }
    await pushProfile();
  }

  void _schedulePush() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 2), pushProfile);
  }

  Future<String?> _currentUid() async {
    if (!_ready) return null;
    if (FirebaseAuth.instance.currentUser == null) {
      // The first launch may have been offline; try again now.
      await AuthService.instance.ensureUser();
    }
    return FirebaseAuth.instance.currentUser?.uid;
  }

  DocumentReference<Map<String, dynamic>> _userDoc(String uid) =>
      _db.collection('users').doc(uid);

  Future<void> _pullProfile(String uid) async {
    try {
      final snap = await _userDoc(uid).get();
      final data = snap.data();
      if (data != null) {
        await ProfileStore.instance.mergeCloud(data);
        ArrestStore.instance.mergeCloud(
          (data['scrollPatrol'] as Map?)?.cast<String, dynamic>(),
        );
        await ProgressStore.instance.mergeCloud(
          (data['reelProgress'] as Map?)?.cast<String, dynamic>(),
        );
        await WordInteractions.instance.mergeCloud(
          (data['interactions'] as Map?)?.cast<String, dynamic>(),
        );
      }
    } catch (e) {
      debugPrint('CloudSync: could not load profile: $e');
    }
  }

  /// Writes the learner's details, settings and progress to `users/{uid}`.
  Future<void> pushProfile() async {
    final user = _ready ? FirebaseAuth.instance.currentUser : null;
    if (user == null) return;
    WordState? words;
    try {
      words = await const WordService().getState();
    } catch (_) {
      // Native side unavailable.
    }
    final created = user.metadata.creationTime;
    unawaited(
      _userDoc(user.uid)
          .set({
            'uid': user.uid,
            'email': user.email,
            'displayName': user.displayName,
            'isAnonymous': user.isAnonymous,
            'providers': [for (final p in user.providerData) p.providerId],
            if (created != null) 'createdAt': Timestamp.fromDate(created),
            'lastSeenAt': FieldValue.serverTimestamp(),
            'platform': defaultTargetPlatform.name,
            ...ProfileStore.instance.toCloud(),
            'interactions': WordInteractions.instance.toCloud(),
            'reelProgress': ProgressStore.instance.toCloud(),
            'scrollPatrol': ArrestStore.instance.toCloud(),
            'premium': PremiumStore.instance.toCloud(),
            if (words != null)
              'wordNotifications': {
                'enabled': words.enabled,
                'onScreenOn': words.onScreenOn,
                'onUnlock': words.onUnlock,
                'languages': words.languages.toList(),
                'trackedApps': words.trackedApps.toList(),
                'limitMinutes': words.limitMinutes,
                'shownToday': words.shownToday,
                'totalShown': words.totalShown,
                'streak': words.streak,
                'learned': words.learned,
              },
          }, SetOptions(merge: true))
          .catchError((Object e) => debugPrint('CloudSync: profile: $e')),
    );
  }

  /// Saves one finished Read & Speak attempt and adds it to the totals.
  Future<void> recordReading(Passage passage, ReadingResult r) async {
    final uid = await _currentUid();
    if (uid == null) return;
    final now = DateTime.now();
    final day =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final seconds = r.duration.inSeconds;
    final user = _userDoc(uid);
    final batch = _db.batch()
      ..set(user.collection('readingSessions').doc(), {
        'topic': passage.request.topic,
        'difficulty': passage.request.difficulty.name,
        'length': passage.request.length.name,
        'practice': passage.practice,
        'totalWords': r.total,
        'matchedWords': r.matched,
        'missedWords': r.unmatched - r.notReached,
        'notReachedWords': r.notReached,
        'accuracy': r.accuracy,
        'wordsPerMinute': r.wordsPerMinute,
        'durationSeconds': seconds,
        'completed': r.completed,
        'missedWordList': r.missedWords.take(50).toList(),
        'day': day,
        'createdAt': FieldValue.serverTimestamp(),
      })
      ..set(user, {
        'reading': {
          'sessions': FieldValue.increment(1),
          'completedSessions': FieldValue.increment(r.completed ? 1 : 0),
          'wordsMatched': FieldValue.increment(r.matched),
          'wordsTotal': FieldValue.increment(r.total),
          'secondsRead': FieldValue.increment(seconds),
          'accuracySum': FieldValue.increment(r.accuracy),
          'lastTopic': passage.request.topic,
          'lastDifficulty': passage.request.difficulty.name,
          'lastReadAt': FieldValue.serverTimestamp(),
        },
        'lastSeenAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true))
      ..set(user.collection('daily').doc(day), {
        'day': day,
        'readingSessions': FieldValue.increment(1),
        'wordsMatched': FieldValue.increment(r.matched),
        'secondsRead': FieldValue.increment(seconds),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    // Not awaited: offline, commit only completes once the server has it.
    unawaited(
      batch.commit().catchError(
        (Object e) => debugPrint('CloudSync: reading: $e'),
      ),
    );
  }

  /// Reads the guest's reading history before signing in to an existing
  /// account, which replaces the guest user. Null when not a guest.
  Future<GuestData?> takeGuestData() async {
    final user = _ready ? FirebaseAuth.instance.currentUser : null;
    if (user == null || !user.isAnonymous) return null;
    try {
      final doc = _userDoc(user.uid);
      final results = await Future.wait([
        doc.get(),
        doc.collection('readingSessions').limit(300).get(),
        doc.collection('daily').limit(90).get(),
      ]);
      final profile = results[0] as DocumentSnapshot<Map<String, dynamic>>;
      final sessions = results[1] as QuerySnapshot<Map<String, dynamic>>;
      final daily = results[2] as QuerySnapshot<Map<String, dynamic>>;
      return GuestData(
        user.uid,
        (profile.data()?['reading'] as Map<String, dynamic>?) ?? const {},
        [for (final d in sessions.docs) d.data()],
        {for (final d in daily.docs) d.id: d.data()},
      );
    } catch (e) {
      debugPrint('CloudSync: could not read guest data: $e');
      return null;
    }
  }

  /// Adds a former guest's reading history to the account now signed in.
  Future<void> adoptGuestData(GuestData guest) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid == guest.uid) return;
    final user = _userDoc(uid);
    final writes = <void Function(WriteBatch)>[
      for (final s in guest.sessions)
        (b) => b.set(user.collection('readingSessions').doc(), {
          ...s,
          'fromGuest': guest.uid,
        }),
      for (final e in guest.daily.entries)
        (b) => b.set(user.collection('daily').doc(e.key), {
          'day': e.key,
          for (final k in const [
            'readingSessions',
            'wordsMatched',
            'secondsRead',
          ])
            k: FieldValue.increment((e.value[k] as num?) ?? 0),
        }, SetOptions(merge: true)),
      (b) => b.set(user, {
        'reading': {
          for (final e in guest.reading.entries)
            if (e.value is num) e.key: FieldValue.increment(e.value as num),
        },
      }, SetOptions(merge: true)),
    ];
    // A batch holds at most 500 writes.
    for (var i = 0; i < writes.length; i += 450) {
      final batch = _db.batch();
      for (final w in writes.skip(i).take(450)) {
        w(batch);
      }
      unawaited(
        batch.commit().catchError(
          (Object e) => debugPrint('CloudSync: guest data: $e'),
        ),
      );
    }
  }
}

/// A guest's reading history, carried over when they sign in to an
/// account that already existed.
class GuestData {
  const GuestData(this.uid, this.reading, this.sessions, this.daily);

  final String uid;
  final Map<String, dynamic> reading;
  final List<Map<String, dynamic>> sessions;
  final Map<String, Map<String, dynamic>> daily;
}
