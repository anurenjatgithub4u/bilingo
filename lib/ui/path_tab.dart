import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/profile_store.dart';
import '../services/progress_store.dart';
import '../services/reels.dart' show kCodeNames;
import '../services/vocab.dart' show kLanguageNames;
import '../services/word_service.dart';
import 'app_theme.dart';
import 'lesson_screen.dart';
import 'mascot.dart';

/// Each level is its own coloured section of the path.
const _levelColors = {
  1: Color(0xFF2EB67D),
  2: kBrandBlue,
  3: Color(0xFF8E5CF7),
};

const _levelTitles = {
  1: 'Everyday words',
  2: 'Grow your vocabulary',
  3: 'Rare and tricky words',
};

const _gold = Color(0xFFFFB627);
const _streakOrange = Color(0xFFFF9F1C);

/// Target words per lesson; a level's words are split evenly around this.
const _lessonSize = 5;

const _rowHeight = 104.0;
const _checkpointHeight = 128.0;
const _dividerHeight = 96.0;

/// Sideways position of the k-th node in a section, as a fraction of the swing.
const _snake = [0.0, 0.5, 0.85, 0.5, 0.0, -0.5, -0.85, -0.5];

enum _Status { done, current, open, locked }

class _Node {
  _Node.lesson(this.level, this.words, this.number) : checkpoint = false;
  _Node.checkpoint(this.level, this.words) : checkpoint = true, number = 0;

  final int level;
  final List<ShownWord> words;

  /// Lesson number within its level (1-based); 0 for the level test.
  final int number;

  /// The level test at the end of each section; it covers the whole level.
  final bool checkpoint;
}

/// Home: a winding path of lessons for the chosen language, grouped into one
/// coloured section per level, with a level test (checkpoint) at the end of each.
///
/// Coding and maths have no word lessons, so they get a road of XP levels
/// instead, practised in the feed through [onPractise].
class PathTab extends StatefulWidget {
  const PathTab({super.key, this.onPractise});

  /// Takes the learner to the feed to practise.
  final VoidCallback? onPractise;

  @override
  State<PathTab> createState() => _PathTabState();
}

class _PathTabState extends State<PathTab> {
  final _service = const WordService();
  final _scroll = ScrollController();
  final _store = ProfileStore.instance;

  /// Level of the section under the top banner.
  final _visibleLevel = ValueNotifier<int>(1);

  String? _lang;
  List<ShownWord> _words = const [];
  List<_Node> _nodes = const [];
  bool _loading = true;

  /// Node that just got finished, so it can pop; bumped token replays the pop.
  int? _popIndex;
  int _popToken = 0;
  bool _scrolledToCurrent = false;

  /// The unlock-word streak from the native side, part of the shared streak.
  int _wordStreak = 0;

  /// Learned in a lesson, or known from the reels.
  bool _learned(ShownWord w) =>
      _store.isLearned(w.key) || ProgressStore.instance.isKnown(w.key);

  /// Section start offsets (y) by level, filled during layout.
  final Map<int, double> _sectionTops = {};

  @override
  void initState() {
    super.initState();
    _store.addListener(_onStore);
    ProgressStore.instance.addListener(_onStore);
    _scroll.addListener(_trackSection);
    _load();
  }

  @override
  void dispose() {
    _store.removeListener(_onStore);
    ProgressStore.instance.removeListener(_onStore);
    _scroll.dispose();
    _visibleLevel.dispose();
    super.dispose();
  }

  void _onStore() {
    if (_store.language != _lang) {
      _scrolledToCurrent = false;
      _load();
    } else if (mounted) {
      setState(() {});
    }
  }

  Future<void> _load() async {
    final lang = _store.language;
    _lang = lang;
    List<ShownWord> words = const [];
    try {
      words = await _service.pathWords(lang);
      _wordStreak = (await _service.getState()).streak;
    } catch (_) {
      // No native side (tests): show the empty state.
    }
    if (!mounted || lang != _lang) return;
    setState(() {
      _words = words;
      _nodes = _buildNodes(words);
      _loading = false;
    });
  }

  static List<_Node> _buildNodes(List<ShownWord> words) {
    final nodes = <_Node>[];
    for (final level in const [1, 2, 3]) {
      final inLevel = [
        for (final w in words)
          if ((w.level == 0 ? 2 : w.level) == level) w,
      ];
      if (inLevel.isEmpty) continue;
      // Spread words evenly: 16 words become 4 lessons of 4 rather than 5+5+5+1.
      final count = (inLevel.length / _lessonSize).ceil();
      var start = 0;
      for (var i = 0; i < count; i++) {
        final size = ((inLevel.length - start) / (count - i)).ceil();
        nodes.add(
          _Node.lesson(level, inLevel.sublist(start, start + size), i + 1),
        );
        start += size;
      }
      nodes.add(_Node.checkpoint(level, inLevel));
    }
    return nodes;
  }

  bool _isDone(_Node n) => n.checkpoint
      ? _store.checkpointPassed(_lang!, n.level)
      : n.words.every(_learned);

  /// Lessons below the chosen level stay open; from there on the path unlocks in order.
  List<_Status> _statuses() {
    var start = _nodes.indexWhere((n) => n.level >= _store.level);
    if (start < 0) start = 0;
    var current = -1;
    for (var i = start; i < _nodes.length; i++) {
      if (!_isDone(_nodes[i])) {
        current = i;
        break;
      }
    }
    return [
      for (var i = 0; i < _nodes.length; i++)
        if (_isDone(_nodes[i]))
          _Status.done
        else if (i == current)
          _Status.current
        else if (i < start)
          _Status.open
        else
          _Status.locked,
    ];
  }

  void _trackSection() {
    final y = _scroll.hasClients
        ? _scroll.offset + _scroll.position.viewportDimension * 0.35
        : 40.0;
    var level = _visibleLevel.value;
    for (final e in _sectionTops.entries) {
      if (e.value <= y) level = e.key;
    }
    // Before the first divider we are always in the first section.
    if (_sectionTops.isNotEmpty && y < _sectionTops.values.reduce(math.min)) {
      level = _sectionTops.keys.reduce(math.min);
    }
    _visibleLevel.value = level;
  }

  void _scrollTo(double y, {bool animate = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final target = (y - _scroll.position.viewportDimension * 0.4).clamp(
        0.0,
        _scroll.position.maxScrollExtent,
      );
      animate
          ? _scroll.animateTo(
              target,
              duration: const Duration(milliseconds: 700),
              curve: Curves.easeInOutCubic,
            )
          : _scroll.jumpTo(target);
      _trackSection();
    });
  }

  Future<void> _start(int index) async {
    final node = _nodes[index];
    final color = _levelColors[node.level]!;
    final finished = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => LessonScreen(
          words: node.words,
          pool: _words,
          color: color,
          test: node.checkpoint,
        ),
      ),
    );
    if (finished != true || !mounted) return;
    if (node.checkpoint) await _store.passCheckpoint(_lang!, node.level);
    HapticFeedback.mediumImpact();
    setState(() {
      _popIndex = index;
      _popToken++;
      // Glide down to the newly unlocked node.
      _scrolledToCurrent = false;
    });
  }

  void _openNode(int index, _Status status) {
    HapticFeedback.selectionClick();
    final node = _nodes[index];
    final color = status == _Status.locked
        ? Colors.blueGrey
        : _levelColors[node.level]!;
    final title = node.checkpoint
        ? '${kLevelNames[node.level]} level test'
        : 'Lesson ${node.number}';
    final subtitle = switch (status) {
      _Status.locked =>
        node.checkpoint
            ? 'Finish every lesson in this level to unlock the test.'
            : 'Finish the lessons above to unlock this one.',
      _Status.done =>
        node.checkpoint
            ? 'Passed! Take it again any time to stay sharp.'
            : 'Done. Practise these ${node.words.length} words again.',
      _ =>
        node.checkpoint
            ? 'Get 75% right to finish ${kLevelNames[node.level]}.'
            : '${node.words.length} new words',
    };
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => SafeArea(
        child: Container(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.9),
                  fontSize: 15,
                ),
              ),
              if (status == _Status.done && !node.checkpoint) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final w in node.words)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          w.word,
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                  ],
                ),
              ],
              if (status != _Status.locked) ...[
                const SizedBox(height: 16),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: color,
                  ),
                  onPressed: () {
                    Navigator.pop(context);
                    _start(index);
                  },
                  child: Text(
                    status == _Status.done
                        ? 'PRACTISE'
                        : node.checkpoint
                        ? 'START TEST'
                        : 'START',
                    style: const TextStyle(letterSpacing: 1),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _openGuide(int level) {
    final words = [
      for (final n in _nodes)
        if (n.level == level && !n.checkpoint) ...n.words,
    ];
    final color = _levelColors[level]!;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        builder: (context, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          children: [
            Text(
              '${kLevelNames[level]} words',
              style: Theme.of(context).textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            for (final w in words)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  _learned(w) ? Icons.check_circle : Icons.lock_outline_rounded,
                  color: _learned(w) ? color : Colors.blueGrey,
                ),
                title: Text(_learned(w) ? w.word : '• • •'),
                subtitle: _learned(w) ? Text(w.meaning) : null,
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final code = _store.flowCode ?? (_store.flowMaths ? 'math' : null);
    if (code != null) {
      return _LevelRoad(subject: code, onPractise: widget.onPractise);
    }
    return Column(
      children: [
        _statsBar(context),
        if (_nodes.isNotEmpty)
          ValueListenableBuilder<int>(
            valueListenable: _visibleLevel,
            builder: (context, level, _) => _banner(context, level),
          ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _nodes.isEmpty
              ? Center(
                  child: Text(
                    'No words for this language yet.',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                )
              : LayoutBuilder(builder: _path),
        ),
      ],
    );
  }

  Widget _statsBar(BuildContext context) {
    final theme = Theme.of(context);
    final goal = _store.dailyGoal;
    final today = _store.learnedToday;
    final streak = sharedStreak(_wordStreak);
    final muted = theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5);
    final langColor = _levelColors[2]!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _stat(
            context,
            icon: Container(
              width: 30,
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: langColor,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Text(
                (_lang ?? 'en').toUpperCase(),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                ),
              ),
            ),
            value: '${_words.where(_learned).length}',
            color: langColor,
            tooltip: 'Words learned',
          ),
          _stat(
            context,
            icon: Icon(
              Icons.local_fire_department_rounded,
              size: 30,
              color: streak > 0 ? _streakOrange : muted,
            ),
            value: '$streak',
            color: streak > 0 ? _streakOrange : muted,
            tooltip: 'Day streak',
          ),
          _stat(
            context,
            icon: SizedBox(
              width: 28,
              height: 28,
              child: TweenAnimationBuilder<double>(
                tween: Tween(end: (today / goal).clamp(0.0, 1.0)),
                duration: const Duration(milliseconds: 700),
                curve: Curves.easeOutCubic,
                builder: (context, v, _) => CircularProgressIndicator(
                  value: v,
                  strokeWidth: 5,
                  strokeCap: StrokeCap.round,
                  backgroundColor: muted.withValues(alpha: 0.25),
                  color: _gold,
                ),
              ),
            ),
            value: '$today/$goal',
            color: _gold,
            tooltip: 'Today\'s goal',
          ),
        ],
      ),
    );
  }

  Widget _stat(
    BuildContext context, {
    required Widget icon,
    required String value,
    required Color color,
    required String tooltip,
  }) => Tooltip(
    message: tooltip,
    child: Row(
      children: [
        icon,
        const SizedBox(width: 8),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w800,
            fontSize: 18,
          ),
        ),
      ],
    ),
  );

  Widget _banner(BuildContext context, int level) {
    final color = _levelColors[level]!;
    final words = [
      for (final n in _nodes)
        if (n.level == level && !n.checkpoint) ...n.words,
    ];
    final learned = words.where(_learned).length;
    final dark = HSLColor.fromColor(color)
        .withLightness(
          (HSLColor.fromColor(color).lightness - 0.12).clamp(0.0, 1.0),
        )
        .toColor();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 350),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: dark, offset: const Offset(0, 4))],
        ),
        child: IntrinsicHeight(
          child: Row(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 14, 12, 14),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: Column(
                      key: ValueKey(level),
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'LEVEL $level · ${kLevelNames[level]!.toUpperCase()}',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.8),
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                            letterSpacing: 0.8,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _levelTitles[level]!,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 19,
                          ),
                        ),
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: TweenAnimationBuilder<double>(
                            tween: Tween(
                              end: words.isEmpty ? 0 : learned / words.length,
                            ),
                            duration: const Duration(milliseconds: 600),
                            builder: (context, v, _) => LinearProgressIndicator(
                              value: v,
                              minHeight: 6,
                              color: Colors.white,
                              backgroundColor: Colors.white.withValues(
                                alpha: 0.3,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '$learned of ${words.length} words learned',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.85),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              VerticalDivider(width: 2, thickness: 2, color: dark),
              InkWell(
                onTap: () => _openGuide(level),
                borderRadius: const BorderRadius.horizontal(
                  right: Radius.circular(20),
                ),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 18),
                  child: Icon(
                    Icons.menu_book_rounded,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _path(BuildContext context, BoxConstraints constraints) {
    final theme = Theme.of(context);
    final statuses = _statuses();
    final width = constraints.maxWidth;
    final center = width / 2;
    final swing = math.min(84.0, width * 0.21);

    // Lay out every node top to bottom: centre point, plus where dividers sit.
    final centers = <Offset>[];
    final dividers = <(int, double)>[];
    final mascots = <Offset>[];
    _sectionTops.clear();
    var y = 28.0;
    var k = 0;
    for (var i = 0; i < _nodes.length; i++) {
      final node = _nodes[i];
      if (i == 0 || node.level != _nodes[i - 1].level) {
        if (i > 0) {
          dividers.add((node.level, y));
          y += _dividerHeight;
        }
        _sectionTops[node.level] = i == 0 ? 0 : y - _dividerHeight;
        k = 0;
      }
      final h = node.checkpoint ? _checkpointHeight : _rowHeight;
      final dx = node.checkpoint ? 0.0 : _snake[k % _snake.length] * swing;
      centers.add(Offset(center + dx, y + h / 2));
      // The mascot keeps each section company, opposite the bend of the path.
      if (k == 2 && dx != 0) {
        mascots.add(Offset(center - dx.sign * swing * 1.45, y + h / 2));
      }
      y += h;
      k++;
    }
    final total = y + 140; // clears the floating nav bar

    final current = statuses.indexOf(_Status.current);
    if (!_scrolledToCurrent && current >= 0) {
      _scrolledToCurrent = true;
      // First open jumps straight there; after a lesson it glides.
      _scrollTo(centers[current].dy, animate: _popIndex != null);
    } else if (!_scrolledToCurrent) {
      _scrolledToCurrent = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _trackSection());
    }

    return SingleChildScrollView(
      controller: _scroll,
      child: SizedBox(
        height: total,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _TrailPainter(
                  centers: centers,
                  levels: [for (final n in _nodes) n.level],
                  reached: current < 0 ? _nodes.length : current,
                  colors: _levelColors,
                  idle: theme.colorScheme.onSurfaceVariant.withValues(
                    alpha: 0.18,
                  ),
                ),
              ),
            ),
            for (final (level, top) in dividers)
              Positioned(
                left: 24,
                right: 24,
                top: top + 24,
                child: _Divider(
                  text: kLevelNames[level]!.toUpperCase(),
                  color: _levelColors[level]!,
                ),
              ),
            for (final m in mascots)
              Positioned(
                left: m.dx - 48,
                top: m.dy - 52,
                child: const IgnorePointer(child: Mascot(size: 96)),
              ),
            for (var i = 0; i < _nodes.length; i++)
              Positioned(
                left: centers[i].dx - 60,
                top: centers[i].dy - 60,
                width: 120,
                height: 120,
                child: _PathNode(
                  key: ValueKey('node$i'),
                  status: statuses[i],
                  checkpoint: _nodes[i].checkpoint,
                  color: _levelColors[_nodes[i].level]!,
                  pop: _popIndex == i ? _popToken : 0,
                  onTap: () => _openNode(i, statuses[i]),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Dotted trail joining the nodes; coloured up to the learner's current spot.
class _TrailPainter extends CustomPainter {
  _TrailPainter({
    required this.centers,
    required this.levels,
    required this.reached,
    required this.colors,
    required this.idle,
  });

  final List<Offset> centers;
  final List<int> levels;
  final int reached;
  final Map<int, Color> colors;
  final Color idle;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    for (var i = 1; i < centers.length; i++) {
      // No trail across a section divider.
      if (levels[i] != levels[i - 1]) continue;
      paint.color = i <= reached
          ? colors[levels[i]]!.withValues(alpha: 0.45)
          : idle;
      final a = centers[i - 1];
      final b = centers[i];
      final length = (b - a).distance;
      // Skip the parts hidden under the nodes themselves.
      for (var d = 46.0; d < length - 46; d += 14) {
        canvas.drawCircle(Offset.lerp(a, b, d / length)!, 3.5, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_TrailPainter old) =>
      old.reached != reached ||
      old.centers.length != centers.length ||
      old.idle != idle;
}

class _Divider extends StatelessWidget {
  const _Divider({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final line = Expanded(
      child: Container(height: 2, color: color.withValues(alpha: 0.35)),
    );
    return Row(
      children: [
        line,
        Flexible(
          flex: 3,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
              ),
            ),
          ),
        ),
        line,
      ],
    );
  }
}

/// A round 3D button on the path (a chest-shaped one for level tests). The
/// current node pulses and has a bobbing "START" label above it.
class _PathNode extends StatefulWidget {
  const _PathNode({
    super.key,
    required this.status,
    required this.checkpoint,
    required this.color,
    required this.pop,
    required this.onTap,
  });

  final _Status status;
  final bool checkpoint;
  final Color color;

  /// Changes when this node was just completed, to play the pop.
  final int pop;
  final VoidCallback onTap;

  @override
  State<_PathNode> createState() => _PathNodeState();
}

class _PathNodeState extends State<_PathNode> with TickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );
  late final AnimationController _popper = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
    value: 1,
  );
  bool _down = false;

  @override
  void initState() {
    super.initState();
    _syncPulse();
  }

  @override
  void didUpdateWidget(_PathNode old) {
    super.didUpdateWidget(old);
    _syncPulse();
    if (widget.pop != old.pop && widget.pop != 0) _popper.forward(from: 0);
  }

  void _syncPulse() {
    if (widget.status == _Status.current) {
      if (!_pulse.isAnimating) _pulse.repeat();
    } else {
      _pulse.stop();
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    _popper.dispose();
    super.dispose();
  }

  static Color _darker(Color c, [double by = 0.14]) {
    final hsl = HSLColor.fromColor(c);
    return hsl.withLightness((hsl.lightness - by).clamp(0.0, 1.0)).toColor();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final status = widget.status;
    final Color face = switch (status) {
      _Status.done => _gold,
      _Status.locked =>
        dark ? const Color(0xFF2B3753) : const Color(0xFFD3DCE8),
      _ => widget.color,
    };
    final base = _darker(face);
    final iconColor = status == _Status.locked
        ? (dark ? const Color(0xFF55627F) : const Color(0xFF9AA8BC))
        : Colors.white;
    final IconData icon = widget.checkpoint
        ? (status == _Status.done
              ? Icons.emoji_events_rounded
              : status == _Status.locked
              ? Icons.lock_rounded
              : Icons.redeem_rounded)
        : switch (status) {
            _Status.done => Icons.check_rounded,
            _Status.locked => Icons.lock_rounded,
            _ => Icons.star_rounded,
          };
    final w = widget.checkpoint ? 84.0 : 72.0;
    const h = 66.0;
    final radius = BorderRadius.circular(widget.checkpoint ? 22 : h);
    final press = _down ? 5.0 : 0.0;

    final button = SizedBox(
      width: w,
      height: h + 8,
      child: Stack(
        children: [
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: h,
            child: DecoratedBox(
              decoration: BoxDecoration(color: base, borderRadius: radius),
            ),
          ),
          AnimatedPositioned(
            duration: const Duration(milliseconds: 80),
            left: 0,
            right: 0,
            top: press,
            height: h,
            child: DecoratedBox(
              decoration: BoxDecoration(color: face, borderRadius: radius),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Glossy highlight across the upper face.
                  Positioned(
                    top: 8,
                    left: w * 0.22,
                    right: w * 0.22,
                    height: 8,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(
                          alpha: status == _Status.locked ? 0.15 : 0.3,
                        ),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                  Icon(icon, color: iconColor, size: 36),
                ],
              ),
            ),
          ),
        ],
      ),
    );

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTapDown: (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTapUp: (_) {
        setState(() => _down = false);
        widget.onTap();
      },
      child: AnimatedBuilder(
        animation: Listenable.merge([_pulse, _popper]),
        builder: (context, child) {
          final pop = Curves.elasticOut.transform(_popper.value);
          return Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              if (status == _Status.current) ...[
                // Ring around the node that keeps breathing outward.
                Container(
                  width: w + 22,
                  height: h + 26,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(
                      widget.checkpoint ? 30 : 60,
                    ),
                    border: Border.all(
                      color: widget.color.withValues(alpha: 0.3),
                      width: 7,
                    ),
                  ),
                ),
                Transform.scale(
                  scale: 1 + _pulse.value * 0.35,
                  child: Opacity(
                    opacity: (1 - _pulse.value) * 0.5,
                    child: Container(
                      width: w + 22,
                      height: h + 26,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(
                          widget.checkpoint ? 30 : 60,
                        ),
                        border: Border.all(color: widget.color, width: 3),
                      ),
                    ),
                  ),
                ),
              ],
              Transform.scale(scale: 0.6 + 0.4 * pop, child: child),
              if (status == _Status.current)
                Positioned(
                  top: -28 + math.sin(_pulse.value * 2 * math.pi) * 4,
                  child: _StartLabel(
                    text: widget.checkpoint ? 'TEST' : 'START',
                    color: widget.color,
                  ),
                ),
            ],
          );
        },
        child: button,
      ),
    );
  }
}

class _StartLabel extends StatelessWidget {
  const _StartLabel({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final bg = dark ? const Color(0xFF1A2540) : Colors.white;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: 0.4), width: 2),
          ),
          child: Text(
            text,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w900,
              letterSpacing: 1,
            ),
          ),
        ),
        // Little pointer under the bubble.
        Transform.translate(
          offset: const Offset(0, -6),
          child: Transform.rotate(
            angle: math.pi / 4,
            child: Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: bg,
                border: Border(
                  right: BorderSide(
                    color: color.withValues(alpha: 0.4),
                    width: 2,
                  ),
                  bottom: BorderSide(
                    color: color.withValues(alpha: 0.4),
                    width: 2,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The streak every screen shows: a day counts if the learner answered a
/// reel, finished a lesson or learned an unlock word.
int sharedStreak(int wordStreak) => [
  wordStreak,
  ProgressStore.instance.practiceStreak,
  ProfileStore.instance.streak,
].reduce(math.max);

/// The name a subject goes by on screen.
String subjectName(String code) => code == 'math'
    ? 'Maths'
    : kCodeNames[code] ?? kLanguageNames[code] ?? code.toUpperCase();

/// A number with its icon in the stats row, like the word path's.
class _Stat extends StatelessWidget {
  const _Stat({
    required this.icon,
    required this.value,
    required this.color,
    required this.tooltip,
  });

  final Widget icon;
  final String value;
  final Color color;
  final String tooltip;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: Row(
      children: [
        icon,
        const SizedBox(width: 8),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w800,
            fontSize: 18,
          ),
        ),
      ],
    ),
  );
}

/// Coding and maths: every XP level as a stop on the path, done up to the
/// learner's level, with a milestone every five. Practice happens in the
/// feed, so the current stop sends the learner there.
class _LevelRoad extends StatefulWidget {
  const _LevelRoad({required this.subject, this.onPractise});

  final String subject;
  final VoidCallback? onPractise;

  @override
  State<_LevelRoad> createState() => _LevelRoadState();
}

class _LevelRoadState extends State<_LevelRoad> {
  static const _perSection = 5;

  final _scroll = ScrollController();
  bool _scrolled = false;
  int _wordStreak = 0;

  @override
  void initState() {
    super.initState();
    _loadStreak();
  }

  Future<void> _loadStreak() async {
    try {
      final state = await const WordService().getState();
      if (mounted) setState(() => _wordStreak = state.streak);
    } catch (_) {
      // No native side (tests): the other streaks still count.
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  static Color _color(int section) => _levelColors[section % 3 + 1]!;

  /// XP still to earn to reach level [target] from where the learner is.
  int _xpTo(SubjectLevel now, int target) {
    var xp = now.xpNeeded - now.xpIntoLevel;
    for (var l = now.level + 1; l < target; l++) {
      xp += xpForLevel(l);
    }
    return xp;
  }

  void _open(int n, _Status status, SubjectLevel now) {
    HapticFeedback.selectionClick();
    final section = (n - 1) ~/ _perSection;
    final color = status == _Status.locked ? Colors.blueGrey : _color(section);
    final milestone = n % _perSection == 0;
    final title = milestone
        ? 'Level $n · ${rankName(n)} milestone'
        : 'Level $n';
    final subtitle = switch (status) {
      _Status.done => 'Reached. Keep practising to climb higher.',
      _Status.current =>
        '${now.xpIntoLevel} / ${now.xpNeeded} XP. Answer reels to reach '
            'level ${n + 1}; harder ones earn more.',
      _ => 'About ${_xpTo(now, n)} more XP to reach this level.',
    };
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => SafeArea(
        child: Container(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.9),
                  fontSize: 15,
                ),
              ),
              if (widget.onPractise != null) ...[
                const SizedBox(height: 16),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: color,
                  ),
                  onPressed: () {
                    Navigator.pop(context);
                    widget.onPractise?.call();
                  },
                  child: const Text(
                    'PRACTISE',
                    style: TextStyle(letterSpacing: 1),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([
      ProgressStore.instance,
      ProfileStore.instance,
    ]),
    builder: (context, _) {
      final now = ProgressStore.instance.levelOf(widget.subject);
      return Column(
        children: [
          _stats(context, now),
          _banner(context, now),
          Expanded(
            child: LayoutBuilder(
              builder: (context, box) => _road(context, box, now),
            ),
          ),
        ],
      );
    },
  );

  Widget _stats(BuildContext context, SubjectLevel now) {
    final theme = Theme.of(context);
    final progress = ProgressStore.instance;
    final streak = sharedStreak(_wordStreak);
    final accuracy = progress.accuracyIn(widget.subject);
    final muted = theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5);
    final blue = _levelColors[2]!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _Stat(
            icon: Container(
              width: 30,
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: blue,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(
                widget.subject == 'math'
                    ? Icons.calculate_rounded
                    : Icons.code_rounded,
                color: Colors.white,
                size: 18,
              ),
            ),
            value: '${progress.correctIn(widget.subject)}',
            color: blue,
            tooltip: 'Questions solved',
          ),
          _Stat(
            icon: Icon(
              Icons.local_fire_department_rounded,
              size: 30,
              color: streak > 0 ? _streakOrange : muted,
            ),
            value: '$streak',
            color: streak > 0 ? _streakOrange : muted,
            tooltip: 'Day streak',
          ),
          _Stat(
            icon: Icon(
              Icons.track_changes_rounded,
              size: 28,
              color: accuracy == null ? muted : _gold,
            ),
            value: accuracy == null ? '--' : '$accuracy%',
            color: accuracy == null ? muted : _gold,
            tooltip: 'Accuracy',
          ),
        ],
      ),
    );
  }

  Widget _banner(BuildContext context, SubjectLevel now) {
    final color = _color((now.level - 1) ~/ _perSection);
    final dark = HSLColor.fromColor(color)
        .withLightness(
          (HSLColor.fromColor(color).lightness - 0.12).clamp(0.0, 1.0),
        )
        .toColor();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      child: Container(
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: dark, offset: const Offset(0, 4))],
        ),
        child: IntrinsicHeight(
          child: Row(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 14, 12, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'LEVEL ${now.level} · ${now.rank.toUpperCase()}',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.8),
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                          letterSpacing: 0.8,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subjectName(widget.subject),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 19,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: TweenAnimationBuilder<double>(
                          tween: Tween(end: now.fraction),
                          duration: const Duration(milliseconds: 600),
                          builder: (context, v, _) => LinearProgressIndicator(
                            value: v,
                            minHeight: 6,
                            color: Colors.white,
                            backgroundColor: Colors.white.withValues(
                              alpha: 0.3,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${now.xpIntoLevel} / ${now.xpNeeded} XP to level '
                        '${now.level + 1}',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.85),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (widget.onPractise != null) ...[
                VerticalDivider(width: 2, thickness: 2, color: dark),
                Semantics(
                  button: true,
                  label: 'Practise now',
                  excludeSemantics: true,
                  child: InkWell(
                    onTap: widget.onPractise,
                    borderRadius: const BorderRadius.horizontal(
                      right: Radius.circular(20),
                    ),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 18),
                      child: Icon(
                        Icons.play_arrow_rounded,
                        color: Colors.white,
                        size: 32,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _road(BuildContext context, BoxConstraints box, SubjectLevel now) {
    final theme = Theme.of(context);
    // Always a few stops ahead, ending on a milestone.
    final last = math.max(
      10,
      ((now.level + 6) / _perSection).ceil() * _perSection,
    );
    final width = box.maxWidth;
    final center = width / 2;
    final swing = math.min(84.0, width * 0.21);

    final centers = <Offset>[];
    final sections = <int>[];
    final dividers = <(int, double)>[];
    final mascots = <Offset>[];
    var y = 28.0;
    var k = 0;
    for (var n = 1; n <= last; n++) {
      final section = (n - 1) ~/ _perSection;
      if (n > 1 && section != sections.last) {
        dividers.add((section, y));
        y += _dividerHeight;
        k = 0;
      }
      final milestone = n % _perSection == 0;
      final h = milestone ? _checkpointHeight : _rowHeight;
      final dx = milestone ? 0.0 : _snake[k % _snake.length] * swing;
      centers.add(Offset(center + dx, y + h / 2));
      sections.add(section);
      if (k == 2 && dx != 0) {
        mascots.add(Offset(center - dx.sign * swing * 1.45, y + h / 2));
      }
      y += h;
      k++;
    }
    final total = y + 140;

    _Status status(int n) => n < now.level
        ? _Status.done
        : n == now.level
        ? _Status.current
        : _Status.locked;

    if (!_scrolled) {
      _scrolled = true;
      final target = centers[now.level - 1].dy;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scroll.hasClients) return;
        _scroll.jumpTo(
          (target - _scroll.position.viewportDimension * 0.4).clamp(
            0.0,
            _scroll.position.maxScrollExtent,
          ),
        );
      });
    }

    return SingleChildScrollView(
      controller: _scroll,
      child: SizedBox(
        height: total,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _TrailPainter(
                  centers: centers,
                  levels: [for (final sec in sections) sec % 3 + 1],
                  reached: now.level - 1,
                  colors: _levelColors,
                  idle: theme.colorScheme.onSurfaceVariant.withValues(
                    alpha: 0.18,
                  ),
                ),
              ),
            ),
            for (final (section, top) in dividers)
              Positioned(
                left: 24,
                right: 24,
                top: top + 24,
                child: _Divider(
                  text:
                      'LEVELS ${section * _perSection + 1}–'
                      '${(section + 1) * _perSection}',
                  color: _color(section),
                ),
              ),
            for (final m in mascots)
              Positioned(
                left: m.dx - 48,
                top: m.dy - 52,
                child: const IgnorePointer(child: Mascot(size: 96)),
              ),
            for (var n = 1; n <= last; n++) ...[
              Positioned(
                left: centers[n - 1].dx - 60,
                top: centers[n - 1].dy - 60,
                width: 120,
                height: 120,
                child: _PathNode(
                  key: ValueKey('level$n'),
                  status: status(n),
                  checkpoint: n % _perSection == 0,
                  color: _color(sections[n - 1]),
                  pop: 0,
                  onTap: () => _open(n, status(n), now),
                ),
              ),
              Positioned(
                left: centers[n - 1].dx - 30,
                top: centers[n - 1].dy + 40,
                width: 60,
                child: IgnorePointer(
                  child: Text(
                    '$n',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: status(n) == _Status.locked
                          ? theme.colorScheme.onSurfaceVariant
                          : _color(sections[n - 1]),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
