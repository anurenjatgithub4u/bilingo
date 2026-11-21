import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/premium_store.dart';
import '../services/word_service.dart';
import 'app_theme.dart';
import 'premium_screen.dart';

/// Which apps Scroll Patrol times, and after how many minutes it warns.
/// Free covers [kFreeTrackedApps] apps; Premium has no limit.
class TrackedAppsScreen extends StatefulWidget {
  const TrackedAppsScreen({super.key, this.service = const WordService()});

  final WordService service;

  @override
  State<TrackedAppsScreen> createState() => _TrackedAppsScreenState();
}

class _TrackedAppsScreenState extends State<TrackedAppsScreen>
    with WidgetsBindingObserver {
  static const _minLimit = 1;
  static const _maxLimit = 60;

  WordState? _state;
  List<InstalledApp>? _apps;
  final Set<String> _picked = {};
  int _limit = 5;
  String _query = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    PremiumStore.instance.addListener(_refresh);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    PremiumStore.instance.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  /// Back from Settings (usage access): read the state again.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
  }

  Future<void> _load() async {
    try {
      final state = await widget.service.getState();
      final apps = _apps ?? await widget.service.installedApps();
      if (!mounted) return;
      setState(() {
        _state = state;
        _apps = apps;
        _picked
          ..clear()
          ..addAll(state.trackedApps);
        _limit = state.limitMinutes.clamp(_minLimit, _maxLimit);
      });
    } catch (_) {
      if (mounted) setState(() => _apps = const []);
    }
  }

  bool get _premium => PremiumStore.instance.isPremium;

  Future<void> _save() async {
    try {
      final state = await widget.service.update(
        trackedApps: _picked,
        limitMinutes: _limit,
      );
      if (mounted) setState(() => _state = state);
    } catch (_) {
      // No native side.
    }
  }

  Future<void> _toggle(InstalledApp app) async {
    HapticFeedback.selectionClick();
    if (_picked.contains(app.package)) {
      setState(() => _picked.remove(app.package));
    } else if (!_premium && _picked.length >= kFreeTrackedApps) {
      await showPremium(
        context,
        reason: 'Free covers up to $kFreeTrackedApps tracked apps.',
      );
      return;
    } else {
      setState(() => _picked.add(app.package));
    }
    await _save();
  }

  /// The background helper must run for limits to work.
  Future<void> _turnOn() async {
    try {
      final granted = await widget.service.requestNotificationPermission();
      if (!granted) return;
      final state = await widget.service.update(enabled: true);
      if (mounted) setState(() => _state = state);
    } catch (_) {
      // No native side.
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final state = _state;
    final apps = _apps;
    final q = _query.trim().toLowerCase();
    final shown = apps == null
        ? const <InstalledApp>[]
        : [
                // Picked ones first, so they're easy to find and remove.
                ...apps.where((a) => _picked.contains(a.package)),
                ...apps.where((a) => !_picked.contains(a.package)),
              ]
              .where((a) => q.isEmpty || a.label.toLowerCase().contains(q))
              .toList();
    final overFree = !_premium && _picked.length > kFreeTrackedApps;
    return GradientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          title: const Text('Tracked apps'),
        ),
        body: apps == null
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                children: [
                  Text(
                    'BiLingo warns you after this many minutes in a row '
                    'in the apps you pick, then arrests you if you keep going.',
                    style: theme.textTheme.bodyMedium?.copyWith(color: muted),
                  ),
                  const SizedBox(height: 14),
                  if (state != null && !state.usageAccessGranted)
                    _Notice(
                      icon: Icons.lock_clock_rounded,
                      text:
                          'Allow usage access so BiLingo can time these '
                          'apps.',
                      action: 'Allow',
                      onTap: widget.service.openUsageAccessSettings,
                    )
                  else if (state != null && !state.enabled)
                    _Notice(
                      icon: Icons.notifications_off_rounded,
                      text:
                          'Word notifications are off, so limits aren’t '
                          'running.',
                      action: 'Turn on',
                      onTap: _turnOn,
                    ),
                  GlassCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.timer_rounded, color: kBrandBlue),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Warn me after',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            Text(
                              '$_limit min',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w900,
                                color: kBrandBlue,
                              ),
                            ),
                          ],
                        ),
                        Slider(
                          value: _limit.toDouble(),
                          min: _minLimit.toDouble(),
                          max: _maxLimit.toDouble(),
                          divisions: _maxLimit - _minLimit,
                          label: '$_limit min',
                          onChanged: (v) => setState(() => _limit = v.round()),
                          onChangeEnd: (_) => _save(),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _premium
                              ? '${_picked.length} apps tracked'
                              : '${_picked.length} of $kFreeTrackedApps free '
                                    'apps',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      if (!_premium)
                        TextButton.icon(
                          onPressed: () => showPremium(context),
                          icon: const Icon(Icons.workspace_premium_rounded),
                          label: const Text('Unlimited'),
                        ),
                    ],
                  ),
                  if (overFree)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        'You picked these before the free limit. They keep '
                        'working; to add another, remove some first or go '
                        'Premium.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: muted,
                        ),
                      ),
                    ),
                  TextField(
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search_rounded),
                      hintText: 'Search apps',
                    ),
                    onChanged: (v) => setState(() => _query = v),
                  ),
                  const SizedBox(height: 8),
                  if (shown.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        q.isEmpty ? 'No apps found' : 'No apps match "$_query"',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: muted,
                        ),
                      ),
                    ),
                  for (final app in shown)
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _picked.contains(app.package),
                      onChanged: (_) => _toggle(app),
                      secondary: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.memory(
                          app.icon,
                          width: 40,
                          height: 40,
                          gaplessPlayback: true,
                          errorBuilder: (_, _, _) =>
                              const Icon(Icons.apps_rounded, size: 40),
                        ),
                      ),
                      title: Text(
                        app.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({
    required this.icon,
    required this.text,
    required this.action,
    required this.onTap,
  });

  final IconData icon;
  final String text;
  final String action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFB627).withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFFE08A00)),
          const SizedBox(width: 10),
          Expanded(child: Text(text)),
          TextButton(onPressed: onTap, child: Text(action)),
        ],
      ),
    ),
  );
}
