import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/profile_store.dart';
import '../services/progress_store.dart';
import '../services/vocab.dart';
import '../services/word_service.dart';
import 'app_theme.dart';
import 'mascot.dart';

const _good = Color(0xFF2EB67D);
const _bad = Color(0xFFE5484D);

/// One screen of a lesson: meet a new word, or answer a multiple-choice question.
sealed class _Step {}

class _Intro extends _Step {
  _Intro(this.word);
  final ShownWord word;
}

class _Question extends _Step {
  _Question(this.word, this.options, {required this.reverse});

  final ShownWord word;

  /// False: show the word, pick its meaning. True: show the meaning, pick the word.
  final bool reverse;
  final List<ShownWord> options;
}

/// A lesson from the learning path. In learn mode every word is introduced, then
/// asked about; wrong answers come back at the end. In [test] mode (a level
/// checkpoint) there are only questions and the learner needs 75% to pass.
///
/// Pops with true when the lesson is finished (or the test passed).
class LessonScreen extends StatefulWidget {
  const LessonScreen({
    super.key,
    required this.words,
    required this.pool,
    required this.color,
    this.test = false,
  });

  final List<ShownWord> words;

  /// Words to draw wrong answers from (normally the whole language).
  final List<ShownWord> pool;
  final Color color;
  final bool test;

  @override
  State<LessonScreen> createState() => _LessonScreenState();
}

class _LessonScreenState extends State<LessonScreen> {
  final _started = Stopwatch()..start();
  static const _testQuestions = 8;

  final _random = math.Random();
  late List<_Step> _steps;
  int _index = 0;
  int _answered = 0;
  int _correct = 0;

  /// The option picked for the current question, or null while still choosing.
  ShownWord? _picked;
  bool _finished = false;
  bool _passed = false;

  @override
  void initState() {
    super.initState();
    _steps = _buildSteps();
  }

  List<_Step> _buildSteps() {
    if (widget.test) {
      final words = List.of(widget.words)..shuffle(_random);
      return [
        for (var i = 0; i < math.min(_testQuestions, words.length); i++)
          _question(words[i], reverse: i.isOdd),
      ];
    }
    // Beginners first see word → meaning; the review round flips it.
    return [
      for (final w in widget.words) ...[
        _Intro(w),
        _question(w, reverse: false),
      ],
      for (final w in List.of(widget.words)..shuffle(_random))
        _question(w, reverse: true),
    ];
  }

  _Question _question(ShownWord word, {required bool reverse}) {
    // Wrong answers from the same level first, so the choices feel fair.
    final others =
        widget.pool
            .where((w) => w.key != word.key && w.meaning != word.meaning)
            .toList()
          ..shuffle(_random);
    others.sort(
      (a, b) => (a.level == word.level ? 0 : 1).compareTo(
        b.level == word.level ? 0 : 1,
      ),
    );
    final options = [word, ...others.take(3)]..shuffle(_random);
    return _Question(word, options, reverse: reverse);
  }

  double get _progress => _finished ? 1 : _index / _steps.length;

  void _answer(ShownWord option) {
    if (_picked != null) return;
    final step = _steps[_index] as _Question;
    final right = option.key == step.word.key;
    right ? HapticFeedback.lightImpact() : HapticFeedback.heavyImpact();
    setState(() {
      _picked = option;
      _answered++;
      if (right) _correct++;
      // In a lesson a missed word comes back later; a test counts it as lost.
      if (!right && !widget.test) {
        _steps.add(_question(step.word, reverse: step.reverse));
      }
    });
    ProfileStore.instance.recordAnswer(correct: right);
  }

  Future<void> _next() async {
    HapticFeedback.selectionClick();
    if (_index + 1 < _steps.length) {
      setState(() {
        _index++;
        _picked = null;
      });
      return;
    }
    final passed = !widget.test || _correct >= (_steps.length * 0.75).ceil();
    if (passed && !widget.test) {
      await ProfileStore.instance.markLearned(widget.words.map((w) => w.key));
      // Capped, in case the lesson sat open for a while.
      ProgressStore.instance.addLearning(
        math.min(_started.elapsedMilliseconds, 20 * 60000),
      );
    }
    if (!mounted) return;
    setState(() {
      _finished = true;
      _passed = passed;
    });
  }

  void _restart() => setState(() {
    _steps = _buildSteps();
    _index = 0;
    _answered = 0;
    _correct = 0;
    _picked = null;
    _finished = false;
  });

  Future<void> _close() async {
    if (_finished) {
      Navigator.pop(context, _passed);
      return;
    }
    if (_index == 0 && _picked == null) {
      Navigator.pop(context, false);
      return;
    }
    final quit = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Leave the lesson?'),
        content: const Text('Your progress in this lesson will be lost.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep going'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Leave'),
          ),
        ],
      ),
    );
    if (quit == true && mounted) Navigator.pop(context, false);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: GradientBackground(
        child: Scaffold(
          body: SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 20, 8),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: _close,
                        icon: const Icon(Icons.close_rounded),
                      ),
                      Expanded(
                        child: _ProgressBar(
                          value: _progress,
                          color: widget.color,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 350),
                    switchInCurve: Curves.easeOutCubic,
                    transitionBuilder: (child, animation) => FadeTransition(
                      opacity: animation,
                      child: SlideTransition(
                        position: Tween(
                          begin: const Offset(0.15, 0),
                          end: Offset.zero,
                        ).animate(animation),
                        child: child,
                      ),
                    ),
                    child: KeyedSubtree(
                      key: ValueKey(_finished ? 'done' : '$_index'),
                      child: _finished ? _results(context) : _stepView(context),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _stepView(BuildContext context) {
    final step = _steps[_index];
    return switch (step) {
      _Intro() => _introView(context, step),
      _Question() => _questionView(context, step),
    };
  }

  Widget _introView(BuildContext context, _Intro step) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
            children: [
              Row(
                children: [
                  const Mascot(size: 96, talking: true, mood: GhostMood.surprised),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _Bubble(
                      text: 'New word! Read it, then I will quiz you.',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 28),
              GlassCard(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    _Tag(text: 'NEW WORD', color: widget.color),
                    const SizedBox(height: 16),
                    Text(
                      step.word.headword,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.displaySmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (step.word.pluralLine case final plural?)
                      Text(
                        plural,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    const SizedBox(height: 14),
                    Text(
                      step.word.meaning,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        _BottomButton(label: 'Got it', color: widget.color, onPressed: _next),
      ],
    );
  }

  Widget _questionView(BuildContext context, _Question step) {
    final theme = Theme.of(context);
    final answered = _picked != null;
    final right = answered && _picked!.key == step.word.key;
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
            children: [
              Text(
                step.reverse
                    ? 'Which word means this?'
                    : 'What does this mean?',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Mascot(
                    size: 84,
                    talking: answered,
                    mood: !answered
                        ? GhostMood.thinking
                        : (right ? GhostMood.happy : GhostMood.sad),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _Bubble(
                      text: step.reverse ? step.word.meaning : step.word.headword,
                      large: !step.reverse,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              for (final option in step.options)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _OptionTile(
                    text: step.reverse ? option.headword : option.meaning,
                    state: !answered
                        ? _OptionState.idle
                        : option.key == step.word.key
                        ? _OptionState.right
                        : option.key == _picked!.key
                        ? _OptionState.wrong
                        : _OptionState.dimmed,
                    onTap: () => _answer(option),
                  ),
                ),
            ],
          ),
        ),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          transitionBuilder: (child, animation) => SizeTransition(
            sizeFactor: CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
            ),
            alignment: Alignment.topCenter,
            child: child,
          ),
          child: answered
              ? _Feedback(
                  key: const ValueKey('feedback'),
                  right: right,
                  answer: step.reverse ? step.word.headword : step.word.meaning,
                  onContinue: _next,
                )
              : const SizedBox(key: ValueKey('none'), width: double.infinity),
        ),
      ],
    );
  }

  Widget _results(BuildContext context) {
    final theme = Theme.of(context);
    final store = ProfileStore.instance;
    final accuracy = _answered == 0 ? 0 : (_correct * 100 / _answered).round();
    final title = widget.test
        ? (_passed ? 'Level test passed!' : 'Almost there')
        : 'Lesson complete!';
    final subtitle = widget.test
        ? (_passed
              ? 'You unlocked the next part of your path.'
              : 'You need ${(_steps.length * 0.75).ceil()} of ${_steps.length} right. Have another go!')
        : 'You learned ${widget.words.length} new words.';
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
            children: [
              Center(
                child: Mascot(
                  size: 170,
                  talking: _passed,
                  mood: _passed ? GhostMood.love : GhostMood.sad,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: _passed ? widget.color : null,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: _StatBox(
                      icon: widget.test
                          ? Icons.quiz_rounded
                          : Icons.menu_book_rounded,
                      label: widget.test ? 'SCORE' : 'WORDS',
                      value: widget.test
                          ? '$_correct/${_steps.length}'
                          : '+${widget.words.length}',
                      color: widget.color,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _StatBox(
                      icon: Icons.track_changes_rounded,
                      label: 'ACCURACY',
                      value: '$accuracy%',
                      color: _good,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              GlassCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      store.learnedToday >= store.dailyGoal
                          ? 'Daily goal reached!'
                          : 'Daily goal',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 10),
                    _ProgressBar(
                      value: store.learnedToday / store.dailyGoal,
                      color: const Color(0xFFFF9F1C),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${store.learnedToday} of ${store.dailyGoal} words today',
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
        if (widget.test && !_passed)
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 0),
            child: TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Back to path'),
            ),
          ),
        _BottomButton(
          label: widget.test && !_passed ? 'Try again' : 'Continue',
          color: widget.color,
          onPressed: widget.test && !_passed
              ? _restart
              : () => Navigator.pop(context, true),
        ),
      ],
    );
  }
}

class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.value, required this.color});

  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final track = Theme.of(context).colorScheme.onSurfaceVariant
        .withValues(alpha: 0.15);
    return TweenAnimationBuilder<double>(
      tween: Tween(end: value.clamp(0.0, 1.0)),
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeOutCubic,
      builder: (context, v, _) => Container(
        height: 16,
        decoration: BoxDecoration(
          color: track,
          borderRadius: BorderRadius.circular(8),
        ),
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: v,
          child: Container(
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(8),
            ),
            // The light streak on top gives the bar a glossy, raised look.
            alignment: Alignment.topCenter,
            padding: const EdgeInsets.fromLTRB(8, 3, 8, 0),
            child: Container(
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Speech bubble next to the mascot.
class _Bubble extends StatelessWidget {
  const _Bubble({required this.text, this.large = false});

  final String text;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.25),
          width: 2,
        ),
      ),
      child: Text(
        text,
        style: large
            ? theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
              )
            : theme.textTheme.bodyLarge,
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      text,
      style: TextStyle(
        color: color,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.2,
        fontSize: 12,
      ),
    ),
  );
}

enum _OptionState { idle, right, wrong, dimmed }

/// An answer choice with a raised bottom edge that presses down when tapped.
class _OptionTile extends StatefulWidget {
  const _OptionTile({
    required this.text,
    required this.state,
    required this.onTap,
  });

  final String text;
  final _OptionState state;
  final VoidCallback onTap;

  @override
  State<_OptionTile> createState() => _OptionTileState();
}

class _OptionTileState extends State<_OptionTile> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final idleBorder = theme.colorScheme.onSurfaceVariant.withValues(
      alpha: 0.25,
    );
    final (border, fill) = switch (widget.state) {
      _OptionState.right => (_good, _good.withValues(alpha: 0.15)),
      _OptionState.wrong => (_bad, _bad.withValues(alpha: 0.15)),
      _ => (
        idleBorder,
        dark ? const Color(0x14FFFFFF) : Colors.white.withValues(alpha: 0.8),
      ),
    };
    final idle = widget.state == _OptionState.idle;
    final pressed = _down && idle;
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: widget.state == _OptionState.dimmed ? 0.45 : 1,
      child: GestureDetector(
        onTapDown: idle ? (_) => setState(() => _down = true) : null,
        onTapCancel: () => setState(() => _down = false),
        onTapUp: idle
            ? (_) {
                setState(() => _down = false);
                widget.onTap();
              }
            : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 90),
          margin: EdgeInsets.only(top: pressed ? 3 : 0),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(16),
            border: Border(
              top: BorderSide(color: border, width: 2),
              left: BorderSide(color: border, width: 2),
              right: BorderSide(color: border, width: 2),
              bottom: BorderSide(color: border, width: pressed ? 2 : 5),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(widget.text, style: theme.textTheme.bodyLarge),
              ),
              if (widget.state == _OptionState.right)
                const Icon(Icons.check_circle, color: _good)
              else if (widget.state == _OptionState.wrong)
                const Icon(Icons.cancel, color: _bad),
            ],
          ),
        ),
      ),
    );
  }
}

/// Slides up under the options once an answer is picked.
class _Feedback extends StatelessWidget {
  const _Feedback({
    super.key,
    required this.right,
    required this.answer,
    required this.onContinue,
  });

  final bool right;
  final String answer;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = right ? _good : _bad;
    return Container(
      width: double.infinity,
      color: color.withValues(alpha: 0.14),
      padding: const EdgeInsets.fromLTRB(24, 18, 24, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                right ? Icons.check_circle : Icons.cancel,
                color: color,
                size: 28,
              ),
              const SizedBox(width: 10),
              Text(
                right ? 'Nice one!' : 'Not quite',
                style: theme.textTheme.titleLarge?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          if (!right) ...[
            const SizedBox(height: 6),
            Text(
              'Correct answer: $answer',
              style: theme.textTheme.bodyMedium?.copyWith(color: color),
            ),
          ],
          const SizedBox(height: 4),
          _BottomButton(
            label: 'Continue',
            color: color,
            onPressed: onContinue,
            horizontal: 0,
          ),
        ],
      ),
    );
  }
}

class _BottomButton extends StatelessWidget {
  const _BottomButton({
    required this.label,
    required this.color,
    required this.onPressed,
    this.horizontal = 24,
  });

  final String label;
  final Color color;
  final VoidCallback onPressed;
  final double horizontal;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(horizontal, 12, horizontal, 20),
    child: FilledButton(
      style: FilledButton.styleFrom(backgroundColor: color),
      onPressed: onPressed,
      child: Text(
        label.toUpperCase(),
        style: const TextStyle(letterSpacing: 1),
      ),
    ),
  );
}

class _StatBox extends StatelessWidget {
  const _StatBox({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color, width: 2),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w800,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 6),
              Text(
                value,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
