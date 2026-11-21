import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/vocab.dart';
import '../services/word_service.dart';
import 'app_theme.dart';
import 'mascot.dart';

/// Full view of a word, opened by tapping the notification.
class WordDetailScreen extends StatefulWidget {
  const WordDetailScreen({super.key, required this.word});

  final ShownWord word;

  @override
  State<WordDetailScreen> createState() => _WordDetailScreenState();
}

class _WordDetailScreenState extends State<WordDetailScreen> {
  static const _languageNames = {
    'en': 'English',
    'de': 'German',
    'hi': 'Hindi',
  };

  final _service = const WordService();
  late ShownWord _word = widget.word;
  WordState? _state;
  bool _loadingNext = false;

  @override
  void initState() {
    super.initState();
    _loadState();
  }

  Future<void> _loadState() async {
    try {
      final s = await _service.getState();
      if (mounted) setState(() => _state = s);
    } catch (_) {
      // Progress is optional here; the word itself still shows.
    }
  }

  Future<void> _next() async {
    setState(() => _loadingNext = true);
    try {
      final next = await _service.showWordNow();
      if (next != null && mounted) setState(() => _word = next);
      await _loadState();
    } finally {
      if (mounted) setState(() => _loadingNext = false);
    }
  }

  /// Marks the current word known or hidden, offers Undo, and moves on.
  Future<void> _mark(WordStatus status) async {
    final word = _word;
    HapticFeedback.selectionClick();
    try {
      await _service.setWordStatus(word, status);
    } catch (_) {
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            status == WordStatus.known
                ? 'Nice! “${word.word}” won’t be shown again.'
                : '“${word.word}” is hidden. You won’t see it again.',
          ),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () async {
              await _service.setWordStatus(word, WordStatus.active);
              await _loadState();
            },
          ),
        ),
      );
    await _next();
  }

  String get _languageName =>
      _languageNames[_word.lang] ?? _word.lang.toUpperCase();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = _state;
    final learned = s?.learned[_word.lang] ?? 0;
    final available = s?.available[_word.lang] ?? 0;
    return GradientBackground(
      child: Scaffold(
        appBar: AppBar(title: const Text('Word of the moment')),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            children: [
              const Center(child: Mascot(size: 130, mood: GhostMood.happy)),
              const SizedBox(height: 16),
              GlassCard(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: kBrandBlue.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        _languageName,
                        style: const TextStyle(
                          color: kBrandBlue,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _word.headword,
                      style: theme.textTheme.displaySmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (_word.pluralLine case final plural?)
                      Text(
                        plural,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    const SizedBox(height: 12),
                    Text(
                      _word.meaning,
                      style: theme.textTheme.titleMedium?.copyWith(height: 1.4),
                    ),
                  ],
                ),
              ),
              if (s != null) ...[
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _Stat(value: '${s.shownToday}', label: 'Today'),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _Stat(value: '${s.streak}', label: 'Day streak'),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _Stat(value: '${s.totalShown}', label: 'Total'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                GlassCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '$_languageName progress',
                            style: theme.textTheme.titleSmall,
                          ),
                          Text(
                            '$learned / $available learned',
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      LinearProgressIndicator(
                        value: available == 0 ? 0 : learned / available,
                        minHeight: 8,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _loadingNext ? null : _next,
                icon: const Icon(Icons.skip_next_rounded),
                label: const Text('Next word'),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _SecondaryButton(
                      icon: Icons.check_circle_outline_rounded,
                      label: 'I know it',
                      onPressed: _loadingNext
                          ? null
                          : () => _mark(WordStatus.known),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _SecondaryButton(
                      icon: Icons.visibility_off_outlined,
                      label: 'Hide word',
                      onPressed: _loadingNext
                          ? null
                          : () => _mark(WordStatus.hidden),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              TextButton.icon(
                onPressed: () {
                  Clipboard.setData(
                    ClipboardData(
                      text:
                          '${VocabWord(_word).headwordWithPlural} - '
                          '${_word.meaning}',
                    ),
                  );
                  ScaffoldMessenger.of(context)
                    ..hideCurrentSnackBar()
                    ..showSnackBar(const SnackBar(content: Text('Copied')));
                },
                icon: const Icon(Icons.copy_rounded),
                label: const Text('Copy'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SecondaryButton extends StatelessWidget {
  const _SecondaryButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    style: OutlinedButton.styleFrom(
      minimumSize: const Size.fromHeight(54),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    onPressed: onPressed,
    icon: Icon(icon, size: 20),
    label: Text(label),
  );
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GlassCard(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
      child: Column(
        children: [
          Text(
            value,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
              color: kBrandBlue,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
