import 'package:flutter/material.dart';

class Topic {
  const Topic(this.code, this.name, this.subtitle, this.icon);

  /// Stable id stored in preferences. en/de match the word-notification languages.
  final String code;
  final String name;
  final String subtitle;
  final IconData icon;
}

const kTopics = [
  Topic('en', 'English', 'Vocabulary & grammar', Icons.translate),
  Topic('de', 'German', 'Wörter & Sätze', Icons.language),
];

const kWordLanguageCodes = {'en', 'de'};

/// Stored in [ProfileStore.topics] when the learner wants maths practice.
const kMathsCode = 'math';

/// Everything a learner can pick in onboarding. Coding then asks which
/// languages.
const kCodingCode = 'coding';

const kSubjects = [
  ...kTopics,
  Topic(kMathsCode, 'Mathematics', 'Numbers & quick sums', Icons.calculate_outlined),
  Topic(kCodingCode, 'Coding', 'Python & JavaScript logic', Icons.code_rounded),
];
