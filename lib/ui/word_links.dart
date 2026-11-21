import 'package:flutter/material.dart';

import '../services/word_service.dart';
import 'patrol.dart';
import 'word_detail_screen.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

/// Routes taps on the word notification to the Word Detail screen, and on
/// the Scroll Patrol notification to the arrest screen.
///
/// A tap can arrive before the home shell exists (cold start, splash, onboarding),
/// so the word is parked until [shellReady] and then opened.
class WordLinks {
  WordLinks._();

  static final WordLinks instance = WordLinks._();

  final _service = const WordService();
  ShownWord? _pending;
  bool _pendingArrest = false;
  bool _shellReady = false;

  void init() {
    _service.onOpenWord(_open);
    _service.onOpenArrest((_, _) => _openArrest());
  }

  /// Called by the home shell once it is on screen.
  Future<void> shellReady() async {
    _shellReady = true;
    try {
      _pending ??= await _service.takeLaunchWord();
    } catch (_) {
      // No native side (e.g. tests): nothing to open.
    }
    final word = _pending;
    _pending = null;
    if (word != null) _push(word);
    try {
      if (await _service.takeLaunchArrest() != null) _pendingArrest = true;
    } catch (_) {
      // No native side.
    }
    final arrest = _pendingArrest;
    _pendingArrest = false;
    final nav = navigatorKey.currentState;
    // Opening the app is also when Scroll Patrol catches up.
    if (nav != null) await Patrol.instance.check(nav, fromNotification: arrest);
  }

  void _openArrest() {
    final nav = navigatorKey.currentState;
    if (_shellReady && nav != null) {
      Patrol.instance.check(nav, fromNotification: true);
    } else {
      _pendingArrest = true;
    }
  }

  void shellGone() => _shellReady = false;

  void _open(ShownWord word) {
    if (_shellReady) {
      _push(word);
    } else {
      _pending = word;
    }
  }

  void _push(ShownWord word) {
    navigatorKey.currentState?.push(
      MaterialPageRoute<void>(builder: (_) => WordDetailScreen(word: word)),
    );
  }
}
