import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../app_info.dart';
import '../services/premium_store.dart';
import '../services/word_service.dart';
import 'app_theme.dart';
import 'mascot.dart';

const _gold = Color(0xFFFFB627);
const _goldDeep = Color(0xFFE08A00);

/// Opens the Premium screen. [reason] says what the learner just ran into,
/// e.g. the free Hard limit.
Future<void> showPremium(BuildContext context, {String? reason}) =>
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => PremiumScreen(reason: reason)),
    );

/// BiLingo Premium: what it adds, the plans from Google Play, and restore.
class PremiumScreen extends StatefulWidget {
  const PremiumScreen({super.key, this.reason});

  final String? reason;

  @override
  State<PremiumScreen> createState() => _PremiumScreenState();
}

class _PremiumScreenState extends State<PremiumScreen> {
  final _store = PremiumStore.instance;
  String _selected = kPremiumYearly;

  @override
  void initState() {
    super.initState();
    _store.addListener(_onStore);
    // Plans may not have loaded on the first start (offline, say).
    if (_store.plans.isEmpty) _store.loadPlans();
  }

  @override
  void dispose() {
    _store.removeListener(_onStore);
    super.dispose();
  }

  bool _wasPremium = PremiumStore.instance.isPremium;

  void _onStore() {
    if (!mounted) return;
    if (_store.isPremium && !_wasPremium) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Welcome to Premium! ✨')));
    }
    _wasPremium = _store.isPremium;
    setState(() {});
  }

  ProductDetails? get _plan {
    for (final p in _store.plans) {
      if (p.id == _selected) return p;
    }
    return _store.plans.firstOrNull;
  }

  Future<void> _manage() async {
    try {
      await const WordService().openUrl(
        'https://play.google.com/store/account/subscriptions'
        '?sku=${_store.product ?? ''}&package=$kPackageId',
      );
    } catch (_) {
      // No native side.
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final premium = _store.isPremium;
    return GradientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          title: const Text('Premium'),
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
          children: [
            Stack(
              alignment: Alignment.topCenter,
              children: [
                const Center(child: Mascot(size: 150, mood: GhostMood.love)),
                Positioned(
                  top: 0,
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(colors: [_gold, _goldDeep]),
                    ),
                    child: const Icon(
                      Icons.workspace_premium_rounded,
                      color: Colors.white,
                      size: 26,
                    ),
                  ),
                ),
              ],
            ),
            Text(
              premium ? 'You’re Premium ✨' : '$kAppName Premium',
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              premium
                  ? 'Thank you for supporting $kAppName.'
                  : widget.reason ?? 'Learn without limits, and without ads.',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(color: muted),
            ),
            const SizedBox(height: 22),
            const GlassCard(
              padding: EdgeInsets.symmetric(vertical: 6, horizontal: 14),
              child: Column(
                children: [
                  _Benefit(
                    icon: Icons.block_rounded,
                    title: 'No ads',
                    free: 'Free: an ad every few reels',
                  ),
                  _Benefit(
                    icon: Icons.apps_rounded,
                    title: 'Unlimited tracked apps',
                    free: 'Free: up to $kFreeTrackedApps apps',
                  ),
                  _Benefit(
                    icon: Icons.local_fire_department_rounded,
                    title: 'Unlimited Hard reels',
                    free: 'Free: $kFreeHardPerDay a day',
                    last: true,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            if (premium) ...[
              if (_store.product != null)
                OutlinedButton.icon(
                  onPressed: _manage,
                  icon: const Icon(Icons.manage_accounts_rounded),
                  label: const Text('Manage subscription'),
                ),
            ] else if (_store.plans.isEmpty)
              GlassCard(
                child: Text(
                  _store.storeAvailable
                      ? 'Premium isn’t on sale yet. Please check back soon.'
                      : 'Google Play isn’t available on this phone, so '
                            'Premium can’t be bought here.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(color: muted),
                ),
              )
            else ...[
              for (final p in _store.plans)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _PlanCard(
                    plan: p,
                    selected: p.id == _plan?.id,
                    onTap: () => setState(() => _selected = p.id),
                  ),
                ),
              const SizedBox(height: 6),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: _gold,
                  foregroundColor: Colors.black87,
                  minimumSize: const Size.fromHeight(54),
                ),
                onPressed: _store.busy || _plan == null
                    ? null
                    : () => _store.buy(_plan!),
                child: _store.busy
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      )
                    : const Text(
                        'Continue',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
              ),
            ],
            if (_store.error case final error?) ...[
              const SizedBox(height: 10),
              Text(
                error,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFFE5484D)),
              ),
            ],
            if (_store.storeAvailable)
              TextButton(
                onPressed: _store.busy ? null : () => _store.restore(),
                child: const Text('Restore purchases'),
              ),
            const SizedBox(height: 8),
            Text(
              'Subscriptions renew automatically until cancelled. Cancel any '
              'time in Google Play → Payments & subscriptions. Payment is '
              'charged to your Google Play account.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(color: muted),
            ),
            if (!kReleaseMode) ...[
              const SizedBox(height: 16),
              SwitchListTile(
                title: const Text('Developer: pretend Premium'),
                subtitle: const Text(
                  'Debug and profile builds only, to try Premium before Play '
                  'is set up.',
                ),
                value: _store.testPremium,
                onChanged: _store.setTestPremium,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Benefit extends StatelessWidget {
  const _Benefit({
    required this.icon,
    required this.title,
    required this.free,
    this.last = false,
  });

  final IconData icon;
  final String title;
  final String free;
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
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: _gold.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: _goldDeep, size: 22),
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
                Text(
                  free,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.check_circle_rounded, color: Color(0xFF2EB67D)),
        ],
      ),
    );
  }
}

/// One plan from Google Play, with its price as Play shows it.
class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.plan,
    required this.selected,
    required this.onTap,
  });

  final ProductDetails plan;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final yearly = plan.id == kPremiumYearly;
    final perMonth = yearly
        ? '${plan.currencySymbol}${(plan.rawPrice / 12).toStringAsFixed(0)} '
              'a month'
        : null;
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: theme.colorScheme.surface.withValues(alpha: 0.9),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(
            color: selected ? _goldDeep : theme.colorScheme.outlineVariant,
            width: selected ? 2.5 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(
                  selected
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_off_rounded,
                  color: selected ? _goldDeep : theme.colorScheme.outline,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            yearly ? 'Yearly' : 'Monthly',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          if (yearly) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: _gold,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Text(
                                'Best value',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.black87,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      if (perMonth != null)
                        Text(
                          perMonth,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
                Text(
                  plan.price,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
