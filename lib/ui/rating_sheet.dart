import 'package:flutter/material.dart';

import '../services/rating_service.dart';
import 'mascot.dart';

enum RatingTrigger {
  firstTenReels,
  dailyGoal,
  levelUp,
  bailPaid,
}

Future<void> showRatingSheet(
  BuildContext context, {
  required RatingTrigger trigger,
}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => RatingSheet(trigger: trigger),
    );

class RatingSheet extends StatelessWidget {
  const RatingSheet({super.key, required this.trigger});

  final RatingTrigger trigger;

  static const _gold = Color(0xFFFFB627);

  (String title, String subtitle, GhostMood mood) get _content => switch (trigger) {
        RatingTrigger.firstTenReels => (
            '10 Reels Completed! 🚀',
            'You’re off to a fantastic start! If you’re enjoying learning with '
                'BiLingo, a quick 5-star rating on Google Play helps us a lot.',
            GhostMood.love,
          ),
        RatingTrigger.dailyGoal => (
            'Daily Goal Smashed! 🎉',
            'Consistency is key, and you’re crushing it today! Would you take '
                'a moment to leave a review on Google Play?',
            GhostMood.happy,
          ),
        RatingTrigger.levelUp => (
            'Level Up! You’re on fire! 🔥',
            'Your dedication is paying off. If BiLingo is helping you learn, '
                'we’d love your 5-star support on Google Play!',
            GhostMood.wink,
          ),
        RatingTrigger.bailPaid => (
            'Freedom! Bail Paid! ✨',
            'Back to scrolling freedom with a sharper mind! Enjoying BiLingo’s '
                'fun approach? Please rate us on Google Play.',
            GhostMood.happy,
          ),
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final (title, subtitle, mood) = _content;

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Drag handle
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              Mascot(size: 110, mood: mood),
              const SizedBox(height: 10),
              // Five golden stars
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < 5; i++)
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 3),
                      child: Icon(Icons.star_rounded, color: _gold, size: 30),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                title,
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: muted,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 22),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: _gold,
                  foregroundColor: Colors.black87,
                  minimumSize: const Size.fromHeight(52),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                onPressed: () {
                  Navigator.of(context).pop();
                  RatingService.instance.markRated();
                },
                icon: const Icon(Icons.star_rounded, color: Colors.black87),
                label: const Text(
                  'Rate on Google Play',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  RatingService.instance.snooze();
                },
                child: const Text('Maybe later'),
              ),
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  RatingService.instance.optOut();
                },
                child: Text(
                  'Don’t ask again',
                  style: TextStyle(
                    fontSize: 12,
                    color: muted.withValues(alpha: 0.7),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
