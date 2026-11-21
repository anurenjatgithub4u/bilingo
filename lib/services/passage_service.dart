import 'dart:math' as math;

import 'passage_bank.dart';

enum Difficulty {
  beginner('Beginner'),
  intermediate('Intermediate'),
  advanced('Advanced');

  const Difficulty(this.label);

  final String label;
}

enum PassageLength {
  short('Short', 50, 75),
  medium('Medium', 100, 150),
  long('Long', 200, 250);

  const PassageLength(this.label, this.minWords, this.maxWords);

  final String label;
  final int minWords;
  final int maxWords;

  String get range => '$minWords–$maxWords words';
}

/// What the learner asked to read.
class PassageRequest {
  const PassageRequest(this.topic, this.difficulty, this.length);

  final String topic;
  final Difficulty difficulty;
  final PassageLength length;

  /// Prompt for a text-generation backend, kept here so an AI source can
  /// be dropped in without touching the screens.
  String get prompt =>
      'Generate one natural English reading passage about $topic for a '
      '${difficulty.label.toLowerCase()} English learner. The passage should '
      'contain ${length.minWords}–${length.maxWords} words. Use grammatically '
      'correct, natural sentences and vocabulary suitable for the selected '
      'difficulty. Return only the passage text without a title, '
      'explanations, numbering, or markdown formatting.';

  @override
  bool operator ==(Object other) =>
      other is PassageRequest &&
      other.topic == topic &&
      other.difficulty == difficulty &&
      other.length == length;

  @override
  int get hashCode => Object.hash(topic, difficulty, length);
}

/// A passage to read aloud; [text] is the reference the reading is checked against.
class Passage {
  const Passage(this.request, this.text, {this.practice = false});

  final PassageRequest request;
  final String text;

  /// Built from the sentences the learner missed, not a fresh passage.
  final bool practice;
}

class PassageException implements Exception {
  const PassageException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Where passages come from.
abstract class PassageSource {
  /// Topics this source can write about without a custom prompt.
  bool supportsCustomTopics();

  /// A passage for [request], different from [previous] where possible.
  Future<Passage> generate(PassageRequest request, {Passage? previous});
}

/// Hand-written passages bundled with the app (no network). Each topic and
/// level has three short paragraphs; lengths combine one, two or all three.
class BundledPassageSource implements PassageSource {
  BundledPassageSource({math.Random? random})
    : _random = random ?? math.Random();

  final math.Random _random;

  @override
  bool supportsCustomTopics() => false;

  @override
  Future<Passage> generate(PassageRequest request, {Passage? previous}) async {
    final parts = kPassageBank[request.topic]?[request.difficulty];
    if (parts == null || parts.isEmpty) {
      throw PassageException(
        'There are no passages about “${request.topic}” yet. Pick one of the topics above.',
      );
    }
    final count = switch (request.length) {
      PassageLength.short => 1,
      PassageLength.medium => 2,
      PassageLength.long => parts.length,
    };
    String pick() {
      final order = [for (var i = 0; i < parts.length; i++) i]
        ..shuffle(_random);
      return order.take(count).map((i) => parts[i]).join(' ');
    }

    var text = pick();
    // Short and medium have several combinations; avoid repeating the last one.
    for (var tries = 0; tries < 6 && text == previous?.text; tries++) {
      text = pick();
    }
    return Passage(request, text);
  }
}

/// Hands out passages and remembers the last one per request, so going
/// back and forth does not replace the text unless a new one is asked for.
class PassageService {
  PassageService(this.source);

  static final PassageService instance = PassageService(BundledPassageSource());

  final PassageSource source;
  final _byRequest = <PassageRequest, Passage>{};

  /// The passage most recently handed out.
  Passage? last;

  Future<Passage> passageFor(
    PassageRequest request, {
    bool fresh = false,
  }) async {
    final cached = _byRequest[request];
    if (cached != null && !fresh) return last = cached;
    final passage = await source.generate(request, previous: cached);
    if (passage.text.trim().isEmpty) {
      throw const PassageException('The passage came back empty. Try again.');
    }
    _byRequest[request] = passage;
    return last = passage;
  }
}
