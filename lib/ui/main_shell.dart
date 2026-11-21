import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'patrol.dart';
import 'profile_tab.dart';
import 'time_tab.dart';
import 'word_flow_tab.dart';
import 'word_links.dart';

/// Holds WordFlow (Home), Your Time and Profile with a floating pill navigation bar.
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> with WidgetsBindingObserver {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    shellTabRequest.addListener(_onTabRequest);
    WordLinks.instance.shellReady();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    shellTabRequest.removeListener(_onTabRequest);
    WordLinks.instance.shellGone();
    super.dispose();
  }

  /// Back from another app: Scroll Patrol may have made an arrest meanwhile.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final nav = navigatorKey.currentState;
    if (state == AppLifecycleState.resumed && nav != null) {
      Patrol.instance.check(nav);
    }
  }

  /// Another screen asked for a tab, e.g. "Pay bail" goes to the feed.
  void _onTabRequest() {
    final tab = shellTabRequest.value;
    if (tab == null) return;
    shellTabRequest.value = null;
    if (mounted && tab != _index) setState(() => _index = tab);
  }

  @override
  Widget build(BuildContext context) {
    return GradientBackground(
      child: Scaffold(
        extendBody: true,
        body: SafeArea(
          bottom: false,
          child: IndexedStack(
            index: _index,
            // Keyed so Profile reloads its stats each time the tab is opened.
            children: [
              const WordFlowTab(),
              // Keyed so its figures refresh and animate in each time it opens.
              TimeTab(key: ValueKey(_index == 1)),
              ProfileTab(
                key: ValueKey(_index == 2),
                onBack: () => setState(() => _index = 0),
              ),
            ],
          ),
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _PillNav(
              index: _index,
              // The feed is only dark in the dark theme.
              onReels:
                  _index == 0 &&
                  Theme.of(context).brightness == Brightness.dark,
              onChanged: (i) => setState(() => _index = i),
            ),
          ),
        ),
      ),
    );
  }
}

class _PillNav extends StatelessWidget {
  const _PillNav({
    required this.index,
    required this.onReels,
    required this.onChanged,
  });

  /// Over the dark-theme reel feed: a black bar with a white pill.
  final bool onReels;
  final int index;
  final ValueChanged<int> onChanged;

  static const _items = [
    (Icons.home_outlined, Icons.home_rounded, 'Home'),
    (Icons.hourglass_empty_rounded, Icons.hourglass_bottom_rounded, 'Your Time'),
    (Icons.person_outline, Icons.person_rounded, 'Profile'),
  ];

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: onReels
                ? const Color(0xFF1A1B21)
                : dark
                ? const Color(0xFF1A2540)
                : Colors.white,
            borderRadius: BorderRadius.circular(40),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: dark ? 0.4 : 0.12),
                blurRadius: 20,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < _items.length; i++)
                Semantics(
                  button: true,
                  selected: i == index,
                  label: _items[i].$3,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => onChanged(i),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeOut,
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 22,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: i != index
                            ? Colors.transparent
                            : onReels
                            ? Colors.white
                            : kBrandBlue,
                        borderRadius: BorderRadius.circular(30),
                      ),
                      child: Icon(
                        i == index ? _items[i].$2 : _items[i].$1,
                        size: 26,
                        color: i == index
                            ? (onReels ? const Color(0xFF0E0F13) : Colors.white)
                            : onReels
                            ? const Color(0x99FFFFFF)
                            : Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
