import 'package:dmonly/services/rating_service.dart';
import 'package:dmonly/ui/app_theme.dart';
import 'package:dmonly/ui/rating_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await RatingService.instance.load();
    RatingService.instance.resetForTest();
  });

  group('RatingService', () {
    test('does not prompt before 10 reels', () async {
      final s = RatingService.instance;
      expect(s.shouldPrompt(), isFalse);

      for (var i = 0; i < 9; i++) {
        await s.recordReelAnswered();
      }
      expect(s.totalReelsAnswered, 9);
      expect(s.shouldPrompt(), isFalse);

      await s.recordReelAnswered();
      expect(s.totalReelsAnswered, 10);
      expect(s.shouldPrompt(), isTrue);
    });

    test('snooze delays prompts for 14 days', () async {
      final s = RatingService.instance;
      for (var i = 0; i < 10; i++) {
        await s.recordReelAnswered();
      }
      expect(s.shouldPrompt(), isTrue);

      await s.snooze();
      expect(s.shouldPrompt(), isFalse);
    });

    test('markRated silences prompts permanently', () async {
      final s = RatingService.instance;
      for (var i = 0; i < 10; i++) {
        await s.recordReelAnswered();
      }
      expect(s.shouldPrompt(), isTrue);

      await s.markRated();
      expect(s.hasRated, isTrue);
      expect(s.shouldPrompt(), isFalse);
    });

    test('optOut silences prompts permanently', () async {
      final s = RatingService.instance;
      for (var i = 0; i < 10; i++) {
        await s.recordReelAnswered();
      }
      expect(s.shouldPrompt(), isTrue);

      await s.optOut();
      expect(s.dontAskAgain, isTrue);
      expect(s.shouldPrompt(), isFalse);
    });
  });

  group('RatingSheet UI', () {
    testWidgets('renders celebratory content and 5 stars for daily goal', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(Brightness.light),
          home: const Scaffold(
            body: RatingSheet(trigger: RatingTrigger.dailyGoal),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Daily Goal Smashed! 🎉'), findsOneWidget);
      expect(find.byIcon(Icons.star_rounded), findsNWidgets(6)); // 5 stars + 1 button icon
      expect(find.text('Rate on Google Play'), findsOneWidget);
      expect(find.text('Maybe later'), findsOneWidget);
      expect(find.text('Don’t ask again'), findsOneWidget);
    });

    testWidgets('renders first ten reels trigger correctly', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(Brightness.light),
          home: const Scaffold(
            body: RatingSheet(trigger: RatingTrigger.firstTenReels),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('10 Reels Completed! 🚀'), findsOneWidget);
      expect(find.text('Maybe later'), findsOneWidget);
    });
  });
}
