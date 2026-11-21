import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/profile_store.dart';
import 'app_theme.dart';
import 'main_shell.dart';
import 'onboarding_screen.dart';

/// Shown on launch: letters rain from the top, the screen vibrates briefly,
/// then the app name pops in, then onboarding (first run) or Home.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _RainLetter {
  _RainLetter(math.Random r)
      : char = _glyphs[r.nextInt(_glyphs.length)],
        x = r.nextDouble(),
        delay = r.nextDouble() * 0.34,
        span = 0.18 + r.nextDouble() * 0.18,
        size = 16 + r.nextDouble() * 30,
        spin = (r.nextDouble() - 0.5) * 1.6,
        hueMix = r.nextDouble();

  static final _glyphs = [
    ...'ABCDEFGHIJKLMNOPQRSTUVWXYZabdeghilmnoprstuy'.split(''),
    'ñ', 'é', 'ü', 'あ', '你', 'अ', 'ق', 'Ж',
  ];

  final String char;
  final double x; // 0..1 across the screen
  final double delay; // start offset within the rain phase (timeline fraction)
  final double span; // fall duration (timeline fraction)
  final double size;
  final double spin;
  final double hueMix;
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  static const _total = Duration(milliseconds: 3800);
  static const _shakeStart = 0.52;
  static const _shakeEnd = 0.70;
  static const _revealStart = 0.66;

  late final AnimationController _c;
  late final List<_RainLetter> _letters;
  Timer? _timer;
  bool _buzzed = false;

  @override
  void initState() {
    super.initState();
    final rng = math.Random(11);
    _letters = List.generate(110, (_) => _RainLetter(rng));
    _c = AnimationController(vsync: this, duration: _total)
      ..addListener(_maybeBuzz)
      ..forward();
    _timer = Timer(const Duration(milliseconds: 4200), () {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        PageRouteBuilder<void>(
          pageBuilder: (_, _, _) => ProfileStore.instance.onboarded
              ? const MainShell()
              : const OnboardingScreen(),
          transitionsBuilder: (_, animation, _, child) =>
              FadeTransition(opacity: animation, child: child),
          transitionDuration: const Duration(milliseconds: 500),
        ),
      );
    });
  }

  void _maybeBuzz() {
    if (!_buzzed && _c.value >= _shakeStart) {
      _buzzed = true;
      HapticFeedback.mediumImpact();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _c.dispose();
    super.dispose();
  }

  /// Decaying horizontal/vertical jitter during the vibration window.
  Offset _shake(double t) {
    if (t < _shakeStart || t > _shakeEnd) return Offset.zero;
    final p = (t - _shakeStart) / (_shakeEnd - _shakeStart);
    final amp = 7 * (1 - p);
    return Offset(
      math.sin(p * math.pi * 14) * amp,
      math.cos(p * math.pi * 11) * amp * 0.5,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return GradientBackground(
      child: Scaffold(
        body: AnimatedBuilder(
          animation: _c,
          builder: (context, _) {
            final t = _c.value;
            final reveal = Curves.easeOutBack.transform(
              ((t - _revealStart) / (1 - _revealStart)).clamp(0.0, 1.0),
            );
            final revealFade = ((t - _revealStart) / 0.18).clamp(0.0, 1.0);
            final tagline = ((t - 0.85) / 0.15).clamp(0.0, 1.0);
            return Transform.translate(
              offset: _shake(t),
              child: LayoutBuilder(
                builder: (context, box) => Stack(
                  fit: StackFit.expand,
                  children: [
                    for (final l in _letters)
                      _buildLetter(l, t, box.biggest, scheme),
                    Center(
                      child: Opacity(
                        opacity: revealFade,
                        child: Transform.scale(
                          scale: 0.6 + 0.4 * reveal,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'BiLingo',
                                style: theme.textTheme.headlineLarge?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Opacity(
                                opacity: tagline,
                                child: Text(
                                  'Turn Scrolling To Learning',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildLetter(
      _RainLetter l, double t, Size area, ColorScheme scheme) {
    final p = ((t - l.delay) / l.span).clamp(0.0, 1.0);
    if (p <= 0 || p >= 1) return const SizedBox.shrink();
    // Fall with acceleration, fade in at the top and out near the bottom.
    final y = -60 + Curves.easeIn.transform(p) * (area.height + 120);
    final opacity = (p * 6).clamp(0.0, 1.0) * (1 - ((p - 0.8) / 0.2).clamp(0.0, 1.0));
    final color = Color.lerp(scheme.primary, scheme.tertiary, l.hueMix)!;
    return Positioned(
      left: l.x * (area.width - l.size),
      top: y,
      child: Opacity(
        opacity: opacity * 0.85,
        child: Transform.rotate(
          angle: l.spin * p,
          child: Text(
            l.char,
            style: TextStyle(
              fontSize: l.size,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ),
      ),
    );
  }
}
