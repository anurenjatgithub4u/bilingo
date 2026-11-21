import 'package:flutter/material.dart';

import 'german_plurals.dart';
import 'word_extras.dart';
import 'word_service.dart';

/// Extra details for a word that words.json does not carry (see word_extras.dart).
class WordExtra {
  const WordExtra({
    this.article,
    this.display,
    required this.example,
    this.translation,
  });

  /// der, die or das for German nouns; null otherwise.
  final String? article;

  /// Correct spelling when the stored word differs (e.g. "Auf Wiedersehen").
  final String? display;

  /// A sentence using the word, in the word's language.
  final String example;

  /// English translation of [example]; null for English words.
  final String? translation;
}

const kLanguageNames = {'en': 'English', 'de': 'German', 'hi': 'Hindi'};

/// Grammatical gender of a German noun, shown with a colour per article
/// (blue der, red die, green das), as most German courses do.
enum GermanGender {
  masculine('der', 'masculine', Color(0xFF2F80FF)),
  feminine('die', 'feminine', Color(0xFFE5484D)),
  neuter('das', 'neuter', Color(0xFF2EB67D));

  const GermanGender(this.article, this.label, this.color);

  final String article;
  final String label;
  final Color color;

  static GermanGender? of(String? article) => switch (article) {
    'der' => masculine,
    'die' => feminine,
    'das' => neuter,
    _ => null,
  };
}

/// A word ready to show on a card: article, clean meaning, example sentence.
class VocabWord {
  VocabWord(this.source) : _extra = kWordExtras[source.key];

  final ShownWord source;
  final WordExtra? _extra;

  static final _romanised = RegExp(r'^\((.+?)\)\s*');

  /// Stable id, also used for likes and saves: "lang|word".
  String get id => source.key;
  String get lang => source.lang;
  int get level => source.level;
  String get languageName => kLanguageNames[lang] ?? lang.toUpperCase();

  /// The word itself, without the article.
  String get word => _extra?.display ?? source.word;

  String? get article => _extra?.article;
  GermanGender? get gender => GermanGender.of(article);

  /// The word as a learner should say it: "das Fernweh", "Auf Wiedersehen".
  String get headword => article == null ? word : '$article $word';

  /// A German noun's plural with its article, "die Äpfel"; null for nouns
  /// without one in everyday use, and for everything else.
  String? get pluralHeadword {
    if (article == null) return null;
    final plural = kGermanPlurals[source.word];
    return plural == null || plural.isEmpty ? null : 'die $plural';
  }

  /// A German noun used only in the singular (das Fernweh, die Geduld).
  bool get singularOnly =>
      article != null && kGermanPlurals[source.word]?.isEmpty == true;

  /// "Plural: die Äpfel" or "No plural" under a German noun, else null.
  String? get pluralLine {
    final plural = pluralHeadword;
    if (plural != null) return 'Plural: $plural';
    return singularOnly ? 'No plural' : null;
  }

  /// Dictionary style: "der Apfel, die Äpfel".
  String get headwordWithPlural {
    final plural = pluralHeadword;
    return plural == null ? headword : '$headword, $plural';
  }

  /// Latin spelling of a Hindi word, taken from the start of its meaning.
  String? get romanised => _romanised.firstMatch(source.meaning)?.group(1);

  /// The meaning without the Hindi romanisation prefix.
  String get meaning => source.meaning.replaceFirst(_romanised, '');

  String? get example => _extra?.example;
  String? get translation => _extra?.translation;

  /// Plain-text version for apps that ignore the image.
  String get shareText {
    final b = StringBuffer(headwordWithPlural);
    if (romanised != null) b.write(' ($romanised)');
    b
      ..write(' · $languageName\n')
      ..write(meaning);
    if (example != null) {
      b.write('\n\n“$example”');
      if (translation != null) b.write('\n$translation');
    }
    b.write('\n\nLearning with BiLingo');
    return b.toString();
  }
}

extension ShownWordHeadword on ShownWord {
  /// The word with its German article in front, when it has one.
  String get headword => VocabWord(this).headword;

  /// "Plural: die Äpfel" or "No plural" for a German noun, else null.
  String? get pluralLine => VocabWord(this).pluralLine;
}
