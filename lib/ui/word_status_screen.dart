import 'package:flutter/material.dart';

import '../services/word_service.dart';
import 'app_theme.dart';

/// Words the user marked "I know it" or "Hide", with a way to bring them back.
class WordStatusScreen extends StatelessWidget {
  const WordStatusScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: GradientBackground(
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Known & hidden words'),
            bottom: const TabBar(
              dividerColor: Colors.transparent,
              tabs: [
                Tab(text: 'Known'),
                Tab(text: 'Hidden'),
              ],
            ),
          ),
          body: const TabBarView(
            children: [
              _WordList(
                status: WordStatus.known,
                empty: 'Tap “I know it” on a word notification and it '
                    'will move here instead of coming back.',
              ),
              _WordList(
                status: WordStatus.hidden,
                empty: 'Tap “Hide” on a word you don’t want to see and '
                    'it will move here.',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WordList extends StatefulWidget {
  const _WordList({required this.status, required this.empty});

  final WordStatus status;
  final String empty;

  @override
  State<_WordList> createState() => _WordListState();
}

class _WordListState extends State<_WordList> {
  static const _badges = {'en': 'EN', 'de': 'DE', 'hi': 'HI'};

  final _service = const WordService();
  List<ShownWord>? _words;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final words = await _service.wordsWithStatus(widget.status);
      if (mounted) setState(() => _words = words);
    } catch (_) {
      if (mounted) setState(() => _words = const []);
    }
  }

  Future<void> _restore(ShownWord word) async {
    await _service.setWordStatus(word, WordStatus.active);
    if (!mounted) return;
    setState(() => _words = [...?_words]..remove(word));
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('“${word.word}” will show up in notifications again.'),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () async {
              await _service.setWordStatus(word, widget.status);
              await _load();
            },
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final words = _words;
    if (words == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (words.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            widget.empty,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.4,
            ),
          ),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      itemCount: words.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        final word = words[i];
        return GlassCard(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: kBrandBlue.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Text(
                  _badges[word.lang] ?? word.lang.toUpperCase(),
                  style: const TextStyle(
                    color: kBrandBlue,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      word.word,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      word.meaning,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: () => _restore(word),
                child: const Text('Restore'),
              ),
            ],
          ),
        );
      },
    );
  }
}
