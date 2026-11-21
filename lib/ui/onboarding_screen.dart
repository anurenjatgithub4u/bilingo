import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/premium_store.dart';
import '../services/profile_store.dart';
import '../services/usage_summary.dart';
import '../services/word_service.dart';
import 'app_theme.dart';
import 'main_shell.dart';
import 'mascot.dart';
import 'topics.dart';

const _pageDuration = Duration(milliseconds: 480);
const _pageCurve = Curves.easeInOutCubic;

/// First-run flow: welcome, name, subjects, how much time goes on scrolling,
/// how BiLingo helps, apps to watch, the reminder limit (only with apps
/// picked), then unlock learning and the permissions those need, then Home.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with WidgetsBindingObserver {
  static const _pageCount = 8;
  static const _welcomeIndex = 0;
  static const _nameIndex = 1;
  static const _subjectsIndex = 2;
  static const _usageIndex = 3;
  static const _howIndex = 4;
  static const _setupIndex = 5;
  static const _reminderIndex = 6;
  static const _permissionsIndex = 7;

  /// Popular scrolling apps, picked for the user up front if installed.
  static const _timeSinks = {
    'com.instagram.android',
    'com.google.android.youtube',
    'com.facebook.katana',
    'com.zhiliaoapp.musically',
    'com.ss.android.ugc.trill',
    'com.snapchat.android',
    'com.twitter.android',
    'com.reddit.frontpage',
    'in.mohalla.sharechat',
    'in.mohalla.video',
    'com.eterno.shortvideos',
    'com.pinterest',
    'com.netflix.mediaclient',
  };

  /// The reminder time a learner can choose, in minutes.
  static const _minLimit = 1;
  static const _maxLimit = 60;

  /// Apps shown before "Show all": two rows of the grid.
  static const _collapsedApps = 8;

  final _service = const WordService();
  final _pages = PageController();
  final _name = TextEditingController();

  /// Subjects picked on the third step: language codes and/or [kMathsCode].
  final Set<String> _subjects = {};

  /// What the learner picked.
  Set<String> get _topicCodes => _subjects;

  /// The learner's own estimate of daily scrolling, in hours.
  int _scrollHours = 3;

  /// Whether real usage data was successfully detected via usage access.
  bool _usageDetected = false;

  /// Whether we're currently loading usage data after permission grant.
  bool _usageLoading = false;

  /// Whether the user chose to enter manually (skipped auto-detect).
  bool _usageManual = false;

  /// The real detected daily average in milliseconds, if available.
  int _realDailyMs = 0;

  /// Top apps from real usage data.
  List<AppUsage> _realApps = const [];

  /// Words from the first chosen language, for the notification preview.
  List<ShownWord> _samples = const [];

  int _page = 0;
  bool _navigating = false;
  bool _notificationsOk = false;
  bool _batteryOk = false;
  bool _usageOk = false;
  bool _finishing = false;

  /// Apps on the phone (null while loading) and the ones the user wants watched.
  List<InstalledApp>? _apps;
  final Set<String> _picked = {};
  String _query = '';
  bool _showAllApps = false;
  int _limit = 5;

  /// A word on every unlock; works with or without app monitoring.
  bool _unlockLearning = true;

  /// Usage access: sent to Settings and waiting to see the result; the phone
  /// seems to block it; the help sheet is showing.
  bool _usageAsked = false;
  bool _usageBlocked = false;
  bool _usageSheetOpen = false;

  bool get _monitoring => _picked.isNotEmpty;

  /// Any feature that needs to show notifications.
  bool get _wantsNotifications => _unlockLearning || _monitoring;

  /// Permissions that matter for what is switched on, and which are granted.
  List<bool> get _relevantGrants => [
    if (_wantsNotifications) _notificationsOk,
    if (_monitoring) _usageOk,
    if (_wantsNotifications) _batteryOk,
  ];

  int get _grantedCount => _relevantGrants.where((ok) => ok).length;

  /// Languages among the picked subjects, in the app's order.
  List<String> get _pickedLanguages => [
    for (final t in kTopics)
      if (_subjects.contains(t.code)) t.code,
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _name.addListener(() => setState(() {}));
    _refreshPermissions();
    _loadApps();
  }

  Future<void> _loadApps() async {
    try {
      final apps = await _service.installedApps();
      if (!mounted) return;
      setState(() {
        _apps = apps;
        // The free limit: the first few popular time sinks found.
        _picked.addAll(
          apps
              .map((a) => a.package)
              .where(_timeSinks.contains)
              .take(kFreeTrackedApps),
        );
      });
    } catch (_) {
      // No native side (tests): show the empty state.
      if (mounted) setState(() => _apps = const []);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pages.dispose();
    _name.dispose();
    super.dispose();
  }

  // The user may flip a permission in system settings and come back.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshPermissions();
      // If we sent them to usage access settings from the usage step,
      // try to fetch the data now.
      if (_usageLoading && _page == _usageIndex) {
        _tryFetchUsageData();
      }
    }
  }

  Future<void> _refreshPermissions() async {
    try {
      final s = await _service.getState();
      if (!mounted) return;
      setState(() {
        _notificationsOk = s.notificationsGranted;
        _batteryOk = s.batteryUnrestricted;
        _usageOk = s.usageAccessGranted;
      });
      // Back from Settings and still off: most likely Android's "restricted
      // setting" block on sideloaded apps, so explain how to lift it.
      if (_usageAsked && !_usageOk && _page == _permissionsIndex) {
        _usageAsked = false;
        _usageBlocked = true;
        await _allowUsage(blocked: true);
      }
    } catch (_) {
      // Native side unavailable (e.g. tests); leave permissions as not granted.
    }
  }

  Future<void> _allowNotifications() async {
    final granted = await _service.requestNotificationPermission();
    // Once denied, Android stops showing the prompt, so send them to settings.
    if (!granted) await _service.openNotificationSettings();
    await _refreshPermissions();
  }

  Future<void> _allowBattery() async {
    await _service.requestIgnoreBatteryOptimizations();
    await _refreshPermissions();
  }

  /// Usage access has no pop-up; it is a toggle deep in Settings, so explain
  /// what to tap before sending them there. The result is picked up on resume.
  /// [blocked] opens straight on the "restricted setting" help.
  Future<void> _allowUsage({bool blocked = false}) async {
    if (_usageSheetOpen) return;
    _usageSheetOpen = true;
    final step = await showModalBottomSheet<_UsageStep>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) =>
          _UsageAccessSheet(blocked: blocked || _usageBlocked),
    );
    _usageSheetOpen = false;
    switch (step) {
      case _UsageStep.settings:
        _usageAsked = true;
        await _service.openUsageAccessSettings();
      case _UsageStep.appInfo:
        _usageAsked = true;
        _usageBlocked = true;
        await _service.openAppSettings();
      case null:
        break;
    }
  }

  String get _buttonLabel =>
      _page == _pageCount - 1 ? 'Get started' : 'Continue';

  bool get _canContinue => switch (_page) {
    _nameIndex => _name.text.trim().isNotEmpty,
    _subjectsIndex => _subjects.isNotEmpty,
    _ => true,
  };

  /// One step at a time: taps during a page change are ignored, so a double
  /// tap can never skip a step.
  Future<void> _go(int delta) async {
    if (_navigating) return;
    var target = _page + delta;
    // No apps picked: nothing to time, so the reminder step is skipped.
    if (target == _reminderIndex && !_monitoring) target += delta;
    target = target.clamp(0, _pageCount - 1);
    if (target == _page) return;
    FocusScope.of(context).unfocus();
    setState(() => _navigating = true);
    try {
      await _pages.animateToPage(
        target,
        duration: _pageDuration,
        curve: _pageCurve,
      );
    } finally {
      if (mounted) setState(() => _navigating = false);
    }
  }

  Future<void> _next() async {
    if (!_canContinue || _navigating) return;
    HapticFeedback.selectionClick();
    if (_page < _pageCount - 1) {
      await _go(1);
      return;
    }
    await _finish();
  }

  /// Ghost face for an estimated number of scrolling hours a day.
  static GhostMood _usageMood(int hours) => switch (hours) {
    1 => GhostMood.happy,
    2 => GhostMood.concerned,
    3 || 4 => GhostMood.surprised,
    5 || 6 => GhostMood.shocked,
    _ => GhostMood.worried,
  };

  /// The ghost reacts to where you are and what you pick.
  GhostMood? get _mood => switch (_page) {
    _welcomeIndex => GhostMood.happy,
    _subjectsIndex => _subjects.isEmpty ? GhostMood.thinking : GhostMood.happy,
    _usageIndex => _usageDetected
        ? _usageMood((_realDailyMs / 3600000).round().clamp(1, 8))
        : (_usageManual ? _usageMood(_scrollHours) : GhostMood.thinking),
    _howIndex => GhostMood.wink,
    _setupIndex => _monitoring ? GhostMood.surprised : GhostMood.thinking,
    _reminderIndex => switch (_limit) {
      <= 2 => GhostMood.surprised,
      <= 15 => GhostMood.happy,
      _ => GhostMood.wink,
    },
    _permissionsIndex =>
      _relevantGrants.isNotEmpty && _grantedCount == _relevantGrants.length
          ? GhostMood.love
          : null,
    _ => null,
  };

  Future<void> _finish() async {
    if (_finishing) return;
    setState(() => _finishing = true);
    final store = ProfileStore.instance;
    final languages = _pickedLanguages;
    // Path, Read & Speak and word notifications follow one language; maths
    // alone falls back to English for those.
    final language = languages.isEmpty ? 'en' : languages.first;
    await store.setName(_name.text);
    await store.setLanguage(language);
    await store.setTopics(_topicCodes);
    if (_topicCodes.contains(kCodingCode) && languages.isEmpty) {
      await store.setFlowCode(kCodingCode);
    } else {
      await store.setFlowMaths(languages.isEmpty);
      if (_topicCodes.contains(kCodingCode)) {
        await store.setFlowCode(kCodingCode);
      }
    }
    await store.setScrollHoursEstimate(_scrollHours);
    await store.saveSetup({
      'subjects': _topicCodes.toList(),
      'appMonitoring': _monitoring,
      'trackedApps': _picked.toList(),
      'reminderMinutes': _monitoring ? _limit : null,
      'unlockLearning': _unlockLearning,
      'notificationsGranted': _notificationsOk,
      'usageAccessGranted': _usageOk,
      'backgroundAllowed': _batteryOk,
    });
    try {
      // Without enabled=true the native service never starts, so no unlock
      // words and no app timing.
      await _service.update(
        enabled: _notificationsOk && _wantsNotifications,
        onScreenOn: false,
        onUnlock: _unlockLearning,
        languages: {
          ...languages.isEmpty ? [language] : languages,
        },
        trackedApps: _picked,
        limitMinutes: _limit,
      );
    } catch (_) {
      // Word notifications can be configured later from Profile.
    }
    // Last, so an interrupted setup runs onboarding again.
    await store.completeOnboarding();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      PageRouteBuilder<void>(
        pageBuilder: (_, _, _) => const MainShell(),
        transitionsBuilder: (_, animation, _, child) => FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
          child: ScaleTransition(
            scale: Tween(begin: 0.96, end: 1.0).animate(
              CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
            ),
            child: child,
          ),
        ),
        transitionDuration: const Duration(milliseconds: 650),
      ),
      (_) => false,
    );
  }

  double get _pagePosition =>
      _pages.hasClients ? (_pages.page ?? _page.toDouble()) : _page.toDouble();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    return GradientBackground(
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        body: SafeArea(
          child: Column(
            children: [
              // The orb is large on the welcome and usage steps, where the
              // ghost is the star, and eases smaller elsewhere as you swipe.
              AnimatedBuilder(
                animation: _pages,
                builder: (context, child) {
                  final p = _pagePosition;
                  final welcomeRatio =
                      (1 - (p - _welcomeIndex).abs()).clamp(0.0, 1.0);
                  final usageRatio =
                      (1 - (p - _usageIndex).abs()).clamp(0.0, 1.0);
                  final height = keyboardOpen
                      ? 70.0
                      : 90.0 + 30.0 * welcomeRatio + 80.0 * usageRatio;
                  return Padding(
                    padding: EdgeInsets.only(
                      top: keyboardOpen ? 8 : (welcomeRatio > 0.5 ? 12 : 24),
                    ),
                    child: SizedBox(height: height, child: child),
                  );
                },
                child: FittedBox(child: Mascot(size: 200, mood: _mood)),
              ),
              Expanded(
                child: PageView(
                  controller: _pages,
                  physics: const NeverScrollableScrollPhysics(),
                  onPageChanged: (i) {
                    setState(() => _page = i);
                    if (i == _usageIndex &&
                        _usageOk &&
                        !_usageDetected &&
                        !_usageManual) {
                      _tryFetchUsageData();
                    }
                  },
                  children: [
                    _PageFx(
                      controller: _pages,
                      index: _welcomeIndex,
                      child: _welcomePage(theme),
                    ),
                    _PageFx(
                      controller: _pages,
                      index: _nameIndex,
                      child: _namePage(theme),
                    ),
                    _PageFx(
                      controller: _pages,
                      index: _subjectsIndex,
                      child: _subjectsPage(theme),
                    ),
                    _PageFx(
                      controller: _pages,
                      index: _usageIndex,
                      child: _usagePage(theme),
                    ),
                    _PageFx(
                      controller: _pages,
                      index: _howIndex,
                      child: _howItWorksPage(theme),
                    ),
                    _PageFx(
                      controller: _pages,
                      index: _setupIndex,
                      child: _setupPage(theme),
                    ),
                    _PageFx(
                      controller: _pages,
                      index: _reminderIndex,
                      child: _reminderPage(theme),
                    ),
                    _PageFx(
                      controller: _pages,
                      index: _permissionsIndex,
                      child: _permissionsPage(theme),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (var i = 0; i < _pageCount; i++)
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeOutCubic,
                            margin: const EdgeInsets.symmetric(horizontal: 4),
                            width: i == _page ? 24 : 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: i <= _page
                                  ? kBrandBlue
                                  : kBrandBlue.withValues(alpha: 0.25),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        // Back button slides its space open/closed instead of popping in.
                        AnimatedSize(
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeOutCubic,
                          child: _page > 0
                              ? Padding(
                                  padding: const EdgeInsets.only(right: 12),
                                  child: IconButton.filledTonal(
                                    style: IconButton.styleFrom(
                                      minimumSize: const Size(54, 54),
                                    ),
                                    onPressed: _finishing || _navigating
                                        ? null
                                        : () => _go(-1),
                                    icon: const Icon(Icons.arrow_back),
                                  ),
                                )
                              : const SizedBox.shrink(),
                        ),
                        Expanded(
                          child: AnimatedOpacity(
                            duration: const Duration(milliseconds: 250),
                            opacity: _canContinue ? 1 : 0.45,
                            child: FilledButton(
                              onPressed:
                                  (_canContinue && !_finishing && !_navigating)
                                  ? _next
                                  : null,
                              child: AnimatedSwitcher(
                                duration: const Duration(milliseconds: 250),
                                transitionBuilder: (child, animation) =>
                                    FadeTransition(
                                      opacity: animation,
                                      child: SlideTransition(
                                        position: Tween(
                                          begin: const Offset(0, 0.4),
                                          end: Offset.zero,
                                        ).animate(animation),
                                        child: child,
                                      ),
                                    ),
                                child: _finishing
                                    ? const SizedBox(
                                        key: ValueKey('busy'),
                                        width: 22,
                                        height: 22,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.5,
                                        ),
                                      )
                                    : Text(
                                        _buttonLabel,
                                        key: ValueKey(_buttonLabel),
                                      ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _heading(ThemeData theme, int page, String title, String subtitle) =>
      Column(
        children: [
          _FadeSlide(
            play: _page == page,
            child: Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 8),
          _FadeSlide(
            play: _page == page,
            delay: const Duration(milliseconds: 90),
            child: Text(
              subtitle,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      );

  /// Small left-aligned label over a group on the setup step.
  Widget _sectionLabel(ThemeData theme, String text) => Align(
    alignment: Alignment.centerLeft,
    child: Text(
      text,
      style: theme.textTheme.labelLarge?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
        fontWeight: FontWeight.w700,
      ),
    ),
  );

  static const _valueProps = [
    (
      Icons.laptop_chromebook_rounded,
      'Focus, uninterrupted.',
      'Finally do your best work yet.',
      Color(0xFF6366F1),
    ),
    (
      Icons.hourglass_bottom_rounded,
      'Own your time.',
      'And fill your days with more intention.',
      Color(0xFFF59E0B),
    ),
    (
      Icons.self_improvement_rounded,
      'Be fully present.',
      "Because life isn't happening on your screen.",
      Color(0xFF10B981),
    ),
  ];

  Widget _stackedBar({required double baseHeight, double topHeight = 0}) {
    const orangeColor = Color(0xFFF97316);
    const topColor = Color(0xFF94A3B8);
    const barWidth = 14.0;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (topHeight > 0)
          Container(
            width: barWidth,
            height: topHeight,
            margin: const EdgeInsets.only(bottom: 2),
            decoration: BoxDecoration(
              color: topColor.withValues(alpha: 0.65),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        Container(
          width: barWidth,
          height: baseHeight,
          decoration: BoxDecoration(
            color: orangeColor,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      ],
    );
  }

  Widget _shortBar({required double baseHeight, double topHeight = 3}) {
    const orangeColor = Color(0xFFF97316);
    const topColor = Color(0xFFCBD5E1);
    const barWidth = 14.0;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: barWidth,
          height: topHeight,
          margin: const EdgeInsets.only(bottom: 2),
          decoration: BoxDecoration(
            color: topColor.withValues(alpha: 0.8),
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        Container(
          width: barWidth,
          height: baseHeight,
          decoration: BoxDecoration(
            color: orangeColor.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      ],
    );
  }

  Widget _comparisonCard(ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    final cardBg = isDark
        ? theme.colorScheme.surfaceContainerHigh
        : Colors.white;
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.06);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.05),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Left: Before SCROLLING
            Expanded(
              child: Column(
                children: [
                  Text(
                    'Before',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'SCROLLING',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Daily Average',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '6h 32m',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 72,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        _stackedBar(baseHeight: 34),
                        _stackedBar(baseHeight: 46, topHeight: 18),
                        _stackedBar(baseHeight: 40, topHeight: 22),
                        _stackedBar(baseHeight: 32, topHeight: 14),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // Vertical Divider
            Container(
              width: 1,
              margin: const EdgeInsets.symmetric(horizontal: 12),
              color: theme.dividerColor.withValues(alpha: 0.18),
            ),
            // Right: After BILINGO
            Expanded(
              child: Column(
                children: [
                  Text(
                    'After',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'BILINGO',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.5,
                      color: kBrandBlue,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Daily Average',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '1h 49m',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                      color: const Color(0xFF16A34A),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 72,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        _shortBar(baseHeight: 12),
                        _shortBar(baseHeight: 18),
                        _shortBar(baseHeight: 14),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _headline(ThemeData theme) {
    final style = theme.textTheme.titleLarge?.copyWith(
      fontWeight: FontWeight.w800,
      height: 1.25,
      letterSpacing: -0.3,
    );
    return RichText(
      textAlign: TextAlign.center,
      text: TextSpan(
        style: style,
        children: [
          const TextSpan(text: 'Use '),
          TextSpan(
            text: 'BiLingo',
            style: TextStyle(
              color: kBrandBlue,
              fontWeight: FontWeight.w900,
            ),
          ),
          const TextSpan(text: ' and Turn Scrolling to '),
          TextSpan(
            text: 'Learning',
            style: TextStyle(
              color: kBrandBlue,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _valuePropRow(
    ThemeData theme,
    IconData icon,
    String title,
    String subtitle,
    Color color,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, color: color, size: 24),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _welcomePage(ThemeData theme) => SingleChildScrollView(
    padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
    child: Column(
      children: [
        _FadeSlide(
          play: _page == _welcomeIndex,
          child: _comparisonCard(theme),
        ),
        const SizedBox(height: 20),
        _FadeSlide(
          play: _page == _welcomeIndex,
          delay: const Duration(milliseconds: 100),
          child: _headline(theme),
        ),
        const SizedBox(height: 22),
        for (var i = 0; i < _valueProps.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: _FadeSlide(
              play: _page == _welcomeIndex,
              delay: Duration(milliseconds: 180 + i * 80),
              child: _valuePropRow(
                theme,
                _valueProps[i].$1,
                _valueProps[i].$2,
                _valueProps[i].$3,
                _valueProps[i].$4,
              ),
            ),
          ),
      ],
    ),
  );

  Widget _namePage(ThemeData theme) => SingleChildScrollView(
    padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
    child: Column(
      children: [
        _heading(
          theme,
          _nameIndex,
          'What should I call you?',
          'So I know who I am haunting.',
        ),
        const SizedBox(height: 28),
        _FadeSlide(
          play: _page == _nameIndex,
          delay: const Duration(milliseconds: 200),
          child: TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _next(),
            decoration: const InputDecoration(
              hintText: 'Your name',
              prefixIcon: Icon(Icons.person_outline),
            ),
          ),
        ),
      ],
    ),
  );

  void _toggleSubject(String code) {
    HapticFeedback.selectionClick();
    setState(() {
      if (!_subjects.remove(code)) _subjects.add(code);
    });
    _loadSamples();
  }

  /// Words for the reminder preview, from the first language picked.
  Future<void> _loadSamples() async {
    final languages = _pickedLanguages;
    final code = languages.isEmpty ? 'en' : languages.first;
    try {
      final words = await _service.pathWords(code);
      final now = _pickedLanguages;
      if (mounted && (now.isEmpty ? 'en' : now.first) == code) {
        setState(() => _samples = words);
      }
    } catch (_) {
      // No native side (tests): the preview shows a generic line.
    }
  }

  /// A full-width choice row; the selected one gets a brand border and a tick.
  Widget _option(
    ThemeData theme, {
    required bool selected,
    required Widget leading,
    required String title,
    String? subtitle,
    String? trailing,
    required VoidCallback onTap,
  }) {
    final dark = theme.brightness == Brightness.dark;
    return AnimatedScale(
      scale: selected ? 1.02 : 1,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutBack,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: selected
                ? kBrandBlue.withValues(alpha: dark ? 0.25 : 0.12)
                : (dark
                      ? const Color(0x22FFFFFF)
                      : Colors.white.withValues(alpha: 0.75)),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? kBrandBlue : Colors.transparent,
              width: 2,
            ),
          ),
          child: Row(
            children: [
              leading,
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              if (trailing != null)
                Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: Text(
                    trailing,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                transitionBuilder: (child, animation) =>
                    ScaleTransition(scale: animation, child: child),
                child: Icon(
                  selected ? Icons.check_circle : Icons.circle_outlined,
                  key: ValueKey(selected),
                  color: selected
                      ? kBrandBlue
                      : theme.colorScheme.onSurfaceVariant.withValues(
                          alpha: 0.4,
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _iconBox(IconData icon) => Container(
    width: 46,
    height: 46,
    decoration: BoxDecoration(
      color: kBrandBlue.withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Icon(icon, color: kBrandBlue),
  );

  Widget _subjectsPage(ThemeData theme) => SingleChildScrollView(
    padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
    child: Column(
      children: [
        _heading(
          theme,
          _subjectsIndex,
          'What would you like to learn?',
          'Pick one or more. You can change this later in Profile.',
        ),
        const SizedBox(height: 24),
        for (var i = 0; i < kSubjects.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _FadeSlide(
              play: _page == _subjectsIndex,
              // Options slide in one after another.
              delay: Duration(milliseconds: 160 + i * 70),
              child: _option(
                theme,
                selected: _subjects.contains(kSubjects[i].code),
                leading: _iconBox(kSubjects[i].icon),
                title: kSubjects[i].name,
                subtitle: kSubjects[i].subtitle,
                onTap: () => _toggleSubject(kSubjects[i].code),
              ),
            ),
          ),
      ],
    ),
  );

  void _setScrollHours(int hours) {
    if (hours == _scrollHours) return;
    HapticFeedback.selectionClick();
    setState(() => _scrollHours = hours);
  }

  /// Ask for usage access, then fetch actual screen time data.
  Future<void> _detectUsage() async {
    setState(() => _usageLoading = true);
    try {
      await _allowUsage();
      if (_usageOk) {
        await _tryFetchUsageData();
      } else {
        if (mounted) {
          setState(() {
            _usageLoading = false;
            // Fall back to manual if user backed out/denied
            _usageManual = true;
          });
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _usageLoading = false;
          _usageManual = true;
        });
      }
    }
  }

  /// Called when the app resumes after the user granted (or denied) usage access.
  Future<void> _tryFetchUsageData() async {
    try {
      final summary = await _service.usageSummary();
      if (!mounted) return;
      if (summary.granted) {
        final dailyMs = summary.averageMs ?? summary.todayMs;
        final hours = (dailyMs / 3600000).round().clamp(1, 8);
        setState(() {
          _usageOk = true;
          _usageDetected = true;
          _usageLoading = false;
          _usageManual = false;
          _realDailyMs = dailyMs;
          _scrollHours = hours;
          _realApps = [
            for (final a in summary.apps)
              if (a.todayMs >= 60000) a,
          ].take(5).toList();
        });
      } else {
        setState(() {
          _usageLoading = false;
          _usageManual = true;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _usageLoading = false;
          _usageManual = true;
        });
      }
    }
  }

  /// Switch to manual entry mode.
  void _useManualEntry() {
    HapticFeedback.selectionClick();
    setState(() {
      _usageManual = true;
      _usageDetected = false;
    });
  }

  /// Switch back to auto-detect mode.
  void _useAutoDetect() {
    HapticFeedback.selectionClick();
    setState(() {
      _usageManual = false;
    });
  }

  static String _usageMessage(int hours) {
    final week = 'That’s ${hours * 7} hours every week';
    return switch (hours) {
      1 => "$week. Let's make them count!",
      2 => '$week. Some of that could be learning.',
      3 || 4 => '$week. Imagine what you could learn!',
      5 || 6 => '$week. Your ghost is worried!',
      _ => '$week! We need a little change.',
    };
  }

  Widget _detectedAppsPreview(ThemeData theme) {
    if (_realApps.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Top apps found:',
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          for (final app in _realApps.take(3))
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: SizedBox.square(
                      dimension: 22,
                      child: app.icon == null
                          ? const Icon(Icons.apps_rounded, size: 18)
                          : Image.memory(app.icon!, gaplessPlayback: true),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      app.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Text(
                    formatDuration(app.todayMs),
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: kBrandBlue,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _autoDetectPromptPage(ThemeData theme) {
    final muted = theme.colorScheme.onSurfaceVariant;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      child: Column(
        children: [
          _heading(
            theme,
            _usageIndex,
            'How much time do you really spend scrolling?',
            'Let BiLingo check your actual app usage so you don’t have to guess.',
          ),
          const SizedBox(height: 20),
          _FadeSlide(
            play: _page == _usageIndex,
            delay: const Duration(milliseconds: 180),
            child: GlassCard(
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
              child: Column(
                children: [
                  Container(
                    width: 58,
                    height: 58,
                    decoration: BoxDecoration(
                      color: kBrandBlue.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: const Icon(
                      Icons.auto_graph_rounded,
                      color: kBrandBlue,
                      size: 30,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Track actual time automatically',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      fontSize: 18,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Allow usage access so BiLingo can check how long social '
                    'and entertainment apps are open. We only count the time, '
                    'never what you do inside.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: muted,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.shield_outlined,
                          size: 15,
                          color: Color(0xFF10B981),
                        ),
                        SizedBox(width: 6),
                        Text(
                          '100% on-device · Private · Never uploaded',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF10B981),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: _usageLoading ? null : _detectUsage,
                      icon: _usageLoading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.speed_rounded, size: 20),
                      label: Text(
                        _usageLoading
                            ? 'Checking screen time...'
                            : 'Check my actual screen time',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          _FadeSlide(
            play: _page == _usageIndex,
            delay: const Duration(milliseconds: 260),
            child: TextButton.icon(
              onPressed: _useManualEntry,
              icon: const Icon(Icons.tune_rounded, size: 18),
              label: const Text(
                "I'd rather estimate manually",
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _detectedUsagePage(ThemeData theme) {
    final hours = _scrollHours;
    final perYear = hours * 365;
    final days = (perYear / 24).round();
    final muted = theme.colorScheme.onSurfaceVariant;
    String grouped(int n) => n.toString().replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => ',',
    );
    Widget stat(String value, String label) => Expanded(
      child: GlassCard(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        child: Column(
          children: [
            Text(
              value,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
                color: kBrandBlue,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(color: muted),
            ),
          ],
        ),
      ),
    );

    final displayDaily = _realDailyMs > 0
        ? formatDuration(_realDailyMs)
        : '$hours ${hours == 1 ? 'hour' : 'hours'}';

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      child: Column(
        children: [
          _heading(
            theme,
            _usageIndex,
            'Here is where your time really goes',
            'Measured directly from your phone’s recent app usage.',
          ),
          const SizedBox(height: 20),
          _FadeSlide(
            play: _page == _usageIndex,
            delay: const Duration(milliseconds: 180),
            child: GlassCard(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.verified_rounded,
                          color: Color(0xFF10B981),
                          size: 16,
                        ),
                        SizedBox(width: 6),
                        Text(
                          'Measured from your phone',
                          style: TextStyle(
                            color: Color(0xFF10B981),
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '$displayDaily a day',
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: kBrandBlue,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Average across your active social & media apps',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(color: muted),
                  ),
                  if (_realApps.isNotEmpty) _detectedAppsPreview(theme),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          _FadeSlide(
            play: _page == _usageIndex,
            delay: const Duration(milliseconds: 260),
            child: Row(
              children: [
                stat('${hours * 7} h', 'every week'),
                const SizedBox(width: 10),
                stat('${grouped(perYear)} h', 'a year, about $days days'),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Text(
            _usageMessage(hours),
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: _useManualEntry,
            icon: const Icon(Icons.tune_rounded, size: 16),
            label: const Text(
              'Adjust estimate manually',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _manualUsagePage(ThemeData theme) {
    final hours = _scrollHours;
    final perYear = hours * 365;
    final days = (perYear / 24).round();
    final muted = theme.colorScheme.onSurfaceVariant;
    String grouped(int n) => n.toString().replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => ',',
    );
    Widget stat(String value, String label) => Expanded(
      child: GlassCard(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        child: Column(
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              transitionBuilder: (child, animation) =>
                  ScaleTransition(scale: animation, child: child),
              child: Text(
                value,
                key: ValueKey(value),
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: kBrandBlue,
                ),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(color: muted),
            ),
          ],
        ),
      ),
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      child: Column(
        children: [
          _heading(
            theme,
            _usageIndex,
            'Uh-oh! How much time do you spend on apps you don’t really need?',
            'Be honest! How much time do you spend scrolling every day?',
          ),
          const SizedBox(height: 16),
          if (!_usageOk)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: TextButton.icon(
                onPressed: _useAutoDetect,
                icon: const Icon(Icons.auto_graph_rounded, size: 16),
                label: const Text(
                  'Prefer automatic? Measure with BiLingo',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ),
          _FadeSlide(
            play: _page == _usageIndex,
            delay: const Duration(milliseconds: 180),
            child: GlassCard(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
              child: Column(
                children: [
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    transitionBuilder: (child, animation) => FadeTransition(
                      opacity: animation,
                      child: ScaleTransition(scale: animation, child: child),
                    ),
                    child: Text(
                      '$hours ${hours == 1 ? 'hour' : 'hours'} a day',
                      key: ValueKey(hours),
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: kBrandBlue,
                      ),
                    ),
                  ),
                  Semantics(
                    label: 'Hours of scrolling a day',
                    value: '$hours',
                    child: Slider(
                      value: hours.toDouble(),
                      min: 1,
                      max: 8,
                      divisions: 7,
                      label: '${hours}h',
                      onChanged: (v) => _setScrollHours(v.round()),
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('1h', style: theme.textTheme.labelMedium),
                      Text('8h', style: theme.textTheme.labelMedium),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          _FadeSlide(
            play: _page == _usageIndex,
            delay: const Duration(milliseconds: 260),
            child: Row(
              children: [
                stat('${hours * 7} h', 'every week'),
                const SizedBox(width: 10),
                stat('${grouped(perYear)} h', 'a year, about $days days'),
              ],
            ),
          ),
          const SizedBox(height: 14),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: Text(
              _usageMessage(hours),
              key: ValueKey(hours),
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'An estimate from your answer, not measured usage.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(color: muted),
          ),
        ],
      ),
    );
  }

  Widget _usagePage(ThemeData theme) {
    if (_usageDetected) {
      return _detectedUsagePage(theme);
    }
    if (_usageManual) {
      return _manualUsagePage(theme);
    }
    return _autoDetectPromptPage(theme);
  }

  static const _howSteps = [
    (
      Icons.timer_outlined,
      'Scrolling reminders',
      'I time the apps you pick. Past your limit, I offer a learning break.',
    ),
    (
      Icons.lock_open_outlined,
      'Unlock learning',
      'If you want, a new word pops up each time you unlock your phone.',
    ),
    (
      Icons.swipe_up_outlined,
      'WordFlow',
      'Open BiLingo any time and swipe through interactive learning cards.',
    ),
  ];

  Widget _howItWorksPage(ThemeData theme) => SingleChildScrollView(
    padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
    child: Column(
      children: [
        _heading(
          theme,
          _howIndex,
          'Turn scrolling into learning',
          'Three ways I help, in a friendly-ghost way',
        ),
        const SizedBox(height: 24),
        for (var i = 0; i < _howSteps.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _FadeSlide(
              play: _page == _howIndex,
              delay: Duration(milliseconds: 160 + i * 90),
              child: GlassCard(
                child: Row(
                  children: [
                    _iconBox(_howSteps[i].$1),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _howSteps[i].$2,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            _howSteps[i].$3,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        const SizedBox(height: 4),
        _FadeSlide(
          play: _page == _howIndex,
          delay: const Duration(milliseconds: 480),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.lock_outline,
                size: 16,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  'Bilingo measures how long selected apps are in use. It does '
                  'not read your messages or inspect what you do inside those '
                  'apps.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  /// The picked apps' names, for copy like "Instagram and 2 more".
  List<String> get _pickedLabels => [
    for (final a in _apps ?? const <InstalledApp>[])
      if (_picked.contains(a.package)) a.label,
  ];

  /// Setup, part one: apps to watch.
  Widget _setupPage(ThemeData theme) {
    const page = _setupIndex;
    final muted = theme.colorScheme.onSurfaceVariant;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
      child: Column(
        children: [
          _heading(
            theme,
            page,
            'Which apps eat your time?',
            'Optional. I will step in when you scroll them too long.',
          ),
          const SizedBox(height: 20),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Pick the ones you scroll too much. Pick none to skip app '
              'reminders.',
              style: theme.textTheme.bodySmall?.copyWith(color: muted),
            ),
          ),
          const SizedBox(height: 10),
          _appsPicker(theme),
        ],
      ),
    );
  }

  /// Setup, part two: unlock learning and the permissions that what is
  /// switched on needs, on a screen of their own so they are not missed.
  Widget _permissionsPage(ThemeData theme) {
    const page = _permissionsIndex;
    final muted = theme.colorScheme.onSurfaceVariant;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
      child: Column(
        children: [
          _heading(
            theme,
            page,
            'Let me in',
            'Allow what your reminders need, so I can pop in with words.',
          ),
          const SizedBox(height: 20),
          _sectionLabel(theme, 'Unlock learning'),
          const SizedBox(height: 8),
          GlassCard(
            child: Row(
              children: [
                _iconBox(Icons.lock_open_outlined),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'A word when I unlock',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        'A new word each time you unlock your phone',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: muted,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: _unlockLearning,
                  onChanged: (v) {
                    HapticFeedback.selectionClick();
                    setState(() => _unlockLearning = v);
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          _permissions(theme),
        ],
      ),
    );
  }

  Widget _appsPicker(ThemeData theme) {
    final apps = _apps;
    final q = _query.trim().toLowerCase();
    final shown = apps == null
        ? const <InstalledApp>[]
        : (q.isEmpty
              ? apps
              : apps.where((a) => a.label.toLowerCase().contains(q)).toList());
    // Suggested time-wasters first, then everything else A to Z.
    final ordered = [
      ...shown.where((a) => _timeSinks.contains(a.package)),
      ...shown.where((a) => !_timeSinks.contains(a.package)),
    ];
    // Two rows until asked for more, so the rest of setup stays in reach.
    final collapsed =
        !_showAllApps && q.isEmpty && ordered.length > _collapsedApps;
    final visible = collapsed ? ordered.take(_collapsedApps).toList() : ordered;
    return Column(
      children: [
        TextField(
          onChanged: (v) => setState(() => _query = v),
          textInputAction: TextInputAction.search,
          decoration: const InputDecoration(
            hintText: 'Search apps',
            prefixIcon: Icon(Icons.search),
          ),
        ),
        const SizedBox(height: 12),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          transitionBuilder: (child, animation) =>
              ScaleTransition(scale: animation, child: child),
          child: Text(
            _picked.isEmpty
                ? 'Nothing picked: app reminders are off'
                : '${_picked.length} ${_picked.length == 1 ? 'app' : 'apps'} picked',
            key: ValueKey(_picked.length),
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
              color: _picked.isEmpty
                  ? theme.colorScheme.onSurfaceVariant
                  : kBrandBlue,
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (apps == null)
          const Padding(
            padding: EdgeInsets.all(32),
            child: CircularProgressIndicator(),
          )
        else if (ordered.isEmpty)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              q.isEmpty ? 'No apps found' : 'No apps match "$_query"',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          )
        else ...[
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 96,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 0.82,
            ),
            itemCount: visible.length,
            itemBuilder: (context, i) {
              final app = visible[i];
              return _AppTile(
                app: app,
                selected: _picked.contains(app.package),
                onTap: () {
                  HapticFeedback.selectionClick();
                  final adding = !_picked.contains(app.package);
                  if (adding &&
                      !PremiumStore.instance.isPremium &&
                      _picked.length >= kFreeTrackedApps) {
                    ScaffoldMessenger.of(context)
                      ..hideCurrentSnackBar()
                      ..showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Free covers $kFreeTrackedApps apps. Premium '
                            'unlocks more, any time in Profile.',
                          ),
                        ),
                      );
                    return;
                  }
                  setState(() {
                    if (!_picked.remove(app.package)) _picked.add(app.package);
                  });
                },
              );
            },
          ),
          if (q.isEmpty && ordered.length > _collapsedApps)
            TextButton.icon(
              onPressed: () => setState(() => _showAllApps = !_showAllApps),
              icon: Icon(
                _showAllApps
                    ? Icons.expand_less_rounded
                    : Icons.expand_more_rounded,
              ),
              label: Text(
                _showAllApps ? 'Show fewer' : 'Show all ${ordered.length} apps',
              ),
            ),
        ],
      ],
    );
  }

  void _setLimit(int minutes) {
    if (minutes == _limit) return;
    HapticFeedback.selectionClick();
    setState(() => _limit = minutes);
  }

  /// Setup, part two: how long before a reminder, with a preview of the
  /// notification. Only shown when apps are picked.
  Widget _reminderPage(ThemeData theme) {
    final sample = _samples.isNotEmpty ? _samples.first : null;
    final labels = _pickedLabels;
    final first = labels.isEmpty ? 'your apps' : labels.first;
    final summary = labels.length > 1
        ? '$first and ${labels.length - 1} more'
        : first;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
      child: Column(
        children: [
          _heading(
            theme,
            _reminderIndex,
            'How long before I step in?',
            'After this long in a row on $summary, I pop in with a new word.',
          ),
          const SizedBox(height: 24),
          GlassCard(
            padding: const EdgeInsets.fromLTRB(12, 18, 12, 10),
            child: Column(
              children: [
                Row(
                  children: [
                    IconButton.filledTonal(
                      tooltip: 'One minute less',
                      onPressed: _limit > _minLimit
                          ? () => _setLimit(_limit - 1)
                          : null,
                      icon: const Icon(Icons.remove_rounded),
                    ),
                    Expanded(
                      child: Text(
                        '$_limit ${_limit == 1 ? 'minute' : 'minutes'}',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: kBrandBlue,
                        ),
                      ),
                    ),
                    IconButton.filledTonal(
                      tooltip: 'One minute more',
                      onPressed: _limit < _maxLimit
                          ? () => _setLimit(_limit + 1)
                          : null,
                      icon: const Icon(Icons.add_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Semantics(
                  label: 'Minutes before a reminder',
                  value: '$_limit',
                  child: Slider(
                    value: _limit.toDouble(),
                    min: _minLimit.toDouble(),
                    max: _maxLimit.toDouble(),
                    divisions: _maxLimit - _minLimit,
                    label: '$_limit min',
                    onChanged: (v) => _setLimit(v.round()),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '$_minLimit min',
                        style: theme.textTheme.labelMedium,
                      ),
                      Text(
                        '$_maxLimit min',
                        style: theme.textTheme.labelMedium,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // A mock of the real notification, updating with the chosen limit.
          GlassCard(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(
                  width: 44,
                  height: 44,
                  child: FittedBox(
                    child: Mascot(size: 120, mood: GhostMood.surprised),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 250),
                        child: Text(
                          'BiLingo  ·  $_limit min on $first',
                          key: ValueKey(_limit),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        "Enough scrolling! Let's learn something new",
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        sample == null
                            ? 'A new word and its meaning'
                            : '${sample.word}  ·  ${sample.meaning}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Switching between picked apps keeps the clock running. '
            'Leaving them or locking your phone resets it.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  /// Only the permissions the switched-on features need.
  Widget _permissions(ThemeData theme) {
    final total = _relevantGrants.length;
    if (total == 0) {
      return Text(
        'Reminders are off, so I need no permissions. WordFlow is always '
        'there when you open BiLingo.',
        textAlign: TextAlign.center,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
    }
    final allSet = _grantedCount == total;
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: _sectionLabel(theme, 'Permissions')),
            // Progress pill: counts up as each permission comes back granted.
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              transitionBuilder: (child, animation) =>
                  ScaleTransition(scale: animation, child: child),
              child: Container(
                key: ValueKey('$_grantedCount/$total'),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: (allSet ? Colors.green : kBrandBlue).withValues(
                    alpha: 0.14,
                  ),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  allSet
                      ? 'All set. Boo-tiful!'
                      : '$_grantedCount of $total ready',
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: allSet ? Colors.green.shade700 : kBrandBlue,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _permissionTile(
          theme,
          icon: Icons.notifications_outlined,
          title: 'Notifications',
          subtitle: 'So I can pop in with a word',
          tag: 'Needed',
          granted: _notificationsOk,
          onAllow: _allowNotifications,
        ),
        if (_monitoring) ...[
          const SizedBox(height: 12),
          _permissionTile(
            theme,
            icon: Icons.hourglass_bottom_outlined,
            title: 'Usage access',
            subtitle: 'So I know when you have scrolled too long',
            tag: 'Needed',
            granted: _usageOk,
            onAllow: _allowUsage,
          ),
        ],
        const SizedBox(height: 12),
        _permissionTile(
          theme,
          icon: Icons.battery_charging_full_outlined,
          title: 'Background activity',
          subtitle: 'So your phone does not put me to sleep',
          tag: 'Recommended',
          granted: _batteryOk,
          onAllow: _allowBattery,
        ),
        const SizedBox(height: 16),
        Text(
          _notificationsOk
              ? 'You can change these any time in your phone settings.'
              : 'Without notifications I cannot show you words. '
                    'You can turn them on later from Profile.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _permissionTile(
    ThemeData theme, {
    required IconData icon,
    required String title,
    required String subtitle,
    required String tag,
    required bool granted,
    required VoidCallback onAllow,
  }) => GlassCard(
    child: Row(
      children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: kBrandBlue.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, color: kBrandBlue),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    tag.toUpperCase(),
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                      color: tag == 'Needed'
                          ? const Color(0xFFE5533D)
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              Text(
                subtitle,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        // The button turns into a tick with a little pop once granted.
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 350),
          switchInCurve: Curves.easeOutBack,
          transitionBuilder: (child, animation) =>
              ScaleTransition(scale: animation, child: child),
          child: granted
              ? const Icon(
                  Icons.check_circle,
                  key: ValueKey('ok'),
                  color: Colors.green,
                  size: 30,
                )
              : FilledButton.tonal(
                  key: const ValueKey('allow'),
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
                  onPressed: onAllow,
                  child: const Text('Allow'),
                ),
        ),
      ],
    ),
  );
}

/// One app in the picker: icon, name, and a tick badge that pops in when picked.
class _AppTile extends StatelessWidget {
  const _AppTile({
    required this.app,
    required this.selected,
    required this.onTap,
  });

  final InstalledApp app;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedScale(
        scale: selected ? 1.0 : 0.94,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutBack,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          padding: const EdgeInsets.fromLTRB(6, 10, 6, 6),
          decoration: BoxDecoration(
            color: selected
                ? kBrandBlue.withValues(alpha: dark ? 0.25 : 0.12)
                : (dark
                      ? const Color(0x22FFFFFF)
                      : Colors.white.withValues(alpha: 0.75)),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected ? kBrandBlue : Colors.transparent,
              width: 2,
            ),
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Align(
                alignment: Alignment.topCenter,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.memory(
                        app.icon,
                        width: 42,
                        height: 42,
                        gaplessPlayback: true,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      app.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(
                top: -6,
                right: -2,
                child: AnimatedScale(
                  scale: selected ? 1 : 0,
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOutBack,
                  child: const Icon(
                    Icons.check_circle,
                    color: kBrandBlue,
                    size: 20,
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

/// Where the usage-access sheet sends the user next.
enum _UsageStep { settings, appInfo }

/// Shown before opening Settings: usage access has no pop-up, so say what to
/// tap. Android 13+ also blocks this switch for apps installed outside an app
/// store ("App was denied access"); the [blocked] view explains how to lift it.
class _UsageAccessSheet extends StatefulWidget {
  const _UsageAccessSheet({required this.blocked});

  final bool blocked;

  @override
  State<_UsageAccessSheet> createState() => _UsageAccessSheetState();
}

class _UsageAccessSheetState extends State<_UsageAccessSheet> {
  late bool _blocked = widget.blocked;

  static const _steps = [
    'Find BiLingo in the list',
    'Turn on "Permit usage access"',
    'Come back here, I will be waiting',
  ];

  static const _unblockSteps = [
    'Tap "Open App info" below',
    'Tap ⋮ in the top right corner',
    'Tap "Allow restricted settings" and confirm',
    'Come back and turn on usage access',
  ];

  Widget _step(ThemeData theme, int i, String text) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(
      children: [
        CircleAvatar(
          radius: 13,
          backgroundColor: kBrandBlue.withValues(alpha: 0.15),
          child: Text(
            '${i + 1}',
            style: theme.textTheme.labelLarge?.copyWith(
              color: kBrandBlue,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(child: Text(text, style: theme.textTheme.bodyLarge)),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
        child: AnimatedSize(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Mascot(
                size: 96,
                talking: true,
                mood: _blocked ? GhostMood.sad : GhostMood.wink,
              ),
              const SizedBox(height: 8),
              Text(
                _blocked
                    ? 'Your phone blocked the switch'
                    : 'One switch in Settings',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _blocked
                    ? 'Android blocks usage access for apps installed outside '
                          'the Play Store and shows "App was denied access". '
                          'It takes four taps to allow it:'
                    : 'I only count minutes per app. I never see your '
                          'messages, posts or screen.',
                textAlign: TextAlign.center,
                style: muted,
              ),
              const SizedBox(height: 16),
              for (final (i, text)
                  in (_blocked ? _unblockSteps : _steps).indexed)
                _step(theme, i, text),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.of(context)
                      .pop(_blocked ? _UsageStep.appInfo : _UsageStep.settings),
                  child: Text(_blocked ? 'Open App info' : 'Open Settings'),
                ),
              ),
              if (_blocked)
                TextButton(
                  onPressed: () =>
                      Navigator.of(context).pop(_UsageStep.settings),
                  child: const Text('Already allowed? Open usage access'),
                )
              else
                TextButton(
                  onPressed: () => setState(() => _blocked = true),
                  child: const Text('Phone says "App was denied access"?'),
                ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Not now'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Fades and drifts the page as it scrolls in or out, so steps blend instead of cutting.
class _PageFx extends StatelessWidget {
  const _PageFx({
    required this.controller,
    required this.index,
    required this.child,
  });

  final PageController controller;
  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      child: child,
      builder: (context, child) {
        final page = controller.hasClients
            ? (controller.page ?? controller.initialPage.toDouble())
            : controller.initialPage.toDouble();
        final delta = page - index; // <0: page is ahead, >0: page is behind
        final visibility = (1 - delta.abs()).clamp(0.0, 1.0);
        return Opacity(
          opacity: visibility,
          child: Transform.translate(
            offset: Offset(-delta * 36, 0),
            child: child,
          ),
        );
      },
    );
  }
}

/// Fades in and slides up when [play] becomes true (after [delay]); eases back out when false.
class _FadeSlide extends StatefulWidget {
  const _FadeSlide({
    required this.play,
    required this.child,
    this.delay = Duration.zero,
  });

  final bool play;
  final Widget child;
  final Duration delay;

  @override
  State<_FadeSlide> createState() => _FadeSlideState();
}

class _FadeSlideState extends State<_FadeSlide>
    with SingleTickerProviderStateMixin {
  static const _run = Duration(milliseconds: 520);

  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: _run + widget.delay,
    reverseDuration: const Duration(milliseconds: 200),
  );
  late final Animation<double> _t = CurvedAnimation(
    parent: _c,
    curve: Interval(
      widget.delay.inMilliseconds / (_run + widget.delay).inMilliseconds,
      1,
      curve: Curves.easeOutCubic,
    ),
  );

  @override
  void initState() {
    super.initState();
    if (widget.play) _c.forward();
  }

  @override
  void didUpdateWidget(_FadeSlide old) {
    super.didUpdateWidget(old);
    if (widget.play != old.play) {
      widget.play ? _c.forward(from: 0) : _c.reverse();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _t,
      child: SlideTransition(
        position: Tween(
          begin: const Offset(0, 0.25),
          end: Offset.zero,
        ).animate(_t),
        child: widget.child,
      ),
    );
  }
}
