import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/app_block_store.dart';
import '../services/profile_store.dart';
import '../services/progress_store.dart';
import '../services/screen_time_store.dart';
import '../services/usage_summary.dart';
import '../services/word_service.dart';
import 'app_control_screen.dart';
import 'app_theme.dart';
import 'mascot.dart';
import 'patrol.dart';
import 'screen_time_settings_sheet.dart';

const _green = Color(0xFF2EB67D);
const _amber = Color(0xFFFFB020);
const _red = Color(0xFFE5484D);
const _purple = Color(0xFF8E5CF7);

const _categories = {
  'social': ('Social media', Icons.forum_rounded, Color(0xFFEC4899)),
  'video': ('Video', Icons.play_circle_rounded, Color(0xFFE5484D)),
  'games': ('Games', Icons.sports_esports_rounded, _purple),
  'other': ('Your picked apps', Icons.apps_rounded, kBrandBlue),
};

/// The center tab: how long social media, video and games took today, what
/// that adds up to across a year and a life, and the time saved. The ghost
/// floats in a glowing orb inside a gauge of the waking day.
class TimeTab extends StatefulWidget {
  const TimeTab({super.key, this.service = const WordService(), this.now});

  final WordService service;

  /// Overrides the clock (tests).
  final DateTime? now;

  @override
  State<TimeTab> createState() => _TimeTabState();
}

class _TimeTabState extends State<TimeTab>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  /// Numbers, gauge and bars grow from zero when the screen opens.
  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  UsageSummary? _summary;
  UsageBaseline? _baseline;

  /// Sent to Settings and waiting; the toggle may be blocked on sideloads.
  bool _asked = false;
  bool _maybeBlocked = false;
  bool _dismissedRec = false;

  int? get _estimate => ProfileStore.instance.scrollHoursEstimate;
  DateTime get _now => widget.now ?? DateTime.now();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ScreenTimeStore.instance.addListener(_onStoreChanged);
    AppBlockStore.instance.addListener(_onStoreChanged);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    ScreenTimeStore.instance.removeListener(_onStoreChanged);
    AppBlockStore.instance.removeListener(_onStoreChanged);
    _intro.dispose();
    super.dispose();
  }

  void _onStoreChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
  }

  Future<void> _load() async {
    UsageSummary summary;
    try {
      summary = await widget.service.usageSummary();
    } catch (_) {
      summary = const UsageSummary(granted: false);
    }
    await ProgressStore.instance.ensureLoaded();
    await ScreenTimeStore.instance.ensureLoaded();
    await AppBlockStore.instance.ensureLoaded();
    // The fixed "before" is taken once, as soon as there are enough real days.
    var baseline = await UsageBaseline.load();
    if (baseline == null && summary.granted) {
      baseline = summary.measureBaseline(_now);
      if (baseline != null && baseline.totalMs > 0) {
        await baseline.save();
      } else {
        baseline = null;
      }
    }
    if (!mounted) return;
    final first = _summary == null || _summary!.granted != summary.granted;
    setState(() {
      _maybeBlocked = _asked && !summary.granted;
      _asked = false;
      _summary = summary;
      _baseline = baseline;
    });
    if (first) _intro.forward(from: 0);
  }

  Future<void> _allow() async {
    _asked = true;
    await widget.service.openUsageAccessSettings();
  }

  /// A usual day: measured first, then a recent average, then their guess.
  int? _usualMs(UsageSummary s) {
    final estimate = _estimate;
    return _baseline?.totalMs ??
        s.averageMs ??
        (estimate == null ? null : estimate * 3600000);
  }

  @override
  Widget build(BuildContext context) {
    final summary = _summary;
    if (summary == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 120),
      children: summary.granted ? _content(summary) : _needsAccess(context),
    );
  }

  List<Widget> _needsAccess(BuildContext context) {
    final theme = Theme.of(context);
    return [
      const SizedBox(height: 16),
      _Gauge(
        intro: _intro,
        todayMs: 0,
        usualByNowMs: null,
        usualMs: null,
        projectedMs: 0,
        effectiveLimitMinutes: ScreenTimeStore.instance.effectiveLimitMinutes(_now),
      ),
      const SizedBox(height: 20),
      Text(
        'See where your time really goes',
        textAlign: TextAlign.center,
        style: theme.textTheme.headlineSmall?.copyWith(
          fontWeight: FontWeight.w800,
        ),
      ),
      const SizedBox(height: 8),
      Text(
        'Allow usage access and I’ll show how long social media, video and '
        'games take, and what that adds up to. I only see how long apps are '
        'open, never what you do in them, and it stays on your phone.',
        textAlign: TextAlign.center,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      const SizedBox(height: 20),
      FilledButton(onPressed: _allow, child: const Text('Allow usage access')),
      if (_maybeBlocked) ...[
        const SizedBox(height: 16),
        GlassCard(
          child: Text(
            'Is the switch greyed out? Open App info for BiLingo, tap the ⋮ '
            'menu at the top, choose “Allow restricted settings”, then try '
            'again.',
            style: theme.textTheme.bodyMedium,
          ),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () {
            _asked = true;
            widget.service.openAppSettings();
          },
          child: const Text('Open App info'),
        ),
      ],
    ];
  }

  List<Widget> _content(UsageSummary s) {
    final estimate = _estimate;
    final usual = _usualMs(s);
    final baseline = _baseline;
    final categories = {
      for (final e in s.categories.entries)
        if (e.value >= 60000) e.key: e.value,
    };
    final apps = [
      for (final a in s.apps)
        if (a.todayMs >= 60000) a,
    ];
    final (daily, _) = s.costDaily(estimate);

    final effectiveLimit = ScreenTimeStore.instance.effectiveLimitMinutes(_now);
    final limitMs = effectiveLimit * 60 * 1000;
    final exceeded = s.todayMs > limitMs;
    final topApp = apps.isNotEmpty ? apps.first : null;
    final showRec = exceeded && topApp != null && !_dismissedRec;

    return [
      _Hero(
        intro: _intro,
        todayMs: s.todayMs,
        usualMs: usual,
        usualByNowMs:
            baseline?.at(_now) ??
            (usual == null
                ? null
                : (usual * UsageSummary.dayFraction(_now)).round()),
        projectedMs: s.projectedTodayMs(baseline, _now, daily),
        effectiveLimitMinutes: effectiveLimit,
      ),
      const SizedBox(height: 18),
      _DailyLimitCard(
        todayMs: s.todayMs,
        effectiveLimitMinutes: effectiveLimit,
        onEdit: () => ScreenTimeSettingsSheet.show(context),
      ),
      if (showRec) ...[
        const SizedBox(height: 16),
        _UsageRecommendationBanner(
          topApp: topApp,
          todayLimitMinutes: effectiveLimit,
          onBlock: () async {
            await AppBlockStore.instance.blockApps(
              apps: [(topApp.package, topApp.label)],
              duration: const Duration(hours: 1),
              blockType: 'limit_exceeded',
            );
            setState(() => _dismissedRec = true);
          },
          onChooseAnother: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AppControlScreen()),
            );
          },
          onDismiss: () {
            setState(() => _dismissedRec = true);
          },
        ),
      ],
      const SizedBox(height: 18),
      _SavedRow(
        intro: _intro,
        savedTodayMs: baseline == null ? null : s.savedTodayMs(baseline, _now),
        savedWeekMs: baseline == null ? null : s.savedWeekMs(baseline, _now),
        learnMs: ProgressStore.instance.learningTodayMs,
      ),
      const SizedBox(height: 18),
      _BlockedAppsSection(
        blockedApps: AppBlockStore.instance.blockedApps,
        onManage: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const AppControlScreen()),
          );
        },
        onUnblock: (pkg) => AppBlockStore.instance.unblockApp(pkg),
        onExtend: (pkg) => AppBlockStore.instance.extendBlock(pkg, const Duration(minutes: 30)),
      ),
      if (apps.isNotEmpty) ...[
        const SizedBox(height: 18),
        _TopApps(intro: _intro, apps: apps),
      ],
      if (categories.isNotEmpty) ...[
        const SizedBox(height: 18),
        _Breakdown(intro: _intro, categories: categories),
      ],
      const SizedBox(height: 18),
      const CaseFileCard(),
      if (baseline == null) ...[
        const SizedBox(height: 8),
        Text(
          'Learning your usual day: ${s.finishedDaysWithData} of '
          '${UsageBaseline.minDays} days. Saved time starts then.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      ],
      const SizedBox(height: 16),
      Text(
        'Counts social, video and game apps, plus any you picked. Saved time '
        'compares today with your usual use by this hour. Learning counts '
        'active time in lessons and reels. This stays on your phone.',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodySmall
            ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
    ];
  }
}

double _ease(double t) => Curves.easeOutCubic.transform(t);

const _todayColor = Color(0xFFFFA94D);
const _usualColor = Color(0xFF6C7BFF);

/// The gauge with today and the usual pace named below it.
class _Hero extends StatelessWidget {
  const _Hero({
    required this.intro,
    required this.todayMs,
    required this.usualMs,
    required this.usualByNowMs,
    required this.projectedMs,
    this.effectiveLimitMinutes = 120,
  });

  final Animation<double> intro;
  final int todayMs;
  final int? usualMs;
  final int? usualByNowMs;
  final int projectedMs;
  final int effectiveLimitMinutes;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final byNow = usualByNowMs;
    return Column(
      children: [
        Text(
          'YOUR TIME TODAY',
          style: theme.textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: 2,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        _Gauge(
          intro: intro,
          todayMs: todayMs,
          usualByNowMs: byNow,
          usualMs: usualMs,
          projectedMs: projectedMs,
          effectiveLimitMinutes: effectiveLimitMinutes,
        ),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 16,
          runSpacing: 4,
          children: [
            _LegendDot(
              color: _todayColor,
              label: 'Today',
              value: formatDuration(todayMs),
            ),
            if (byNow != null)
              _LegendDot(
                color: _usualColor,
                label: 'Usual by now',
                value: formatDuration(byNow),
              ),
          ],
        ),
      ],
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({
    required this.color,
    required this.label,
    required this.value,
  });

  final Color color;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          '$label ',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        Text(
          value,
          style: theme.textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

/// A 270° gauge of the waking day (full at 8 hours, half of it), with the
/// ghost floating in a glowing orb and the lifetime cost of this pace below it.
class _Gauge extends StatefulWidget {
  const _Gauge({
    super.key,
    required this.intro,
    required this.todayMs,
    required this.usualByNowMs,
    required this.usualMs,
    required this.projectedMs,
    this.effectiveLimitMinutes = 120,
  });

  /// Drawn at this size, then scaled to the screen.
  static const _width = 300.0;
  static const _height = 262.0;

  final Animation<double> intro;
  final int todayMs;
  final int? usualByNowMs;
  final int? usualMs;
  final int projectedMs;
  final int effectiveLimitMinutes;

  @override
  State<_Gauge> createState() => _GaugeState();
}

class _GaugeState extends State<_Gauge> {
  Timer? _timer;
  int _mode = 0; // 0: Screen time today, 1: Today · ≈ X yrs in life

  static String _formatLimit(int min) {
    final h = min ~/ 60;
    final m = min % 60;
    if (h > 0 && m > 0) return '${h}h ${m}m';
    if (h > 0) return '${h}h';
    return '${m}m';
  }

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted) return;
      setState(() => _mode = (_mode + 1) % 2);
    });
  }

  void _toggle() {
    HapticFeedback.selectionClick();
    setState(() => _mode = (_mode + 1) % 2);
    _startTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final years = TimeCost(widget.projectedMs).yearsOfLife;
    return Semantics(
      label:
          '${formatDuration(widget.todayMs)} today. At this pace, '
          '${years.toStringAsFixed(1)} years of your next '
          '${TimeCost.lifeYears}.',
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: AspectRatio(
            aspectRatio: _Gauge._width / _Gauge._height,
            child: FittedBox(
              child: SizedBox(
                width: _Gauge._width,
                height: _Gauge._height,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: RepaintBoundary(
                        child: AnimatedBuilder(
                          animation: widget.intro,
                          builder: (context, _) => CustomPaint(
                            painter: _GaugePainter(
                              t: _ease(widget.intro.value),
                              todayMs: widget.todayMs,
                              usualByNowMs: widget.usualByNowMs,
                              usualMs: widget.usualMs,
                              track: theme.colorScheme.onSurface.withValues(
                                alpha: 0.12,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 66,
                      top: 54,
                      child: GestureDetector(
                        onTap: _toggle,
                        behavior: HitTestBehavior.opaque,
                        child: Container(
                          width: 168,
                          height: 168,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: RadialGradient(
                              center: Alignment(0, -0.16),
                              radius: 0.72,
                              colors: [
                                Color(0xFFFFF6EE),
                                Color(0xFFF4A9D8),
                                Color(0xFF6C5CF0),
                              ],
                              stops: [0, 0.6, 1],
                            ),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 106,
                      top: 56,
                      child: GestureDetector(
                        onTap: _toggle,
                        child: const Mascot(size: 88, mood: GhostMood.happy),
                      ),
                    ),
                    Positioned(
                      left: 66,
                      width: 168,
                      top: 145,
                      child: GestureDetector(
                        onTap: _toggle,
                        behavior: HitTestBehavior.opaque,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  formatDuration(widget.todayMs),
                                  style: const TextStyle(
                                    color: Color(0xFF1F1A2E),
                                    fontSize: 21,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: -0.5,
                                    height: 1.0,
                                  ),
                                ),
                                Text(
                                  ' / Limit: ${_formatLimit(widget.effectiveLimitMinutes)}',
                                  style: const TextStyle(
                                    color: Color(0xFF5A4EB8),
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w800,
                                    height: 1.0,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 3),
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 400),
                              switchInCurve: Curves.easeOutBack,
                              switchOutCurve: Curves.easeInCubic,
                              transitionBuilder: (child, animation) =>
                                  FadeTransition(
                                    opacity: animation,
                                    child: SlideTransition(
                                      position: Tween<Offset>(
                                        begin: const Offset(0, 0.35),
                                        end: Offset.zero,
                                      ).animate(animation),
                                      child: child,
                                    ),
                                  ),
                              child: _mode == 0
                                  ? Container(
                                      key: const ValueKey(0),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 7,
                                        vertical: 1.5,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withValues(
                                          alpha: 0.5,
                                        ),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Text(
                                        'Screen time today',
                                        style: TextStyle(
                                          color: Color(0xFF3B2C55),
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    )
                                  : Container(
                                      key: const ValueKey(1),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 7,
                                        vertical: 1.5,
                                      ),
                                      decoration: BoxDecoration(
                                        color: const Color(
                                          0xFF6C5CF0,
                                        ).withValues(alpha: 0.18),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        '≈ ${years.toStringAsFixed(1)} yrs in life',
                                        style: const TextStyle(
                                          color: Color(0xFF3B2C55),
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                            ),
                            const SizedBox(height: 3),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                AnimatedContainer(
                                  duration: const Duration(milliseconds: 300),
                                  width: _mode == 0 ? 10 : 3.5,
                                  height: 3,
                                  decoration: BoxDecoration(
                                    color: _mode == 0
                                        ? const Color(0xFF3B2C55)
                                        : const Color(
                                            0xFF3B2C55,
                                          ).withValues(alpha: 0.25),
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                AnimatedContainer(
                                  duration: const Duration(milliseconds: 300),
                                  width: _mode == 1 ? 10 : 3.5,
                                  height: 3,
                                  decoration: BoxDecoration(
                                    color: _mode == 1
                                        ? const Color(0xFF3B2C55)
                                        : const Color(
                                            0xFF3B2C55,
                                          ).withValues(alpha: 0.25),
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GaugePainter extends CustomPainter {
  _GaugePainter({
    required this.t,
    required this.todayMs,
    required this.usualByNowMs,
    required this.usualMs,
    required this.track,
  });

  /// The gauge is full at this much time.
  static const _fullMs = 8 * 3600000;
  static const _radius = 112.0;
  static const _center = Offset(150, 138);
  static const _start = 135 * math.pi / 180;
  static const _sweep = 270 * math.pi / 180;

  final double t;
  final int todayMs;
  final int? usualByNowMs;
  final int? usualMs;
  final Color track;

  Offset _at(double fraction, double radius) {
    final a = _start + _sweep * fraction;
    return _center + Offset(math.cos(a), math.sin(a)) * radius;
  }

  void _arc(Canvas canvas, double fraction, Color color, double width) {
    final f = fraction.clamp(0.0, 1.0);
    if (f <= 0) return;
    canvas.drawArc(
      Rect.fromCircle(center: _center, radius: _radius),
      _start,
      _sweep * f,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round
        ..color = color,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    _arc(canvas, 1, track, 26);
    final byNow = usualByNowMs;
    if (byNow != null) _arc(canvas, byNow / _fullMs * t, _usualColor, 26);
    _arc(canvas, todayMs / _fullMs * t, _todayColor, 15);

    // The usual full day: staying below this is the goal.
    final usual = usualMs;
    if (usual != null && usual > 0) {
      final f = (usual / _fullMs).clamp(0.0, 1.0);
      canvas.drawLine(
        _at(f, _radius - 17),
        _at(f, _radius + 17),
        Paint()
          ..color = _green
          ..strokeWidth = 7
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(_GaugePainter old) =>
      old.t != t ||
      old.todayMs != todayMs ||
      old.usualByNowMs != usualByNowMs ||
      old.usualMs != usualMs ||
      old.track != track;
}

class _SavedRow extends StatelessWidget {
  const _SavedRow({
    required this.intro,
    required this.savedTodayMs,
    required this.savedWeekMs,
    required this.learnMs,
  });

  final Animation<double> intro;
  final int? savedTodayMs;
  final int? savedWeekMs;
  final int learnMs;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: intro,
    builder: (context, _) {
      final t = _ease(intro.value);
      String show(int? ms) =>
          ms == null ? '--' : formatDuration((ms * t).round());
      return Row(
        children: [
          Expanded(
            child: _Stat(
              icon: Icons.savings_rounded,
              color: _green,
              value: show(savedTodayMs),
              label: 'Saved today',
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _Stat(
              icon: Icons.calendar_month_rounded,
              color: kBrandBlue,
              value: show(savedWeekMs),
              label: 'This week',
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _Stat(
              icon: Icons.school_rounded,
              color: _purple,
              value: show(learnMs),
              label: 'Learning',
            ),
          ),
        ],
      );
    },
  );
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.icon,
    required this.color,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final Color color;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          Text(
            label,
            maxLines: 2,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// A progress bar with a glow that grows in with the screen.
class _GlowBar extends StatelessWidget {
  const _GlowBar({
    required this.fraction,
    required this.color,
    this.height = 12,
  });

  final double fraction;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final width = box.maxWidth * fraction.clamp(0.0, 1.0);
      return Stack(
        children: [
          Container(
            height: height,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.onSurface
                  .withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(height),
            ),
          ),
          Container(
            height: height,
            width: width,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(height),
              gradient: LinearGradient(
                colors: [color.withValues(alpha: 0.7), color],
              ),
              boxShadow: [
                BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 10),
              ],
            ),
          ),
        ],
      );
    },
  );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Text(
      text,
      style: Theme.of(context).textTheme.titleMedium
          ?.copyWith(fontWeight: FontWeight.w800),
    ),
  );
}

/// Today's time split into social, video and games.
class _Breakdown extends StatelessWidget {
  const _Breakdown({required this.intro, required this.categories});

  final Animation<double> intro;
  final Map<String, int> categories;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entries = categories.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final longest = entries.first.value;
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionTitle('Where it went'),
          AnimatedBuilder(
            animation: intro,
            builder: (context, _) => Column(
              children: [
                for (final e in entries)
                  if (_categories[e.key] case (
                    final name,
                    final icon,
                    final color,
                  ))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Icon(icon, color: color, size: 18),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  name,
                                  style: theme.textTheme.labelLarge?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              Text(
                                formatDuration(e.value),
                                style: theme.textTheme.labelLarge?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          _GlowBar(
                            fraction: e.value / longest * _ease(intro.value),
                            color: color,
                          ),
                        ],
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

/// Card displaying the user's daily limit, actual combined usage, remaining time, and progress.
class _DailyLimitCard extends StatelessWidget {
  const _DailyLimitCard({
    required this.todayMs,
    required this.effectiveLimitMinutes,
    required this.onEdit,
  });

  final int todayMs;
  final int effectiveLimitMinutes;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final limitMs = effectiveLimitMinutes * 60 * 1000;
    final remainingMs = math.max(0, limitMs - todayMs);
    final progress = limitMs > 0 ? (todayMs / limitMs).clamp(0.0, 1.0) : 0.0;
    final percent = (progress * 100).round();
    final exceeded = todayMs > limitMs;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF1E2028) : Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: dark
            ? const []
            : const [
                BoxShadow(
                  color: Color(0x10000000),
                  blurRadius: 16,
                  offset: Offset(0, 4),
                ),
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: kBrandBlue.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.timer_outlined, color: kBrandBlue, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Daily Screen-Time Limit',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.edit_outlined, size: 18, color: kBrandBlue),
                tooltip: 'Edit screen-time settings',
                onPressed: onEdit,
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _StatBlock(
                  label: 'Daily Limit',
                  value: _formatFull(limitMs),
                  color: dark ? Colors.white : const Color(0xFF1E2028),
                ),
              ),
              Expanded(
                child: _StatBlock(
                  label: 'Total Usage',
                  value: _formatFull(todayMs),
                  color: exceeded ? const Color(0xFFE5484D) : (dark ? Colors.white : const Color(0xFF1E2028)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _StatBlock(
                  label: exceeded ? 'Exceeded By' : 'Remaining Time',
                  value: exceeded ? _formatFull(todayMs - limitMs) : _formatFull(remainingMs),
                  color: exceeded ? const Color(0xFFE5484D) : _green,
                ),
              ),
              Expanded(
                child: _StatBlock(
                  label: 'Usage Progress',
                  value: '$percent%',
                  color: exceeded ? const Color(0xFFE5484D) : (percent > 85 ? _amber : kBrandBlue),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              backgroundColor: dark ? const Color(0xFF2B2D38) : const Color(0xFFEEF1F6),
              valueColor: AlwaysStoppedAnimation<Color>(
                exceeded ? const Color(0xFFE5484D) : (percent > 85 ? _amber : kBrandBlue),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _formatFull(int ms) {
    final min = (ms / 60000).round();
    final h = min ~/ 60;
    final m = min % 60;
    if (h > 0 && m > 0) return '$h ${h == 1 ? "Hour" : "Hours"} $m ${m == 1 ? "Minute" : "Minutes"}';
    if (h > 0) return '$h ${h == 1 ? "Hour" : "Hours"}';
    return '$min ${min == 1 ? "Minute" : "Minutes"}';
  }
}

class _StatBlock extends StatelessWidget {
  const _StatBlock({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          style: TextStyle(
            fontSize: 14.5,
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
      ],
    );
  }
}

/// Replaces the old 'What it really costs' card with Blocked Applications.
class _BlockedAppsSection extends StatelessWidget {
  const _BlockedAppsSection({
    required this.blockedApps,
    required this.onManage,
    required this.onUnblock,
    required this.onExtend,
  });

  final List<BlockedApp> blockedApps;
  final VoidCallback onManage;
  final ValueChanged<String> onUnblock;
  final ValueChanged<String> onExtend;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF1E2028) : Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: dark
            ? const []
            : const [
                BoxShadow(
                  color: Color(0x10000000),
                  blurRadius: 16,
                  offset: Offset(0, 4),
                ),
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xFFE5484D).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.block_rounded, color: Color(0xFFE5484D), size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Blocked Applications',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (blockedApps.isNotEmpty)
                TextButton(
                  onPressed: onManage,
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    foregroundColor: kBrandBlue,
                  ),
                  child: const Text('Manage', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                ),
            ],
          ),
          const SizedBox(height: 14),
          if (blockedApps.isEmpty) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: Column(
                  children: [
                    Icon(
                      Icons.shield_outlined,
                      size: 44,
                      color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'No apps blocked yet.',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.onSurfaceVariant,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Select distracting apps to block whenever you need focus.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 14),
                    FilledButton.icon(
                      icon: const Icon(Icons.add_moderator_rounded, size: 18),
                      label: const Text('Select Apps to Block'),
                      style: FilledButton.styleFrom(
                        backgroundColor: kBrandBlue,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                      ),
                      onPressed: onManage,
                    ),
                  ],
                ),
              ),
            ),
          ] else ...[
            for (final app in blockedApps) ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: dark ? const Color(0xFF282A36) : const Color(0xFFF1F3F8),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        app.label.isNotEmpty ? app.label.substring(0, 1).toUpperCase() : 'A',
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            app.label.isNotEmpty ? app.label : app.packageName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Container(
                                width: 6,
                                height: 6,
                                decoration: const BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Color(0xFFE5484D),
                                ),
                              ),
                              const SizedBox(width: 5),
                              Text(
                                'Blocked · ${app.formattedRemaining}',
                                style: const TextStyle(
                                  color: Color(0xFFE5484D),
                                  fontWeight: FontWeight.w600,
                                  fontSize: 11.5,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    // Action: Extend (+30m)
                    IconButton(
                      icon: const Icon(Icons.more_time_rounded, size: 20, color: kBrandBlue),
                      tooltip: 'Extend by 30 minutes',
                      onPressed: () => onExtend(app.packageName),
                      visualDensity: VisualDensity.compact,
                    ),
                    // Action: Unblock
                    IconButton(
                      icon: const Icon(Icons.lock_open_rounded, size: 20, color: Color(0xFFE5484D)),
                      tooltip: 'Unblock app',
                      onPressed: () => onUnblock(app.packageName),
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
              ),
              if (app != blockedApps.last) const Divider(height: 12),
            ],
            const SizedBox(height: 10),
            Center(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.tune_rounded, size: 16),
                label: const Text('Manage Blocked Apps', style: TextStyle(fontSize: 12.5)),
                onPressed: onManage,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Intelligent usage-based recommendation banner shown when the daily limit is exceeded.
class _UsageRecommendationBanner extends StatelessWidget {
  const _UsageRecommendationBanner({
    required this.topApp,
    required this.todayLimitMinutes,
    required this.onBlock,
    required this.onChooseAnother,
    required this.onDismiss,
  });

  final AppUsage topApp;
  final int todayLimitMinutes;
  final VoidCallback onBlock;
  final VoidCallback onChooseAnother;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final topMin = (topApp.todayMs / 60000).round();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF2E241E) : const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFFFFB020).withValues(alpha: 0.4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.warning_amber_rounded, color: Color(0xFFFFB020), size: 20),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Daily Screen-Time Limit Exceeded!',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    color: Color(0xFFC26100),
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded, size: 16),
                onPressed: onDismiss,
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${topApp.label} has been your most-used application today ($topMin minutes). Would you like to block ${topApp.label} for a while?',
            style: const TextStyle(fontSize: 13, height: 1.3),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFE5484D),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                ),
                onPressed: onBlock,
                child: Text('Block ${topApp.label} (1h)'),
              ),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                onPressed: onChooseAnother,
                child: const Text('Choose Another'),
              ),
              TextButton(
                onPressed: onDismiss,
                child: const Text('Maybe Later', style: TextStyle(fontSize: 12, color: Colors.grey)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TopApps extends StatelessWidget {
  const _TopApps({required this.intro, required this.apps});

  final Animation<double> intro;
  final List<AppUsage> apps;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final longest = apps.first.todayMs;
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionTitle('Top apps today'),
          AnimatedBuilder(
            animation: intro,
            builder: (context, _) => Column(
              children: [
                for (final app in apps)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: SizedBox.square(
                            dimension: 38,
                            child: app.icon == null
                                ? const Icon(Icons.apps_rounded)
                                : Image.memory(
                                    app.icon!,
                                    gaplessPlayback: true,
                                  ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      app.label,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.labelLarge
                                          ?.copyWith(
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                  ),
                                  Text(
                                    formatDuration(app.todayMs),
                                    style: theme.textTheme.labelLarge?.copyWith(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              _GlowBar(
                                fraction:
                                    app.todayMs / longest * _ease(intro.value),
                                color:
                                    _categories[app.category]?.$3 ?? kBrandBlue,
                                height: 8,
                              ),
                            ],
                          ),
                        ),
                      ],
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
