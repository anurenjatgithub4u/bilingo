import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/profile_store.dart';
import '../services/word_service.dart';
import 'app_theme.dart';
import 'mascot.dart';
import 'word_detail_screen.dart';

String _greeting() {
  final h = DateTime.now().hour;
  if (h < 12) return 'Good Morning';
  if (h < 17) return 'Good Afternoon';
  if (h < 21) return 'Good Evening';
  return 'Good Night';
}

const _languageTags = {'en': 'EN', 'de': 'DE', 'hi': 'HI'};

class _Message {
  _Message.user(this.text) : fromUser = true, words = const [];
  _Message.bot(this.text, [this.words = const []]) : fromUser = false;

  final String text;
  final bool fromUser;
  final List<ShownWord> words;
}

/// Home: the mascot up top, then a chat where the learner asks about words
/// and BiLingo answers from its built-in word list.
class HomeTab extends StatefulWidget {
  const HomeTab({super.key});

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  final _service = const WordService();
  final _input = TextEditingController();
  final _focus = FocusNode();
  final _scroll = ScrollController();
  final _messages = <_Message>[];

  bool _thinking = false;
  bool _talking = false;
  Timer? _talkTimer;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _talkTimer?.cancel();
    _input.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// "What does X mean?", "meaning of X", "define X" → X.
  static String _extractWord(String input) {
    var s = input.trim().toLowerCase();
    final patterns = [
      RegExp(r'^what(?: does| is|s|’s|' "'" r's) (.+?)(?: mean)?\s*\??$'),
      RegExp(r'^(?:meaning of|define|translate|explain) (.+?)\s*\??$'),
    ];
    for (final p in patterns) {
      final m = p.firstMatch(s);
      if (m != null) {
        s = m.group(1)!;
        break;
      }
    }
    return s.replaceAll(RegExp(r'''^[\s"'“”‘’]+|[\s"'“”‘’?!.,]+$'''), '');
  }

  Future<void> _send([String? preset]) async {
    final text = (preset ?? _input.text).trim();
    if (text.isEmpty || _thinking) return;
    HapticFeedback.selectionClick();
    _input.clear();
    setState(() {
      _messages.add(_Message.user(text));
      _thinking = true;
    });
    _scrollToEnd();

    final word = _extractWord(text);
    List<ShownWord> found = const [];
    try {
      found = await _service.lookup(word);
    } catch (_) {
      // No native side (tests): answer as if nothing matched.
    }
    // A short beat so the reply feels considered rather than instant.
    await Future<void>.delayed(const Duration(milliseconds: 650));
    if (!mounted) return;

    final exact = found.isNotEmpty && found.first.word.toLowerCase() == word;
    _reply(
      found.isEmpty
          ? _Message.bot(
              'I don’t know “$word” yet. Try another word, or tap the dice for a surprise.',
            )
          : _Message.bot(
              exact ? 'Here it is!' : 'Closest words I know:',
              exact ? found.take(1).toList() : found,
            ),
    );
  }

  Future<void> _surprise() async {
    if (_thinking) return;
    HapticFeedback.selectionClick();
    setState(() {
      _messages.add(_Message.user('Surprise me!'));
      _thinking = true;
    });
    _scrollToEnd();
    ShownWord? word;
    try {
      word = await _service.randomWord();
    } catch (_) {}
    await Future<void>.delayed(const Duration(milliseconds: 650));
    if (!mounted) return;
    _reply(
      word == null
          ? _Message.bot('I’m out of words for your languages right now.')
          : _Message.bot('Here’s one for you ✨', [word]),
    );
  }

  void _reply(_Message message) {
    _talkTimer?.cancel();
    setState(() {
      _thinking = false;
      _talking = true;
      _messages.add(message);
    });
    _talkTimer = Timer(const Duration(milliseconds: 1400), () {
      if (mounted) setState(() => _talking = false);
    });
    _scrollToEnd();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
      );
    });
  }

  void _openWord(ShownWord word) {
    _focus.unfocus();
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => WordDetailScreen(word: word)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = ProfileStore.instance;
    // The shell's body ends at the keyboard; without it, clear the pill nav.
    final keyboardOpen = View.of(context).viewInsets.bottom > 0;
    final bottomGap = keyboardOpen ? 12.0 : MediaQuery.paddingOf(context).bottom + 8;
    final chatting = _messages.isNotEmpty;

    return Column(
      children: [
        Expanded(
          child: ListView(
            controller: _scroll,
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            children: [
              Center(
                child: TweenAnimationBuilder<double>(
                  tween: Tween(end: chatting || keyboardOpen ? 130 : 230),
                  duration: const Duration(milliseconds: 450),
                  curve: Curves.easeOutCubic,
                  builder: (context, size, _) => Mascot(
                    size: size,
                    talking: _talking || _thinking,
                    listening: _focus.hasFocus,
                    mood: _thinking ? GhostMood.thinking : null,
                  ),
                ),
              ),
              ListenableBuilder(
                listenable: store,
                builder: (context, _) => _Greeting(name: store.firstName),
              ),
              const SizedBox(height: 20),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: chatting
                    ? const SizedBox.shrink()
                    : _Suggestions(onPick: _send, onSurprise: _surprise),
              ),
              for (final m in _messages)
                _Appear(
                  key: ObjectKey(m),
                  child: m.fromUser
                      ? _UserBubble(text: m.text)
                      : _BotBubble(message: m, onOpenWord: _openWord),
                ),
              if (_thinking)
                const _Appear(key: ValueKey('typing'), child: _TypingBubble()),
            ],
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(16, 4, 16, bottomGap),
          child: _ChatInput(
            controller: _input,
            focusNode: _focus,
            busy: _thinking,
            onSend: _send,
            onSurprise: _surprise,
          ),
        ),
      ],
    );
  }
}

class _Greeting extends StatelessWidget {
  const _Greeting({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        ShaderMask(
          shaderCallback: (bounds) => LinearGradient(
            colors: theme.brightness == Brightness.dark
                ? const [Color(0xFFFFD54F), Color(0xFFFF9F43)]
                : const [Color(0xFFE08A00), Color(0xFFFF6B3D)],
          ).createShader(bounds),
          child: Text(
            name.isEmpty ? _greeting() : '${_greeting()}, $name',
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'What word shall we explore today?',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

/// Starter prompts shown before the first message.
class _Suggestions extends StatelessWidget {
  const _Suggestions({required this.onPick, required this.onSurprise});

  final ValueChanged<String> onPick;
  final VoidCallback onSurprise;

  static const _prompts = [
    'What does serendipity mean?',
    'Define resilient',
    'ephemeral',
  ];

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 8,
      runSpacing: 8,
      children: [
        _Chip(
          icon: Icons.casino_outlined,
          label: 'Surprise me',
          onTap: onSurprise,
          highlight: true,
        ),
        for (final p in _prompts)
          _Chip(icon: Icons.auto_awesome, label: p, onTap: () => onPick(p)),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.icon,
    required this.label,
    required this.onTap,
    this.highlight = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return Material(
      color: highlight
          ? kBrandBlue.withValues(alpha: 0.14)
          : dark
          ? const Color(0x22FFFFFF)
          : Colors.white.withValues(alpha: 0.75),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: kBrandBlue),
              const SizedBox(width: 6),
              Text(
                label,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Fades and slides a chat item in once, when it is first built.
class _Appear extends StatelessWidget {
  const _Appear({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeOutCubic,
      builder: (context, v, child) => Opacity(
        opacity: v,
        child: Transform.translate(
          offset: Offset(0, 18 * (1 - v)),
          child: Transform.scale(scale: 0.96 + 0.04 * v, child: child),
        ),
      ),
      child: Padding(padding: const EdgeInsets.only(bottom: 12), child: child),
    );
  }
}

class _UserBubble extends StatelessWidget {
  const _UserBubble({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.75,
        ),
        child: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF4A90FF), kBrandBlue],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
              bottomLeft: Radius.circular(20),
              bottomRight: Radius.circular(6),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Text(
              text,
              style: const TextStyle(color: Colors.white, fontSize: 15),
            ),
          ),
        ),
      ),
    );
  }
}

class _BotAvatar extends StatelessWidget {
  const _BotAvatar();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 30,
      height: 30,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          center: Alignment(-0.35, -0.5),
          colors: [Color(0xFFD6EFFF), Color(0xFF5BA8FF), Color(0xFF2F6FF0)],
          stops: [0.0, 0.5, 1.0],
        ),
      ),
      child: const Icon(Icons.auto_awesome, size: 15, color: Colors.white),
    );
  }
}

class _BotBubble extends StatelessWidget {
  const _BotBubble({required this.message, required this.onOpenWord});

  final _Message message;
  final ValueChanged<ShownWord> onOpenWord;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _BotAvatar(),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 5),
                child: Text(message.text, style: theme.textTheme.bodyLarge),
              ),
              for (final w in message.words) ...[
                const SizedBox(height: 10),
                _WordCard(word: w, onTap: () => onOpenWord(w)),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _WordCard extends StatelessWidget {
  const _WordCard({required this.word, required this.onTap});

  final ShownWord word;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GlassCard(
      onTap: onTap,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        word.word,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: kBrandBlue.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _languageTags[word.lang] ?? word.lang.toUpperCase(),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: kBrandBlue,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  word.meaning,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right),
        ],
      ),
    );
  }
}

/// Three bouncing dots while BiLingo "thinks".
class _TypingBubble extends StatefulWidget {
  const _TypingBubble();

  @override
  State<_TypingBubble> createState() => _TypingBubbleState();
}

class _TypingBubbleState extends State<_TypingBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    return Row(
      children: [
        const _BotAvatar(),
        const SizedBox(width: 12),
        AnimatedBuilder(
          animation: _c,
          builder: (context, _) => Row(
            children: [
              for (var i = 0; i < 3; i++)
                Transform.translate(
                  offset: Offset(
                    0,
                    -5 * math.max(0, math.sin((_c.value - i * 0.18) * 2 * math.pi)),
                  ),
                  child: Container(
                    width: 8,
                    height: 8,
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.7),
                      shape: BoxShape.circle,
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

/// Rounded prompt box with a slowly rotating gradient border that brightens
/// on focus. The trailing button is a dice until there is text to send.
class _ChatInput extends StatefulWidget {
  const _ChatInput({
    required this.controller,
    required this.focusNode,
    required this.busy,
    required this.onSend,
    required this.onSurprise,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool busy;
  final VoidCallback onSend;
  final VoidCallback onSurprise;

  @override
  State<_ChatInput> createState() => _ChatInputState();
}

class _ChatInputState extends State<_ChatInput>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 6),
  )..repeat();

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
  }

  void _changed() => setState(() {});

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final focused = widget.focusNode.hasFocus;
    final hasText = widget.controller.text.trim().isNotEmpty;

    return AnimatedBuilder(
      animation: _spin,
      builder: (context, child) => AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: EdgeInsets.all(focused ? 2 : 1.4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          gradient: SweepGradient(
            colors: [
              for (final c in const [
                kBrandBlue,
                Color(0xFFB784FF),
                Color(0xFFFF7A9C),
                Color(0xFFFFC83D),
                kBrandBlue,
              ])
                c.withValues(alpha: focused ? 1 : 0.45),
            ],
            transform: GradientRotation(_spin.value * 2 * math.pi),
          ),
          boxShadow: [
            BoxShadow(
              color: kBrandBlue.withValues(alpha: focused ? 0.3 : 0.12),
              blurRadius: focused ? 24 : 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: child,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: dark ? const Color(0xFF111A2E) : Colors.white,
          borderRadius: BorderRadius.circular(26),
        ),
        padding: const EdgeInsets.fromLTRB(18, 4, 6, 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: widget.controller,
                focusNode: widget.focusNode,
                minLines: 1,
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => widget.onSend(),
                style: theme.textTheme.bodyLarge,
                decoration: InputDecoration(
                  filled: false,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 14),
                  hintText: 'Ask about any word…',
                  hintStyle: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant.withValues(
                      alpha: 0.7,
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                transitionBuilder: (child, anim) => ScaleTransition(
                  scale: anim,
                  child: RotationTransition(
                    turns: Tween(begin: 0.75, end: 1.0).animate(anim),
                    child: child,
                  ),
                ),
                child: hasText
                    ? _RoundButton(
                        key: const ValueKey('send'),
                        icon: Icons.arrow_upward_rounded,
                        filled: true,
                        onTap: widget.busy ? null : widget.onSend,
                      )
                    : _RoundButton(
                        key: const ValueKey('dice'),
                        icon: Icons.casino_outlined,
                        filled: false,
                        onTap: widget.busy ? null : widget.onSurprise,
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    super.key,
    required this.icon,
    required this.filled,
    required this.onTap,
  });

  final IconData icon;
  final bool filled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: filled ? kBrandBlue : kBrandBlue.withValues(alpha: 0.12),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 42,
          height: 42,
          child: Icon(icon, color: filled ? Colors.white : kBrandBlue),
        ),
      ),
    );
  }
}
