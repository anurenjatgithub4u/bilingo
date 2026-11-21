import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/arrest_store.dart';
import '../services/profile_store.dart';
import '../services/progress_store.dart';
import '../services/word_service.dart';
import 'app_theme.dart';
import 'mascot.dart';

const _siren = Color(0xFFFF3B5C);
const _sirenBlue = Color(0xFF2F80FF);
const _night = Color(0xFF0B1020);
const _paper = Color(0xFFF4E4C1);
const _ink = Color(0xFF4A2F17);
const _gold = Color(0xFFF6CB4A);

/// Asks the home shell to show a tab (0 is the feed).
final shellTabRequest = ValueNotifier<int?>(null);

/// Runs Scroll Patrol: collects arrests from the background tracker, shows
/// the arrest screen for a fresh one, and puts up the evening Wanted poster.
class Patrol {
  Patrol._();

  static final Patrol instance = Patrol._();

  final _service = const WordService();
  bool _busy = false;

  bool get _police => ProfileStore.instance.mascot == MascotStyle.police;

  /// Brings in arrests made in the background.
  Future<void> collect() async {
    final store = ArrestStore.instance;
    await store.ensureLoaded();
    try {
      for (final (at, app, minutes) in await _service.takeArrests()) {
        store.book(
          offence: Offence.scrolling,
          at: at,
          app: app,
          minutes: minutes,
        );
      }
      final (warnings, heeded) = await _service.patrolCounts();
      store.setWarnings(warnings, heeded);
    } catch (_) {
      // No native side (tests).
    }
  }

  /// On opening the app or coming back to it. [fromNotification] is a tap
  /// on the arrest notification, which always shows the screen.
  Future<void> check(
    NavigatorState navigator, {
    bool fromNotification = false,
  }) async {
    if (_busy) return;
    _busy = true;
    try {
      await collect();
      final store = ArrestStore.instance;
      final arrest = fromNotification ? store.current : store.fresh;
      if (arrest != null && navigator.mounted) {
        store.markSeen(arrest);
        await navigator.push(
          MaterialPageRoute<void>(
            fullscreenDialog: true,
            builder: (_) => ArrestScreen(arrest: arrest),
          ),
        );
        return;
      }
      await ProgressStore.instance.ensureLoaded();
      final goal = ProfileStore.instance.dailyGoal;
      final answered = ProgressStore.instance.answeredToday;
      if (_police &&
          navigator.mounted &&
          store.shouldShowWanted(answered: answered, goal: goal)) {
        store.markWantedShown();
        await showDialog<void>(
          context: navigator.context,
          builder: (_) => WantedPoster(answered: answered, goal: goal),
        );
      }
    } finally {
      _busy = false;
    }
  }
}

/// "Busted!": what the learner was caught doing and the bail to pay.
class ArrestScreen extends StatefulWidget {
  const ArrestScreen({super.key, required this.arrest});

  final Arrest arrest;

  @override
  State<ArrestScreen> createState() => _ArrestScreenState();
}

class _ArrestScreenState extends State<ArrestScreen>
    with TickerProviderStateMixin {
  late final _lights = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );
  late final _stamp = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 500),
  );

  /// The cell bars: 0 up and open, 1 down and locked.
  late final _bars = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 650),
  );

  @override
  void initState() {
    super.initState();
    HapticFeedback.heavyImpact();
    ArrestStore.instance.addListener(_onStore);
    if (ArrestStore.instance.serving) {
      _bars.forward().whenComplete(() {
        if (mounted && _bars.value == 1) HapticFeedback.mediumImpact();
      });
    }
    Future.delayed(const Duration(milliseconds: 650), () {
      if (mounted) _stamp.forward();
    });
  }

  /// Bail paid while the screen is open: the bars lift.
  void _onStore() {
    if (!ArrestStore.instance.serving && _bars.value > 0) _bars.reverse();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Flashing lights only when the phone allows animation.
    if (MediaQuery.disableAnimationsOf(context)) {
      _lights.value = 0.5;
    } else if (!_lights.isAnimating) {
      _lights.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    ArrestStore.instance.removeListener(_onStore);
    _lights.dispose();
    _stamp.dispose();
    _bars.dispose();
    super.dispose();
  }

  void _payBail() {
    Navigator.of(context).pop();
    shellTabRequest.value = 0;
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.arrest;
    final unit = a.minutes == 1 ? 'minute' : 'minutes';
    final charge = a.offence == Offence.scrolling
        ? 'Kept scrolling ${a.app} after a warning: ${a.minutes} $unit'
        : 'Skipping study: daily goal not met';
    final name = ProfileStore.instance.name.trim();
    return Theme(
      data: buildTheme(Brightness.dark),
      child: Scaffold(
        backgroundColor: _night,
        body: Stack(
          children: [
            // Police lights washing in from the top corners.
            Positioned.fill(
              child: AnimatedBuilder(
                animation: _lights,
                builder: (context, _) =>
                    CustomPaint(painter: _LightsPainter(_lights.value)),
              ),
            ),
            SafeArea(
              child: ListenableBuilder(
                listenable: ArrestStore.instance,
                builder: (context, _) => ListView(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                  children: [
                    Align(
                      alignment: Alignment.centerRight,
                      child: IconButton(
                        tooltip: 'Close',
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ),
                    SizedBox(
                      height: 260,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              _Cell(bars: _bars, name: name),
                              Mascot(
                                size: 150,
                                mood: ArrestStore.instance.serving
                                    ? GhostMood.thinking
                                    : GhostMood.happy,
                                style: MascotStyle.police,
                              ),
                            ],
                          ),
                          Positioned(
                            bottom: 0,
                            child: ScaleTransition(
                              scale: CurvedAnimation(
                                parent: _stamp,
                                curve: Curves.elasticOut,
                              ),
                              child: _Stamp(
                                ArrestStore.instance.serving
                                    ? 'BUSTED!'
                                    : 'RELEASED',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      ArrestStore.instance.serving
                          ? 'You’re under arrest!'
                          : 'You’re free to go!',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 16),
                    _InfoCard(
                      icon: Icons.gavel_rounded,
                      color: _siren,
                      title: 'Charge',
                      body: charge,
                    ),
                    const SizedBox(height: 12),
                    _BailCard(store: ArrestStore.instance),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: _gold,
                        foregroundColor: Colors.black87,
                        minimumSize: const Size.fromHeight(54),
                      ),
                      onPressed: _payBail,
                      icon: const Icon(Icons.lock_open_rounded),
                      label: const Text(
                        'Pay bail now',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Later'),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'No XP or streak is ever taken away. Paying bail only '
                      'earns you more.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: Colors.white60),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
    ),
    child: Row(
      children: [
        Icon(icon, color: color, size: 28),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title.toUpperCase(),
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                body,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

/// The bail as a row of locks that open as reels are answered.
class _BailCard extends StatelessWidget {
  const _BailCard({required this.store});

  final ArrestStore store;

  @override
  Widget build(BuildContext context) {
    final total = math.max(store.bailTotal, 1);
    final paid = store.serving ? total - store.bailLeft : total;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.account_balance_rounded, color: _gold),
              const SizedBox(width: 10),
              const Text(
                'BAIL',
                style: TextStyle(
                  color: _gold,
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                  letterSpacing: 1,
                ),
              ),
              const Spacer(),
              Text(
                '+${store.serving ? store.bailReward : ArrestStore.bailXp} XP',
                style: const TextStyle(
                  color: Color(0xFFB7F34D),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            store.serving
                ? 'Answer ${store.bailLeft} more '
                      '${store.bailLeft == 1 ? 'reel' : 'reels'} to walk free'
                : 'Paid. You’re free to go!',
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              for (var i = 0; i < total; i++)
                Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: Icon(
                    i < paid ? Icons.lock_open_rounded : Icons.lock_rounded,
                    color: i < paid ? const Color(0xFFB7F34D) : Colors.white38,
                    size: 28,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Stamp extends StatelessWidget {
  const _Stamp(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Transform.rotate(
    angle: -0.14,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        border: Border.all(color: _siren, width: 4),
        borderRadius: BorderRadius.circular(10),
        color: _night.withValues(alpha: 0.6),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: _siren,
          fontSize: 34,
          fontWeight: FontWeight.w900,
          letterSpacing: 3,
        ),
      ),
    ),
  );
}

/// Red and blue glows that trade places, like a patrol car's lights.
class _LightsPainter extends CustomPainter {
  _LightsPainter(this.t);

  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    void glow(Offset c, Color color, double a) {
      final r = size.width * 0.9;
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..shader = RadialGradient(
            colors: [
              color.withValues(alpha: a),
              color.withValues(alpha: 0),
            ],
          ).createShader(Rect.fromCircle(center: c, radius: r)),
      );
    }

    glow(Offset(0, 0), _siren, 0.12 + 0.33 * t);
    glow(Offset(size.width, 0), _sirenBlue, 0.12 + 0.33 * (1 - t));
  }

  @override
  bool shouldRepaint(_LightsPainter old) => old.t != t;
}

/// A jail cell: the learner, in prison stripes, behind bars that drop in
/// as [bars] goes to 1 and lift as it goes back.
class _Cell extends StatelessWidget {
  const _Cell({required this.bars, required this.name});

  final Animation<double> bars;
  final String name;

  @override
  Widget build(BuildContext context) {
    final initial = name.isEmpty ? '?' : name.characters.first.toUpperCase();
    return Semantics(
      label: 'You, behind bars',
      excludeSemantics: true,
      child: Container(
        width: 160,
        height: 200,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: const Color(0xFF1B2233),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFF3A4458), width: 3),
        ),
        child: Stack(
          alignment: Alignment.bottomCenter,
          children: [
            // Bricks on the back wall.
            const Positioned.fill(child: CustomPaint(painter: _BrickPainter())),
            // The prisoner: a striped shirt and a worried face.
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 74,
                  height: 74,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    color: Color(0xFFFFD3B6),
                    shape: BoxShape.circle,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        initial,
                        style: const TextStyle(
                          color: Color(0xFF5A3A28),
                          fontWeight: FontWeight.w900,
                          fontSize: 26,
                          height: 1,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        '•  •',
                        style: TextStyle(
                          color: Color(0xFF2A1A12),
                          fontSize: 14,
                          height: 1,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                const SizedBox(
                  width: 110,
                  height: 62,
                  child: CustomPaint(painter: _StripesPainter()),
                ),
              ],
            ),
            // The bars, dropping from the top.
            Positioned.fill(
              child: AnimatedBuilder(
                animation: bars,
                builder: (context, _) => CustomPaint(
                  painter: _BarsPainter(
                    Curves.bounceOut.transform(bars.value.clamp(0.0, 1.0)),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BrickPainter extends CustomPainter {
  const _BrickPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = Colors.white.withValues(alpha: 0.05)
      ..strokeWidth = 1.5;
    const h = 18.0;
    const w = 36.0;
    for (var row = 0; row * h < size.height; row++) {
      final y = row * h;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
      final shift = row.isEven ? 0.0 : w / 2;
      for (var x = shift; x < size.width; x += w) {
        canvas.drawLine(Offset(x, y), Offset(x, y + h), line);
      }
    }
  }

  @override
  bool shouldRepaint(_BrickPainter old) => false;
}

/// Black and white prison stripes on a rounded shirt.
class _StripesPainter extends CustomPainter {
  const _StripesPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final shirt = RRect.fromRectAndCorners(
      Offset.zero & size,
      topLeft: const Radius.circular(40),
      topRight: const Radius.circular(40),
    );
    canvas.save();
    canvas.clipRRect(shirt);
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);
    final black = Paint()..color = const Color(0xFF15161B);
    for (var y = 6.0; y < size.height; y += 16) {
      canvas.drawRect(Rect.fromLTWH(0, y, size.width, 8), black);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_StripesPainter old) => false;
}

/// Steel bars and a crossbar, [drop] of the way down (0..1).
class _BarsPainter extends CustomPainter {
  _BarsPainter(this.drop);

  final double drop;

  @override
  void paint(Canvas canvas, Size size) {
    if (drop <= 0) return;
    final offset = -size.height * (1 - drop);
    const count = 5;
    final gap = size.width / (count + 1);
    final bar = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFF8D96A8), Color(0xFFE9EDF4), Color(0xFF8D96A8)],
      ).createShader(Rect.fromLTWH(0, 0, 10, 1));
    for (var i = 1; i <= count; i++) {
      final x = gap * i;
      canvas.save();
      canvas.translate(x - 5, offset);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(0, 0, 10, size.height),
          const Radius.circular(5),
        ),
        bar,
      );
      canvas.restore();
    }
    final cross = Paint()..color = const Color(0xFFB9C1CF);
    for (final y in [size.height * 0.22, size.height * 0.62]) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(0, y + offset, size.width, 9),
          const Radius.circular(4),
        ),
        cross,
      );
    }
  }

  @override
  bool shouldRepaint(_BarsPainter old) => old.drop != drop;
}

/// The evening poster for a missed daily goal: turn yourself in for XP.
class WantedPoster extends StatelessWidget {
  const WantedPoster({super.key, required this.answered, required this.goal});

  final int answered;
  final int goal;

  void _turnIn(BuildContext context) {
    final left = (goal - answered).clamp(1, ArrestStore.maxWantedBail);
    ArrestStore.instance.book(offence: Offence.goal, bail: left);
    Navigator.of(context).pop();
    shellTabRequest.value = 0;
  }

  @override
  Widget build(BuildContext context) {
    final name = ProfileStore.instance.name.trim();
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(28),
      child: Container(
        padding: const EdgeInsets.fromLTRB(22, 18, 22, 14),
        decoration: BoxDecoration(
          color: _paper,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: _ink.withValues(alpha: 0.6), width: 3),
          boxShadow: const [
            BoxShadow(
              color: Colors.black38,
              blurRadius: 18,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'WANTED',
              style: TextStyle(
                color: _ink,
                fontSize: 44,
                fontWeight: FontWeight.w900,
                letterSpacing: 6,
              ),
            ),
            Container(height: 2, color: _ink.withValues(alpha: 0.5)),
            const SizedBox(height: 10),
            const Mascot(
              size: 120,
              mood: GhostMood.wink,
              style: MascotStyle.police,
            ),
            Text(
              name.isEmpty ? 'YOU' : name.toUpperCase(),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: _ink,
                fontSize: 26,
                fontWeight: FontWeight.w900,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'For skipping study: $answered of $goal reels today',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _ink.withValues(alpha: 0.85),
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: _ink,
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                'REWARD: +${ArrestStore.wantedXp} XP FOR TURNING YOURSELF IN',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _paper,
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            const SizedBox(height: 14),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: _ink,
                foregroundColor: _paper,
                minimumSize: const Size.fromHeight(48),
              ),
              onPressed: () => _turnIn(context),
              child: const Text(
                'Turn myself in',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: _ink),
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Not today'),
            ),
          ],
        ),
      ),
    );
  }
}

/// A slim reminder over the feed while bail is being served.
class BailBanner extends StatelessWidget {
  const BailBanner({super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: ArrestStore.instance,
    builder: (context, _) {
      final store = ArrestStore.instance;
      if (!store.serving) return const SizedBox.shrink();
      final total = math.max(store.bailTotal, 1);
      final paid = total - store.bailLeft;
      return Semantics(
        label:
            'Bail: ${store.bailLeft} more reels to answer, '
            '${store.bailReward} XP when free',
        excludeSemantics: true,
        child: Container(
          margin: const EdgeInsets.fromLTRB(16, 6, 16, 0),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: _siren.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _siren.withValues(alpha: 0.4)),
          ),
          child: Row(
            children: [
              const Text('🚨', style: TextStyle(fontSize: 15)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Bail: answer ${store.bailLeft} more '
                  '${store.bailLeft == 1 ? 'reel' : 'reels'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              for (var i = 0; i < total; i++)
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Icon(
                    i < paid ? Icons.lock_open_rounded : Icons.lock_rounded,
                    size: 16,
                    color: i < paid ? const Color(0xFF2EB67D) : _siren,
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );
}

/// Bail paid: the officer lets the learner go, with their XP.
Future<void> showReleased(BuildContext context, int xp) {
  HapticFeedback.mediumImpact();
  return showDialog<void>(
    context: context,
    builder: (context) {
      final theme = Theme.of(context);
      return Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Mascot(
                size: 130,
                mood: GhostMood.happy,
                style: MascotStyle.police,
              ),
              Text(
                'Released!',
                style: theme.textTheme.displaySmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: const Color(0xFF2EB67D),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Bail paid. +$xp XP. Stay on patrol!',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 18),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Keep going'),
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// This week's arrests, for Your Time.
class CaseFileCard extends StatelessWidget {
  const CaseFileCard({super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([ArrestStore.instance, ProfileStore.instance]),
    builder: (context, _) {
      final store = ArrestStore.instance;
      final file = store.caseFile();
      final police = ProfileStore.instance.mascot == MascotStyle.police;
      if (!police && file.arrests == 0) return const SizedBox.shrink();
      final theme = Theme.of(context);
      final muted = theme.colorScheme.onSurfaceVariant;
      final recent = store.arrests.reversed.take(3).toList();
      Widget stat(String value, String label) => Expanded(
        child: Column(
          children: [
            Text(
              value,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w900,
              ),
            ),
            Text(
              label,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(color: muted),
            ),
          ],
        ),
      );
      return GlassCard(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.local_police_rounded, color: _siren),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Case file',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Text('7 days', style: theme.textTheme.bodySmall),
              ],
            ),
            const SizedBox(height: 14),
            if (file.arrests == 0)
              Text(
                'No arrests this week. The patrol is proud of you!',
                style: theme.textTheme.bodyMedium?.copyWith(color: muted),
              )
            else ...[
              Row(
                children: [
                  stat('${file.arrests}', 'Arrests'),
                  stat('${file.bailPaid}', 'Bail paid'),
                  stat('${file.longestMinutes}m', 'Longest scroll'),
                ],
              ),
              if (file.topApp != null) ...[
                const SizedBox(height: 10),
                Text(
                  'Caught most on ${file.topApp}',
                  style: theme.textTheme.bodySmall?.copyWith(color: muted),
                ),
              ],
              const SizedBox(height: 12),
              for (final a in recent)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Row(
                    children: [
                      Icon(
                        a.offence == Offence.goal
                            ? Icons.assignment_late_rounded
                            : Icons.phone_android_rounded,
                        size: 18,
                        color: muted,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          a.offence == Offence.goal
                              ? 'Daily goal missed'
                              : '${a.minutes}m on ${a.app}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        a.bailPaid ? 'Bail paid' : 'Pending',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: a.bailPaid ? const Color(0xFF2EB67D) : _siren,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ],
        ),
      );
    },
  );
}

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// "9 Nov, 7:30 pm".
String _when(DateTime d) {
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final m = d.minute.toString().padLeft(2, '0');
  return '${d.day} ${_months[d.month - 1]}, $h:$m ${d.hour < 12 ? 'am' : 'pm'}';
}

/// The learner's Scroll Patrol record for Profile: jail status, all-time
/// arrests and bail, warnings and how often they stopped in time. Tapping
/// it lists every arrest.
class PatrolRecordCard extends StatelessWidget {
  const PatrolRecordCard({super.key, this.onPayBail});

  /// Takes the learner to the feed to pay bail.
  final VoidCallback? onPayBail;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([ArrestStore.instance, ProfileStore.instance]),
    builder: (context, _) {
      final store = ArrestStore.instance;
      final police = ProfileStore.instance.mascot == MascotStyle.police;
      if (!police && store.totalArrests == 0) return const SizedBox.shrink();
      final theme = Theme.of(context);
      final muted = theme.colorScheme.onSurfaceVariant;
      final clean = store.daysClean;
      const free = Color(0xFF2EB67D);
      final (statusIcon, status, statusColor) = store.serving
          ? (
              Icons.lock_rounded,
              'In jail now · ${store.bailLeft} '
                  '${store.bailLeft == 1 ? 'reel' : 'reels'} to bail',
              _siren,
            )
          : clean == null
          ? (Icons.verified_rounded, 'Clean record', free)
          : (
              Icons.lock_open_rounded,
              clean == 0
                  ? 'Free · arrested today'
                  : 'Free · $clean ${clean == 1 ? 'day' : 'days'} clean',
              free,
            );
      Widget stat(String value, String label) => Expanded(
        child: Column(
          children: [
            Text(
              value,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w900,
              ),
            ),
            Text(
              label,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(color: muted),
            ),
          ],
        ),
      );
      return GlassCard(
        onTap: () => showArrestHistory(context),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.local_police_rounded, color: _siren),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Arrest record',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const Icon(Icons.chevron_right_rounded),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(statusIcon, size: 16, color: statusColor),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      status,
                      style: TextStyle(
                        color: statusColor,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                stat('${store.totalArrests}', 'Times in jail'),
                stat('${store.totalPaid}', 'Bail paid'),
                stat('${store.warnings}', 'Warnings'),
                stat('${store.heeded}', 'Stopped in time'),
              ],
            ),
            if (store.serving && onPayBail != null) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: _gold,
                    foregroundColor: Colors.black87,
                  ),
                  onPressed: onPayBail,
                  icon: const Icon(Icons.lock_open_rounded),
                  label: const Text('Pay bail'),
                ),
              ),
            ],
          ],
        ),
      );
    },
  );
}

/// Every arrest on record, newest first.
Future<void> showArrestHistory(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        builder: (context, controller) {
          final theme = Theme.of(context);
          final store = ArrestStore.instance;
          final list = store.arrests.reversed.toList();
          final muted = theme.colorScheme.onSurfaceVariant;
          const free = Color(0xFF2EB67D);
          final times = store.totalArrests == 1 ? 'time' : 'times';
          return ListView(
            controller: controller,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            children: [
              Text(
                'Arrest history',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${store.totalArrests} $times in jail · '
                '${store.heeded} of ${store.warnings} warnings heeded',
                style: theme.textTheme.bodyMedium?.copyWith(color: muted),
              ),
              const SizedBox(height: 12),
              if (list.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                    'No arrests yet. Keep it that way!',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyLarge?.copyWith(color: muted),
                  ),
                ),
              for (final a in list)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    backgroundColor: (a.bailPaid ? free : _siren).withValues(
                      alpha: 0.15,
                    ),
                    child: Icon(
                      a.offence == Offence.goal
                          ? Icons.assignment_late_rounded
                          : Icons.phone_android_rounded,
                      color: a.bailPaid ? free : _siren,
                    ),
                  ),
                  title: Text(
                    a.offence == Offence.goal
                        ? 'Daily goal missed'
                        : '${a.minutes} min on ${a.app}',
                  ),
                  subtitle: Text(_when(a.at)),
                  trailing: Text(
                    a.bailPaid ? 'Released' : 'In jail',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: a.bailPaid ? free : _siren,
                    ),
                  ),
                ),
              if (store.totalArrests > list.length)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Showing the latest ${list.length}.',
                    style: theme.textTheme.bodySmall?.copyWith(color: muted),
                  ),
                ),
            ],
          );
        },
      ),
    );
