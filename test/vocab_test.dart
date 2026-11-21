import 'dart:convert';
import 'dart:io';

import 'package:dmonly/services/vocab.dart';
import 'package:dmonly/services/word_extras.dart';
import 'package:dmonly/services/word_service.dart';
import 'package:flutter_test/flutter_test.dart';

VocabWord _word(String lang, String word, [String meaning = 'm']) =>
    VocabWord(ShownWord(word: word, meaning: meaning, lang: lang));

void main() {
  test('every word in words.json has an example', () {
    final words = jsonDecode(
      File('android/app/src/main/assets/words.json').readAsStringSync(),
    ) as List;
    for (final w in words.cast<Map<String, dynamic>>()) {
      final key = '${w['lang']}|${w['word']}';
      expect(kWordExtras[key]?.example, isNotNull, reason: key);
      if (w['lang'] != 'en') {
        expect(kWordExtras[key]?.translation, isNotNull, reason: key);
      }
    }
  });

  test('German nouns get their article', () {
    expect(_word('de', 'Fernweh').headword, 'das Fernweh');
    expect(_word('de', 'Freundschaft').headword, 'die Freundschaft');
    expect(_word('de', 'Augenblick').headword, 'der Augenblick');
    expect(_word('de', 'Fernweh').gender, GermanGender.neuter);
    expect(_word('de', 'Ohrwurm').gender, GermanGender.masculine);
  });

  test('German words that are not nouns are spelled correctly, no article', () {
    expect(_word('de', 'Aufwiedersehen').headword, 'Auf Wiedersehen');
    expect(_word('de', 'Hilfsbereit').headword, 'hilfsbereit');
    expect(_word('de', 'Verschlimmbessern').article, isNull);
  });

  test('only German words have articles', () {
    for (final e in kWordExtras.entries) {
      if (!e.key.startsWith('de|')) expect(e.value.article, isNull);
      if (e.value.article != null) {
        expect(GermanGender.of(e.value.article), isNotNull, reason: e.key);
      }
    }
  });

  test('Hindi romanisation is split from the meaning', () {
    final w = _word('hi', 'घर', '(ghar) Home; house.');
    expect(w.romanised, 'ghar');
    expect(w.meaning, 'Home; house.');
    expect(_word('en', 'keen', 'Eager.').romanised, isNull);
  });

  test('share text has word, language, meaning and example', () {
    final text = _word(
      'de',
      'Fernweh',
      'A longing for far-off places.',
    ).shareText;
    expect(text, contains('das Fernweh · German'));
    expect(text, contains('A longing for far-off places.'));
    expect(text, contains('Im Winter habe ich oft Fernweh.'));
    expect(text, contains('BiLingo'));
  });

  test('notification articles match the articles on word cards', () {
    final articles =
        (jsonDecode(
                  File(
                    'android/app/src/main/assets/german_articles.json',
                  ).readAsStringSync(),
                )
                as Map)
            .cast<String, String>();
    final expected = {
      for (final e in kWordExtras.entries)
        if (e.key.startsWith('de|') && e.value.article != null)
          e.key.substring(3): e.value.article!,
    };
    expect(articles, expected);
    expect(articles['Gemeinschaft'], 'die');
    expect(articles['Fernweh'], 'das');
  });
}
