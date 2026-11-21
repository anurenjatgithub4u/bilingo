import 'package:flutter/material.dart';

import 'services/word_service.dart';

/// Must match the codes in Languages.kt and words.json.
const kLanguages = [
  (code: 'en', label: 'English'),
  (code: 'de', label: 'Deutsch'),
];

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.service});

  final WordService service;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  WordState? _state;
  ShownWord? _preview;
  bool _setupPrompted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // The user may change the notification permission in system settings.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final state = await widget.service.getState();
    if (!mounted) return;
    setState(() => _state = state);
    if (!_setupPrompted && !_setupComplete(state)) {
      _setupPrompted = true;
      _showSetupDialog();
    }
  }

  bool _setupComplete(WordState s) =>
      s.notificationsGranted && s.batteryUnrestricted;

  /// Walks the user through the settings the system will not let an app flip itself.
  Future<void> _fixSetup() async {
    var state = await widget.service.getState();
    if (!state.notificationsGranted) {
      final granted = await widget.service.requestNotificationPermission();
      // Once denied, Android stops showing the prompt, so send them to settings.
      if (!granted) await widget.service.openNotificationSettings();
      return;
    }
    if (!state.batteryUnrestricted) {
      await widget.service.requestIgnoreBatteryOptimizations();
    }
  }

  Future<void> _showSetupDialog() async {
    final state = _state!;
    final fix = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.shield_outlined),
        title: const Text('Allow permissions'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'BiLingo needs these to show a word when you unlock your phone:',
              ),
              const SizedBox(height: 12),
              _dialogRow(state.notificationsGranted, 'Notifications'),
              _dialogRow(
                state.batteryUnrestricted,
                'Battery: allow background activity',
              ),
              const SizedBox(height: 12),
              const Text(
                'Also check App info: set Battery usage to Unrestricted '
                '(or allow background activity / auto-launch) and turn off '
                '"Manage app if unused". Otherwise the phone may stop the app '
                'and unlock words will not appear.',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Later'),
          ),
          TextButton(
            onPressed: () {
              widget.service.openAppSettings();
              Navigator.pop(context, false);
            },
            child: const Text('App settings'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Allow now'),
          ),
        ],
      ),
    );
    if (fix == true) await _fixSetup();
  }

  Widget _dialogRow(bool ok, String label) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      children: [
        Icon(
          ok ? Icons.check_circle : Icons.error_outline,
          size: 20,
          color: ok ? Colors.green : Theme.of(context).colorScheme.error,
        ),
        const SizedBox(width: 8),
        Expanded(child: Text(label)),
      ],
    ),
  );

  Future<void> _setEnabled(bool value) async {
    if (value && !_state!.notificationsGranted) {
      final granted = await widget.service.requestNotificationPermission();
      if (!granted) {
        await _refresh();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Allow notifications so words can be shown.'),
            ),
          );
        }
        return;
      }
    }
    final state = await widget.service.update(enabled: value);
    if (mounted) setState(() => _state = state);
  }

  Future<void> _toggleLanguage(String lang, bool selected) async {
    final next = {..._state!.languages};
    selected ? next.add(lang) : next.remove(lang);
    if (next.isEmpty) return; // At least one language must stay on.
    final state = await widget.service.update(languages: next);
    if (mounted) setState(() => _state = state);
  }

  Future<void> _showNow() async {
    if (!_state!.notificationsGranted) {
      if (!await widget.service.requestNotificationPermission()) return;
    }
    final word = await widget.service.showWordNow();
    await _refresh();
    if (mounted) setState(() => _preview = word);
  }

  @override
  Widget build(BuildContext context) {
    final state = _state;
    return Scaffold(
      appBar: AppBar(title: const Text('BiLingo')),
      body: state == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  'Get a new English or German word, with its meaning, '
                  'as a notification whenever your screen turns on or you unlock your phone.',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const SizedBox(height: 16),
                Card(
                  child: SwitchListTile(
                    title: const Text('Show words'),
                    subtitle: Text(state.enabled ? 'On' : 'Off'),
                    value: state.enabled,
                    onChanged: _setEnabled,
                  ),
                ),
                const SizedBox(height: 16),
                if (!_setupComplete(state)) ...[
                  Card(
                    color: Theme.of(context).colorScheme.errorContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Setup needed',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          _dialogRow(
                            state.notificationsGranted,
                            'Notifications',
                          ),
                          _dialogRow(
                            state.batteryUnrestricted,
                            'Battery: allow background activity',
                          ),
                          const SizedBox(height: 12),
                          FilledButton(
                            style: FilledButton.styleFrom(
                              minimumSize: const Size.fromHeight(48),
                            ),
                            onPressed: _fixSetup,
                            child: const Text('Fix now'),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                _section(context, 'Your progress'),
                _ProgressCard(state: state),
                const SizedBox(height: 16),
                _section(context, 'When'),
                Card(
                  child: Column(
                    children: [
                      SwitchListTile(
                        title: const Text('Screen turns on'),
                        value: state.onScreenOn,
                        onChanged: (v) async {
                          final s = await widget.service.update(onScreenOn: v);
                          if (mounted) setState(() => _state = s);
                        },
                      ),
                      SwitchListTile(
                        title: const Text('Phone is unlocked'),
                        value: state.onUnlock,
                        onChanged: (v) async {
                          final s = await widget.service.update(onUnlock: v);
                          if (mounted) setState(() => _state = s);
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _section(context, 'Languages'),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final language in kLanguages)
                      FilterChip(
                        label: Text(language.label),
                        selected: state.languages.contains(language.code),
                        onSelected: (v) => _toggleLanguage(language.code, v),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${state.wordCount} words in the local database',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 24),
                OutlinedButton.icon(
                  onPressed: _showNow,
                  icon: const Icon(Icons.notifications_active_outlined),
                  label: const Text('Show a word now'),
                ),
                if (_preview != null) ...[
                  const SizedBox(height: 16),
                  Card(
                    child: ListTile(
                      title: Text(_preview!.word),
                      subtitle: Text(_preview!.meaning),
                      trailing: Text(_preview!.lang.toUpperCase()),
                    ),
                  ),
                ],
                if (!state.notificationsGranted) ...[
                  const SizedBox(height: 16),
                  Text(
                    'Notifications are blocked for this app, so no words can be shown.',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
              ],
            ),
    );
  }

  Widget _section(BuildContext context, String title) => Padding(
    padding: const EdgeInsets.only(bottom: 8, left: 4),
    child: Text(title, style: Theme.of(context).textTheme.titleSmall),
  );
}

class _ProgressCard extends StatelessWidget {
  const _ProgressCard({required this.state});

  final WordState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _stat(theme, '${state.shownToday}', 'Today'),
                _stat(theme, '${state.totalShown}', 'Total shown'),
              ],
            ),
            const SizedBox(height: 16),
            for (final language in kLanguages) ...[
              _language(theme, language.label, language.code),
              const SizedBox(height: 12),
            ],
          ],
        ),
      ),
    );
  }

  Widget _stat(ThemeData theme, String value, String label) => Expanded(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value, style: theme.textTheme.headlineMedium),
        Text(label, style: theme.textTheme.bodySmall),
      ],
    ),
  );

  Widget _language(ThemeData theme, String name, String code) {
    final learned = state.learned[code] ?? 0;
    final available = state.available[code] ?? 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(name, style: theme.textTheme.bodyMedium),
            Text(
              '$learned / $available learned',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
        const SizedBox(height: 6),
        LinearProgressIndicator(
          value: available == 0 ? 0 : learned / available,
          minHeight: 8,
          borderRadius: BorderRadius.circular(4),
        ),
      ],
    );
  }
}
