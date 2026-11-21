import 'package:dmonly/services/like_counts.dart';
import 'package:dmonly/services/word_interactions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final likes = LikeCounts.instance;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    likes.resetForTest();
    await likes.start();
    await WordInteractions.instance.load();
  });

  test('counts read like a feed', () {
    expect(LikeCounts.format(0), '0');
    expect(LikeCounts.format(999), '999');
    expect(LikeCounts.format(1000), '1K');
    expect(LikeCounts.format(1250), '1.3K');
    expect(LikeCounts.format(12400), '12K');
    expect(LikeCounts.format(1500000), '1.5M');
  });

  test('ids are stable, Firestore-safe and distinct', () {
    const key = 'code|What is the output?\nlet x = 5;|7';
    final id = LikeCounts.docId(key);
    expect(id, LikeCounts.docId(key));
    expect(id, matches(RegExp(r'^r[0-9a-f]{16}$')));
    expect(LikeCounts.docId('math|1/2|0.5'), isNot(contains('/')));
    expect(LikeCounts.docId('en|keen'), isNot(LikeCounts.docId('en|keem')));
  });

  test('a like shows at once and an unlike takes it back', () {
    expect(likes.countOf('en|keen', likedHere: false), isNull);
    likes.record('en|keen', true);
    expect(likes.countOf('en|keen', likedHere: true), 1);
    likes.record('en|keen', false);
    // Back to unknown, so the button says Like again.
    expect(likes.countOf('en|keen', likedHere: false), isNull);
  });

  test('liking in the app goes to the count', () async {
    await WordInteractions.instance.toggleLike('de|Heimat');
    expect(likes.countOf('de|Heimat', likedHere: true), 1);
    await WordInteractions.instance.toggleLike('de|Heimat');
    expect(likes.countOf('de|Heimat', likedHere: false), isNull);
    // Liking again only ever adds one, however often it is tapped.
    await WordInteractions.instance.setLiked('de|Heimat', true);
    await WordInteractions.instance.setLiked('de|Heimat', true);
    expect(likes.countOf('de|Heimat', likedHere: true), 1);
  });

  test('a like made offline is kept for later', () async {
    likes.record('en|brave', true);
    await Future<void>.delayed(Duration.zero);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('like_pending'), contains('en|brave'));
    // Liked then unliked before it was sent: nothing left to send.
    likes.record('en|brave', false);
    await Future<void>.delayed(Duration.zero);
    expect(prefs.getString('like_pending'), isNot(contains('en|brave')));
  });

  test('likes from before counts existed are sent once', () async {
    SharedPreferences.setMockInitialValues({});
    likes.resetForTest();
    await likes.start(earlierLikes: ['en|calm']);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('like_pending'), contains('en|calm'));
    expect(prefs.getBool('like_backfilled'), isTrue);
    likes.resetForTest();
    await prefs.remove('like_pending');
    await likes.start(earlierLikes: ['en|calm']);
    expect(prefs.getString('like_pending'), isNull);
  });
}
