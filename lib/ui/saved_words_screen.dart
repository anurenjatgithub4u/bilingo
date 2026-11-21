import 'package:flutter/material.dart';

import '../services/reading_bank.dart';
import '../services/reels.dart';
import '../services/vocab.dart';
import '../services/word_interactions.dart';
import '../services/word_service.dart';
import 'app_theme.dart';
import 'mascot.dart';

/// Words and maths questions the learner bookmarked or liked in WordFlow,
/// newest first.
class SavedWordsScreen extends StatefulWidget {
  const SavedWordsScreen({super.key, this.service = const WordService()});

  final WordService service;

  @override
  State<SavedWordsScreen> createState() => _SavedWordsScreenState();
}

class _SavedWordsScreenState extends State<SavedWordsScreen> {
  final _interactions = WordInteractions.instance;

  /// Every word of the languages that have a saved or liked word, by id.
  Map<String, VocabWord> _byId = const {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final cloud = _interactions.toCloud();
    final ids = [
      ...(cloud['savedWords'] as List<String>),
      ...(cloud['likedWords'] as List<String>),
    ];
    final langs = {
      for (final id in ids)
        if (parseMathsId(id) == null && !id.startsWith('read|'))
          id.split('|').first,
    };
    final byId = <String, VocabWord>{};
    for (final lang in langs) {
      try {
        for (final w in await widget.service.pathWords(lang)) {
          byId[w.key] = VocabWord(w);
        }
      } catch (_) {
        // Native side unavailable: those words show without a meaning.
      }
    }
    if (mounted) {
      setState(() {
        _byId = byId;
        _loading = false;
      });
    }
  }

  /// A word that is no longer in the list (hidden, or from an older word set).
  VocabWord _fallback(String id) {
    final i = id.indexOf('|');
    return VocabWord(
      ShownWord(
        word: id.substring(i + 1),
        meaning: '',
        lang: id.substring(0, i),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GradientBackground(
      child: DefaultTabController(
        length: 2,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Saved Words'),
            bottom: const TabBar(
              tabs: [
                Tab(text: 'Saved'),
                Tab(text: 'Liked'),
              ],
            ),
          ),
          body: _loading
              ? const Center(child: CircularProgressIndicator())
              : ListenableBuilder(
                  listenable: _interactions,
                  builder: (context, _) {
                    final cloud = _interactions.toCloud();
                    final saved = _interactions.savedIds;
                    final liked = (cloud['likedWords'] as List<String>).reversed
                        .toList();
                    return TabBarView(
                      children: [
                        _list(saved, saved: true),
                        _list(liked, saved: false),
                      ],
                    );
                  },
                ),
        ),
      ),
    );
  }

  Widget _list(List<String> ids, {required bool saved}) {
    final theme = Theme.of(context);
    if (ids.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Mascot(size: 110, mood: GhostMood.thinking),
              const SizedBox(height: 12),
              Text(
                saved
                    ? 'Tap Save on a WordFlow card to keep it here.'
                    : 'Words and questions you like in WordFlow show up here.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge,
              ),
            ],
          ),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      itemCount: ids.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, i) {
        final id = ids[i];
        final maths = parseMathsId(id);
        if (maths != null) return _mathsCard(theme, id, maths, saved: saved);
        if (readingById(id) case final reading?) {
          return _readingCard(theme, reading, saved: saved);
        }
        final word = _byId[id] ?? _fallback(id);
        return GlassCard(
          padding: const EdgeInsets.fromLTRB(18, 14, 8, 14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text.rich(
                      TextSpan(
                        children: [
                          if (word.article != null)
                            TextSpan(
                              text: '${word.article} ',
                              style: TextStyle(color: word.gender?.color),
                            ),
                          TextSpan(text: word.word),
                        ],
                      ),
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (word.meaning.isNotEmpty)
                      Text(
                        word.meaning,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    const SizedBox(height: 4),
                    Text(
                      word.languageName,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: kBrandBlue,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: saved ? 'Remove from saved' : 'Unlike',
                icon: Icon(
                  saved ? Icons.bookmark_rounded : Icons.favorite_rounded,
                  color: saved
                      ? const Color(0xFFFFB300)
                      : const Color(0xFFFF3B5C),
                ),
                onPressed: () => _remove(word.id, word.headword, saved: saved),
              ),
            ],
          ),
        );
      },
    );
  }

  /// A saved maths question with its answer.
  Widget _mathsCard(
    ThemeData theme,
    String id,
    ({String title, String solution}) item, {
    required bool saved,
  }) => GlassCard(
    padding: const EdgeInsets.fromLTRB(18, 14, 8, 14),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.title,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                'Answer: ${item.solution}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                switch (id.split('|').first) {
                  'code' => 'Coding',
                  'quiz' => 'Quiz',
                  _ => 'Maths',
                },
                style: theme.textTheme.labelSmall?.copyWith(
                  color: const Color(0xFF8E5CF7),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: saved ? 'Remove from saved' : 'Unlike',
          icon: Icon(
            saved ? Icons.bookmark_rounded : Icons.favorite_rounded,
            color: saved ? const Color(0xFFFFB300) : const Color(0xFFFF3B5C),
          ),
          onPressed: () => _remove(id, item.title, saved: saved),
        ),
      ],
    ),
  );

  /// A saved paragraph to read aloud: topic, first sentence, language.
  Widget _readingCard(
    ThemeData theme,
    ReadingText reading, {
    required bool saved,
  }) => GlassCard(
    padding: const EdgeInsets.fromLTRB(18, 14, 8, 14),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '📖 ${reading.topic}',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                reading.excerpt,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${reading.lang == 'de' ? 'German' : 'English'} · Read aloud',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: kBrandBlue,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: saved ? 'Remove from saved' : 'Unlike',
          icon: Icon(
            saved ? Icons.bookmark_rounded : Icons.favorite_rounded,
            color: saved ? const Color(0xFFFFB300) : const Color(0xFFFF3B5C),
          ),
          onPressed: () => _remove(reading.id, reading.topic, saved: saved),
        ),
      ],
    ),
  );

  void _remove(String id, String label, {required bool saved}) {
    if (saved) {
      _interactions.setSaved(id, false);
    } else {
      _interactions.setLiked(id, false);
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            saved ? '“$label” removed from saved.' : '“$label” unliked.',
          ),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () => saved
                ? _interactions.setSaved(id, true)
                : _interactions.setLiked(id, true),
          ),
        ),
      );
  }
}
