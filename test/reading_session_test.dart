import 'dart:async';

import 'package:dmonly/services/passage_service.dart';
import 'package:dmonly/services/reading_session.dart';
import 'package:dmonly/services/speech_service.dart';
import 'package:dmonly/services/word_aligner.dart';
import 'package:flutter_test/flutter_test.dart';

/// Recogniser that plays back whatever the test tells it to.
class FakeSpeechEngine implements SpeechEngine {
  FakeSpeechEngine({this.availability = SpeechAvailability.ready});

  SpeechAvailability availability;
  final _events = StreamController<SpeechEvent>.broadcast(sync: true);
  int listens = 0;
  int stops = 0;
  bool listening = false;

  @override
  Stream<SpeechEvent> get events => _events.stream;

  @override
  Future<SpeechAvailability> prepare() async => availability;

  @override
  Future<void> listen({List<String> hints = const []}) async {
    if (listening) throw StateError('two listen sessions at once');
    listening = true;
    listens++;
  }

  @override
  Future<void> stop() async {
    stops++;
    if (!listening) return;
    listening = false;
    _events.add(const SpeechDone());
  }

  @override
  Future<void> cancel() async => listening = false;

  void partial(String words) => _events.add(SpeechWords(words, isFinal: false));

  /// The recogniser ends a session by itself (pause or time limit).
  void finalAndDone(String words) {
    _events.add(SpeechWords(words, isFinal: true));
    listening = false;
    _events.add(const SpeechDone());
  }

  void fail(String code) {
    listening = false;
    _events.add(SpeechFailure(code));
  }
}

const _text = 'The sun is a very big star. It gives us light and heat.';

Passage _passage([String text = _text]) => Passage(
  const PassageRequest('Science', Difficulty.beginner, PassageLength.short),
  text,
);

Future<void> _tick() => Future<void>.delayed(const Duration(milliseconds: 20));

void main() {
  late FakeSpeechEngine engine;
  late ReadingSession session;

  setUp(() {
    engine = FakeSpeechEngine();
    session = ReadingSession(
      _passage(),
      engine: engine,
      restartDelay: const Duration(milliseconds: 1),
    );
  });

  tearDown(() => session.dispose());

  test('partial results light words up as they come in', () async {
    await session.start();
    expect(session.phase, ReadingPhase.listening);
    engine.partial('the sun');
    expect(session.marks.value.take(2), everyElement(WordMark.matched));
    engine.partial('the sun is a very');
    expect(session.matchedWords, 5);
  });

  test('restarts listening when the recogniser stops by itself', () async {
    await session.start();
    engine.finalAndDone('the sun is a very');
    await _tick();
    expect(engine.listens, 2);
    expect(session.phase, ReadingPhase.listening);
    // The new session's partials continue after the saved words.
    engine.partial('big star');
    expect(session.matchedWords, 7);
  });

  test('a slow reader with many short sessions keeps every word', () async {
    await session.start();
    for (final chunk in ['the sun', 'is a', 'very big', 'star it gives']) {
      engine.finalAndDone(chunk);
      await _tick();
    }
    expect(session.matchedWords, 9);
    expect(engine.listens, 5);
  });

  test(
    'a fast reader saying everything in one go finishes by itself',
    () async {
      await session.start();
      engine.partial('the sun is a very big star it gives us light and heat');
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      expect(session.phase, ReadingPhase.finished);
      expect(session.result!.accuracy, 100);
    },
  );

  test('silence timeouts restart quietly', () async {
    await session.start();
    engine.fail('error_speech_timeout');
    await _tick();
    expect(engine.listens, 2);
    expect(session.issue, isNull);
  });

  test('a recogniser that keeps failing pauses with an issue', () async {
    await session.start();
    engine.partial('the sun');
    for (var i = 0; i < 5; i++) {
      engine.fail('error_network');
      await _tick();
    }
    expect(session.phase, ReadingPhase.paused);
    expect(session.issue, ReadingIssue.network);
    // What was heard before the failure is kept.
    expect(session.matchedWords, 2);
  });

  test('a recogniser that never answers is restarted', () async {
    session.dispose();
    session = ReadingSession(
      _passage(),
      engine: engine,
      restartDelay: const Duration(milliseconds: 1),
      stallTimeout: const Duration(milliseconds: 30),
    );
    await session.start();
    await Future<void>.delayed(const Duration(milliseconds: 120));
    expect(engine.listens, greaterThan(1));
  });

  test('microphone permission denied', () async {
    engine.availability = SpeechAvailability.denied;
    await session.start();
    expect(session.phase, ReadingPhase.ready);
    expect(session.issue, ReadingIssue.permissionDenied);
    expect(engine.listens, 0);
  });

  test('pause and resume continue the same reading', () async {
    await session.start();
    engine.partial('the sun is');
    await session.pause();
    expect(session.phase, ReadingPhase.paused);
    expect(engine.stops, 1);
    await _tick();
    // No automatic restart while paused.
    expect(engine.listens, 1);
    await session.start();
    engine.partial('a very big');
    expect(session.matchedWords, 6);
  });

  test('tapping start twice opens only one listen session', () async {
    await Future.wait([session.start(), session.start()]);
    expect(engine.listens, 1);
  });

  test('stopping early scores unread words as unmatched', () async {
    await session.start();
    engine.partial('the sun is a big star');
    await session.finish();
    final r = session.result!;
    expect(session.phase, ReadingPhase.finished);
    expect(r.total, 13);
    expect(r.matched, 6);
    expect(r.notReached, 6);
    expect(r.missedWords, ['very']);
    expect(r.accuracy, 46);
    expect(r.missedSentences, 'The sun is a very big star.');
    expect(r.completed, isFalse);
  });

  test('reset clears the reading for another go', () async {
    await session.start();
    engine.partial('the sun is');
    await session.reset();
    expect(session.phase, ReadingPhase.ready);
    expect(session.matchedWords, 0);
    expect(session.marks.value, everyElement(WordMark.unread));
  });
}
