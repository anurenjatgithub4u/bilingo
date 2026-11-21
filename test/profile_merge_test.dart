import 'package:dmonly/services/profile_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final store = ProfileStore.instance;

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'name': '',
      'learned_words': ['en|apple', 'en|book'],
      'checkpoints': ['en:1'],
      'answered': 10,
      'correct': 7,
      'learn_streak': 2,
      'last_learn_day': 20261030,
    });
    await store.load();
  });

  test(
    'cloud progress is combined with this phone\'s, keeping the best',
    () async {
      await store.mergeCloud({
        'name': 'Asha',
        'progress': {
          'learnedWords': ['en|book', 'en|cat'],
          'checkpoints': ['en:2'],
          'quizAnswered': 30,
          'quizCorrect': 25,
          'streakCount': 5,
          'lastLearnDay': 20261031,
        },
      });
      expect(store.name, 'Asha');
      expect(store.isLearned('en|apple'), isTrue);
      expect(store.isLearned('en|cat'), isTrue);
      expect(store.checkpointPassed('en', 1), isTrue);
      expect(store.checkpointPassed('en', 2), isTrue);
      expect(store.accuracy, 83);
      expect(store.toCloud()['progress'], containsPair('streakCount', 5));
    },
  );

  test('older or smaller cloud progress changes nothing', () async {
    await store.setName('Ravi');
    await store.mergeCloud({
      'name': 'Someone else',
      'progress': {
        'learnedWords': ['en|apple'],
        'quizAnswered': 3,
        'quizCorrect': 3,
        'streakCount': 9,
        'lastLearnDay': 20260101,
      },
    });
    expect(store.name, 'Ravi');
    expect(store.accuracy, 70);
    expect(store.toCloud()['progress'], containsPair('streakCount', 2));
    expect((store.toCloud()['progress'] as Map)['learnedCount'], 2);
  });

  test('the profile written to the cloud has settings and progress', () {
    final cloud = store.toCloud();
    expect(cloud.keys, containsAll(['name', 'settings', 'progress']));
    expect((cloud['settings'] as Map)['levelName'], 'Beginner');
  });
}
