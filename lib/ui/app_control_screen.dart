import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/app_block_store.dart';
import '../services/word_service.dart';
import 'app_theme.dart';

/// Screen where users discover installed apps, select apps to block,
/// configure blocking durations, and manage currently blocked apps.
class AppControlScreen extends StatefulWidget {
  const AppControlScreen({super.key, this.service = const WordService()});

  final WordService service;

  @override
  State<AppControlScreen> createState() => _AppControlScreenState();
}

class _AppControlScreenState extends State<AppControlScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  List<InstalledApp>? _allApps;
  final Set<String> _selectedPackages = {};
  String _query = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
    AppBlockStore.instance.addListener(_onBlocksChanged);
  }

  @override
  void dispose() {
    AppBlockStore.instance.removeListener(_onBlocksChanged);
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onBlocksChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    try {
      await AppBlockStore.instance.ensureLoaded();
      final apps = await widget.service.installedApps();
      if (!mounted) return;
      setState(() {
        _allApps = apps;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _toggleSelect(String package) {
    HapticFeedback.selectionClick();
    setState(() {
      if (_selectedPackages.contains(package)) {
        _selectedPackages.remove(package);
      } else {
        _selectedPackages.add(package);
      }
    });
  }

  Future<void> _showDurationSheet() async {
    if (_selectedPackages.isEmpty) return;

    final selectedApps = [
      for (final app in _allApps ?? const <InstalledApp>[])
        if (_selectedPackages.contains(app.package)) (app.package, app.label),
    ];

    final duration = await showModalBottomSheet<Duration>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _BlockingDurationPickerSheet(count: selectedApps.length),
    );

    if (duration == null || !mounted) return;

    // Review & Confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => _ConfirmBlockDialog(
        apps: selectedApps,
        duration: duration,
      ),
    );

    if (confirmed == true && mounted) {
      await AppBlockStore.instance.blockApps(
        apps: selectedApps,
        duration: duration,
        blockType: 'manual',
      );
      setState(() => _selectedPackages.clear());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${selectedApps.length} ${selectedApps.length == 1 ? 'app' : 'apps'} blocked for ${_formatDuration(duration)}',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  static String _formatDuration(Duration d) {
    if (d.inHours > 0) {
      final m = d.inMinutes % 60;
      return m > 0 ? '${d.inHours}h ${m}m' : '${d.inHours}h';
    }
    return '${d.inMinutes}m';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final blockStore = AppBlockStore.instance;

    final blockedList = blockStore.blockedApps;
    final all = _allApps ?? const <InstalledApp>[];
    final q = _query.trim().toLowerCase();

    final filtered = q.isEmpty
        ? all
        : all.where((a) => a.label.toLowerCase().contains(q) || a.package.toLowerCase().contains(q)).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('App Control & Blocking', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
        centerTitle: true,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Search box
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: TextField(
                    controller: _searchCtrl,
                    onChanged: (v) => setState(() => _query = v),
                    decoration: InputDecoration(
                      hintText: 'Search installed apps...',
                      prefixIcon: const Icon(Icons.search_rounded, size: 20),
                      suffixIcon: _query.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear_rounded, size: 18),
                              onPressed: () {
                                _searchCtrl.clear();
                                setState(() => _query = '');
                              },
                            )
                          : null,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                  ),
                ),

                // Currently Blocked Apps Banner (if any)
                if (blockedList.isNotEmpty && _query.isEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: dark ? const Color(0xFF2B1D24) : const Color(0xFFFFECEF),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: const Color(0xFFE5484D).withValues(alpha: 0.3),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.lock_rounded, size: 16, color: Color(0xFFE5484D)),
                              const SizedBox(width: 6),
                              Text(
                                '${blockedList.length} Currently Blocked ${blockedList.length == 1 ? 'App' : 'Apps'}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 13,
                                  color: Color(0xFFE5484D),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final blocked in blockedList)
                                Chip(
                                  avatar: const Icon(Icons.block_rounded, size: 16, color: Color(0xFFE5484D)),
                                  label: Text(
                                    '${blocked.label.isNotEmpty ? blocked.label : blocked.packageName} (${blocked.formattedRemaining})',
                                    style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
                                  ),
                                  deleteIcon: const Icon(Icons.lock_open_rounded, size: 16),
                                  onDeleted: () => blockStore.unblockApp(blocked.packageName),
                                  backgroundColor: dark ? const Color(0xFF38181A) : Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    side: BorderSide(
                                      color: const Color(0xFFE5484D).withValues(alpha: 0.25),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],

                // App list header
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                  child: Row(
                    children: [
                      Text(
                        'INSTALLED APPS (${filtered.length})',
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.2,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const Spacer(),
                      if (_selectedPackages.isNotEmpty)
                        TextButton(
                          onPressed: () => setState(() => _selectedPackages.clear()),
                          child: const Text('Clear selection', style: TextStyle(fontSize: 12)),
                        ),
                    ],
                  ),
                ),

                // App list
                Expanded(
                  child: filtered.isEmpty
                      ? Center(
                          child: Text(
                            q.isEmpty ? 'No installed apps found' : 'No apps match "$q"',
                            style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                          ),
                        )
                      : ListView.builder(
                          itemCount: filtered.length,
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                          itemBuilder: (context, i) {
                            final app = filtered[i];
                            final isBlocked = blockStore.isBlocked(app.package);
                            final blockedItem = blockStore.getBlock(app.package);
                            final isSelected = _selectedPackages.contains(app.package);

                            return Card(
                              elevation: 0,
                              color: isSelected
                                  ? kBrandBlue.withValues(alpha: 0.1)
                                  : (dark ? const Color(0xFF1E2028) : Colors.white),
                              margin: const EdgeInsets.only(bottom: 8),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                                side: BorderSide(
                                  color: isSelected
                                      ? kBrandBlue
                                      : (isBlocked
                                          ? const Color(0xFFE5484D).withValues(alpha: 0.4)
                                          : (dark ? const Color(0x1AFFFFFF) : const Color(0xFFEDF0F7))),
                                  width: isSelected ? 1.5 : 1,
                                ),
                              ),
                              child: ListTile(
                                leading: ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: Image.memory(
                                    app.icon,
                                    width: 40,
                                    height: 40,
                                    errorBuilder: (_, __, ___) => Container(
                                      width: 40,
                                      height: 40,
                                      color: Colors.grey.shade200,
                                      child: const Icon(Icons.android_rounded),
                                    ),
                                  ),
                                ),
                                title: Text(
                                  app.label,
                                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5),
                                ),
                                subtitle: isBlocked
                                    ? Text(
                                        'Blocked · ${blockedItem?.formattedRemaining ?? ''}',
                                        style: const TextStyle(
                                          color: Color(0xFFE5484D),
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      )
                                    : Text(
                                        app.package,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: theme.colorScheme.onSurfaceVariant,
                                          fontSize: 11.5,
                                        ),
                                      ),
                                trailing: isBlocked
                                    ? TextButton.icon(
                                        icon: const Icon(Icons.lock_open_rounded, size: 16),
                                        label: const Text('Unblock', style: TextStyle(fontSize: 12)),
                                        style: TextButton.styleFrom(foregroundColor: const Color(0xFFE5484D)),
                                        onPressed: () => blockStore.unblockApp(app.package),
                                      )
                                    : Checkbox(
                                        value: isSelected,
                                        activeColor: kBrandBlue,
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
                                        onChanged: (_) => _toggleSelect(app.package),
                                      ),
                                onTap: isBlocked ? null : () => _toggleSelect(app.package),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
      bottomSheet: _selectedPackages.isEmpty
          ? null
          : Container(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              decoration: BoxDecoration(
                color: dark ? const Color(0xFF1E2028) : Colors.white,
                boxShadow: const [
                  BoxShadow(color: Color(0x1F000000), blurRadius: 16, offset: Offset(0, -4)),
                ],
              ),
              child: SafeArea(
                top: false,
                child: Row(
                  children: [
                    Text(
                      '${_selectedPackages.length} selected',
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                    ),
                    const Spacer(),
                    FilledButton.icon(
                      icon: const Icon(Icons.lock_rounded, size: 18),
                      label: const Text('Block Selected'),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFE5484D),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      onPressed: _showDurationSheet,
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

/// Modal bottom sheet providing flexible blocking duration options.
class _BlockingDurationPickerSheet extends StatefulWidget {
  const _BlockingDurationPickerSheet({required this.count});

  final int count;

  @override
  State<_BlockingDurationPickerSheet> createState() => _BlockingDurationPickerSheetState();
}

class _BlockingDurationPickerSheetState extends State<_BlockingDurationPickerSheet> {
  int _customMinutes = 45;

  Duration _untilMidnight() {
    final now = DateTime.now();
    final midnight = DateTime(now.year, now.month, now.day, 23, 59, 59);
    final diff = midnight.difference(now);
    return diff.isNegative ? const Duration(hours: 1) : diff;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF1C1E26) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Block ${widget.count} ${widget.count == 1 ? 'App' : 'Apps'}',
            style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            'Select how long you want to block access to these apps:',
            style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 13),
          ),
          const SizedBox(height: 18),
          _DurationTile(
            title: '30 Minutes',
            subtitle: 'Quick focus burst',
            icon: Icons.timer_outlined,
            onTap: () => Navigator.pop(context, const Duration(minutes: 30)),
          ),
          _DurationTile(
            title: '1 Hour',
            subtitle: 'Standard deep-work block',
            icon: Icons.hourglass_top_rounded,
            onTap: () => Navigator.pop(context, const Duration(hours: 1)),
          ),
          _DurationTile(
            title: '2 Hours',
            subtitle: 'Extended productivity session',
            icon: Icons.hourglass_bottom_rounded,
            onTap: () => Navigator.pop(context, const Duration(hours: 2)),
          ),
          _DurationTile(
            title: 'Until Midnight',
            subtitle: 'Rest of the day offline',
            icon: Icons.bedtime_outlined,
            onTap: () => Navigator.pop(context, _untilMidnight()),
          ),
          const Divider(height: 24),
          Text(
            'Custom Duration: $_customMinutes min',
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
          ),
          Slider(
            value: _customMinutes.toDouble(),
            min: 10,
            max: 360,
            divisions: 35,
            label: '$_customMinutes min',
            activeColor: kBrandBlue,
            onChanged: (v) => setState(() => _customMinutes = v.round()),
          ),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () => Navigator.pop(context, Duration(minutes: _customMinutes)),
              child: Text('Confirm $_customMinutes Minutes'),
            ),
          ),
        ],
      ),
    );
  }
}

class _DurationTile extends StatelessWidget {
  const _DurationTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: kBrandBlue.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: kBrandBlue, size: 20),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: onTap,
    );
  }
}

class _ConfirmBlockDialog extends StatelessWidget {
  const _ConfirmBlockDialog({required this.apps, required this.duration});

  final List<(String package, String label)> apps;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    final format = duration.inHours > 0
        ? '${duration.inHours}h ${duration.inMinutes % 60 > 0 ? '${duration.inMinutes % 60}m' : ''}'
        : '${duration.inMinutes}m';

    return AlertDialog(
      title: const Text('Confirm App Blocking', style: TextStyle(fontWeight: FontWeight.w800)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Are you sure you want to block ${apps.length} ${apps.length == 1 ? 'app' : 'apps'} for $format?'),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.grey.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final (_, lbl) in apps.take(5))
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: [
                        const Icon(Icons.circle, size: 6, color: Color(0xFFE5484D)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(lbl, maxLines: 1, overflow: TextOverflow.ellipsis),
                        ),
                      ],
                    ),
                  ),
                if (apps.length > 5) Text('+ ${apps.length - 5} more...', style: const TextStyle(fontSize: 11)),
              ],
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'You can unblock or extend any app anytime from the Center Screen.',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: const Color(0xFFE5484D)),
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Block Now'),
        ),
      ],
    );
  }
}
