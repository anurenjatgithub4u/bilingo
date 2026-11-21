import 'dart:convert';
import 'dart:io';

import 'package:dmonly/services/german_plurals.dart';
import 'package:dmonly/services/vocab.dart';
import 'package:dmonly/services/word_extras.dart';
import 'package:dmonly/services/word_service.dart';
import 'package:flutter_test/flutter_test.dart';

VocabWord _de(String word) =>
    VocabWord(ShownWord(word: word, meaning: 'm', lang: 'de'));

Map<String, String> _asset(String name) => (jsonDecode(
  File('android/app/src/main/assets/$name').readAsStringSync(),
) as Map).cast<String, String>();

void main() {
  final articles = _asset('german_articles.json');

  test('the notification and the app use the same articles', () {
    final inApp = {
      for (final e in kWordExtras.entries)
        if (e.key.startsWith('de|') && e.value.article != null)
          e.key.substring(3): e.value.article,
    };
    expect(inApp, articles);
    expect(articles.values.toSet(), {'der', 'die', 'das'});
  });

  test('every noun has a plural entry, the same in both places', () {
    expect(kGermanPlurals.keys.toSet(), articles.keys.toSet());
    expect(_asset('german_plurals.json'), kGermanPlurals);
    for (final plural in kGermanPlurals.values.where((p) => p.isNotEmpty)) {
      // A noun, written without an article.
      expect(plural[0], plural[0].toUpperCase(), reason: plural);
      expect(plural.contains(' '), isFalse, reason: plural);
    }
  });

  test('der, die and das, with the plural die', () {
    expect(_de('Apfel').headword, 'der Apfel');
    expect(_de('Apfel').pluralHeadword, 'die Äpfel');
    expect(_de('Apfel').headwordWithPlural, 'der Apfel, die Äpfel');
    expect(_de('Katze').pluralLine, 'Plural: die Katzen');
    expect(_de('Haus').pluralLine, 'Plural: die Häuser');
    // Same form in the plural.
    expect(_de('Fenster').pluralHeadword, 'die Fenster');
    // No plural in everyday use: said so, never invented.
    expect(_de('Fernweh').headword, 'das Fernweh');
    expect(_de('Fernweh').pluralHeadword, isNull);
    expect(_de('Fernweh').pluralLine, 'No plural');
  });

  test('words that are not nouns get no article or plural', () {
    expect(_de('Hilfsbereit').headword, 'hilfsbereit');
    expect(_de('Verschlimmbessern').headword, 'verschlimmbessern');
    expect(_de('Aufwiedersehen').headword, 'Auf Wiedersehen');
    expect(_de('lernen').pluralLine, isNull);
    expect(
      VocabWord(const ShownWord(word: 'keen', meaning: 'm', lang: 'en'))
          .pluralLine,
      isNull,
    );
  });
}
