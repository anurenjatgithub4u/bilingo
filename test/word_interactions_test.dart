import 'package:dmonly/services/word_interactions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final store = WordInteractions.instance;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await store.load();
  });

  test('like and save are independent per word', () async {
    await store.toggleLike('de|Fernweh');
    await store.toggleSave('en|keen');

    expect(store.stateOf('de|Fernweh').isLiked, isTrue);
    expect(store.stateOf('de|Fernweh').isSaved, isFalse);
    expect(store.stateOf('en|keen').isLiked, isFalse);
    expect(store.stateOf('en|keen').isSaved, isTrue);
    expect(store.stateOf('en|lucid').toJson(), {
      'wordId': 'en|lucid',
      'isLiked': false,
      'isSaved': false,
    });
  });

  test('toggling twice undoes, and saving twice keeps one bookmark', () async {
    await store.toggleLike('en|keen');
    await store.toggleLike('en|keen');
    expect(store.isLiked('en|keen'), isFalse);

    await store.setSaved('en|keen', true);
    await store.setSaved('en|keen', true);
    expect(store.savedIds, ['en|keen']);
  });

  test('state survives a restart', () async {
    await store.toggleLike('hi|घर');
    await store.toggleSave('de|Heimat');
    await store.toggleSave('de|Zeitgeist');

    await store.load();
    expect(store.isLiked('hi|घर'), isTrue);
    expect(store.savedIds, ['de|Zeitgeist', 'de|Heimat']);
  });

  test('cloud data is added to what is on the phone', () async {
    await store.toggleSave('en|keen');
    await store.mergeCloud({
      'likedWords': ['de|Fernweh'],
      'savedWords': ['en|keen', 'en|lucid'],
    });
    expect(store.isLiked('de|Fernweh'), isTrue);
    expect(store.savedIds.toSet(), {'en|keen', 'en|lucid'});
    expect(store.savedIds.length, 2);
  });

  test('listeners hear about a change straight away', () async {
    var calls = 0;
    void listener() => calls++;
    store.addListener(listener);
    addTearDown(() => store.removeListener(listener));
    final pending = store.toggleLike('en|keen');
    expect(calls, 1);
    await pending;
  });
}
