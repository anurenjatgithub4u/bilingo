import 'package:flutter/material.dart';

import '../app_info.dart';
import '../services/rating_service.dart';
import '../services/word_service.dart';
import 'app_theme.dart';
import 'mascot.dart';

/// About BiLingo: what it does, how it treats your data, and ways to rate,
/// share, read the privacy policy or send feedback.
class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key, this.service = const WordService()});

  final WordService service;

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  String? _version;

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    try {
      final (name, code) = await widget.service.appVersion();
      if (mounted && name.isNotEmpty) {
        setState(() => _version = 'Version $name ($code)');
      }
    } catch (_) {
      // No native side (tests): no version pill.
    }
  }

  Future<void> _open(String url, {String? fallback}) async {
    var opened = false;
    try {
      opened = await widget.service.openUrl(url, fallback: fallback);
    } catch (_) {
      // Reported below.
    }
    if (!opened && mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Couldn’t open that. Please try again.'),
          ),
        );
    }
  }

  Future<void> _share() async {
    try {
      await widget.service.shareText(
        'I’m learning a new word every time I unlock my phone with '
        '$kAppName. Try it: $kPlayStoreUrl',
      );
    } catch (_) {
      // Nothing to share with in tests.
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return GradientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('About'),
          backgroundColor: Colors.transparent,
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
          children: [
            // Who we are.
            const Center(child: Mascot(size: 150, mood: GhostMood.happy)),
            Text(
              kAppName,
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              kTagline,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(color: muted),
            ),
            if (_version case final version?) ...[
              const SizedBox(height: 10),
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: kBrandBlue.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    version,
                    style: const TextStyle(
                      color: kBrandBlue,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
            const _Heading('What you can do'),
            const GlassCard(
              padding: EdgeInsets.symmetric(vertical: 6, horizontal: 14),
              child: Column(
                children: [
                  _Feature(
                    icon: Icons.lock_open_rounded,
                    color: Color(0xFF2EB67D),
                    title: 'A word every unlock',
                    text:
                        'English or German, with its meaning, right on your '
                        'lock screen.',
                  ),
                  _Feature(
                    icon: Icons.play_circle_fill_rounded,
                    color: kBrandBlue,
                    title: 'Learning reels',
                    text:
                        'Swipe through quizzes, puzzles and read-aloud for '
                        'languages, maths and coding, at your level.',
                  ),
                  _Feature(
                    icon: Icons.local_police_rounded,
                    color: Color(0xFFE5484D),
                    title: 'Scroll Stop',
                    text:
                        'A friendly warning when you scroll too long, and a '
                        'playful arrest if you keep going.',
                  ),
                  _Feature(
                    icon: Icons.hourglass_bottom_rounded,
                    color: Color(0xFF8E5CF7),
                    title: 'Your Time',
                    text:
                        'See where your screen time goes and how much you '
                        'win back.',
                    last: true,
                  ),
                ],
              ),
            ),
            const _Heading('Your data'),
            const GlassCard(
              padding: EdgeInsets.symmetric(vertical: 6, horizontal: 14),
              child: Column(
                children: [
                  _Feature(
                    icon: Icons.cloud_done_rounded,
                    color: kBrandBlue,
                    title: 'Progress',
                    text:
                        'Your levels, likes and settings are kept on your '
                        'phone and backed up to your account (Google '
                        'Firebase), so they come back on a new phone.',
                  ),
                  _Feature(
                    icon: Icons.phone_android_rounded,
                    color: Color(0xFF2EB67D),
                    title: 'Screen time',
                    text:
                        'Read with Android’s usage access and worked out on '
                        'your phone. Only the apps you choose to limit and '
                        'your limit are saved with your account.',
                  ),
                  _Feature(
                    icon: Icons.mic_rounded,
                    color: Color(0xFFFF9F1C),
                    title: 'Read aloud',
                    text:
                        'Uses your phone’s speech recognition, which may '
                        'send audio to Google to turn it into text.',
                  ),
                  _Feature(
                    icon: Icons.campaign_rounded,
                    color: Color(0xFF5B6B8C),
                    title: 'Ads',
                    text:
                        'Shown by Google AdMob, which may use your device’s '
                        'advertising ID.',
                    last: true,
                  ),
                ],
              ),
            ),
            const _Heading('More'),
            GlassCard(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                children: [
                  _Action(
                    icon: Icons.star_rounded,
                    color: const Color(0xFFFFB627),
                    title: 'Rate $kAppName',
                    onTap: () {
                      RatingService.instance.markRated();
                      _open(kPlayStoreAppUrl, fallback: kPlayStoreUrl);
                    },
                  ),
                  _Action(
                    icon: Icons.share_rounded,
                    color: kBrandBlue,
                    title: 'Share with a friend',
                    onTap: _share,
                  ),
                  if (kPrivacyPolicyUrl.isNotEmpty)
                    _Action(
                      icon: Icons.privacy_tip_rounded,
                      color: const Color(0xFF2EB67D),
                      title: 'Privacy policy',
                      onTap: () => _open(kPrivacyPolicyUrl),
                    ),
                  if (kSupportEmail.isNotEmpty)
                    _Action(
                      icon: Icons.mail_rounded,
                      color: const Color(0xFF8E5CF7),
                      title: 'Send feedback',
                      onTap: () => _open(
                        'mailto:$kSupportEmail?subject=$kAppName%20feedback',
                      ),
                    ),
                  _Action(
                    icon: Icons.description_rounded,
                    color: const Color(0xFF5B6B8C),
                    title: 'Open-source licences',
                    onTap: () => showLicensePage(
                      context: context,
                      applicationName: kAppName,
                      applicationVersion: _version,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Text(
              '© ${DateTime.now().year} $kAppName',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(color: muted),
            ),
          ],
        ),
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 28, 4, 10),
    child: Text(
      text,
      style: Theme.of(context).textTheme.titleLarge
          ?.copyWith(fontWeight: FontWeight.w800),
    ),
  );
}

/// An icon in a tinted square, a title and a line or two of text.
class _Feature extends StatelessWidget {
  const _Feature({
    required this.icon,
    required this.color,
    required this.title,
    required this.text,
    this.last = false,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String text;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        border: last
            ? null
            : Border(
                bottom: BorderSide(
                  color: theme.colorScheme.outlineVariant.withValues(
                    alpha: 0.5,
                  ),
                ),
              ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  text,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({
    required this.icon,
    required this.color,
    required this.title,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    onTap: onTap,
    leading: Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, color: color, size: 22),
    ),
    title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
    trailing: const Icon(Icons.chevron_right_rounded),
  );
}
