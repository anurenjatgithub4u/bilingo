import 'dart:async';

import 'package:flutter/foundation.dart';

import 'passage_service.dart';
import 'speech_service.dart';
import 'word_aligner.dart';

enum ReadingPhase { ready, starting, listening, paused, finished }

/// Why listening stopped on its own.
enum ReadingIssue {
  permissionDenied,
  unavailable,
  microphone,
  network,
  language,
  noSpeech,
  failed,
}

/// Outcome of one reading. Everything here comes from matching the
/// recogniser's text to the passage; it is not a pronunciation score.
class ReadingResult {
  const ReadingResult({
    required this.reference,
    required this.marks,
    required this.matched,
    required this.reached,
    required this.duration,
  });

  final ReferenceText reference;
  final List<WordMark> marks;
  final int matched;

  /// Passage words up to the last one heard.
  final int reached;
  final Duration duration;

  int get total => marks.length;

  /// Skipped, misread and not-reached words all count as unmatched.
  int get unmatched => total - matched;
  int get notReached => total - reached;
  bool get completed => notReached == 0;

  /// Matched passage words / all passage words × 100.
  int get accuracy => total == 0 ? 0 : (matched * 100 / total).round();

  int get wordsPerMinute => duration.inSeconds < 3
      ? 0
      : (reached * 60000 / duration.inMilliseconds).round();

  /// Distinct missed words, in passage order.
  List<String> get missedWords {
    final seen = <String>{};
    return [
      for (var i = 0; i < marks.length; i++)
        if (marks[i] == WordMark.missed && seen.add(reference.words[i].key))
          reference.words[i].display.replaceAll(
            RegExp(r'''^[^\w]+|[^\w']+$'''),
            '',
          ),
    ];
  }

  /// The original sentences that contain a missed word, for practice.
  String get missedSentences {
    final picked = <int>{
      for (var i = 0; i < marks.length; i++)
        if (marks[i] == WordMark.missed) reference.words[i].sentence,
    };
    return [
      for (var s = 0; s < reference.sentences.length; s++)
        if (picked.contains(s)) reference.sentences[s],
    ].join(' ');
  }

  String get headline {
    if (accuracy >= 90 && completed) return 'Great job!';
    if (accuracy >= 75) return 'Nicely read!';
    if (accuracy >= 50) return 'Good effort!';
    return 'Keep practising!';
  }

  String get feedback {
    final parts = <String>[
      if (accuracy >= 90 && completed)
        'You completed the reading exercise and almost every word was recognised.'
      else if (accuracy >= 75)
        'Your reading was consistent. Try practising the words you missed.'
      else if (accuracy >= 50)
        'Many words came through clearly. Slow down a little on the tricky ones.'
      else
        'Read a little slower and speak clearly. Every attempt helps.',
      if (!completed && reached > 0) 'You stopped before the end, so the rest of the passage counts as unread.',
    ];
    return parts.join(' ');
  }
}

/// One attempt at reading a passage aloud: drives the recogniser, keeps the
/// transcript and turns it into per-word marks.
///
/// Mobile recognisers end a listen session after a pause or a time limit,
/// so while the learner is reading the session is restarted automatically.
/// Each session's text is kept separately: partial results replace the
/// current session's words, final results are added for good.
class ReadingSession extends ChangeNotifier {
  ReadingSession(
    this.passage, {
    SpeechEngine? engine,
    this.restartDelay = const Duration(milliseconds: 250),
    this.stallTimeout = const Duration(seconds: 8),
  }) : reference = ReferenceText(passage.text),
       _engine = engine ?? DeviceSpeechEngine.instance {
    _aligner = WordAligner(reference);
    marks = ValueNotifier(List.filled(reference.words.length, WordMark.unread));
    _alignment = WordAlignment(marks.value, const {}, -1);
    _sub = _engine.events.listen(_onEvent);
  }

  final Passage passage;
  final ReferenceText reference;
  final SpeechEngine _engine;
  final Duration restartDelay;

  /// A working session sends level updates many times a second; this long
  /// without any event means the recogniser never started or got stuck.
  final Duration stallTimeout;
  late final WordAligner _aligner;
  late final StreamSubscription<SpeechEvent> _sub;

  /// Per-word marks; changes only when a mark actually changes.
  late final ValueNotifier<List<WordMark>> marks;

  /// Time spent listening, excluding pauses.
  final elapsed = ValueNotifier(Duration.zero);

  /// Microphone level 0..1 while listening.
  final level = ValueNotifier(0.0);

  ReadingPhase _phase = ReadingPhase.ready;
  ReadingIssue? _issue;
  ReadingResult? _result;
  late WordAlignment _alignment;

  ReadingPhase get phase => _phase;
  ReadingIssue? get issue => _issue;
  ReadingResult? get result => _result;
  int get totalWords => reference.words.length;
  int get matchedWords => _alignment.matchedCount;

  /// Next passage word to read, or -1 once the end is reached.
  int get cursor {
    final next = _alignment.frontier + 1;
    return next < totalWords ? next : -1;
  }

  bool get hasStarted => _settled.isNotEmpty || _live.isNotEmpty;

  /// Words from finished listen sessions, and from the current one.
  final _settled = <String>[];
  List<String> _live = const [];

  /// Passage words matched in final results; they stay green.
  final _locked = <int>{};

  bool _wantListening = false;
  bool _engineActive = false;
  Completer<void>? _closed;
  int _idleRestarts = 0;
  int _failures = 0;
  Timer? _restartTimer;
  Timer? _ticker;
  Timer? _finishTimer;
  Timer? _watchdog;
  final _watch = Stopwatch();
  bool _disposed = false;

  /// About 40 s of silence (Android ends a session after ~5 s without speech).
  static const _maxIdleRestarts = 8;
  static const _maxFailures = 3;

  late final List<String> _hints = {
    for (final w in reference.words)
      w.display.replaceAll(RegExp(r'''^[^\w]+|[^\w']+$'''), ''),
  }.take(100).toList();

  /// Starts listening, or resumes after a pause.
  Future<void> start() async {
    if (_disposed ||
        _phase == ReadingPhase.starting ||
        _phase == ReadingPhase.listening ||
        _phase == ReadingPhase.finished) {
      return;
    }
    _issue = null;
    _setPhase(ReadingPhase.starting);
    final availability = await _engine.prepare();
    if (_disposed || _phase != ReadingPhase.starting) return;
    if (availability != SpeechAvailability.ready) {
      _issue = availability == SpeechAvailability.denied
          ? ReadingIssue.permissionDenied
          : ReadingIssue.unavailable;
      _setPhase(hasStarted ? ReadingPhase.paused : ReadingPhase.ready);
      return;
    }
    _wantListening = true;
    _idleRestarts = 0;
    _failures = 0;
    _watch.start();
    _ticker ??= Timer.periodic(const Duration(milliseconds: 500), (_) {
      elapsed.value = _watch.elapsed;
    });
    _setPhase(ReadingPhase.listening);
    await _listen();
  }

  Future<void> pause() async {
    if (_phase != ReadingPhase.listening && _phase != ReadingPhase.starting) {
      return;
    }
    _stopClock();
    _setPhase(ReadingPhase.paused);
    if (_engineActive) {
      try {
        // Delivers a final result for what was said so far.
        await _engine.stop();
      } catch (_) {}
    }
  }

  /// Stops reading and scores what was heard.
  Future<void> finish() async {
    if (_disposed || _phase == ReadingPhase.finished) return;
    _stopClock();
    _finishTimer?.cancel();
    if (_engineActive) {
      try {
        await _engine.stop();
        await _closed?.future.timeout(
          const Duration(milliseconds: 800),
          onTimeout: () {},
        );
      } catch (_) {}
    }
    if (_disposed) return;
    _settleLive();
    _recompute(finished: true);
    _result = ReadingResult(
      reference: reference,
      marks: marks.value,
      matched: _alignment.matchedCount,
      reached: _alignment.frontier + 1,
      duration: _watch.elapsed,
    );
    _setPhase(ReadingPhase.finished);
  }

  /// Clears everything heard so the passage can be read from the start.
  Future<void> reset() async {
    _stopClock();
    _finishTimer?.cancel();
    if (_engineActive) {
      _engineActive = false;
      _closeSession();
      try {
        await _engine.cancel();
      } catch (_) {}
    }
    _settled.clear();
    _live = const [];
    _locked.clear();
    _watch.reset();
    elapsed.value = Duration.zero;
    _issue = null;
    _result = null;
    _recompute();
    _setPhase(ReadingPhase.ready);
  }

  void clearIssue() {
    if (_issue == null) return;
    _issue = null;
    notifyListeners();
  }

  void _stopClock() {
    _wantListening = false;
    _restartTimer?.cancel();
    _watch.stop();
    elapsed.value = _watch.elapsed;
    level.value = 0;
  }

  Future<void> _listen() async {
    if (_engineActive || !_wantListening || _disposed) return;
    _engineActive = true;
    _closed = Completer<void>();
    _feedWatchdog();
    try {
      await _engine.listen(hints: _hints);
    } catch (_) {
      _onFailure(const SpeechFailure('error_listen_failed'));
    }
  }

  void _onEvent(SpeechEvent event) {
    if (_disposed || !_engineActive) return;
    _feedWatchdog();
    switch (event) {
      case SpeechWords(:final words, :final isFinal):
        _onWords(words, isFinal);
      case SpeechLevel(level: final value):
        if (_phase == ReadingPhase.listening) level.value = value;
      case SpeechDone():
        _onClosed();
      case SpeechFailure():
        _onFailure(event);
    }
  }

  void _onWords(String words, bool isFinal) {
    final wasStarted = hasStarted;
    final heard = transcriptWords(words);
    if (heard.isNotEmpty) {
      _idleRestarts = 0;
      _failures = 0;
    }
    if (isFinal) {
      _settled.addAll(heard);
      _live = const [];
    } else {
      _live = heard;
    }
    _recompute(lock: isFinal);
    // The first words enable Finish and Start over.
    if (!wasStarted && hasStarted) notifyListeners();
    _maybeAutoFinish();
  }

  /// The listen session ended; open the next one if still reading.
  void _onClosed() {
    _engineActive = false;
    _closeSession();
    _settleLive();
    level.value = 0;
    if (_wantListening) _scheduleRestart(restartDelay);
  }

  void _onFailure(SpeechFailure failure) {
    _engineActive = false;
    _closeSession();
    _settleLive();
    level.value = 0;
    if (!_wantListening) return;
    if (failure.isPermission) return _halt(ReadingIssue.permissionDenied);
    if (failure.isAudio) return _halt(ReadingIssue.microphone);
    if (failure.isLanguage) return _halt(ReadingIssue.language);
    if (failure.isSilence) return _scheduleRestart(restartDelay);
    if (++_failures > _maxFailures) {
      return _halt(
        failure.isNetwork ? ReadingIssue.network : ReadingIssue.failed,
      );
    }
    // Busy or a network blip: give the recogniser a moment.
    _scheduleRestart(restartDelay * 3);
  }

  void _scheduleRestart(Duration delay) {
    // A failure is often followed by a "done"; restart once.
    if (_restartTimer?.isActive ?? false) return;
    if (++_idleRestarts > _maxIdleRestarts) {
      return _halt(ReadingIssue.noSpeech);
    }
    _restartTimer = Timer(delay, () {
      if (_wantListening && !_disposed) _listen();
    });
  }

  void _halt(ReadingIssue issue) {
    _stopClock();
    _issue = issue;
    _setPhase(hasStarted ? ReadingPhase.paused : ReadingPhase.ready);
  }

  void _feedWatchdog() {
    _watchdog?.cancel();
    _watchdog = Timer(stallTimeout, () {
      if (!_engineActive || _disposed) return;
      _engine.cancel().catchError((_) {});
      _onFailure(const SpeechFailure('error_stalled'));
    });
  }

  void _closeSession() {
    _watchdog?.cancel();
    final c = _closed;
    if (c != null && !c.isCompleted) c.complete();
  }

  /// A session that ended without a final result keeps its last partial.
  void _settleLive() {
    if (_live.isEmpty) return;
    _settled.addAll(_live);
    _live = const [];
    _recompute(lock: true);
  }

  void _recompute({bool lock = false, bool finished = false}) {
    final a = _aligner.align(
      [..._settled, ..._live],
      locked: _locked,
      finished: finished,
    );
    if (lock) _locked.addAll(a.matched);
    _alignment = a;
    if (!listEquals(a.marks, marks.value)) marks.value = a.marks;
  }

  /// The last word was heard: wrap up once the recogniser settles.
  void _maybeAutoFinish() {
    if (_alignment.frontier != totalWords - 1) return;
    if (_finishTimer?.isActive ?? false) return;
    _finishTimer = Timer(const Duration(milliseconds: 900), () {
      if (_alignment.frontier == totalWords - 1) finish();
    });
  }

  void _setPhase(ReadingPhase phase) {
    if (_disposed) return;
    _phase = phase;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _wantListening = false;
    _restartTimer?.cancel();
    _ticker?.cancel();
    _finishTimer?.cancel();
    _watchdog?.cancel();
    _sub.cancel();
    if (_engineActive) _engine.cancel().catchError((_) {});
    marks.dispose();
    elapsed.dispose();
    level.dispose();
    super.dispose();
  }
}
