import 'package:dmonly/services/word_aligner.dart';
import 'package:flutter_test/flutter_test.dart';

const _text =
    'The quick brown fox jumps over the lazy dog. It was a sunny, '
    'well-known morning in the old town.';

WordAligner _aligner() => WordAligner(ReferenceText(_text));

String _marks(WordAlignment a) => a.marks
    .map(
      (m) => switch (m) {
        WordMark.unread => '.',
        WordMark.pending => '?',
        WordMark.matched => 'G',
        WordMark.missed => 'R',
      },
    )
    .join();

void main() {
  test('splits words and sentences, keeping punctuation for display', () {
    final r = ReferenceText(_text);
    expect(r.words.length, 19);
    expect(r.sentences.length, 2);
    expect(r.words[8].display, 'dog.');
    expect(r.words[8].key, 'dog');
    expect(r.words[12].key, 'sunny');
    expect(r.words[13].key, 'wellknown');
    expect(r.words[9].sentence, 1);
  });

  test('every word read correctly turns everything green', () {
    final a = _aligner().align(
      transcriptWords(
        'the quick brown fox jumps over the lazy dog it was a sunny well known '
        'morning in the old town',
      ),
      finished: true,
    );
    expect(a.matchedCount, 19);
    expect(_marks(a), 'G' * 19);
  });

  test('ignores punctuation and capitalisation', () {
    final a = _aligner().align(transcriptWords('THE Quick, brown... FOX!'));
    expect(_marks(a).substring(0, 4), 'GGGG');
  });

  test('a skipped word is pending first, then red once reading moves on', () {
    final aligner = _aligner();
    // "brown" skipped, only one word after it so far.
    var a = aligner.align(transcriptWords('the quick fox'));
    expect(_marks(a).substring(0, 4), 'GG?G');
    // Two more words heard after it: now confirmed missed.
    a = aligner.align(transcriptWords('the quick fox jumps over'));
    expect(_marks(a).substring(0, 6), 'GGRGGG');
    expect(a.matchedCount, 5);
  });

  test('a replaced word is missed and does not shift the rest', () {
    final a = _aligner().align(
      transcriptWords('the quick brown cat jumps over the lazy dog'),
    );
    expect(_marks(a).substring(0, 9), 'GGGRGGGGG');
  });

  test('a repeated word counts once and shifts nothing', () {
    final a = _aligner().align(
      transcriptWords('the quick quick brown brown fox jumps'),
    );
    expect(_marks(a).substring(0, 5), 'GGGGG');
    expect(a.matchedCount, 5);
  });

  test('re-reading the start of a sentence after a pause is harmless', () {
    final a = _aligner().align(
      transcriptWords('the quick brown the quick brown fox jumps over'),
    );
    expect(_marks(a).substring(0, 6), 'GGGGGG');
  });

  test('words not reached yet stay grey', () {
    final a = _aligner().align(transcriptWords('the quick brown'));
    expect(_marks(a), 'GGG${'.' * 16}');
  });

  test('a misheard word at the end waits in orange instead of red', () {
    final a = _aligner().align(transcriptWords('the quick brown fax'));
    // Short words must match exactly, so "fax" is not "fox".
    expect(_marks(a).substring(0, 5), 'GGG?.');
  });

  test('close spellings and homophones still match', () {
    final r = ReferenceText('Their colour is right for the weather.');
    final a = WordAligner(r)
        .align(transcriptWords('there color is write four the whether'));
    expect(a.matchedCount, 7);
  });

  test('two heard words can match one hyphenated word', () {
    final a = _aligner().align(
      transcriptWords(
        'the quick brown fox jumps over the lazy dog it was a sunny well known morning',
      ),
    );
    expect(a.marks[13], WordMark.matched);
    expect(a.marks[14], WordMark.matched);
  });

  test('a later transcript can revise an earlier partial', () {
    final aligner = _aligner();
    var a = aligner.align(transcriptWords('the quick brown box'));
    expect(a.marks[3], isNot(WordMark.matched));
    // The recogniser corrects itself in the next partial result.
    a = aligner.align(transcriptWords('the quick brown fox jumps'));
    expect(_marks(a).substring(0, 5), 'GGGGG');
  });

  test('locked words stay green even if a partial lines up differently', () {
    final a = _aligner().align(transcriptWords('xyz'), locked: {0, 1, 2});
    expect(_marks(a).substring(0, 3), 'GGG');
  });

  test(
    'finishing early turns pending words red and leaves the rest unread',
    () {
      final a = _aligner().align(
        transcriptWords('the quick fox'),
        finished: true,
      );
      expect(_marks(a), 'GGRG${'.' * 15}');
    },
  );

  test('going back to re-read a missed word picks it up again', () {
    final a = _aligner().align(
      transcriptWords('the quick fox jumps over the lazy dog quick brown fox'),
    );
    expect(a.marks[2], WordMark.matched);
  });

  test('silence matches nothing', () {
    final a = _aligner().align(const []);
    expect(a.matchedCount, 0);
    expect(a.frontier, -1);
    expect(_marks(a), '.' * 19);
  });

  test('number words and digits are the same word', () {
    final r = ReferenceText('I have five cats and 2 dogs.');
    final a = WordAligner(r)
        .align(transcriptWords('I have 5 cats and two dogs'));
    expect(a.matchedCount, 7);
  });

  test('a long passage aligns quickly', () {
    final words = List.generate(250, (i) => 'word$i').join(' ');
    final aligner = WordAligner(ReferenceText(words));
    final heard = transcriptWords(words);
    final sw = Stopwatch()..start();
    for (var i = 0; i < 20; i++) {
      aligner.align(heard);
    }
    expect(aligner.align(heard).matchedCount, 250);
    expect(sw.elapsedMilliseconds, lessThan(2000));
  });
}
