import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/profile_store.dart';
import 'app_theme.dart';

/// Faces the ghost can pull. Each has its own eyes, mouth and little extras
/// (hearts, a tear, floating z's, a question mark).
enum GhostMood {
  calm,
  happy,
  love,
  surprised,
  sad,
  sleepy,
  wink,
  thinking,

  /// A little uneasy: worried brows, a wavy mouth.
  concerned,

  /// Dramatic: huge eyes, big open mouth, a bead of sweat.
  shocked,

  /// Over the top: trembling, pale, gloom lines and sweat.
  worried,
}

/// The BiLingo character, Scroll Patrol: a pink ghost officer in a beanie
/// with a police badge, a navy uniform and a duty belt. It floats, sways,
/// blinks, glances around and is circled by twinkling sparkles; its hem
/// ripples, its beanie lags behind and its arms follow its mood (a salute
/// for a wink, a magnifying glass while thinking, a wave when tapped).
///
/// Set [mood] to show a particular face; leave it null and the ghost stays
/// calm, pulling a different face every few seconds. Faces change with a
/// quick blink. Tap it for a happy jump and wiggle. [listening] makes it look
/// down at the chat box; [talking] moves its mouth while it answers.
class Mascot extends StatefulWidget {
  const Mascot({
    super.key,
    this.size = 220,
    this.talking = false,
    this.listening = false,
    this.mood,
    this.still = false,
    this.style,
  });

  final double size;
  final bool talking;
  final bool listening;
  final GhostMood? mood;

  /// Centred, unmoving pose without sparkles or shadow, for rendering icons.
  final bool still;

  /// Draws this character whatever the profile says (e.g. in the picker).
  final MascotStyle? style;

  @override
  State<Mascot> createState() => _MascotState();
}

/// Seconds a face change takes (eyes squeeze shut, new face opens).
const _switchTime = 0.36;

/// Pseudo-random -1..1 for an integer seed, stable across frames.
double _rand(int seed) {
  final x = math.sin(seed * 12.9898 + 78.233) * 43758.5453;
  return (x - x.floorToDouble()) * 2 - 1;
}

const _idleMoods = [
  GhostMood.wink,
  GhostMood.love,
  GhostMood.surprised,
  GhostMood.thinking,
  GhostMood.happy,
  GhostMood.sleepy,
];

/// Idle routine: calm most of the time, then a short burst of another face.
/// Returns (from, to, progress) so the painter can blend the switch.
(GhostMood, GhostMood, double) _idleMood(double t) {
  const period = 7.5;
  const calmFor = 4.8;
  GhostMood pick(int k) => _idleMoods[((_rand(k) + 1) / 2 * _idleMoods.length)
      .floor()
      .clamp(0, _idleMoods.length - 1)];
  final k = (t / period).floor();
  final p = t - k * period;
  if (p < calmFor) {
    return (pick(k - 1), GhostMood.calm, (p / _switchTime).clamp(0.0, 1.0));
  }
  return (
    GhostMood.calm,
    pick(k),
    ((p - calmFor) / _switchTime).clamp(0.0, 1.0),
  );
}

class _MascotState extends State<Mascot> with TickerProviderStateMixin {
  static const _loopSeconds = 3600;
  static const _happyTime = 1.2;

  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(seconds: _loopSeconds),
  )..repeat();

  /// Pop-in when the mascot first appears.
  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..forward();

  /// Eases the gaze between wandering and looking down at the input.
  late final AnimationController _listen = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 400),
    value: widget.listening ? 1 : 0,
  );

  late final AnimationController _talk = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 250),
    value: widget.talking ? 1 : 0,
  );

  double _tapAt = -100;

  /// The face shown before the last [Mascot.mood] change, and when it changed.
  GhostMood _from = GhostMood.calm;
  double _moodAt = -100;

  double get _t => _c.value * _loopSeconds;

  (GhostMood, GhostMood, double) _moods(double t) {
    final mood = widget.mood;
    final since = t - _moodAt;
    if (mood == null) {
      final idle = _idleMood(t);
      // Just handed back to the idle routine: ease out of the face that was set.
      return since < _switchTime ? (_from, idle.$2, since / _switchTime) : idle;
    }
    return (_from, mood, (since / _switchTime).clamp(0.0, 1.0));
  }

  @override
  void didUpdateWidget(Mascot old) {
    super.didUpdateWidget(old);
    if (old.listening != widget.listening) {
      _listen.animateTo(widget.listening ? 1 : 0, curve: Curves.easeOutCubic);
    }
    if (old.talking != widget.talking) {
      _talk.animateTo(widget.talking ? 1 : 0);
    }
    if (old.mood != widget.mood) {
      _from = old.mood ?? _idleMood(_t).$2;
      _moodAt = _t;
    }
  }

  void _onTap() {
    HapticFeedback.lightImpact();
    _tapAt = _t;
  }

  @override
  void dispose() {
    _c.dispose();
    _intro.dispose();
    _listen.dispose();
    _talk.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _onTap,
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: Listenable.merge([
            _c,
            _intro,
            _listen,
            _talk,
            ProfileStore.instance,
          ]),
          builder: (context, _) {
            final t = _t;
            final tapAge = t >= _tapAt ? t - _tapAt : 100.0;
            // A tap always gets a big happy face, straight away.
            final (from, to, p) = tapAge < _happyTime
                ? (GhostMood.happy, GhostMood.happy, 1.0)
                : _moods(t);
            return CustomPaint(
              size: Size.square(widget.size),
              painter: _GhostPainter(
                t: t,
                tapAge: tapAge,
                intro: Curves.elasticOut.transform(_intro.value),
                listen: _listen.value,
                talk: _talk.value,
                from: from,
                to: to,
                moodT: p,
                still: widget.still,
                police:
                    (widget.style ?? ProfileStore.instance.mascot) ==
                    MascotStyle.police,
              ),
            );
          },
        ),
      ),
    );
  }
}

enum _Eye { oval, arc, closed, heart }

class _GhostPainter extends CustomPainter {
  _GhostPainter({
    required this.t,
    required this.tapAge,
    required this.intro,
    required this.listen,
    required this.talk,
    required this.from,
    required this.to,
    required this.moodT,
    this.still = false,
    this.police = true,
  });

  /// Seconds since the animation started.
  final double t;

  /// Seconds since the last tap (large when not recently tapped).
  final double tapAge;
  final double intro;
  final double listen;
  final double talk;

  /// Face change in progress: [from] blends into [to] as [moodT] goes 0..1.
  final GhostMood from;
  final GhostMood to;
  final double moodT;
  final bool still;

  /// The Scroll Patrol officer; false draws the original ghost.
  final bool police;

  static const _ink = Color(0xFF1F1A2E);
  static const _blush = Color(0xFFF2557E);
  static const _ghostBlush = Color(0xFFFF8A5C);
  static const _heart = Color(0xFFFF4D6D);
  static const _tear = Color(0xFF7CC6FF);
  static const _sparkle = [
    Color(0xFFFFC83D),
    Color(0xFFFF6B6B),
    Color(0xFF3DDC97),
    Color(0xFFB784FF),
    Color(0xFF4FC3F7),
    Color(0xFFFF9F43),
  ];

  bool get _swapping => from != to && moodT < 1;

  /// How much of [m] is showing, 0..1.
  double _w(GhostMood m) {
    if (!_swapping) return m == to ? 1 : 0;
    return (m == to ? moodT : 0) + (m == from ? 1 - moodT : 0);
  }

  /// The face whose eyes and mouth are drawn: the old one until halfway.
  GhostMood get _face => _swapping && moodT < 0.5 ? from : to;

  /// 0..1 jump height when tapped.
  double get _hop {
    const tapHop = 0.7;
    return tapAge < tapHop ? math.sin(math.pi * tapAge / tapHop) : 0.0;
  }

  /// Gentle up-and-down drift, -1..1; calmer while listening or sleepy.
  double get _float => still
      ? 0
      : math.sin(t * 1.7) * (1 - listen * 0.6) * (1 - _w(GhostMood.sleepy) * 0.5);

  /// Side-to-side lean in radians, plus a quick wiggle after a tap. A sleepy
  /// ghost droops its head to one side.
  double get _tilt {
    if (still) return 0;
    const wiggle = 0.9;
    final tap = tapAge < wiggle
        ? math.sin(tapAge / wiggle * math.pi * 4) * 0.16 * (1 - tapAge / wiggle)
        : 0.0;
    final droop = _w(GhostMood.sleepy) * (0.09 + 0.02 * math.sin(t * 0.9));
    // Shocked shivers a little; worried trembles.
    final shiver = math.sin(t * 38) *
        (0.012 * _w(GhostMood.shocked) + 0.025 * _w(GhostMood.worried));
    return math.sin(t * 1.1) * 0.045 * (1 - listen) + tap + droop + shiver;
  }

  /// 1 = eyes open, 0 = closed; a blink every few seconds, sometimes a double.
  double get _blink {
    if (still) return 1;
    const blink = 0.15;
    final p = t % 4.1;
    final second = (t / 4.1).floor() % 3 == 0 ? p - 0.28 : -1.0;
    double closed(double x) =>
        x >= 0 && x < blink ? 0.5 - 0.5 * math.cos(x / blink * 2 * math.pi) : 0;
    return 1 - math.max(closed(p), closed(second));
  }

  /// 0..1 mouth opening: steady chatter while talking, otherwise a short
  /// murmur now and then.
  double get _mouthOpen {
    if (still) return 0;
    final chatter =
        (0.5 - 0.5 * math.cos(t * 2 * math.pi * 3.1)) *
        (0.65 + 0.35 * math.sin(t * 7.3));
    const period = 8.0;
    const burst = 1.4;
    final p = t % period;
    final idle = p < burst
        ? math.sin(math.pi * p / burst) *
              (0.5 - 0.5 * math.cos(p * 2 * math.pi * 2.6)) *
              0.7
        : 0.0;
    return math.max(chatter * talk * 0.9, idle * (1 - talk) * (1 - listen));
  }

  /// Darting glances: hold a point, then flick quickly to the next one.
  /// Thinking looks up and away; sleepy looks down.
  Offset get _gaze {
    if (still) return Offset.zero;
    const hold = 1.7;
    final k = (t / hold).floor();
    final f = t / hold - k;
    Offset target(int i) => Offset(_rand(i), _rand(i + 9999) * 0.6);
    final e = Curves.easeOutCubic.transform((f / 0.1).clamp(0.0, 1.0));
    var g = Offset.lerp(target(k - 1), target(k), e)!;
    g = Offset.lerp(g, const Offset(0.8, -1), _w(GhostMood.thinking))!;
    g = Offset.lerp(g, const Offset(0, 0.4), _w(GhostMood.sleepy))!;
    return Offset.lerp(g, const Offset(0, 1), listen)!;
  }

  static const _pinkTop = Color(0xFFFFCAD8);
  static const _pinkMid = Color(0xFFFFAFC6);
  static const _pinkLow = Color(0xFFF792B1);
  static const _pinkShade = Color(0xFFE2729A);
  // Police cap matches the navy uniform.
  static const _beanieLight = Color(0xFF3D5FAD); // same as _navyLight
  static const _beanie = Color(0xFF2B4689);      // same as _navy
  static const _beanieDark = Color(0xFF1C3065);  // same as _navyDark
  static const _navyLight = Color(0xFF3D5FAD);
  static const _navy = Color(0xFF2B4689);
  static const _navyDark = Color(0xFF1C3065);
  static const _belt = Color(0xFF1C2230);
  static const _gold = Color(0xFFF6CB4A);
  static const _goldDark = Color(0xFFC58F1B);
  static const _steel = Color(0xFFC9CED8);

  /// Where the head's dome is centred, for a body centred on [c].
  static Offset _headOf(Offset c, double r) => c + Offset(0, -r * 0.38);

  @override
  void paint(Canvas canvas, Size size) =>
      police ? _paintPolice(canvas, size) : _paintGhost(canvas, size);

  /// Scroll Patrol: the pink officer.
  void _paintPolice(Canvas canvas, Size size) {
    final s = size.width;
    final r = s * 0.3 * intro.clamp(0.0, 1.3);
    if (r <= 0) return;

    final hop = _hop;
    final float = _float;
    final center = Offset(s / 2, s * 0.5 + float * s * 0.02 - hop * s * 0.09);

    // Shadow shrinks and fades as it rises. Gradients, not blurs: cheaper
    // to draw every frame.
    final lift = (hop + (float + 1) * 0.15).clamp(0.0, 1.0);
    if (!still) {
      final shadow = Rect.fromCenter(
        center: Offset(s / 2, s * 0.93),
        width: s * 0.5 * (1 - lift * 0.35),
        height: s * 0.07 * (1 - lift * 0.3),
      );
      _soft(
        canvas,
        shadow,
        _ink,
        0.24 * (1 - lift * 0.5) * intro.clamp(0.0, 1.0),
        from: 0.3,
      );
    }

    if (!still) _paintSparkles(canvas, center, r, front: false);

    // Surprise makes it jump up tall for a moment.
    final shock =
        _w(GhostMood.surprised) +
        1.4 * _w(GhostMood.shocked) +
        _w(GhostMood.worried);
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(_tilt);
    canvas.scale(1 - hop * 0.04 - shock * 0.03, 1 + hop * 0.06 + shock * 0.05);
    canvas.translate(-center.dx, -center.dy);

    final body = _body(center, r);
    final bounds = body.getBounds();

    // Soft glow so it still reads on dark backgrounds.
    _soft(
      canvas,
      bounds.inflate(r * 0.3),
      Colors.white,
      0.22 + 0.05 * math.sin(t * 2),
      from: 0.65,
    );

    canvas.drawPath(
      body,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_pinkTop, _pinkMid, _pinkLow],
          stops: [0.0, 0.55, 1.0],
        ).createShader(bounds),
    );

    canvas.save();
    canvas.clipPath(body);
    // Rounded, clay-like light: a shade down the right, a sheen top left.
    final shade = Rect.fromCenter(
      center: Offset(bounds.right - r * 0.05, center.dy + r * 0.1),
      width: r * 0.9,
      height: r * 2.6,
    );
    _soft(canvas, shade, _pinkShade, 0.75);
    final sheen = Rect.fromCenter(
      center: Offset(center.dx - r * 0.3, bounds.top + r * 0.75),
      width: r * 0.7,
      height: r * 0.55,
    );
    _soft(canvas, sheen, Colors.white, 0.5);
    _paintUniform(canvas, center, r, bounds);
    // The same shade over the uniform, so it sits on the round body.
    _soft(canvas, shade, Colors.black, 0.18);
    canvas.restore();

    canvas.drawPath(
      body,
      Paint()
        ..color = _pinkShade.withValues(alpha: 0.55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.03,
    );

    _paintHandcuffs(canvas, center, r);
    _paintBeanie(canvas, center, r);

    // The face sits between the beanie and the collar, a little smaller than
    // the old ghost's, so the same expressions fit.
    final face = _headOf(center, r) + Offset(0, r * 0.37);
    final fr = r * 0.92;
    _paintFace(canvas, face, fr);
    _paintExtras(canvas, face, fr);
    _paintArms(canvas, center, r);
    canvas.restore();

    if (!still) _paintSparkles(canvas, center, r, front: true);
    if (tapAge < 0.9) _paintBurst(canvas, center, r);
  }

  /// A tall rounded blob, wider at the bottom, with a soft three-lobed hem
  /// that ripples.
  Path _body(Offset c, double r) {
    final headR = r * 0.8;
    final hc = _headOf(c, r);
    final hemY = c.dy + r * 0.97;
    final flare = r * 0.94;

    final path = Path()
      ..moveTo(hc.dx - headR, hc.dy)
      ..arcTo(
        Rect.fromCircle(center: hc, radius: headR),
        math.pi,
        math.pi,
        false,
      )
      ..cubicTo(
        hc.dx + headR * 1.08,
        hc.dy + r * 0.75,
        hc.dx + flare * 1.02,
        hemY - r * 0.45,
        hc.dx + flare,
        hemY,
      );

    // Hem, right to left: three rounded lobes that each bob on their own.
    const n = 48;
    for (var i = 1; i < n; i++) {
      final u = i / n;
      final lobe = math.sin(u * math.pi * 3).abs();
      final depth = r * (0.13 + 0.04 * math.sin(t * 3.2 + u * 7));
      final sway =
          r * 0.03 * math.sin(t * 2.4 + u * 5) * math.sin(u * math.pi);
      path.lineTo(hc.dx + flare - u * flare * 2 + sway, hemY + lobe * depth);
    }

    return path
      ..lineTo(hc.dx - flare, hemY)
      ..cubicTo(
        hc.dx - flare * 1.02,
        hemY - r * 0.45,
        hc.dx - headR * 1.08,
        hc.dy + r * 0.75,
        hc.dx - headR,
        hc.dy,
      )
      ..close();
  }

  /// Navy shirt with a collar, buttons, a pocket and a badge, then the duty
  /// belt. Drawn clipped to the body.
  void _paintUniform(Canvas canvas, Offset c, double r, Rect b) {
    final top = c.dy + r * 0.44;
    final beltTop = c.dy + r * 0.72;
    final beltBottom = beltTop + r * 0.12;

    final shirt = Path()
      ..moveTo(b.left - r, top)
      ..lineTo(c.dx - r * 0.2, top)
      ..lineTo(c.dx, top + r * 0.17)
      ..lineTo(c.dx + r * 0.2, top)
      ..lineTo(b.right + r, top)
      ..lineTo(b.right + r, beltTop)
      ..lineTo(b.left - r, beltTop)
      ..close();
    canvas.drawPath(
      shirt,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: const [_navyLight, _navy, _navyDark],
          stops: const [0.0, 0.35, 1.0],
        ).createShader(Rect.fromLTRB(b.left, top, b.right, beltTop)),
    );

    // Collar: two lapels meeting at the neck.
    final lapel = Paint()
      ..color = _navyLight
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = r * 0.03;
    final edge = Paint()
      ..color = _navyDark
      ..style = PaintingStyle.stroke
      ..strokeWidth = r * 0.018
      ..strokeJoin = StrokeJoin.round;
    for (final side in [-1, 1]) {
      final flap = Path()
        ..moveTo(c.dx + side * r * 0.36, top - r * 0.03)
        ..lineTo(c.dx + side * r * 0.03, top + r * 0.18)
        ..lineTo(c.dx + side * r * 0.24, top + r * 0.21)
        ..close();
      canvas.drawPath(flap, lapel..style = PaintingStyle.fill);
      canvas.drawPath(flap, lapel..style = PaintingStyle.stroke);
      canvas.drawPath(flap, edge);
    }

    // Button line.
    canvas.drawLine(
      Offset(c.dx, top + r * 0.19),
      Offset(c.dx, beltTop),
      edge,
    );
    for (final y in [0.26, 0.34]) {
      canvas.drawCircle(
        Offset(c.dx + r * 0.035, top + r * y),
        r * 0.022,
        Paint()..color = _navyDark,
      );
    }

    // Pocket on one side, the badge on the other.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(c.dx - r * 0.34, top + r * 0.17),
          width: r * 0.22,
          height: r * 0.065,
        ),
        Radius.circular(r * 0.02),
      ),
      Paint()..color = _navyDark,
    );
    _badge(canvas, Offset(c.dx + r * 0.34, top + r * 0.17), r * 0.15);

    // Duty belt with pouches and a buckle.
    canvas.drawRect(
      Rect.fromLTRB(b.left, beltTop, b.right, beltBottom),
      Paint()..color = _belt,
    );
    canvas.drawLine(
      Offset(b.left, beltTop + r * 0.01),
      Offset(b.right, beltTop + r * 0.01),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.12)
        ..strokeWidth = r * 0.012,
    );
    for (final side in [-1, 1]) {
      final pouch = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          c.dx + side * r * 0.56 - r * 0.075,
          beltTop - r * 0.015,
          r * 0.15,
          r * 0.17,
        ),
        Radius.circular(r * 0.03),
      );
      canvas.drawRRect(pouch, Paint()..color = const Color(0xFF12161F));
      canvas.drawLine(
        Offset(pouch.left + r * 0.02, pouch.top + r * 0.06),
        Offset(pouch.right - r * 0.02, pouch.top + r * 0.06),
        Paint()
          ..color = Colors.white.withValues(alpha: 0.1)
          ..strokeWidth = r * 0.01,
      );
    }
    final buckle = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(c.dx, (beltTop + beltBottom) / 2),
        width: r * 0.13,
        height: r * 0.095,
      ),
      Radius.circular(r * 0.02),
    );
    canvas.drawRRect(buckle, Paint()..color = _steel);
    canvas.drawRRect(
      buckle.deflate(r * 0.022),
      Paint()..color = const Color(0xFF8D94A3),
    );
  }

  /// Two small cuffs hanging from the belt, swinging a little.
  void _paintHandcuffs(Canvas canvas, Offset c, double r) {
    final anchor = Offset(c.dx + r * 0.3, c.dy + r * 0.84);
    final swing = still ? 0.0 : math.sin(t * 2.1) * 0.18;
    final ring = Paint()
      ..color = _steel
      ..style = PaintingStyle.stroke
      ..strokeWidth = r * 0.024;
    canvas.save();
    canvas.translate(anchor.dx, anchor.dy);
    canvas.rotate(swing);
    canvas.drawLine(Offset.zero, Offset(0, r * 0.03), ring);
    canvas.drawCircle(Offset(-r * 0.045, r * 0.08), r * 0.05, ring);
    canvas.drawCircle(Offset(r * 0.06, r * 0.1), r * 0.05, ring);
    canvas.restore();
  }

  /// Police cap (peaked cap) with a navy crown, a dark brim and a police
  /// badge on the front band. It lags behind the body a little and bounces
  /// when tapped.
  void _paintBeanie(Canvas canvas, Offset c, double r) {
    final hc = _headOf(c, r);
    final headR = r * 0.8;
    final bandTop = hc.dy - r * 0.08;
    final bandBottom = hc.dy + r * 0.14;
    final w = headR * 1.08;
    final top = hc.dy - headR * 1.18;

    canvas.save();
    final pivot = Offset(hc.dx, bandBottom);
    final bounce = tapAge < 0.6
        ? math.sin(tapAge / 0.6 * math.pi * 3) * 0.07 * (1 - tapAge / 0.6)
        : 0.0;
    canvas.translate(pivot.dx, pivot.dy);
    canvas.rotate(still ? 0 : math.sin(t * 1.3) * 0.025 - _tilt * 0.25 + bounce);
    canvas.translate(-pivot.dx, -pivot.dy);

    // ── Crown: smooth rounded dome, same navy gradient as the uniform.
    final crown = Path()
      ..moveTo(hc.dx - w * 0.96, bandTop + r * 0.03)
      ..cubicTo(
        hc.dx - w * 0.98,
        top + r * 0.15,
        hc.dx - w * 0.45,
        top,
        hc.dx,
        top,
      )
      ..cubicTo(
        hc.dx + w * 0.45,
        top,
        hc.dx + w * 0.98,
        top + r * 0.15,
        hc.dx + w * 0.96,
        bandTop + r * 0.03,
      )
      ..close();
    final crownBox = crown.getBounds();
    canvas.drawPath(
      crown,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_beanieLight, _beanie, _beanieDark],
          stops: [0.0, 0.5, 1.0],
        ).createShader(crownBox),
    );
    // Subtle sheen on the top-left of the crown.
    _soft(
      canvas,
      Rect.fromCenter(
        center: Offset(hc.dx - w * 0.2, top + r * 0.22),
        width: w * 0.6,
        height: r * 0.3,
      ),
      Colors.white,
      0.14,
    );

    // ── Hat band: slightly darker strip around the base of the crown.
    final band = RRect.fromLTRBR(
      hc.dx - w,
      bandTop,
      hc.dx + w,
      bandBottom,
      Radius.circular(r * 0.10),
    );
    canvas.drawRRect(
      band,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_beanie, _beanieDark],
        ).createShader(band.outerRect),
    );
    // Thin gold trim line along the top of the band.
    canvas.drawLine(
      Offset(hc.dx - w + r * 0.05, bandTop + r * 0.012),
      Offset(hc.dx + w - r * 0.05, bandTop + r * 0.012),
      Paint()
        ..color = _gold.withValues(alpha: 0.80)
        ..strokeWidth = r * 0.018,
    );
    // Badge centred on the front band.
    _badge(canvas, Offset(hc.dx, (bandTop + bandBottom) / 2), r * 0.19);

    // ── Peak / brim: flat elliptical visor that sticks out in front.
    final brimY = bandBottom - r * 0.02;
    final brimPath = Path()
      ..moveTo(hc.dx - w * 0.72, brimY)
      ..cubicTo(
        hc.dx - w * 0.68, brimY + r * 0.14,
        hc.dx + w * 0.68, brimY + r * 0.14,
        hc.dx + w * 0.72, brimY,
      )
      ..lineTo(hc.dx + w * 0.72, brimY)
      ..lineTo(hc.dx - w * 0.72, brimY)
      ..close();
    canvas.drawPath(brimPath, Paint()..color = _beanieDark);
    // Thin bright edge on the brim for depth.
    canvas.drawLine(
      Offset(hc.dx - w * 0.72, brimY + r * 0.01),
      Offset(hc.dx + w * 0.72, brimY + r * 0.01),
      Paint()
        ..color = _beanieLight.withValues(alpha: 0.55)
        ..strokeWidth = r * 0.014,
    );

    canvas.restore();
  }

  /// Gold police shield, [h] tall, with a blue seal and a star.
  void _badge(Canvas canvas, Offset c, double h) {
    final w = h * 0.85;
    final shield = Path()
      ..moveTo(c.dx, c.dy - h * 0.5)
      ..quadraticBezierTo(
        c.dx + w * 0.28,
        c.dy - h * 0.36,
        c.dx + w * 0.5,
        c.dy - h * 0.42,
      )
      ..lineTo(c.dx + w * 0.5, c.dy)
      ..quadraticBezierTo(c.dx + w * 0.45, c.dy + h * 0.32, c.dx, c.dy + h * 0.5)
      ..quadraticBezierTo(c.dx - w * 0.45, c.dy + h * 0.32, c.dx - w * 0.5, c.dy)
      ..lineTo(c.dx - w * 0.5, c.dy - h * 0.42)
      ..quadraticBezierTo(
        c.dx - w * 0.28,
        c.dy - h * 0.36,
        c.dx,
        c.dy - h * 0.5,
      )
      ..close();
    canvas.drawPath(
      shield,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_gold, _goldDark],
        ).createShader(shield.getBounds()),
    );
    canvas.drawPath(
      shield,
      Paint()
        ..color = _goldDark
        ..style = PaintingStyle.stroke
        ..strokeWidth = h * 0.07
        ..strokeJoin = StrokeJoin.round,
    );
    final seal = c + Offset(0, -h * 0.02);
    canvas.drawCircle(seal, h * 0.22, Paint()..color = _navy);
    canvas.drawPath(_starPath(seal, h * 0.15), Paint()..color = _gold);
  }

  /// Five-point star centred on [c], [rad] to its tips.
  static Path _starPath(Offset c, double rad) {
    final path = Path();
    for (var i = 0; i < 10; i++) {
      final a = -math.pi / 2 + i * math.pi / 5;
      final d = i.isEven ? rad : rad * 0.45;
      final p = c + Offset(math.cos(a) * d, math.sin(a) * d);
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    return path..close();
  }

  static double _lerp(double a, double b, double t) => a + (b - a) * t;

  /// A soft-edged oval filling [rect], [color] at [alpha] in the middle,
  /// fading out from [from] (0..1) to the edge. Cheaper than a blur.
  static void _soft(
    Canvas canvas,
    Rect rect,
    Color color,
    double alpha, {
    double from = 0,
  }) {
    final rad = rect.width / 2;
    canvas.save();
    canvas.translate(rect.center.dx, rect.center.dy);
    canvas.scale(1, rect.height / rect.width);
    canvas.drawCircle(
      Offset.zero,
      rad,
      Paint()
        ..shader = RadialGradient(
          colors: [
            color.withValues(alpha: alpha),
            color.withValues(alpha: 0),
          ],
          stops: [from, 1],
        ).createShader(Rect.fromCircle(center: Offset.zero, radius: rad)),
    );
    canvas.restore();
  }

  /// One arm's angle away from hanging straight down (outwards is positive)
  /// and its length, for the current face.
  (double, double) _arm(int side) {
    var a = 0.7 + (still ? 0 : 0.06 * math.sin(t * 1.7 + side));
    var len = 1.0;
    final startled = (_w(GhostMood.surprised) +
            _w(GhostMood.shocked) +
            _w(GhostMood.worried))
        .clamp(0.0, 1.0);
    // Cheer, hands up by the cheeks, hanging, cupping the cheeks.
    a = _lerp(a, 2.5, _w(GhostMood.happy));
    a = _lerp(a, 2.95, startled);
    len = _lerp(len, 1.2, startled);
    a = _lerp(a, 0.12, _w(GhostMood.sad));
    a = _lerp(a, 0.25, _w(GhostMood.sleepy));
    a = _lerp(a, 3.3, _w(GhostMood.love));
    len = _lerp(len, 1.25, _w(GhostMood.love));
    if (side < 0) {
      // The magnifying glass goes up on this side.
      a = _lerp(a, 2.1, _w(GhostMood.thinking));
    } else {
      // A wink comes with a salute to the beanie.
      a = _lerp(a, 3.25, _w(GhostMood.wink));
      len = _lerp(len, 1.9, _w(GhostMood.wink));
      // A tap gets a wave.
      if (tapAge < 1.0) {
        final wave = math.min(1.0, (1 - tapAge) * 2);
        a = _lerp(a, 2.6 + 0.35 * math.sin(tapAge * 18), wave);
      }
    }
    return (a, len);
  }

  /// Short pink arms in navy sleeves with white gloves; the left one holds a
  /// magnifying glass while thinking.
  void _paintArms(Canvas canvas, Offset c, double r) {
    final think = _w(GhostMood.thinking);
    for (final side in [-1, 1]) {
      final (a, len) = _arm(side);
      final shoulder = Offset(c.dx + side * r * 0.8, c.dy + r * 0.5);
      final l = r * 0.4 * len;
      canvas.save();
      canvas.translate(shoulder.dx, shoulder.dy);
      canvas.rotate(-side * a);
      final arm = RRect.fromLTRBR(
        -r * 0.1,
        -r * 0.02,
        r * 0.1,
        l,
        Radius.circular(r * 0.1),
      );
      canvas.drawRRect(arm, Paint()..color = _pinkMid);
      canvas.drawRRect(
        arm,
        Paint()
          ..color = _pinkShade
          ..style = PaintingStyle.stroke
          ..strokeWidth = r * 0.025,
      );
      canvas.drawRRect(
        RRect.fromLTRBR(
          -r * 0.125,
          -r * 0.1,
          r * 0.125,
          r * 0.1,
          Radius.circular(r * 0.08),
        ),
        Paint()..color = _navy,
      );
      if (side < 0 && think > 0.01) _paintMagnifier(canvas, l, r, think);
      final hand = Offset(0, l);
      final glove = Rect.fromCircle(center: hand, radius: r * 0.125);
      canvas.drawCircle(
        hand,
        r * 0.125,
        Paint()
          ..shader = const RadialGradient(
            center: Alignment(-0.3, -0.4),
            colors: [Colors.white, Color(0xFFDDE1EA)],
          ).createShader(glove),
      );
      canvas.drawCircle(
        hand + Offset(-side * r * 0.1, -r * 0.03),
        r * 0.05,
        Paint()..color = Colors.white,
      );
      canvas.restore();
    }
  }

  /// A magnifying glass held at [l] along the arm, faded in by [alpha].
  void _paintMagnifier(Canvas canvas, double l, double r, double alpha) {
    final lens = Offset(0, l + r * 0.34);
    canvas.drawLine(
      Offset(0, l),
      Offset(0, l + r * 0.18),
      Paint()
        ..color = const Color(0xFF8A5A3B).withValues(alpha: alpha)
        ..strokeWidth = r * 0.06
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(
      lens,
      r * 0.16,
      Paint()..color = const Color(0xFFBFE6FF).withValues(alpha: 0.45 * alpha),
    );
    canvas.drawArc(
      Rect.fromCircle(center: lens, radius: r * 0.1),
      math.pi * 1.1,
      math.pi * 0.45,
      false,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.8 * alpha)
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.025
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(
      lens,
      r * 0.16,
      Paint()
        ..color = _steel.withValues(alpha: alpha)
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.05,
    );
  }

  /// The original ghost: white, outlined, with a dome head.
  void _paintGhost(Canvas canvas, Size size) {
    final s = size.width;
    final r = s * 0.3 * intro.clamp(0.0, 1.3);
    if (r <= 0) return;

    final hop = _hop;
    final float = _float;
    final center = Offset(s / 2, s * 0.46 + float * s * 0.022 - hop * s * 0.12);

    // Shadow shrinks and fades as the ghost rises.
    final lift = (hop + (float + 1) * 0.15).clamp(0.0, 1.0);
    if (!still) {
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(s / 2, s * 0.88),
          width: s * 0.4 * (1 - lift * 0.35),
          height: s * 0.06 * (1 - lift * 0.3),
        ),
        Paint()
          ..color = _ink.withValues(alpha: 0.18 * (1 - lift * 0.5) * intro.clamp(0.0, 1.0))
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, s * 0.02),
      );
    }

    if (!still) _paintSparkles(canvas, center, r, front: false);

    // Surprise makes it jump up tall for a moment.
    final shock = _w(GhostMood.surprised) +
        1.4 * _w(GhostMood.shocked) +
        _w(GhostMood.worried);
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(_tilt);
    canvas.scale(1 - hop * 0.04 - shock * 0.03, 1 + hop * 0.06 + shock * 0.05);
    canvas.translate(-center.dx, -center.dy);

    final body = _ghostBody(center, r);

    // Soft halo so the ghost still reads on dark backgrounds.
    canvas.drawPath(
      body,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.28 + 0.06 * math.sin(t * 2))
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.22),
    );

    final bounds = body.getBounds();
    canvas.drawPath(
      body,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFFFDF8), Color(0xFFF6F2EA), Color(0xFFD6E7EE)],
          stops: [0.0, 0.62, 1.0],
        ).createShader(bounds),
    );

    // Cool shade down the right side and along the hem for depth.
    canvas.save();
    canvas.clipPath(body);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(bounds.right, center.dy + r * 0.35),
        width: r * 0.55,
        height: r * 1.5,
      ),
      Paint()
        ..color = const Color(0xFFB9D3DE).withValues(alpha: 0.55)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.18),
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(center.dx, bounds.bottom),
        width: r * 2.2,
        height: r * 0.35,
      ),
      Paint()
        ..color = const Color(0xFFB9D3DE).withValues(alpha: 0.5)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.12),
    );
    canvas.restore();

    canvas.drawPath(
      body,
      Paint()
        ..color = _ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.075
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );

    final head = center + Offset(0, -r * 0.22);
    _paintFace(canvas, head, r);
    _paintExtras(canvas, head, r);
    canvas.restore();

    if (!still) _paintSparkles(canvas, center, r, front: true);
    if (tapAge < 0.9) _paintBurst(canvas, center, r);
  }

  /// Dome head, sides that flare out a little, and a scalloped hem that ripples.
  Path _ghostBody(Offset c, double r) {
    final headR = r * 0.78;
    final hc = c + Offset(0, -r * 0.22);
    final hemY = c.dy + r * 0.84;
    final flare = headR * 1.18;

    final path = Path()
      ..moveTo(hc.dx - headR, hc.dy)
      ..arcTo(Rect.fromCircle(center: hc, radius: headR), math.pi, math.pi, false)
      ..cubicTo(
        hc.dx + headR,
        hc.dy + r * 0.55,
        hc.dx + headR * 1.02,
        hemY - r * 0.2,
        hc.dx + flare,
        hemY,
      );

    // Hem, right to left: four rounded lobes that each bob on their own.
    const n = 56;
    for (var i = 1; i < n; i++) {
      final u = i / n;
      final lobe = math.sin(u * math.pi * 4).abs();
      final depth = r * (0.15 + 0.045 * math.sin(t * 3.2 + u * 7));
      final sway = r * 0.035 * math.sin(t * 2.4 + u * 5) * math.sin(u * math.pi);
      path.lineTo(hc.dx + flare - u * flare * 2 + sway, hemY + lobe * depth);
    }

    return path
      ..lineTo(hc.dx - flare, hemY)
      ..cubicTo(
        hc.dx - headR * 1.02,
        hemY - r * 0.2,
        hc.dx - headR,
        hc.dy + r * 0.55,
        hc.dx - headR,
        hc.dy,
      )
      ..close();
  }

  /// Sparkles on a tilted orbit: the back half is drawn behind the body.
  void _paintSparkles(Canvas canvas, Offset c, double r, {required bool front}) {
    const n = 9;
    // Sleepy dims them; happy and love make them brighter.
    final glow = (1 - _w(GhostMood.sleepy) * 0.7) *
        (1 + 0.3 * (_w(GhostMood.happy) + _w(GhostMood.love)));
    for (var i = 0; i < n; i++) {
      final a = i * 2 * math.pi / n + t * 0.45;
      final depth = math.sin(a);
      if ((depth > 0) != front) continue;
      // In front, keep to the sides so sparkles never cross the face.
      if (front && math.cos(a).abs() < 0.6) continue;
      final p = c + Offset(math.cos(a) * r * 1.45, depth * r * 0.42 - r * 0.1);
      final twinkle = 0.5 + 0.5 * math.sin(t * 3.1 + i * 2.3);
      final scale = 0.75 + 0.25 * depth;
      final len = r * (0.06 + 0.07 * twinkle) * scale;
      final color = _sparkle[i % _sparkle.length].withValues(
        alpha: ((0.45 + 0.55 * twinkle) * (front ? 1 : 0.6) * glow).clamp(0.0, 1.0),
      );
      if (i.isEven) {
        _star(canvas, p, len, color, t * 0.8 + i);
      } else {
        canvas.drawCircle(p, len * 0.38, Paint()..color = color);
      }
    }
  }

  /// Four-point twinkle star.
  void _star(Canvas canvas, Offset p, double l, Color color, double spin) {
    final w = l * 0.24;
    final path = Path()
      ..moveTo(0, -l)
      ..quadraticBezierTo(w * 0.3, -w * 0.3, l, 0)
      ..quadraticBezierTo(w * 0.3, w * 0.3, 0, l)
      ..quadraticBezierTo(-w * 0.3, w * 0.3, -l, 0)
      ..quadraticBezierTo(-w * 0.3, -w * 0.3, 0, -l)
      ..close();
    canvas.save();
    canvas.translate(p.dx, p.dy);
    canvas.rotate(math.sin(spin) * 0.4);
    canvas.drawPath(path, Paint()..color = color);
    canvas.restore();
  }

  /// Confetti that pops outwards when tapped.
  void _paintBurst(Canvas canvas, Offset c, double r) {
    final p = Curves.easeOutCubic.transform(tapAge / 0.9);
    const n = 12;
    for (var i = 0; i < n; i++) {
      final a = i * 2 * math.pi / n + 0.3;
      final d = r * (1.1 + p * 0.9);
      final pos = c + Offset(math.cos(a), math.sin(a)) * d + Offset(0, p * p * r * 0.4);
      _star(
        canvas,
        pos,
        r * 0.1 * (1 - p),
        _sparkle[i % _sparkle.length].withValues(alpha: 1 - p),
        a + p * 4,
      );
    }
  }

  /// Heart centred on [c], [s] across roughly 2s.
  static Path _heartPath(Offset c, double s) => Path()
    ..moveTo(c.dx, c.dy + s * 0.8)
    ..cubicTo(c.dx - s * 1.25, c.dy, c.dx - s * 0.7, c.dy - s * 1.0, c.dx, c.dy - s * 0.35)
    ..cubicTo(c.dx + s * 0.7, c.dy - s * 1.0, c.dx + s * 1.25, c.dy, c.dx, c.dy + s * 0.8)
    ..close();

  _Eye _eyeFor(GhostMood mood, int side) => switch (mood) {
    GhostMood.happy => _Eye.arc,
    GhostMood.love => _Eye.heart,
    GhostMood.sleepy => _Eye.closed,
    GhostMood.wink => side > 0 ? _Eye.arc : _Eye.oval,
    _ => _Eye.oval,
  };

  /// Face centred on the head's [head] point.
  void _paintFace(Canvas canvas, Offset head, double r) {
    final gaze = _gaze;
    // The whole face shifts a little with the gaze, so the head seems to turn.
    final c = head + Offset(gaze.dx * r * 0.08, gaze.dy * r * 0.06);
    final face = _face;
    // Mid-change the eyes squeeze shut and the mouth shrinks, then the new face opens.
    final swapOpen = _swapping ? 1 - math.sin(math.pi * moodT) : 1.0;
    final mouthScale = _swapping ? math.cos(math.pi * moodT).abs() : 1.0;
    final ink = Paint()..color = _ink;
    final stroke = Paint()
      ..color = _ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = r * 0.06
      ..strokeCap = StrokeCap.round;

    // Cheeks: rosier when happy or in love, pale when sad.
    final rosy = _w(GhostMood.happy) + _w(GhostMood.love) + _w(GhostMood.wink);
    final pale = _w(GhostMood.sad) + 0.3 * _w(GhostMood.concerned) + 0.7 * _w(GhostMood.worried);
    final blushAlpha =
        (police ? 0.55 + 0.25 * rosy - 0.35 * pale : 0.8 + 0.2 * rosy - 0.45 * pale)
            .clamp(0.0, 1.0);
    final blushGrow = 1 + 0.25 * _w(GhostMood.love);
    for (final side in [-1, 1]) {
      canvas.drawOval(
        Rect.fromCenter(
          center: c + Offset(side * r * 0.47, r * 0.34),
          width: r * 0.22 * blushGrow,
          height: r * 0.12 * blushGrow,
        ),
        Paint()
          ..color = (police ? _blush : _ghostBlush).withValues(
            alpha: blushAlpha,
          ),
      );
    }

    _paintBrows(canvas, c, r);

    // Eyes
    final eyeScale = (1 + 0.08 * listen) *
        (1 +
            0.22 * _w(GhostMood.surprised) +
            0.34 * _w(GhostMood.shocked) +
            0.4 * _w(GhostMood.worried) -
            0.06 * _w(GhostMood.sad) -
            0.04 * _w(GhostMood.concerned));
    for (final side in [-1, 1]) {
      final eye = c + Offset(side * r * 0.27, r * 0.08) + gaze * (r * 0.05);
      switch (_eyeFor(face, side)) {
        case _Eye.oval:
          final open = _blink * swapOpen;
          final h = math.max(r * 0.03, r * 0.3 * open * eyeScale);
          canvas.drawOval(
            Rect.fromCenter(center: eye, width: r * 0.22 * eyeScale, height: h),
            ink,
          );
          if (open > 0.5) {
            // Sad gets big glossy puppy-eye highlights.
            final gloss = 1 + 0.45 * _w(GhostMood.sad);
            canvas.drawCircle(
              eye + Offset(r * 0.035, -h * 0.2),
              r * 0.055 * gloss,
              Paint()..color = Colors.white,
            );
            canvas.drawCircle(
              eye + Offset(-r * 0.03, h * 0.22),
              r * 0.02 * gloss,
              Paint()..color = Colors.white.withValues(alpha: 0.8),
            );
          }
        case _Eye.arc:
          // ^ squint
          final w = r * 0.1;
          final lift = w * 1.5 * swapOpen;
          canvas.drawPath(
            Path()
              ..moveTo(eye.dx - w, eye.dy + w * 0.4)
              ..quadraticBezierTo(eye.dx, eye.dy + w * 0.4 - lift, eye.dx + w, eye.dy + w * 0.4),
            stroke,
          );
        case _Eye.closed:
          // Sleepy lids: a soft downward curve.
          final w = r * 0.1;
          final sag = w * 0.7 * swapOpen;
          canvas.drawPath(
            Path()
              ..moveTo(eye.dx - w, eye.dy)
              ..quadraticBezierTo(eye.dx, eye.dy + sag, eye.dx + w, eye.dy),
            stroke,
          );
        case _Eye.heart:
          final beat = 1 + 0.12 * math.pow(math.sin(t * 5).abs(), 4);
          canvas.save();
          canvas.translate(eye.dx, eye.dy);
          canvas.scale(beat, beat * math.max(0.08, swapOpen));
          canvas.drawPath(_heartPath(Offset.zero, r * 0.13), Paint()..color = _heart);
          canvas.drawCircle(
            Offset(-r * 0.05, -r * 0.05),
            r * 0.025,
            Paint()..color = Colors.white.withValues(alpha: 0.85),
          );
          canvas.restore();
      }
    }

    // Mouth
    final o = _mouthOpen;
    final m = c + Offset(gaze.dx * r * 0.03, r * 0.4);
    canvas.save();
    canvas.translate(m.dx, m.dy);
    canvas.scale(math.max(0.01, mouthScale));
    switch (face) {
      case GhostMood.calm:
        police
            ? _lensMouth(canvas, r * 0.09, r * 0.07, o * 0.5, r, stroke)
            : _oMouth(canvas, r * (0.11 + 0.05 * o), r * (0.17 + 0.1 * o));
      case GhostMood.surprised:
        _oMouth(canvas, r * (0.16 + 0.04 * o), r * (0.25 + 0.08 * o));
      case GhostMood.shocked:
        _oMouth(canvas, r * (0.2 + 0.03 * o), r * (0.34 + 0.06 * o));
      case GhostMood.concerned:
        // Small uneasy wave.
        final w = r * 0.09;
        canvas.drawPath(
          Path()
            ..moveTo(-w, r * 0.02)
            ..cubicTo(-w / 3, -r * 0.04, w / 3, r * 0.06, w, -r * 0.01),
          stroke,
        );
      case GhostMood.worried:
        // Wide, trembling, open frown.
        canvas.translate(0, r * 0.03 + r * 0.01 * math.sin(t * 30));
        _lensMouth(canvas, r * 0.14, -r * 0.1, 0.45 + 0.15 * o, r, stroke);
      case GhostMood.sleepy:
        final breathe = 0.5 + 0.5 * math.sin(t * 1.6);
        _oMouth(canvas, r * (0.06 + 0.02 * breathe), r * (0.07 + 0.04 * breathe + 0.08 * o));
      case GhostMood.happy:
        // Big open grin with a tongue.
        final w = r * 0.14;
        final depth = r * (0.18 + 0.08 * o);
        final grin = Path()
          ..moveTo(-w, -r * 0.03)
          ..quadraticBezierTo(0, r * 0.01, w, -r * 0.03)
          ..cubicTo(w * 0.9, depth, -w * 0.9, depth, -w, -r * 0.03)
          ..close();
        canvas.drawPath(grin, ink);
        canvas.save();
        canvas.clipPath(grin);
        canvas.drawOval(
          Rect.fromCenter(center: Offset(0, depth * 0.78), width: w * 1.2, height: depth * 0.6),
          Paint()..color = const Color(0xFFFF7A9C),
        );
        canvas.restore();
      case GhostMood.love:
      case GhostMood.wink:
        _lensMouth(canvas, r * 0.12, r * 0.1, o, r, stroke);
      case GhostMood.sad:
        // Wobbly frown.
        final wobble = r * 0.012 * math.sin(t * 9);
        canvas.translate(0, r * 0.04 + wobble);
        _lensMouth(canvas, r * 0.11, -r * 0.09, o * 0.6, r, stroke);
      case GhostMood.thinking:
        // Mouth pulled to one side: a squiggle, or a small "o" while answering.
        canvas.translate(r * 0.07, 0);
        if (o > 0.15) {
          _oMouth(canvas, r * 0.08, r * (0.06 + 0.12 * o));
        } else {
          final w = r * 0.08;
          canvas.drawPath(
            Path()
              ..moveTo(-w, r * 0.01)
              ..cubicTo(-w / 3, -r * 0.05, w / 3, r * 0.05, w, -r * 0.01),
            stroke,
          );
        }
    }
    canvas.restore();
  }

  void _oMouth(Canvas canvas, double w, double h) => canvas.drawOval(
    Rect.fromCenter(center: Offset.zero, width: w, height: h),
    Paint()..color = _ink,
  );

  /// A curved line (smile when [curve] > 0, frown when < 0) that opens into a
  /// filled bowl below it as [open] rises.
  void _lensMouth(Canvas canvas, double w, double curve, double open, double r, Paint stroke) {
    final line = Path()
      ..moveTo(-w, 0)
      ..quadraticBezierTo(0, curve, w, 0);
    if (open > 0.02) {
      final low = math.max(curve, 0.0) + open * r * 0.32;
      canvas.drawPath(
        Path()
          ..moveTo(-w, 0)
          ..quadraticBezierTo(0, curve, w, 0)
          ..cubicTo(w * 0.9, low, -w * 0.9, low, -w, 0)
          ..close(),
        Paint()..color = _ink,
      );
    }
    canvas.drawPath(line, stroke);
  }

  /// Brows only appear for the faces that need them, fading with the face.
  void _paintBrows(Canvas canvas, Offset c, double r) {
    final sad = _w(GhostMood.sad) + 0.75 * _w(GhostMood.concerned) + _w(GhostMood.worried);
    final shock = _w(GhostMood.surprised) + _w(GhostMood.shocked);
    final think = _w(GhostMood.thinking);
    final steady = police ? (1 - sad - shock - think).clamp(0.0, 1.0) : 0.0;
    Paint brow(double a) => Paint()
      ..color = _ink.withValues(alpha: a.clamp(0.0, 1.0))
      ..style = PaintingStyle.stroke
      ..strokeWidth = r * 0.065
      ..strokeCap = StrokeCap.round;
    for (final side in [-1, 1]) {
      final x = c.dx + side * r * 0.27;
      final y = c.dy + r * 0.08 - r * 0.24;
      // An officer's brows: short, thick, inner ends a touch lower.
      if (steady > 0) {
        canvas.drawLine(
          Offset(x - side * r * 0.075, y + r * 0.02),
          Offset(x + side * r * 0.075, y - r * 0.015),
          brow(steady),
        );
      }
      // Sad: inner ends tilt up.
      if (sad > 0) {
        canvas.drawLine(
          Offset(x + side * r * 0.1, y + r * 0.03),
          Offset(x - side * r * 0.08, y - r * 0.05),
          brow(sad),
        );
      }
      // Surprised: both arch up high. Thinking: just the right one.
      final arch = shock + (side > 0 ? think : 0);
      if (arch > 0) {
        final ay = y - r * 0.07;
        canvas.drawPath(
          Path()
            ..moveTo(x - r * 0.09, ay + r * 0.02)
            ..quadraticBezierTo(x, ay - r * 0.06, x + r * 0.09, ay + r * 0.02),
          brow(arch),
        );
      }
      // Thinking: the left one sits low and flat.
      if (think > 0 && side < 0) {
        canvas.drawLine(
          Offset(x - r * 0.08, y + r * 0.02),
          Offset(x + r * 0.08, y + r * 0.03),
          brow(think),
        );
      }
    }
  }

  /// Floating hearts, a tear, z's or a question mark, depending on the face.
  void _paintExtras(Canvas canvas, Offset head, double r) {
    final love = _w(GhostMood.love);
    if (love > 0.01) {
      for (var i = 0; i < 3; i++) {
        final p = (t * 0.55 + i / 3) % 1;
        final side = i.isEven ? 1 : -1;
        final pos = head +
            Offset(side * r * (0.75 + 0.1 * math.sin(t * 2 + i)), -r * 0.5 - p * r * 0.9);
        canvas.drawPath(
          _heartPath(pos, r * (0.06 + 0.04 * p)),
          Paint()..color = _heart.withValues(alpha: love * math.sin(math.pi * p)),
        );
      }
    }

    final sad = _w(GhostMood.sad);
    if (sad > 0.01 && _face == GhostMood.sad) {
      // A tear wells up under the left eye and rolls down the cheek.
      final p = (t * 0.6) % 1;
      final start = head + Offset(-r * 0.36, r * 0.2);
      final pos = start + Offset(0, Curves.easeIn.transform(p) * r * 0.4);
      final size = r * 0.05 * math.min(1.0, p * 4);
      canvas.drawPath(
        Path()
          ..moveTo(pos.dx, pos.dy - size * 1.8)
          ..quadraticBezierTo(pos.dx + size * 1.1, pos.dy - size * 0.2, pos.dx, pos.dy + size)
          ..quadraticBezierTo(pos.dx - size * 1.1, pos.dy - size * 0.2, pos.dx, pos.dy - size * 1.8)
          ..close(),
        Paint()..color = _tear.withValues(alpha: sad * (1 - p * 0.6)),
      );
    }

    // A bead of sweat slides down the side of the head.
    final sweat = _w(GhostMood.shocked) + _w(GhostMood.worried);
    if (sweat > 0.01) {
      for (final (i, side) in [(0, 1), if (_w(GhostMood.worried) > 0.5) (1, -1)]) {
        final p = (t * 0.7 + i * 0.5) % 1;
        final pos = head + Offset(side * r * 0.72, -r * 0.3 + p * r * 0.35);
        final size = r * 0.07;
        canvas.drawPath(
          Path()
            ..moveTo(pos.dx, pos.dy - size * 1.8)
            ..quadraticBezierTo(pos.dx + size * 1.1, pos.dy - size * 0.2, pos.dx, pos.dy + size)
            ..quadraticBezierTo(pos.dx - size * 1.1, pos.dy - size * 0.2, pos.dx, pos.dy - size * 1.8)
            ..close(),
          Paint()..color = _tear.withValues(alpha: sweat.clamp(0.0, 1.0) * (1 - p * 0.7)),
        );
      }
    }

    // Worried: gloom lines across the forehead.
    final gloom = _w(GhostMood.worried);
    if (gloom > 0.01) {
      final paint = Paint()
        ..color = const Color(0xFF6B8CFF).withValues(alpha: 0.7 * gloom)
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.035
        ..strokeCap = StrokeCap.round;
      for (var i = -2; i <= 2; i++) {
        final x = head.dx + i * r * 0.11;
        final top = head.dy - r * 0.62 + i.abs() * r * 0.05;
        canvas.drawLine(Offset(x, top), Offset(x, top + r * 0.16), paint);
      }
    }

    final sleepy = _w(GhostMood.sleepy);
    if (sleepy > 0.01) {
      for (var i = 0; i < 3; i++) {
        final p = (t * 0.4 + i / 3) % 1;
        _text(
          canvas,
          'z',
          head + Offset(r * (0.6 + p * 0.45), -r * (0.55 + p * 0.75)),
          r * (0.16 + 0.16 * p),
          _ink.withValues(alpha: 0.75 * sleepy * math.sin(math.pi * p)),
        );
      }
    }

    final think = _w(GhostMood.thinking);
    if (think > 0.01) {
      _text(
        canvas,
        '?',
        head + Offset(r * 0.95, -r * 0.75 + math.sin(t * 3) * r * 0.05),
        r * 0.36,
        kBrandBlue.withValues(alpha: think),
        angle: math.sin(t * 2) * 0.15,
      );
    }
  }

  void _text(Canvas canvas, String text, Offset at, double size, Color color, {double angle = 0}) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(fontSize: size, fontWeight: FontWeight.w900, color: color),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    canvas.save();
    canvas.translate(at.dx, at.dy);
    canvas.rotate(angle);
    tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
    canvas.restore();
  }

  @override
  bool shouldRepaint(_GhostPainter old) =>
      old.t != t ||
      old.intro != intro ||
      old.listen != listen ||
      old.talk != talk ||
      old.tapAge != tapAge ||
      old.from != from ||
      old.to != to ||
      old.moodT != moodT ||
      old.still != still ||
      old.police != police;
}
