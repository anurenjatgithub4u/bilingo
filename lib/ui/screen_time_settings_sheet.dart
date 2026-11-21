import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/screen_time_store.dart';
import 'app_theme.dart';

/// Modal bottom sheet to manage flexible screen-time settings:
/// - Today's temporary customized limit
/// - Default daily limit
/// - Optional weekly schedule (Mon - Sun)
class ScreenTimeSettingsSheet extends StatefulWidget {
  const ScreenTimeSettingsSheet({super.key});

  static Future<void> show(BuildContext context) => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => const ScreenTimeSettingsSheet(),
      );

  @override
  State<ScreenTimeSettingsSheet> createState() => _ScreenTimeSettingsSheetState();
}

class _ScreenTimeSettingsSheetState extends State<ScreenTimeSettingsSheet>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl = TabController(length: 3, vsync: this);
  final store = ScreenTimeStore.instance;

  @override
  void initState() {
    super.initState();
    store.addListener(_onStoreChanged);
  }

  @override
  void dispose() {
    store.removeListener(_onStoreChanged);
    _tabCtrl.dispose();
    super.dispose();
  }

  void _onStoreChanged() {
    if (mounted) setState(() {});
  }

  static String _formatMinutes(int minutes) {
    final h = minutes ~/ 60;
    final m = minutes % 60;
    if (h > 0) {
      return m > 0 ? '$h h $m m' : '$h Hours';
    }
    return '$m Minutes';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final now = DateTime.now();
    final effective = store.effectiveLimitMinutes(now);

    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF1C1E26) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          // Drag handle
          Center(
            child: Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Screen-Time Limits',
                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Effective Today: ${_formatMinutes(effective)}',
                        style: const TextStyle(
                          color: kBrandBlue,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          TabBar(
            controller: _tabCtrl,
            labelColor: kBrandBlue,
            unselectedLabelColor: theme.colorScheme.onSurfaceVariant,
            indicatorColor: kBrandBlue,
            labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            tabs: const [
              Tab(text: "Today's Limit"),
              Tab(text: 'Default Limit'),
              Tab(text: 'Weekly Schedule'),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabCtrl,
              children: [
                _TodayLimitTab(now: now),
                const _DefaultLimitTab(),
                const _WeeklyScheduleTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TodayLimitTab extends StatelessWidget {
  const _TodayLimitTab({required this.now});

  final DateTime now;

  static const _presets = [60, 90, 120, 150, 180, 240];

  @override
  Widget build(BuildContext context) {
    final store = ScreenTimeStore.instance;
    final custom = store.todayCustomLimitMinutes;

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          "Change Today's Screen-Time Limit",
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
        ),
        const SizedBox(height: 6),
        Text(
          'Temporarily adjust your limit for today. Tomorrow will automatically revert back to your default schedule.',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 12.5,
          ),
        ),
        const SizedBox(height: 18),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final m in _presets)
              ChoiceChip(
                label: Text(_ScreenTimeSettingsSheetState._formatMinutes(m)),
                selected: custom == m,
                onSelected: (sel) {
                  HapticFeedback.selectionClick();
                  store.setTodayCustomLimit(sel ? m : null, now);
                },
                selectedColor: kBrandBlue,
                labelStyle: TextStyle(
                  color: custom == m ? Colors.white : null,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
          ],
        ),
        const SizedBox(height: 24),
        if (custom != null) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: kBrandBlue.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline_rounded, size: 18, color: kBrandBlue),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Custom limit active: ${_ScreenTimeSettingsSheetState._formatMinutes(custom)} today',
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                  ),
                ),
                TextButton(
                  onPressed: () => store.setTodayCustomLimit(null, now),
                  child: const Text('Reset', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
          ),
        ] else ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Row(
              children: [
                Icon(Icons.check_circle_outline_rounded, size: 18, color: Colors.grey),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Using standard default limit today.',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _DefaultLimitTab extends StatelessWidget {
  const _DefaultLimitTab();

  static const _options = [60, 90, 120, 150, 180, 210, 240, 300];

  @override
  Widget build(BuildContext context) {
    final store = ScreenTimeStore.instance;
    final current = store.defaultDailyLimitMinutes;

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'Default Daily Limit',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
        ),
        const SizedBox(height: 6),
        Text(
          'Your baseline daily limit. This applies to all regular days unless overridden by a custom limit or weekly schedule.',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 12.5,
          ),
        ),
        const SizedBox(height: 18),
        for (final m in _options)
          RadioListTile<int>(
            value: m,
            groupValue: current,
            title: Text(
              _ScreenTimeSettingsSheetState._formatMinutes(m),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            activeColor: kBrandBlue,
            onChanged: (v) {
              if (v != null) {
                HapticFeedback.selectionClick();
                store.setDefaultDailyLimit(v);
              }
            },
          ),
      ],
    );
  }
}

class _WeeklyScheduleTab extends StatelessWidget {
  const _WeeklyScheduleTab();

  static const _days = [
    (DateTime.monday, 'Monday'),
    (DateTime.tuesday, 'Tuesday'),
    (DateTime.wednesday, 'Wednesday'),
    (DateTime.thursday, 'Thursday'),
    (DateTime.friday, 'Friday'),
    (DateTime.saturday, 'Saturday'),
    (DateTime.sunday, 'Sunday'),
  ];

  @override
  Widget build(BuildContext context) {
    final store = ScreenTimeStore.instance;
    final enabled = store.weeklyScheduleEnabled;
    final schedule = store.weeklySchedule;

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Row(
          children: [
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Optional Weekly Schedule',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Configure different limits for different weekdays.',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),
            Switch(
              value: enabled,
              activeColor: kBrandBlue,
              onChanged: (v) => store.setWeeklyScheduleEnabled(v),
            ),
          ],
        ),
        const Divider(height: 24),
        if (!enabled)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Text(
                'Weekly scheduling is disabled.\nAll days use your Default Daily Limit.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
            ),
          )
        else
          for (final (dayCode, dayName) in _days) ...[
            _WeekdayLimitRow(
              dayName: dayName,
              currentMinutes: schedule[dayCode] ?? store.defaultDailyLimitMinutes,
              onChanged: (newMin) => store.setWeekdayLimit(dayCode, newMin),
            ),
            const Divider(height: 12),
          ],
      ],
    );
  }
}

class _WeekdayLimitRow extends StatelessWidget {
  const _WeekdayLimitRow({
    required this.dayName,
    required this.currentMinutes,
    required this.onChanged,
  });

  final String dayName;
  final int currentMinutes;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(dayName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
          ),
          const Spacer(),
          DropdownButton<int>(
            value: currentMinutes,
            underline: const SizedBox.shrink(),
            items: [
              for (final m in [60, 90, 120, 150, 180, 210, 240, 300])
                DropdownMenuItem(
                  value: m,
                  child: Text(
                    _ScreenTimeSettingsSheetState._formatMinutes(m),
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                ),
            ],
            onChanged: (v) {
              if (v != null) onChanged(v);
            },
          ),
        ],
      ),
    );
  }
}
