/// One short sentence to say aloud in WordFlow.
class ReadingText {
  const ReadingText({
    required this.lang,
    required this.level,
    required this.topic,
    required this.index,
    required this.text,
    this.translation,
  });

  final String lang;

  /// 1 beginner, 2 intermediate, 3 advanced.
  final int level;
  final String topic;

  /// Position in its language's list; only ever append, so ids stay stable.
  final int index;
  final String text;

  /// English meaning, for sentences in another language.
  final String? translation;

  /// Stable across days, so likes and saves keep pointing at it.
  String get id => 'read|$lang|$topic~$level~$index';

  /// How it reads in a list.
  String get excerpt => text;
}

/// English sentences people really say: (level, topic, sentence).
const _english = [
  (1, 'Daily Life', 'I wake up at seven every day.'),
  (1, 'Daily Life', 'Please close the door.'),
  (1, 'Daily Life', 'What time is it now?'),
  (1, 'Daily Life', 'My sister lives near me.'),
  (1, 'Food', 'I would like a cup of tea.'),
  (1, 'Food', 'This soup is very good.'),
  (1, 'Food', 'Can I have some water, please?'),
  (1, 'Travel', 'Where is the bus stop?'),
  (1, 'Travel', 'I am going to the market.'),
  (1, 'Travel', 'How far is the station?'),
  (1, 'Feelings', 'I am very happy today.'),
  (1, 'Feelings', 'Thank you for your help.'),
  (1, 'Feelings', 'Are you feeling better now?'),
  (1, 'Education', 'I read a book every night.'),
  (1, 'Education', 'Can you say that again?'),
  (1, 'Nature', 'It is raining outside today.'),
  (1, 'Nature', 'The sun is very hot.'),
  (1, 'Sports', 'We play football after school.'),
  (1, 'Work', 'I start work at nine.'),
  (1, 'Technology', 'My phone needs to charge.'),
  (2, 'Daily Life', 'I usually go for a walk after dinner.'),
  (2, 'Daily Life', 'Could you remind me to call her tomorrow?'),
  (2, 'Daily Life', 'We need to clean the house this weekend.'),
  (2, 'Food', 'I have never tried this dish before.'),
  (2, 'Food', 'Could we see the menu, please?'),
  (2, 'Food', 'This restaurant is cheaper than the last one.'),
  (2, 'Travel', 'Could you tell me how to get there?'),
  (2, 'Travel', 'Our flight was delayed by two hours.'),
  (2, 'Travel', 'I would love to visit that city someday.'),
  (2, 'Feelings', 'I was a little nervous before the meeting.'),
  (2, 'Feelings', 'It means a lot that you came today.'),
  (2, 'Education', 'I am learning a little more each day.'),
  (2, 'Education', 'Practice helps me remember new words.'),
  (2, 'Nature', 'The weather has changed a lot this week.'),
  (2, 'Sports', 'She has been running every morning this year.'),
  (2, 'Sports', 'Our team almost won the final game.'),
  (2, 'Work', 'I will send you the report this afternoon.'),
  (2, 'Work', 'Can we move the meeting to Friday?'),
  (2, 'Technology', 'I spend too much time on my phone.'),
  (2, 'Technology', 'Please turn it off and start it again.'),
  (3, 'Daily Life', 'I would rather stay in than go out tonight.'),
  (3, 'Daily Life', 'Small habits eventually shape who we become.'),
  (3, 'Food', 'The flavour was far more subtle than I expected.'),
  (3, 'Travel', 'Had we left earlier, we would have caught the train.'),
  (3, 'Travel', 'Travelling alone taught me to trust my instincts.'),
  (3, 'Feelings', 'I struggled to hide my disappointment at the news.'),
  (3, 'Feelings', 'Honest feedback is uncomfortable but genuinely valuable.'),
  (3, 'Education', 'Curiosity matters more than memorising every detail.'),
  (3, 'Education', 'The explanation was concise, yet surprisingly thorough.'),
  (3, 'Nature', 'Rising temperatures threaten many fragile ecosystems.'),
  (3, 'Nature', 'Conservation requires patience and sustained public support.'),
  (3, 'Sports', 'Despite the injury, she refused to withdraw.'),
  (3, 'Work', 'We need to prioritise quality over short-term growth.'),
  (3, 'Work', 'Her proposal was ambitious but entirely feasible.'),
  (3, 'Work', 'Clear communication prevents most misunderstandings at work.'),
  (
    3,
    'Technology',
    'Automation raises difficult questions about future employment.',
  ),
  (3, 'Technology', 'Convenience often comes at the expense of privacy.'),
  (3, 'Science', 'The evidence does not support that conclusion.'),
  (3, 'Science', 'Correlation alone does not prove a causal relationship.'),
  (3, 'Science', 'The results were consistent across every independent study.'),
];

/// German sentences: (level, topic, sentence, English meaning).
const _german = [
  (1, 'Daily Life', 'Ich stehe um sieben Uhr auf.', 'I get up at seven.'),
  (1, 'Daily Life', 'Wie spät ist es jetzt?', 'What time is it now?'),
  (
    1,
    'Daily Life',
    'Ich wohne in einer kleinen Stadt.',
    'I live in a small town.',
  ),
  (1, 'Daily Life', 'Meine Schwester heißt Anna.', 'My sister is called Anna.'),
  (1, 'Food', 'Ich hätte gern einen Kaffee.', 'I would like a coffee.'),
  (1, 'Food', 'Das Brot ist sehr frisch.', 'The bread is very fresh.'),
  (1, 'Food', 'Was kostet der Apfel?', 'How much is the apple?'),
  (1, 'Travel', 'Wo ist der Bahnhof?', 'Where is the train station?'),
  (1, 'Travel', 'Ich fahre mit dem Bus.', 'I am going by bus.'),
  (1, 'Travel', 'Ist das weit von hier?', 'Is that far from here?'),
  (1, 'Feelings', 'Heute bin ich sehr glücklich.', 'Today I am very happy.'),
  (
    1,
    'Feelings',
    'Vielen Dank für deine Hilfe.',
    'Thank you very much for your help.',
  ),
  (1, 'Feelings', 'Wie geht es dir heute?', 'How are you today?'),
  (1, 'Education', 'Ich lerne jeden Tag Deutsch.', 'I learn German every day.'),
  (
    1,
    'Education',
    'Können Sie das bitte wiederholen?',
    'Could you repeat that, please?',
  ),
  (
    1,
    'Nature',
    'Heute regnet es den ganzen Tag.',
    'Today it is raining all day.',
  ),
  (1, 'Nature', 'Die Sonne scheint heute.', 'The sun is shining today.'),
  (
    1,
    'Sports',
    'Wir spielen am Samstag Fußball.',
    'We play football on Saturday.',
  ),
  (1, 'Work', 'Ich arbeite von neun bis fünf.', 'I work from nine to five.'),
  (1, 'Technology', 'Mein Handy ist leer.', 'My phone battery is empty.'),
  (
    2,
    'Daily Life',
    'Nach dem Essen gehe ich meistens spazieren.',
    'After dinner I usually go for a walk.',
  ),
  (
    2,
    'Daily Life',
    'Kannst du mich morgen daran erinnern?',
    'Can you remind me about it tomorrow?',
  ),
  (
    2,
    'Daily Life',
    'Am Wochenende müssen wir die Wohnung putzen.',
    'We have to clean the flat at the weekend.',
  ),
  (
    2,
    'Food',
    'Dieses Gericht habe ich noch nie probiert.',
    'I have never tried this dish.',
  ),
  (
    2,
    'Food',
    'Könnten wir bitte die Speisekarte haben?',
    'Could we have the menu, please?',
  ),
  (
    2,
    'Food',
    'Dieses Restaurant ist günstiger als das letzte.',
    'This restaurant is cheaper than the last one.',
  ),
  (
    2,
    'Travel',
    'Können Sie mir sagen, wie ich dorthin komme?',
    'Can you tell me how to get there?',
  ),
  (
    2,
    'Travel',
    'Unser Flug hatte zwei Stunden Verspätung.',
    'Our flight was two hours late.',
  ),
  (
    2,
    'Travel',
    'Ich möchte diese Stadt irgendwann besuchen.',
    'I would like to visit this city someday.',
  ),
  (
    2,
    'Feelings',
    'Vor dem Gespräch war ich etwas nervös.',
    'I was a little nervous before the conversation.',
  ),
  (
    2,
    'Feelings',
    'Es freut mich, dass du gekommen bist.',
    'I am glad that you came.',
  ),
  (
    2,
    'Education',
    'Ich lerne jeden Tag ein bisschen mehr.',
    'I learn a little more every day.',
  ),
  (
    2,
    'Education',
    'Durch Übung merke ich mir neue Wörter.',
    'Practice helps me remember new words.',
  ),
  (
    2,
    'Nature',
    'Das Wetter hat sich diese Woche stark verändert.',
    'The weather has changed a lot this week.',
  ),
  (
    2,
    'Sports',
    'Sie läuft dieses Jahr jeden Morgen.',
    'She has been running every morning this year.',
  ),
  (
    2,
    'Sports',
    'Unsere Mannschaft hätte fast gewonnen.',
    'Our team almost won.',
  ),
  (
    2,
    'Work',
    'Ich schicke Ihnen den Bericht heute Nachmittag.',
    'I will send you the report this afternoon.',
  ),
  (
    2,
    'Work',
    'Können wir den Termin auf Freitag verschieben?',
    'Can we move the appointment to Friday?',
  ),
  (
    2,
    'Technology',
    'Ich verbringe zu viel Zeit am Handy.',
    'I spend too much time on my phone.',
  ),
  (
    2,
    'Technology',
    'Schalte es bitte aus und wieder ein.',
    'Please turn it off and on again.',
  ),
  (
    3,
    'Daily Life',
    'Ich würde heute Abend lieber zu Hause bleiben.',
    'I would rather stay at home tonight.',
  ),
  (
    3,
    'Daily Life',
    'Kleine Gewohnheiten prägen langfristig unser Leben.',
    'Small habits shape our lives in the long run.',
  ),
  (
    3,
    'Food',
    'Der Geschmack war viel feiner als erwartet.',
    'The flavour was much more delicate than expected.',
  ),
  (
    3,
    'Travel',
    'Wären wir früher losgefahren, hätten wir den Zug erreicht.',
    'Had we left earlier, we would have caught the train.',
  ),
  (
    3,
    'Travel',
    'Allein zu reisen hat mein Selbstvertrauen gestärkt.',
    'Travelling alone strengthened my self-confidence.',
  ),
  (
    3,
    'Feelings',
    'Ich konnte meine Enttäuschung kaum verbergen.',
    'I could hardly hide my disappointment.',
  ),
  (
    3,
    'Feelings',
    'Ehrliche Kritik ist unangenehm, aber wertvoll.',
    'Honest criticism is unpleasant but valuable.',
  ),
  (
    3,
    'Education',
    'Neugier ist wichtiger als reines Auswendiglernen.',
    'Curiosity is more important than pure memorising.',
  ),
  (
    3,
    'Education',
    'Die Erklärung war kurz und trotzdem gründlich.',
    'The explanation was short and yet thorough.',
  ),
  (
    3,
    'Nature',
    'Steigende Temperaturen gefährden viele empfindliche Ökosysteme.',
    'Rising temperatures endanger many fragile ecosystems.',
  ),
  (
    3,
    'Nature',
    'Umweltschutz erfordert Geduld und breite Unterstützung.',
    'Environmental protection requires patience and broad support.',
  ),
  (
    3,
    'Sports',
    'Trotz der Verletzung wollte sie nicht aufgeben.',
    'Despite the injury, she did not want to give up.',
  ),
  (
    3,
    'Work',
    'Qualität sollte wichtiger sein als kurzfristiges Wachstum.',
    'Quality should matter more than short-term growth.',
  ),
  (
    3,
    'Work',
    'Ihr Vorschlag war ehrgeizig, aber durchaus machbar.',
    'Her proposal was ambitious but quite feasible.',
  ),
  (
    3,
    'Work',
    'Klare Kommunikation verhindert die meisten Missverständnisse.',
    'Clear communication prevents most misunderstandings.',
  ),
  (
    3,
    'Technology',
    'Automatisierung wirft schwierige Fragen zur Arbeit auf.',
    'Automation raises difficult questions about work.',
  ),
  (
    3,
    'Technology',
    'Bequemlichkeit geht oft auf Kosten der Privatsphäre.',
    'Convenience often comes at the expense of privacy.',
  ),
  (
    3,
    'Science',
    'Die Daten stützen diese Schlussfolgerung nicht.',
    'The data do not support this conclusion.',
  ),
  (
    3,
    'Science',
    'Ein Zusammenhang beweist noch keine Ursache.',
    'A correlation does not yet prove a cause.',
  ),
  (
    3,
    'Science',
    'Alle unabhängigen Studien kamen zum selben Ergebnis.',
    'All independent studies reached the same result.',
  ),
];

/// Every sentence for [lang] ('en' or 'de').
List<ReadingText> readingTexts(String lang) => switch (lang) {
  'en' => [
    for (final (i, s) in _english.indexed)
      ReadingText(lang: 'en', level: s.$1, topic: s.$2, index: i, text: s.$3),
  ],
  'de' => [
    for (final (i, s) in _german.indexed)
      ReadingText(
        lang: 'de',
        level: s.$1,
        topic: s.$2,
        index: i,
        text: s.$3,
        translation: s.$4,
      ),
  ],
  _ => const [],
};

/// The sentence a [ReadingText.id] points to, or null.
ReadingText? readingById(String id) {
  final parts = id.split('|');
  if (parts.length != 3 || parts.first != 'read') return null;
  for (final r in readingTexts(parts[1])) {
    if (r.id == id) return r;
  }
  return null;
}
