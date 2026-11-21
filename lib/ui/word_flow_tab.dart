import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/ad_service.dart';
import '../services/arrest_store.dart';
import '../services/content_packs.dart';
import '../services/like_counts.dart';
import '../services/passage_service.dart';
import '../services/premium_store.dart';
import '../services/profile_store.dart';
import '../services/progress_store.dart';
import '../services/rating_service.dart';
import '../services/reading_bank.dart';
import '../services/reading_session.dart';
import '../services/reels.dart';
import '../services/seen_content.dart';
import '../services/speech_service.dart';
import '../services/taste_store.dart';
import '../services/vocab.dart';
import '../services/word_interactions.dart';
import '../services/word_aligner.dart';
import '../services/word_service.dart';
import 'app_theme.dart';
import 'interests_sheet.dart';
import 'mascot.dart';
import 'patrol.dart';
import 'premium_screen.dart';
import 'rating_sheet.dart';
import 'topics.dart';
import 'word_share.dart';

/// Room left at the bottom for the floating navigation bar.
const _navBarSpace = 104.0;

const _correctColor = Color(0xFF2EB67D);
const _wrongColor = Color(0xFFE5484D);
const _quizColor = Color(0xFF8E5CF7);

/// Behind the reel feed in the dark theme, like a video feed. The light
/// theme shows the app's own background.
const _reelBackground = Color(0xFF0E0F13);

/// Edges inside the code panels, which stay dark in both themes.
const _codeBorder = Color(0x26FFFFFF);

/// The reel feed's colours for the app's light or dark theme.
class _Feed {
  const _Feed._(this.dark);

  factory _Feed.of(BuildContext context) =>
      _Feed._(Theme.of(context).brightness == Brightness.dark);

  final bool dark;

  /// Chips, answer buttons and other raised parts.
  Color get surface => dark ? const Color(0xFF1A1B21) : Colors.white;
  Color get border => dark ? const Color(0x26FFFFFF) : const Color(0x1F000000);

  /// Main text and icons, and the quieter version of them.
  Color get ink => dark ? Colors.white : const Color(0xFF14161C);
  Color get muted => dark ? const Color(0x99FFFFFF) : const Color(0x99000000);

  /// A light wash for small circles behind letters and icons.
  Color get faint => dark ? const Color(0x1FFFFFFF) : const Color(0x12000000);

  /// XP, progress and the selected filter: lime on dark, a deeper green on
  /// light so it stays readable.
  Color get xp => dark ? const Color(0xFFB7F34D) : const Color(0xFF3B8A00);

  /// The empty part of progress bars and rings.
  Color get track => dark ? const Color(0x26FFFFFF) : const Color(0x1A000000);
}

/// Reels in each segment of the bar along the top.
const _reelsPerSegment = 5;
const _segments = 3;

/// The maths feed's code in the picker; languages use their own codes.
const _mathsCode = 'math';

/// The difficulty picker's code for Auto; the others are '1' to '3'.
const _autoCode = 'auto';

/// The "What to practise" row that opens the difficulty picker.
const _difficultyCode = 'difficulty';

/// Fewer new reels than this at a picked difficulty, and the learner is told
/// that others fill the feed.
const _fewNew = 5;

/// Home: a full-screen, vertically swiped feed of interactive reels in the
/// learner's language (pick the meaning, der/die/das, spell it, plus plain
/// word cards) or mental-maths questions, with Like, Share and Save on the
/// right of word reels.
class WordFlowTab extends StatefulWidget {
  const WordFlowTab({
    super.key,
    this.service = const WordService(),
    this.interactions,
  });

  final WordService service;

  /// Defaults to [WordInteractions.instance].
  final WordInteractions? interactions;

  @override
  State<WordFlowTab> createState() => _WordFlowTabState();
}

class _WordFlowTabState extends State<WordFlowTab> {
  final _store = ProfileStore.instance;
  var _page = PageController(keepPage: false);
  final _current = ValueNotifier<int>(0);
  var _progress = _ReelProgress();

  late final WordInteractions _interactions =
      widget.interactions ?? WordInteractions.instance;

  String? _feed;
  List<Reel> _reels = const [];
  bool _loading = true;

  /// Bumped per answer, so the header's "+10 XP" plays each time.
  final _reward = ValueNotifier<Reward?>(null);

  /// The Profile setting this feed was built with.
  int? _builtLevel;
  String? _builtFilter;

  /// Nothing more can be added, so the feed ends with a card.
  bool _noMore = false;

  /// When the reel on screen appeared, to notice one swiped straight past.
  DateTime _shownAt = DateTime.now();

  /// Like and save on the reel on screen, to notice them changing.
  bool _liked = false;
  bool _saved = false;
  var _generation = 0;
  bool _extending = false;

  String get _feedKey =>
      _store.flowCode ?? (_store.flowMaths ? _mathsCode : _store.language);

  @override
  void initState() {
    super.initState();
    _store.addListener(_onStore);
    _interactions.addListener(_onInteraction);
    _load();
  }

  @override
  void dispose() {
    _store.removeListener(_onStore);
    _interactions.removeListener(_onInteraction);
    _page.dispose();
    _current.dispose();
    super.dispose();
  }

  /// Whose like and save a reel shows, if it has them.
  String? _interactionId(Reel reel) => switch (reel) {
    LearnReel(:final word) ||
    MeaningReel(:final word) ||
    ArticleReel(:final word) ||
    SpellReel(:final word) => word.id,
    MathsItem(:final saveId) => saveId,
    ReadingReel() => reel.id,
    WordSearchReel(:final words) => words.first.id,
    _ => null,
  };

  /// A new reel is on screen: its taste signals start from here.
  void _showReel(Reel reel) {
    _shownAt = DateTime.now();
    TasteStore.instance.current = reelTopics(reel);
    final id = _interactionId(reel);
    final state = id == null ? null : _interactions.stateOf(id);
    _liked = state?.isLiked ?? false;
    _saved = state?.isSaved ?? false;
  }

  /// Liking or saving the reel on screen says the most about taste.
  void _onInteraction() {
    final at = _current.value;
    if (at >= _reels.length) return;
    final id = _interactionId(_reels[at]);
    if (id == null) return;
    final state = _interactions.stateOf(id);
    if (state.isLiked && !_liked) {
      TasteStore.instance.signalCurrent(TasteStore.like);
    }
    if (state.isSaved && !_saved) {
      TasteStore.instance.signalCurrent(TasteStore.save);
    }
    _liked = state.isLiked;
    _saved = state.isSaved;
  }

  /// The chosen chip for [feed], if that feed still has it.
  String _filterOf(String feed) {
    final filter = _store.flowFilter(feed);
    return filtersFor(feed).any((f) => f.$1 == filter) ? filter : kFilterAll;
  }

  void _onStore() {
    if (_feedKey != _feed ||
        _store.level != _builtLevel ||
        _filterOf(_feedKey) != _builtFilter) {
      _load();
    }
  }

  Future<void> _load() async {
    final feed = _feedKey;
    final filter = _filterOf(feed);
    _feed = feed;
    _builtFilter = filter;
    setState(() => _loading = true);
    _builtLevel = _store.level;
    final seen = SeenContent.instance;
    await seen.ensureLoaded();
    await ProgressStore.instance.ensureLoaded();
    await ContentPacks.instance.ensureLoaded();
    await TasteStore.instance.ensureLoaded();
    ProgressStore.instance.startTier = _store.level;
    _generation = 0;
    final reels = await _build(feed, _generation);
    if (!mounted || feed != _feed || filter != _builtFilter) return;
    // A new list starts at its first reel with a fresh controller; the old
    // one is still attached until this frame is built.
    final old = _page;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      old.dispose();
    });
    final chosen = ProgressStore.instance.chosenTier(feed);
    // Counted before the first reel is marked seen.
    final freshAtChosen = chosen == null
        ? 0
        : reels
              .where((r) => reelLevel(r) == chosen && !seen.has(contentKey(r)))
              .length;
    setState(() {
      _reels = reels;
      _loading = false;
      _page = PageController(keepPage: false);
      _progress = _ReelProgress(
        subject: feed,
        onReward: _onReward,
        onReleased: _onReleased,
      )..addLevels(reels);
      _noMore = false;
    });
    _current.value = 0;
    if (chosen != null && reels.isNotEmpty && freshAtChosen < _fewNew) {
      _tellMixed(chosen, none: freshAtChosen == 0);
    }
    if (reels.isNotEmpty) {
      SeenContent.instance.mark(contentKey(reels.first));
      _showReel(reels.first);
    }
    _askInterests();
    if (reels.length < 5) unawaited(_extend());
  }

  /// Once, for anyone past onboarding who hasn't been asked yet.
  Future<void> _askInterests() async {
    if (!_store.onboarded || TasteStore.instance.asked) return;
    await TasteStore.instance.markAsked();
    if (!mounted) return;
    if (await showInterestsSheet(context) && mounted) _load();
  }

  /// One batch of reels for [feed], at the learner's current difficulty.
  Future<List<Reel>> _build(String feed, int generation) async {
    final now = DateTime.now();
    // Changes daily but not on every visit.
    final random = math.Random(
      now.year * 10000 + now.month * 100 + now.day + generation * 7919,
    );
    final seen = SeenContent.instance;
    final progress = ProgressStore.instance;
    // A picked difficulty stays put; Auto also slips in harder stretch items.
    final auto = progress.chosenTier(feed) == null;
    final tier = progress.feedTier(feed);
    final filter = _filterOf(feed);
    final taste = TasteStore.instance;
    if (feed == _mathsCode) {
      return buildMathReels(
        tier,
        random,
        avoid: seen.keys,
        filter: filter,
        favourites: favouriteMathKinds(taste),
        stretch: auto,
      );
    }
    final items = ContentPacks.instance.itemsFor(feed);
    final questions = levelledFeed<Reel>(
      [for (final i in items) reelFromItem(i, random)],
      levelOf: (r) => (r as MathsItem).level,
      keyOf: contentKey,
      tier: tier,
      seen: seen,
      random: random,
      tasteOf: (r) => taste.scoreOf(reelTopics(r)),
      stretch: auto,
    );
    if (kCodeNames.containsKey(feed)) {
      return [
        for (final q in questions)
          if (matchesFilter(q, filter)) q,
      ];
    }

    List<ShownWord> shown = const [];
    try {
      shown = await widget.service.pathWords(feed);
    } catch (_) {
      // No native side: the empty state shows.
    }
    final words = [for (final w in shown) VocabWord(w)];
    final due = progress.dueWords(feed).toSet();
    return buildWordReels(
      levelledFeed<VocabWord>(
        words,
        levelOf: (w) => w.level,
        keyOf: (w) => 'w|${w.id}',
        tier: tier,
        seen: seen,
        random: random,
        tasteOf: (w) => taste.score(wordTopic(w.id)),
        review: [
          for (final w in words)
            if (due.contains(w.id)) w,
        ],
        stretch: auto,
      ),
      random,
      readings: levelledFeed<ReadingText>(
        readingTexts(feed),
        levelOf: (t) => t.level,
        keyOf: (t) => t.id,
        tier: tier,
        seen: seen,
        random: random,
        tasteOf: (t) => taste.score(readingTopic(t.topic)),
        stretch: auto,
      ),
      quizzes: questions,
      filter: filter,
    );
  }

  /// Near the end, adds another batch: anything not already in this feed.
  /// Maths never runs out; a word comes back as a reel type not used yet.
  Future<void> _extend() async {
    final feed = _feed;
    if (_extending || feed == null) return;
    _extending = true;
    try {
      final inFeed = {for (final r in _reels) r.id};
      final more = await _build(feed, ++_generation);
      final fresh = more.where((r) => inFeed.add(r.id)).toList();
      if (!mounted || feed != _feed) return;
      setState(() {
        if (fresh.isEmpty) {
          _noMore = true;
        } else {
          _reels = [..._reels, ...fresh];
          _progress.addLevels(fresh);
        }
      });
    } finally {
      _extending = false;
    }
  }

  void _onReward(Reward reward) {
    TasteStore.instance.signalCurrent(TasteStore.answered);
    _reward.value = reward;
    unawaited(RatingService.instance.recordReelAnswered());
    if (reward.leveledUp && mounted) {
      _showLevelUp(reward.level);
    } else {
      _checkRatingMilestone();
    }
    _checkHardLimit();
  }

  void _checkRatingMilestone() {
    final rating = RatingService.instance;
    final progress = ProgressStore.instance;
    final goal = ProfileStore.instance.dailyGoal;
    RatingTrigger? trigger;
    if (rating.totalReelsAnswered == RatingService.minReelsBeforePrompt) {
      trigger = RatingTrigger.firstTenReels;
    } else if (progress.answeredToday == goal) {
      trigger = RatingTrigger.dailyGoal;
    }
    if (trigger == null || !rating.shouldPrompt()) return;
    Future.delayed(const Duration(milliseconds: 1400), () async {
      if (!mounted) return;
      await rating.promptIfEligible(context, trigger: trigger!);
    });
  }

  /// Free Hard reels left today.
  int get _hardLeft =>
      (kFreeHardPerDay - ProgressStore.instance.hardAnsweredToday).clamp(
        0,
        kFreeHardPerDay,
      );

  /// The last free Hard reel of the day: once its answer has been seen,
  /// back to Auto, with the way to unlimited Hard.
  void _checkHardLimit() {
    final feed = _feed ?? _feedKey;
    final progress = ProgressStore.instance;
    if (PremiumStore.instance.isPremium ||
        progress.chosenTier(feed) != 3 ||
        _hardLeft > 0) {
      return;
    }
    Future.delayed(const Duration(milliseconds: 1500), () async {
      if (!mounted || progress.chosenTier(feed) != 3) return;
      await progress.setDifficulty(feed, null);
      if (!mounted) return;
      await _load();
      if (!mounted) return;
      final upgrade = await showModalBottomSheet<bool>(
        context: context,
        showDragHandle: true,
        builder: (context) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Mascot(size: 110, mood: GhostMood.wink),
                Text(
                  'That’s today’s $kFreeHardPerDay free Hard reels',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                const Text(
                  'You’re back on Auto. Come back tomorrow for more, or go '
                  'Premium for unlimited Hard reels.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                  onPressed: () => Navigator.pop(context, true),
                  icon: const Icon(Icons.workspace_premium_rounded),
                  label: const Text('Go Premium'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('OK'),
                ),
              ],
            ),
          ),
        ),
      );
      if (upgrade == true && mounted) await showPremium(context);
    });
  }

  /// Bail paid by this answer: the XP, then the celebration.
  Future<void> _onReleased() async {
    final xp = ArrestStore.instance.bailReward;
    _reward.value = ProgressStore.instance.addXp(_feed ?? _feedKey, xp);
    if (mounted) await showReleased(context, xp);
    if (mounted) {
      await RatingService.instance.promptIfEligible(
        context,
        trigger: RatingTrigger.bailPaid,
      );
    }
  }

  Future<void> _showLevelUp(int level) async {
    HapticFeedback.heavyImpact();
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 350),
      transitionBuilder: (_, animation, _, child) => ScaleTransition(
        scale: CurvedAnimation(parent: animation, curve: Curves.easeOutBack),
        child: child,
      ),
      pageBuilder: (context, _, _) {
        final theme = Theme.of(context);
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Material(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(28),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Mascot(size: 130, mood: GhostMood.love),
                    Text(
                      'Level $level!',
                      style: theme.textTheme.displaySmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: kBrandBlue,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(rankName(level), style: theme.textTheme.titleMedium),
                    const SizedBox(height: 18),
                    FilledButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Keep going'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
    if (mounted) {
      await RatingService.instance.promptIfEligible(
        context,
        trigger: RatingTrigger.levelUp,
      );
    }
  }

  /// One picker sheet; returns the chosen code. [selected] gets the tick,
  /// the current feed by default. [lead] is an extra row above the choices,
  /// set apart by a line.
  Future<String?> _pickSheet(
    String title,
    List<(String, String, String, IconData)> choices, {
    String? selected,
    (String, String, String, IconData)? lead,
  }) => showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    // Grows to fit every choice, and scrolls on a short screen.
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: Text(title, style: Theme.of(context).textTheme.titleLarge),
            ),
            if (lead case (
              final code,
              final name,
              final subtitle,
              final icon,
            )) ...[
              ListTile(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                leading: Icon(icon),
                title: Text(name),
                subtitle: Text(subtitle),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.pop(context, code),
              ),
              const Divider(indent: 16, endIndent: 16),
            ],
            for (final (code, name, subtitle, icon) in choices)
              ListTile(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                leading: Icon(icon),
                title: Text(name),
                subtitle: Text(subtitle),
                trailing: code == (selected ?? _feedKey)
                    ? const Icon(Icons.check_circle, color: kBrandBlue)
                    : null,
                onTap: () => Navigator.pop(context, code),
              ),
          ],
        ),
      ),
    ),
  );

  Future<void> _pickFeed() async {
    final chosen = ProgressStore.instance.chosenTier(_feed ?? _feedKey);
    var code = await _pickSheet(
      'What to practise',
      [
        for (final t in kTopics) (t.code, t.name, t.subtitle, t.icon),
        (_mathsCode, 'Maths', 'Quick mental maths', Icons.calculate_outlined),
        (kCodingCode, 'Coding', 'Python & JavaScript logic', Icons.code_rounded),
      ],
      lead: (
        _difficultyCode,
        'Difficulty: ${chosen == null ? 'Auto' : kDifficultyNames[chosen]}',
        chosen == null
            ? 'Follows how you’re doing'
            : 'Harder ones earn more XP',
        Icons.tune_rounded,
      ),
    );
    if (code == _difficultyCode) {
      await _pickDifficulty();
      return;
    }
    if (code == null || code == _feedKey) return;
    if (code == _mathsCode) {
      await _store.setFlowMaths(true);
      return;
    }
    if (kCodeNames.containsKey(code)) {
      await _store.setFlowCode(code);
      return;
    }
    // Language first, while maths is still on, so the feed loads only once.
    if (code != _store.language) {
      await _store.setLanguage(code);
      try {
        await widget.service.update(languages: {code});
      } catch (_) {
        // Notification languages can still be changed in their own settings.
      }
    }
    await _store.setFlowMaths(false);
  }

  /// Auto, Easy, Medium or Hard for the feed on screen; rebuilds it on a
  /// change.
  Future<void> _pickDifficulty() async {
    final feed = _feed ?? _feedKey;
    final progress = ProgressStore.instance;
    String multiplier(int tier) {
      final m = xpMultiplier(tier);
      return '×${m == m.roundToDouble() ? m.toInt() : m} XP';
    }

    final code = await _pickSheet('How hard?', [
      (
        _autoCode,
        'Auto (recommended)',
        'Follows how you’re doing · now ${kDifficultyNames[progress.tierOf(feed)]}',
        Icons.auto_awesome_rounded,
      ),
      (
        '1',
        kDifficultyNames[1]!,
        'Warm-ups and basics · ${multiplier(1)}',
        Icons.signal_cellular_alt_1_bar_rounded,
      ),
      (
        '2',
        kDifficultyNames[2]!,
        'A real challenge · ${multiplier(2)}',
        Icons.signal_cellular_alt_2_bar_rounded,
      ),
      (
        '3',
        kDifficultyNames[3]!,
        PremiumStore.instance.isPremium
            ? 'For what you know well · ${multiplier(3)}'
            : '${multiplier(3)} · $_hardLeft of $kFreeHardPerDay free today',
        Icons.signal_cellular_alt_rounded,
      ),
    ], selected: '${progress.chosenTier(feed) ?? _autoCode}');
    if (code == null || !mounted) return;
    final tier = int.tryParse(code);
    if (tier == progress.chosenTier(feed)) return;
    if (tier == 3 && !PremiumStore.instance.isPremium && _hardLeft == 0) {
      await showPremium(
        context,
        reason: 'You’ve used today’s $kFreeHardPerDay free Hard reels.',
      );
      return;
    }
    HapticFeedback.selectionClick();
    await progress.setDifficulty(feed, tier);
    if (mounted) await _load();
  }

  /// Says so when a picked difficulty has run low on new reels and others
  /// fill the feed.
  void _tellMixed(int tier, {required bool none}) {
    final name = kDifficultyNames[tier]!;
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.fromLTRB(16, 0, 16, _navBarSpace),
          content: Text(
            none
                ? 'No new $name ones right now, so you’ll see others too.'
                : 'Only a few new $name ones left, so others are mixed in.',
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    // Up behind the status bar too; the shell's SafeArea starts below it.
    final view = View.of(context);
    final top = view.padding.top / view.devicePixelRatio;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Theme(
        data: buildTheme(dark ? Brightness.dark : Brightness.light),
        child: Builder(
          builder: (context) => Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                top: -top,
                left: 0,
                right: 0,
                bottom: -view.padding.bottom / view.devicePixelRatio,
                child: ColoredBox(
                  color: dark ? _reelBackground : Colors.transparent,
                ),
              ),
              Positioned.fill(
                child: Column(
                  children: [
                    _StoryBar(current: _current),
                    _Header(
                      feed: _feed ?? _feedKey,
                      reward: _reward,
                      onFeed: _pickFeed,
                    ),
                    _FilterChips(
                      feed: _feed ?? _feedKey,
                      selected: _filterOf(_feed ?? _feedKey),
                      onSelect: (f) {
                        HapticFeedback.selectionClick();
                        _store.setFlowFilter(_feed ?? _feedKey, f);
                      },
                    ),
                    _GoalBanner(
                      feed: _feed ?? _feedKey,
                      onChange: _pickDifficulty,
                    ),
                    const BailBanner(),
                    Expanded(
                      child: _DifficultyScope(
                        onPick: _pickDifficulty,
                        child: _loading
                            ? const Center(child: CircularProgressIndicator())
                            : _reels.isEmpty
                            ? _Empty(filtered: _builtFilter != kFilterAll)
                            : PageView.builder(
                                key: ValueKey(_page),
                                controller: _page,
                                scrollDirection: Axis.vertical,
                                itemCount: _reels.length + (_noMore ? 1 : 0),
                                onPageChanged: (i) {
                                  ProgressStore.instance.touchLearning();
                                  // Gone within two seconds and not tried: not their thing.
                                  final was = _current.value;
                                  if (was < _reels.length &&
                                      !_progress.attempted.contains(
                                        _reels[was].id,
                                      ) &&
                                      DateTime.now()
                                              .difference(_shownAt)
                                              .inSeconds <
                                          2) {
                                    TasteStore.instance.signal(
                                      reelTopics(_reels[was]),
                                      TasteStore.skipped,
                                    );
                                  }
                                  if (i >= _reels.length) return;
                                  _current.value = i;
                                  _showReel(_reels[i]);
                                  SeenContent.instance.mark(
                                    contentKey(_reels[i]),
                                  );
                                  if (i >= _reels.length - 4) _extend();
                                  AdService.instance.onReelSwiped();
                                },
                                itemBuilder: (context, i) => i >= _reels.length
                                    ? _EndCard(
                                        filtered: _builtFilter != kFilterAll,
                                        onReview: _load,
                                        onAll: () => _store.setFlowFilter(
                                          _feed ?? _feedKey,
                                          kFilterAll,
                                        ),
                                      )
                                    : _ReelPage(
                                        key: ValueKey(_reels[i].id),
                                        reel: _reels[i],
                                        progress: _progress,
                                        interactions: _interactions,
                                        service: widget.service,
                                        showHint: i == 0,
                                        subject: _feed ?? _feedKey,
                                        onNext: () {
                                          if (_page.hasClients) {
                                            _page.nextPage(
                                              duration: const Duration(
                                                milliseconds: 320,
                                              ),
                                              curve: Curves.easeInOut,
                                            );
                                          }
                                        },
                                      ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Answers given in the current feed, so a reel looks the same when the
/// learner swipes back to it, plus the run of correct answers.
class _ReelProgress {
  _ReelProgress({this.subject = '', this.onReward, this.onReleased});

  final String subject;
  final void Function(Reward)? onReward;

  /// The answer that paid the last of a Scroll Patrol bail.
  final VoidCallback? onReleased;
  final choices = <String, int>{};

  /// Spelling and make-the-target reels solved.
  final solved = <String>{};
  final attempted = <String>{};

  /// Each reel's difficulty, 1–3, which sets the XP an answer earns.
  final levels = <String, int>{};

  void addLevels(Iterable<Reel> reels) {
    for (final r in reels) {
      levels[r.id] = reelLevel(r);
    }
  }

  /// Counts only the first try at each reel.
  void record(String reelId, {required bool correct, int bonus = 0}) {
    ProgressStore.instance.touchLearning();
    if (!attempted.add(reelId)) return;
    unawaited(ProfileStore.instance.recordAnswer(correct: correct));
    // Quiz and spelling reels are the ones that test a word.
    final at = reelId.indexOf('|');
    final kind = at < 0 ? '' : reelId.substring(0, at);
    final wordId = const {'meaning', 'article', 'spell'}.contains(kind)
        ? reelId.substring(at + 1)
        : null;
    final reward = ProgressStore.instance.record(
      subject,
      correct: correct,
      bonus: bonus,
      wordId: wordId,
      difficulty: levels[reelId] ?? 1,
    );
    onReward?.call(reward);
    if (ArrestStore.instance.onAnswered()) onReleased?.call();
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.feed,
    required this.reward,
    required this.onFeed,
  });

  final String feed;
  final ValueListenable<Reward?> reward;
  final VoidCallback onFeed;

  String get _flagEmoji => switch (feed) {
    'de' => '🇩🇪',
    'en' => '🇬🇧',
    'hi' => '🇮🇳',
    'math' => '🔢',
    'coding' => '💻',
    'javascript' => '📜',
    'python' => '🐍',
    _ => '🌐',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final maths = feed == _mathsCode;
    final feedName = maths
        ? 'Maths'
        : kCodeNames[feed] ?? kLanguageNames[feed] ?? feed.toUpperCase();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
      child: Row(
        children: [
          ListenableBuilder(
            listenable: ProgressStore.instance,
            builder: (context, _) {
              final days = ProgressStore.instance.practiceStreak;
              if (days == 0) return const SizedBox.shrink();
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0x33FF7A00),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text('🔥 $days', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
              );
            },
          ),
          const Spacer(),
          Semantics(
            button: true,
            label: 'Change what to practise: $feedName',
            excludeSemantics: true,
            child: GestureDetector(
              onTap: onFeed,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? const Color(0xFF222430)
                      : const Color(0xFFF1F3F8),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_flagEmoji, style: const TextStyle(fontSize: 16)),
                    const SizedBox(width: 6),
                    Text(
                      feedName,
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: Theme.of(context).brightness == Brightness.dark
                            ? Colors.white
                            : const Color(0xFF1E2028),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 18,
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Colors.white70
                          : const Color(0xFF5A5D6B),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Goal banner showing user's target with change button.
class _GoalBanner extends StatelessWidget {
  const _GoalBanner({required this.feed, required this.onChange});

  final String feed;
  final VoidCallback onChange;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final maths = feed == _mathsCode;
    final feedName = maths
        ? 'Maths'
        : kCodeNames[feed] ?? kLanguageNames[feed] ?? 'English';

    return ListenableBuilder(
      listenable: ProfileStore.instance,
      builder: (context, _) {
        final goal = ProfileStore.instance.dailyGoal;
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: dark
                  ? const Color(0xFF24223A)
                  : const Color(0xFFEDE8FF),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: dark ? const Color(0xFF332F52) : Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: const Text('🎯', style: TextStyle(fontSize: 22)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Your Goal',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: dark
                              ? const Color(0xFFAAA5C7)
                              : const Color(0xFF6B5899),
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        'Master $feedName · $goal/day',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: dark
                              ? Colors.white
                              : const Color(0xFF261858),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Material(
                  color: dark ? const Color(0xFF3B3566) : const Color(0xFFDDD2FA),
                  borderRadius: BorderRadius.circular(16),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: onChange,
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                      child: Text(
                        'Change',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF5B3FE6),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Lets any reel's difficulty pill open the difficulty picker.
class _DifficultyScope extends InheritedWidget {
  const _DifficultyScope({required this.onPick, required super.child});

  final VoidCallback onPick;

  static VoidCallback? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_DifficultyScope>()?.onPick;

  @override
  bool updateShouldNotify(_DifficultyScope old) => old.onPick != onPick;
}

class _Empty extends StatelessWidget {
  const _Empty({this.filtered = false});

  final bool filtered;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: _navBarSpace),
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Mascot(size: 120, mood: GhostMood.thinking),
          const SizedBox(height: 12),
          Text(
            filtered
                ? 'Nothing here yet. Try another filter.'
                : 'No words for this language yet.',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ],
      ),
    ),
  );
}

/// One screen of the feed: the reel's card with its actions beside it.
class _ReelPage extends StatefulWidget {
  const _ReelPage({
    super.key,
    required this.reel,
    required this.progress,
    required this.interactions,
    required this.service,
    required this.showHint,
    required this.subject,
    this.onNext,
  });

  /// The feed's code, for the name under the reel.
  final String subject;
  final Reel reel;
  final _ReelProgress progress;
  final WordInteractions interactions;
  final WordService service;
  final bool showHint;
  final VoidCallback? onNext;

  @override
  State<_ReelPage> createState() => _ReelPageState();
}

class _ReelPageState extends State<_ReelPage>
    with SingleTickerProviderStateMixin {
  /// Big heart that pops over the card on a double tap.
  late final _burst = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  );

  VocabWord? get _word => switch (widget.reel) {
    LearnReel(:final word) => word,
    MeaningReel(:final word) => word,
    ArticleReel(:final word) => word,
    SpellReel(:final word) => word,
    _ => null,
  };

  @override
  void dispose() {
    _burst.dispose();
    super.dispose();
  }

  void _doubleTap(VocabWord word) {
    HapticFeedback.lightImpact();
    // Like a reel: a double tap only ever likes.
    widget.interactions.setLiked(word.id, true);
    _burst.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final reel = widget.reel;
    final word = _word;
    final Widget card = switch (reel) {
      // Double tap to like only on plain cards, so it never delays an answer.
      LearnReel(:final word) => GestureDetector(
        onDoubleTap: () => _doubleTap(word),
        child: Stack(
          fit: StackFit.expand,
          children: [
            _WordCard(word: word, showHint: widget.showHint),
            Center(
              child: IgnorePointer(child: _HeartBurst(animation: _burst)),
            ),
          ],
        ),
      ),
      SpellReel() => _SpellCard(reel: reel, progress: widget.progress),
      TargetReel() => _TargetCard(reel: reel, progress: widget.progress),
      BlitzReel() => _BlitzCard(reel: reel, progress: widget.progress),
      SortReel() => _SortCard(reel: reel, progress: widget.progress),
      MemoryReel() => _MemoryCard(reel: reel, progress: widget.progress),
      SudokuReel() => _SudokuCard(reel: reel, progress: widget.progress),
      ReadingReel() => _ReadingCard(reel: reel, progress: widget.progress),
      OrderLinesReel() => _OrderLinesCard(
        reel: reel,
        progress: widget.progress,
      ),
      WordSearchReel() => _WordSearchCard(
        reel: reel,
        progress: widget.progress,
      ),
      ChoiceReel() => _ChoiceCard(
        reel: reel,
        progress: widget.progress,
        showHint: widget.showHint,
        onNext: widget.onNext,
      ),
      // Every maths reel is one of the above; the mixin alone never is.
      MathsItem() => const SizedBox.shrink(),
    };

    final dark = Theme.of(context).brightness == Brightness.dark;
    final actionBar = word != null
        ? WordFlowActionBar(
            word: word,
            interactions: widget.interactions,
            service: widget.service,
          )
        : reel is MathsItem
        ? _MathsActionBar(
            item: reel,
            interactions: widget.interactions,
            service: widget.service,
          )
        : reel is ReadingReel
        ? _ReadingActionBar(
            reel: reel,
            interactions: widget.interactions,
            service: widget.service,
          )
        : reel is WordSearchReel
        ? _WordSearchActionBar(
            reel: reel,
            interactions: widget.interactions,
            service: widget.service,
          )
        : null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, _navBarSpace),
      child: Container(
        decoration: BoxDecoration(
          color: dark ? const Color(0xFF1E2028) : Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: dark
              ? const []
              : const [
                  BoxShadow(
                    color: Color(0x12000000),
                    blurRadius: 18,
                    offset: Offset(0, 6),
                  ),
                ],
        ),
        padding: const EdgeInsets.fromLTRB(16, 16, 10, 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: card),
                  const SizedBox(height: 8),
                  _ReelFooter(subject: widget.subject, reel: reel),
                ],
              ),
            ),
            if (actionBar != null) ...[
              const SizedBox(width: 8),
              Align(
                alignment: Alignment.topRight,
                child: actionBar,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Who it's from and how long it takes.
class _ReelFooter extends StatelessWidget {
  const _ReelFooter({required this.subject, required this.reel});

  final String subject;
  final Reel reel;

  static const _names = {
    'coding': ('CODE', '@coding.daily'),
    'python': ('PY', '@python.daily'),
    'javascript': ('JS', '@js.daily'),
    'math': ('MA', '@maths.daily'),
    'de': ('DE', '@german.daily'),
    'en': ('EN', '@english.daily'),
  };

  /// A rough time for this reel, in seconds.
  int get _seconds => switch (reel) {
    SudokuReel() => 60,
    WordSearchReel() => 45,
    BlitzReel(:final seconds) => seconds,
    MemoryReel() || SortReel() || TargetReel() || OrderLinesReel() => 20,
    CodeReel(:final code) => 5 + 2 * '\n'.allMatches(code).length,
    _ => 8,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final (badge, name) = _names[subject] ??
        (
          subject.length > 2 ? subject.substring(0, 2).toUpperCase() : subject.toUpperCase(),
          '@$subject.daily',
        );
    final seconds = _seconds;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 8, 2),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: dark ? const Color(0xFF282A36) : const Color(0xFFF1F3F8),
              border: Border.all(
                color: dark ? const Color(0x33FFFFFF) : const Color(0xFFE2E5EE),
              ),
            ),
            child: Text(
              badge,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 12,
                color: dark ? Colors.white70 : const Color(0xFF4B4F5E),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
                Text(
                  '$seconds sec read · quick win',
                  maxLines: 1,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: _Feed.of(context).muted,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Height a reel's content needs before it has to shrink.
const _minCardHeight = 450.0;

/// The space a reel's content sits in: flat on the dark feed.
class _CardShell extends StatelessWidget {
  const _CardShell({required this.compact, required this.child});

  final bool compact;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) => box.maxHeight >= _minCardHeight
          ? child
          : FittedBox(
              child: SizedBox(
                width: box.maxWidth,
                height: _minCardHeight,
                child: child,
              ),
            ),
    );
  }
}

Color _levelColor(int level) => switch (level) {
  1 => const Color(0xFF2EB67D),
  3 => const Color(0xFF8E5CF7),
  _ => kBrandBlue,
};

/// Kind, subject and level pills along the top of a quiz reel.
class _ReelPills extends StatelessWidget {
  const _ReelPills({
    required this.kind,
    required this.subject,
    required this.level,
  });

  final String kind;
  final String subject;
  final int level;

  @override
  Widget build(BuildContext context) {
    final label = kind.startsWith('What does') ? 'Output' : kind;
    final topicText = subject.isNotEmpty ? '$subject • $label' : label;
    final onPick = _DifficultyScope.of(context);
    final diffName = kDifficultyNames[level] ?? 'Medium';

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Topic pill (Blue)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: const Color(0xFFE8F1FF),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Text(
            topicText,
            style: const TextStyle(
              color: Color(0xFF2F80FF),
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ),
        const SizedBox(width: 8),
        // Difficulty pill (Amber)
        GestureDetector(
          onTap: onPick,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF4E5),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.signal_cellular_alt_rounded,
                  size: 14,
                  color: Color(0xFFD97706),
                ),
                const SizedBox(width: 4),
                Text(
                  diffName,
                  style: const TextStyle(
                    color: Color(0xFFD97706),
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// "Correct!" or "Not quite" with the explanation, after an answer.
class _Feedback extends StatelessWidget {
  const _Feedback({
    required this.correct,
    required this.text,
    required this.compact,
    this.title,
    this.onViewMore,
  });

  final bool correct;
  final String text;
  final bool compact;
  final String? title;
  final VoidCallback? onViewMore;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = correct
        ? (dark ? const Color(0xFF143322) : const Color(0xFFE8F8F0))
        : (dark ? const Color(0xFF38181A) : const Color(0xFFFFECEF));
    final iconColor = correct ? const Color(0xFF22C55E) : const Color(0xFFE5484D);
    final titleColor = correct
        ? (dark ? const Color(0xFF4ADE80) : const Color(0xFF166534))
        : (dark ? const Color(0xFFF87171) : const Color(0xFF991B1B));

    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: 14,
        vertical: compact ? 10 : 12,
      ),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            correct ? Icons.check_circle_rounded : Icons.lightbulb_rounded,
            color: iconColor,
            size: 24,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title ?? (correct ? 'Correct! 🎉 +10 XP' : 'Not quite.'),
                        style: TextStyle(
                          color: titleColor,
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    if (onViewMore != null)
                      GestureDetector(
                        onTap: onViewMore,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'View More',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: dark ? Colors.white70 : const Color(0xFF374151),
                              ),
                            ),
                            const SizedBox(width: 2),
                            Icon(
                              Icons.arrow_forward_rounded,
                              size: 13,
                              color: dark ? Colors.white70 : const Color(0xFF374151),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                if (text.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    text,
                    maxLines: compact ? 2 : 4,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.3,
                      color: dark ? Colors.white70 : const Color(0xFF374151),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Bottom line of a reel: a nudge to swipe on.
class _SwipeHint extends StatelessWidget {
  const _SwipeHint(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      Icon(
        Icons.keyboard_double_arrow_up_rounded,
        size: 18,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      const SizedBox(width: 4),
      Flexible(
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      ),
    ],
  );
}

/// A question with tappable answers: word meanings, der/die/das, or maths.
class _ChoiceCard extends StatefulWidget {
  const _ChoiceCard({
    super.key,
    required this.reel,
    required this.progress,
    required this.showHint,
    this.onNext,
  });

  final ChoiceReel reel;
  final _ReelProgress progress;
  final bool showHint;
  final VoidCallback? onNext;

  @override
  State<_ChoiceCard> createState() => _ChoiceCardState();
}

class _ChoiceCardState extends State<_ChoiceCard> {
  late int? _picked = widget.progress.choices[widget.reel.id];
  int? _selected;

  void _onOptionTap(int i) {
    if (_picked != null) return;
    _pick(i);
  }

  void _submit() {
    if (_picked != null) {
      widget.onNext?.call();
    }
  }

  void _pick(int i) {
    if (_picked != null) return;
    final reel = widget.reel;
    final correct = i == reel.answer;
    correct ? HapticFeedback.lightImpact() : HapticFeedback.mediumImpact();
    widget.progress.choices[reel.id] = i;
    widget.progress.record(reel.id, correct: correct);
    setState(() {
      _selected = i;
      _picked = i;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final reel = widget.reel;
    final picked = _picked;
    final (subject, level) = switch (reel) {
      MeaningReel(:final word) ||
      ArticleReel(:final word) => (word.languageName, word.level),
      MathReel(:final level) => ('Maths', level),
      CodeReel(:final languageName, :final level) => (languageName, level),
      QuizReel(:final subject, :final level) => (
        kLanguageNames[subject] ?? subject,
        level,
      ),
      _ => ('', 2),
    };
    final short = reel.options.every((o) => o.length <= 8);

    return LayoutBuilder(
      builder: (context, box) {
        final compact = box.maxHeight < 520;
        final buttons = [
          for (var i = 0; i < reel.options.length; i++)
            _OptionButton(
              label: reel.options[i],
              letter: short && reel.options.length < 4 ? null : 'ABCD'[i],
              compact: compact,
              state: picked == null
                  ? (_selected == i ? _OptionState.selected : _OptionState.open)
                  : i == reel.answer
                  ? _OptionState.right
                  : i == picked
                  ? _OptionState.wrong
                  : _OptionState.faded,
              onTap: () => _onOptionTap(i),
            ),
        ];

        return _CardShell(
          compact: compact,
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _ReelPills(kind: reel.kind, subject: subject, level: level),
                const SizedBox(height: 14),
                if (reel is CodeReel)
                  _Prompt(reel: reel, revealed: picked != null, compact: compact)
                else
                  _Prompt(reel: reel, revealed: picked != null, compact: compact),
                SizedBox(height: compact ? 12 : 18),
                if (short && buttons.length < 4)
                  Row(
                    children: [
                      for (var i = 0; i < buttons.length; i++) ...[
                        if (i > 0) const SizedBox(width: 8),
                        Expanded(child: buttons[i]),
                      ],
                    ],
                  )
                else
                  for (final b in buttons)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: b,
                    ),
                const SizedBox(height: 10),
                // Submit / Next CTA button
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _picked != null ? _submit : null,
                    icon: Icon(
                      _picked != null
                          ? Icons.arrow_forward_rounded
                          : Icons.play_arrow_rounded,
                      size: 20,
                    ),
                    label: Text(
                      _picked != null ? 'Next Question' : 'Submit Answer',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: kBrandBlue,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: kBrandBlue.withValues(alpha: 0.35),
                      disabledForegroundColor: Colors.white.withValues(alpha: 0.65),
                      minimumSize: const Size.fromHeight(48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: _picked != null || _selected != null ? 2 : 0,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                // Timer & points row
                Row(
                  children: [
                    Icon(
                      Icons.access_time_rounded,
                      size: 14,
                      color: muted,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '8 sec · ${xpFor(correct: true, difficulty: level)} pt',
                      style: TextStyle(
                        color: muted,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    if (_picked == null && widget.showHint)
                      Text(
                        'Select an answer to submit',
                        style: TextStyle(
                          color: muted,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                  ],
                ),
                if (picked != null) ...[
                  const SizedBox(height: 12),
                  _Feedback(
                    correct: picked == reel.answer,
                    text: reel.explanation,
                    compact: compact,
                    onViewMore: () {
                      showModalBottomSheet<void>(
                        context: context,
                        showDragHandle: true,
                        builder: (context) => Padding(
                          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.school_rounded, color: kBrandBlue),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Explanation',
                                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Text(
                                reel.explanation.isNotEmpty
                                    ? reel.explanation
                                    : 'Good job working through this question!',
                                style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.4),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

/// The question itself, sized to fit.
class _Prompt extends StatelessWidget {
  const _Prompt({
    required this.reel,
    required this.revealed,
    required this.compact,
  });

  final ChoiceReel reel;
  final bool revealed;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = TextStyle(
      fontWeight: FontWeight.w800,
      fontSize: compact ? 17 : 20,
      height: 1.3,
      color: _Feed.of(context).ink,
    );
    final Widget text = switch (reel) {
      // The headline stays full size; only long code shrinks to fit.
      CodeReel(:final kind, :final prompt, :final code, :final subject) =>
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              kind.startsWith('What does') ? kind : prompt,
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w800,
                fontSize: compact ? 20 : 24,
                height: 1.15,
              ),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.topLeft,
                child: _CodeBlock(code, subject: subject),
              ),
            ),
          ],
        ),
      QuizReel(:final prompt) => Text(
        prompt,
        style: style,
      ),
      // The article blank fills in, in its gender colour, once answered.
      ArticleReel(:final word) => Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: revealed ? '${word.article} ' : '___ ',
              style: TextStyle(
                color: revealed
                    ? word.gender?.color
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ),
            TextSpan(text: word.word),
          ],
        ),
        style: style,
      ),
      MeaningReel(:final word) => Text.rich(
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
        style: style,
      ),
      _ => Text(reel.prompt, style: style),
    };
    return text;
  }
}

enum _OptionState { open, selected, right, wrong, faded }

class _OptionButton extends StatelessWidget {
  const _OptionButton({
    super.key,
    required this.label,
    required this.state,
    required this.compact,
    required this.onTap,
    this.letter,
  });

  /// "A" to "D" for answers listed in rows.
  final String? letter;
  final String label;
  final _OptionState state;
  final bool compact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;

    final (fill, border, letterBg, letterFg, textFg) = switch (state) {
      _OptionState.right => (
        dark ? const Color(0xFF143322) : const Color(0xFFE8F8F0),
        const Color(0xFF22C55E),
        const Color(0xFF22C55E),
        Colors.white,
        dark ? Colors.white : const Color(0xFF166534),
      ),
      _OptionState.wrong => (
        dark ? const Color(0xFF38181A) : const Color(0xFFFFECEF),
        const Color(0xFFE5484D),
        const Color(0xFFE5484D),
        Colors.white,
        dark ? Colors.white : const Color(0xFF991B1B),
      ),
      _OptionState.selected => (
        dark ? const Color(0xFF1E2838) : const Color(0xFFEFF6FF),
        kBrandBlue,
        kBrandBlue,
        Colors.white,
        dark ? Colors.white : const Color(0xFF1E3A8A),
      ),
      _OptionState.faded => (
        dark ? const Color(0xFF1E2028) : Colors.white,
        dark ? const Color(0x33FFFFFF) : const Color(0xFFE4E7EC),
        dark ? const Color(0x22FFFFFF) : const Color(0xFFF1F3F8),
        dark ? Colors.white38 : const Color(0xFF9CA3AF),
        dark ? Colors.white38 : const Color(0xFF9CA3AF),
      ),
      _OptionState.open => (
        dark ? const Color(0xFF262833) : Colors.white,
        dark ? const Color(0x33FFFFFF) : const Color(0xFFE4E7EC),
        dark ? const Color(0x22FFFFFF) : const Color(0xFFF1F3F8),
        dark ? Colors.white70 : const Color(0xFF4B5563),
        dark ? Colors.white : const Color(0xFF1F2937),
      ),
    };

    return Semantics(
      button: true,
      label: label,
      selected: state == _OptionState.selected || state == _OptionState.right,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: (state == _OptionState.open || state == _OptionState.selected)
            ? onTap
            : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          constraints: BoxConstraints(minHeight: compact ? 44 : 50),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: border,
              width: state == _OptionState.selected ||
                      state == _OptionState.right ||
                      state == _OptionState.wrong
                  ? 2.0
                  : 1.2,
            ),
          ),
          child: Row(
            children: [
              if (letter != null) ...[
                Container(
                  width: 30,
                  height: 30,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: letterBg,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    letter!,
                    style: TextStyle(
                      color: letterFg,
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Text(
                  label,
                  textAlign: TextAlign.start,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: textFg,
                    fontWeight: FontWeight.w700,
                    fontSize: compact ? 14 : 15,
                    height: 1.25,
                  ),
                ),
              ),
              if (state == _OptionState.right)
                const Icon(
                  Icons.check_circle_rounded,
                  color: Color(0xFF22C55E),
                  size: 20,
                )
              else if (state == _OptionState.wrong)
                const Icon(
                  Icons.cancel_rounded,
                  color: Color(0xFFE5484D),
                  size: 20,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Spell it: the meaning is the clue; tap the scrambled letters in order.
class _SpellCard extends StatefulWidget {
  const _SpellCard({required this.reel, required this.progress});

  final SpellReel reel;
  final _ReelProgress progress;

  @override
  State<_SpellCard> createState() => _SpellCardState();
}

class _SpellCardState extends State<_SpellCard> {
  /// Indexes into the reel's letters, in the order tapped.
  final _picked = <int>[];
  late bool _solved = widget.progress.solved.contains(widget.reel.id);
  bool _wrong = false;
  bool _hinted = false;
  Timer? _clear;

  SpellReel get _reel => widget.reel;
  String get _typed => _picked.map((i) => _reel.letters[i]).join();

  @override
  void dispose() {
    _clear?.cancel();
    super.dispose();
  }

  void _tap(int i) {
    if (_solved || _wrong || _picked.contains(i)) return;
    HapticFeedback.selectionClick();
    setState(() => _picked.add(i));
    if (_picked.length == _reel.letters.length) _check();
  }

  void _check() {
    final correct = _typed == _reel.target;
    if (!_hinted) widget.progress.record(_reel.id, correct: correct);
    if (correct) {
      HapticFeedback.lightImpact();
      widget.progress.solved.add(_reel.id);
      setState(() => _solved = true);
      return;
    }
    HapticFeedback.mediumImpact();
    setState(() => _wrong = true);
    _clear = Timer(const Duration(milliseconds: 700), () {
      if (!mounted) return;
      setState(() {
        _wrong = false;
        _picked.clear();
      });
    });
  }

  void _undo() {
    if (_picked.isEmpty || _solved || _wrong) return;
    setState(() => _picked.removeLast());
  }

  /// Keeps the right start of the answer and adds its next letter.
  void _hint() {
    if (_solved || _wrong) return;
    final target = _reel.target;
    var keep = 0;
    while (keep < _picked.length &&
        _reel.letters[_picked[keep]] == target[keep]) {
      keep++;
    }
    _picked.removeRange(keep, _picked.length);
    final next = target[keep];
    final tile = [
      for (var i = 0; i < _reel.letters.length; i++)
        if (_reel.letters[i] == next && !_picked.contains(i)) i,
    ].first;
    _hinted = true;
    _tap(tile);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final word = _reel.word;
    final target = _reel.target;
    final shown = _solved ? target : _typed;

    return LayoutBuilder(
      builder: (context, box) {
        final compact = box.maxHeight < 520;
        final tile = compact ? 36.0 : 42.0;
        final slotColor = _solved
            ? _correctColor
            : _wrong
            ? _wrongColor
            : kBrandBlue;
        return _CardShell(
          compact: compact,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ReelPills(
                kind: 'Spell it',
                subject: word.languageName,
                level: word.level,
              ),
              const Spacer(),
              Text(
                word.meaning,
                maxLines: compact ? 2 : 3,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium?.copyWith(height: 1.4),
              ),
              SizedBox(height: compact ? 12 : 18),
              Semantics(
                label: _solved ? 'Spelled ${word.word}' : 'Answer: $shown',
                excludeSemantics: true,
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (word.article != null)
                      Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: Text(
                          word.article!,
                          style: theme.textTheme.titleLarge?.copyWith(
                            color: word.gender?.color,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    for (var i = 0; i < target.length; i++)
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        width: tile - 4,
                        height: tile,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: i < shown.length
                              ? slotColor
                              : slotColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          i < shown.length ? shown[i] : '',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 18,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              SizedBox(height: compact ? 14 : 22),
              if (_solved) ...[
                _Feedback(
                  correct: true,
                  title: _hinted ? 'Solved!' : null,
                  text: word.example ?? word.meaning,
                  compact: compact,
                ),
              ] else ...[
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (var i = 0; i < _reel.letters.length; i++)
                      _LetterTile(
                        letter: _reel.letters[i],
                        size: tile,
                        used: _picked.contains(i),
                        onTap: () => _tap(i),
                      ),
                  ],
                ),
                SizedBox(height: compact ? 10 : 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _picked.isEmpty ? null : _undo,
                        icon: const Icon(Icons.undo_rounded, size: 18),
                        label: const Text('Undo'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _hint,
                        icon: const Icon(
                          Icons.lightbulb_outline_rounded,
                          size: 18,
                        ),
                        label: const Text('Hint'),
                      ),
                    ),
                  ],
                ),
              ],
              const Spacer(),
              if (_solved)
                const _SwipeHint('Swipe up for the next one')
              else
                Text(
                  'Tap the letters in order.',
                  style: theme.textTheme.bodySmall?.copyWith(color: muted),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _LetterTile extends StatelessWidget {
  const _LetterTile({
    required this.letter,
    required this.size,
    required this.used,
    required this.onTap,
  });

  final String letter;
  final double size;
  final bool used;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return Semantics(
      button: true,
      enabled: !used,
      label: 'Letter $letter',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: used ? null : onTap,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 150),
          opacity: used ? 0.25 : 1,
          child: Container(
            width: size,
            height: size,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: dark ? const Color(0x33FFFFFF) : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: kBrandBlue.withValues(alpha: 0.35),
                width: 2,
              ),
            ),
            child: Text(
              letter,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 18,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Share for maths reels: the question as text.
class _ShareQuestionButton extends StatelessWidget {
  const _ShareQuestionButton({required this.text, required this.service});

  final String text;
  final WordService service;

  @override
  Widget build(BuildContext context) => _ActionButton(
    label: 'Share',
    semantics: 'Share question',
    icon: const Icon(Icons.share_rounded),
    onPressed: () async {
      TasteStore.instance.signalCurrent(TasteStore.share);
      try {
        await service.shareText(text);
      } catch (_) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(
              content: Text('Couldn’t open sharing. Please try again.'),
            ),
          );
      }
    },
  );
}

class _HeartBurst extends StatelessWidget {
  const _HeartBurst({required this.animation});

  final Animation<double> animation;

  static final _scale = TweenSequence([
    TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.25), weight: 30),
    TweenSequenceItem(tween: Tween(begin: 1.25, end: 1.0), weight: 20),
    TweenSequenceItem(tween: ConstantTween(1.0), weight: 30),
    TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.4), weight: 20),
  ]);

  static final _opacity = TweenSequence([
    TweenSequenceItem(tween: ConstantTween(1.0), weight: 80),
    TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 20),
  ]);

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: animation,
    builder: (context, _) {
      if (!animation.isAnimating) return const SizedBox.shrink();
      final t = animation.value;
      return Opacity(
        opacity: _opacity.transform(t),
        child: Transform.scale(
          scale: _scale.transform(t),
          child: const Icon(
            Icons.favorite_rounded,
            size: 110,
            color: Color(0xFFFF3B5C),
            shadows: [Shadow(blurRadius: 24, color: Color(0x55000000))],
          ),
        ),
      );
    },
  );
}

class _WordCard extends StatelessWidget {
  const _WordCard({required this.word, required this.showHint});

  final VocabWord word;
  final bool showHint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final gender = word.gender;

    return LayoutBuilder(
      builder: (context, box) {
        // Short screens (or large text) drop the mascot and tighten up.
        final compact = box.maxHeight < 520;
        return _CardShell(
          compact: compact,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  _Pill(word.languageName, kBrandBlue),
                  _DifficultyPill(word.level),
                  ListenableBuilder(
                    listenable: ProfileStore.instance,
                    builder: (context, _) =>
                        ProfileStore.instance.isLearned(word.id)
                        ? const _Pill(
                            'Learned',
                            Color(0xFF2EB67D),
                            icon: Icons.check_rounded,
                          )
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
              const Spacer(),
              if (gender != null) ...[
                _Pill('${gender.article} · ${gender.label}', gender.color),
                const SizedBox(height: 10),
              ],
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text.rich(
                  TextSpan(
                    children: [
                      if (word.article != null)
                        TextSpan(
                          text: '${word.article} ',
                          style: TextStyle(color: gender?.color),
                        ),
                      TextSpan(text: word.word),
                    ],
                  ),
                  style: theme.textTheme.displaySmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    fontSize: compact ? 30 : 40,
                  ),
                ),
              ),
              if (word.pluralLine case final plural?)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    plural,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: muted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              if (word.romanised != null)
                Text(
                  word.romanised!,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: muted,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              SizedBox(height: compact ? 8 : 14),
              Text(
                word.meaning,
                maxLines: compact ? 3 : 4,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium?.copyWith(height: 1.4),
              ),
              if (word.example != null) ...[
                SizedBox(height: compact ? 12 : 20),
                _Example(word: word, compact: compact),
              ],
              const Spacer(),
              if (!compact)
                Row(
                  children: [
                    const Mascot(size: 64),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        showHint
                            ? 'Swipe up for the next word.\nDouble-tap to like it.'
                            : 'Say it out loud: ${word.headword}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: muted,
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }
}

class _Example extends StatelessWidget {
  const _Example({required this.word, required this.compact});

  final VocabWord word;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: kBrandBlue.withValues(alpha: dark ? 0.16 : 0.08),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.format_quote_rounded, color: kBrandBlue, size: 22),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  word.example!,
                  maxLines: compact ? 2 : 3,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                  ),
                ),
                if (word.translation != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    word.translation!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Easy, Medium or Hard on a reel; a tap opens the difficulty picker.
class _DifficultyPill extends StatelessWidget {
  const _DifficultyPill(this.level);

  final int level;

  @override
  Widget build(BuildContext context) {
    final onPick = _DifficultyScope.of(context);
    final pill = _Pill(
      kDifficultyNames[level] ?? 'Medium',
      _levelColor(level),
      icon: onPick == null ? null : Icons.tune_rounded,
    );
    if (onPick == null) return pill;
    return Semantics(
      button: true,
      label: '${kDifficultyNames[level] ?? 'Medium'}. Change difficulty',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPick,
        child: pill,
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill(this.text, this.color, {this.icon});

  final String text;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
        ],
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
        ),
      ],
    ),
  );
}

/// Like, Share and Save, stacked on the right of a word card.
class WordFlowActionBar extends StatelessWidget {
  const WordFlowActionBar({
    super.key,
    required this.word,
    required this.interactions,
    this.service = const WordService(),
  });

  final VocabWord word;
  final WordInteractions interactions;
  final WordService service;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: interactions,
    builder: (context, _) {
      final state = interactions.stateOf(word.id);
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          LikeActionButton(
            liked: state.isLiked,
            countKey: word.id,
            onPressed: () => interactions.toggleLike(word.id),
          ),
          const SizedBox(height: 14),
          BookmarkActionButton(
            saved: state.isSaved,
            onPressed: () => interactions.toggleSave(word.id),
          ),
          const SizedBox(height: 14),
          ShareActionButton(word: word, service: service),
          const SizedBox(height: 12),
        ],
      );
    },
  );
}

/// Round 48 px action with a label under it, shared by the three buttons.
class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.semantics,
    required this.onPressed,
    this.color,
    this.active = false,
    this.value,
  });

  final Widget icon;
  final String label;
  final String semantics;
  final VoidCallback? onPressed;
  final Color? color;
  final bool active;

  /// Read out after the label, e.g. "12 likes".
  final String? value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return Semantics(
      button: true,
      toggled: active,
      label: semantics,
      value: value,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPressed,
        child: SizedBox(
          width: 56,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: dark
                      ? const Color(0x22FFFFFF)
                      : (active
                          ? (color ?? kBrandBlue).withValues(alpha: 0.1)
                          : Colors.transparent),
                ),
                child: IconTheme.merge(
                  data: IconThemeData(
                    size: 26,
                    color: color ?? (dark ? Colors.white70 : const Color(0xFF4B5563)),
                  ),
                  child: icon,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 11,
                  color: dark ? Colors.white60 : const Color(0xFF6B7280),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Plays a short pop each time [active] turns on.
mixin _PopOnActivate<T extends StatefulWidget>
    on State<T>, SingleTickerProviderStateMixin<T> {
  late final pop = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 380),
  );

  bool get active;

  void didChangeActive(bool was) {
    if (active && !was) pop.forward(from: 0);
  }

  @override
  void dispose() {
    pop.dispose();
    super.dispose();
  }
}

class LikeActionButton extends StatefulWidget {
  const LikeActionButton({
    super.key,
    required this.liked,
    required this.onPressed,
    this.countKey,
  });

  final bool liked;
  final VoidCallback onPressed;

  /// What is liked, for everyone's like count under the heart. Without it
  /// the label just says "Like".
  final String? countKey;

  @override
  State<LikeActionButton> createState() => _LikeActionButtonState();
}

class _LikeActionButtonState extends State<LikeActionButton>
    with SingleTickerProviderStateMixin, _PopOnActivate {
  static const _red = Color(0xFFFF3B5C);
  static final _scale = TweenSequence([
    TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.35), weight: 35),
    TweenSequenceItem(tween: Tween(begin: 1.35, end: 0.9), weight: 30),
    TweenSequenceItem(tween: Tween(begin: 0.9, end: 1.0), weight: 35),
  ]);

  @override
  bool get active => widget.liked;

  @override
  void initState() {
    super.initState();
    if (widget.countKey case final key?) LikeCounts.instance.watch(key);
  }

  @override
  void didUpdateWidget(LikeActionButton old) {
    super.didUpdateWidget(old);
    didChangeActive(old.liked);
    if (old.countKey != widget.countKey) {
      if (old.countKey case final key?) LikeCounts.instance.unwatch(key);
      if (widget.countKey case final key?) LikeCounts.instance.watch(key);
    }
  }

  @override
  void dispose() {
    if (widget.countKey case final key?) LikeCounts.instance.unwatch(key);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: LikeCounts.instance,
    builder: (context, _) {
      final key = widget.countKey;
      final count = key == null
          ? null
          : LikeCounts.instance.countOf(key, likedHere: widget.liked);
      final shown = count != null && count > 0;
      return _ActionButton(
        label: shown ? LikeCounts.format(count) : 'Like',
        semantics: widget.liked ? 'Unlike' : 'Like',
        value: shown ? (count == 1 ? '1 like' : '$count likes') : null,
        active: widget.liked,
        color: widget.liked ? _red : null,
        onPressed: () {
          HapticFeedback.lightImpact();
          widget.onPressed();
        },
        icon: ScaleTransition(
          scale: _scale.animate(pop),
          child: Icon(
            widget.liked
                ? Icons.favorite_rounded
                : Icons.favorite_border_rounded,
          ),
        ),
      );
    },
  );
}

class BookmarkActionButton extends StatefulWidget {
  const BookmarkActionButton({
    super.key,
    required this.saved,
    required this.onPressed,
  });

  final bool saved;
  final VoidCallback onPressed;

  @override
  State<BookmarkActionButton> createState() => _BookmarkActionButtonState();
}

class _BookmarkActionButtonState extends State<BookmarkActionButton>
    with SingleTickerProviderStateMixin, _PopOnActivate {
  static const _gold = Color(0xFFFFB300);

  @override
  bool get active => widget.saved;

  @override
  void didUpdateWidget(BookmarkActionButton old) {
    super.didUpdateWidget(old);
    didChangeActive(old.saved);
  }

  @override
  Widget build(BuildContext context) => _ActionButton(
    label: widget.saved ? 'Saved' : 'Save',
    semantics: widget.saved ? 'Remove from saved words' : 'Save word',
    active: widget.saved,
    color: widget.saved ? _gold : null,
    onPressed: () {
      HapticFeedback.selectionClick();
      widget.onPressed();
    },
    // A small drop: the ribbon dips and settles.
    icon: AnimatedBuilder(
      animation: pop,
      builder: (context, child) {
        final t = Curves.easeOut.transform(pop.value);
        final dip = math.sin(t * math.pi) * 4;
        return Transform.translate(
          offset: Offset(0, dip),
          child: Transform.scale(
            scale: 1 + math.sin(t * math.pi) * 0.15,
            child: child,
          ),
        );
      },
      child: Icon(
        widget.saved ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
      ),
    ),
  );
}

class ShareActionButton extends StatefulWidget {
  const ShareActionButton({
    super.key,
    required this.word,
    this.service = const WordService(),
  });

  final VocabWord word;
  final WordService service;

  @override
  State<ShareActionButton> createState() => _ShareActionButtonState();
}

class _ShareActionButtonState extends State<ShareActionButton> {
  bool _busy = false;

  Future<void> _share() async {
    TasteStore.instance.signalCurrent(TasteStore.share);
    if (_busy) return;
    setState(() => _busy = true);
    final ok = await shareWordCard(
      context,
      widget.word,
      service: widget.service,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (!ok) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Couldn’t open sharing. Please try again.'),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) => _ActionButton(
    label: 'Share',
    semantics: 'Share word',
    onPressed: _busy ? null : _share,
    icon: _busy
        ? const SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          )
        : const Icon(Icons.share_rounded),
  );
}

/// Like, Share and Save for maths reels; likes and saves go by question.
class _MathsActionBar extends StatelessWidget {
  const _MathsActionBar({
    required this.item,
    required this.interactions,
    required this.service,
  });

  final MathsItem item;
  final WordInteractions interactions;
  final WordService service;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: interactions,
    builder: (context, _) {
      final id = item.saveId;
      final state = interactions.stateOf(id);
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          LikeActionButton(
            liked: state.isLiked,
            countKey: id,
            onPressed: () => interactions.toggleLike(id),
          ),
          const SizedBox(height: 14),
          BookmarkActionButton(
            saved: state.isSaved,
            onPressed: () => interactions.toggleSave(id),
          ),
          const SizedBox(height: 14),
          _ShareQuestionButton(text: item.shareText, service: service),
          const SizedBox(height: 12),
        ],
      );
    },
  );
}

/// A number tile for the maths games.
class _NumberTile extends StatelessWidget {
  const _NumberTile({
    super.key,
    required this.value,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final String value;

  /// Fill when selected (blue), right (green) or wrong (red).
  final Color color;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return Semantics(
      button: true,
      selected: selected,
      label: 'Number $value',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedScale(
          scale: selected ? 1.06 : 1,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutBack,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected
                  ? color
                  : (dark ? const Color(0x33FFFFFF) : Colors.white),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: color.withValues(alpha: 0.5), width: 2),
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Text(
                  value,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 26,
                    color: selected
                        ? Colors.white
                        : theme.colorScheme.onSurface,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Make the target: tap the two numbers that add or multiply to it.
class _TargetCard extends StatefulWidget {
  const _TargetCard({required this.reel, required this.progress});

  final TargetReel reel;
  final _ReelProgress progress;

  @override
  State<_TargetCard> createState() => _TargetCardState();
}

class _TargetCardState extends State<_TargetCard> {
  late final TargetReel _reel = widget.reel;
  late bool _solved = widget.progress.solved.contains(_reel.id);
  late final _picked = <int>[
    if (_solved) ...[_reel.pair.$1, _reel.pair.$2],
  ];
  bool _wrong = false;
  Timer? _clear;

  @override
  void dispose() {
    _clear?.cancel();
    super.dispose();
  }

  void _tap(int i) {
    if (_solved || _wrong) return;
    HapticFeedback.selectionClick();
    setState(() {
      if (!_picked.remove(i)) _picked.add(i);
    });
    if (_picked.length < 2) return;
    final made = _reel.apply(
      _reel.numbers[_picked[0]],
      _reel.numbers[_picked[1]],
    );
    final correct = made == _reel.target;
    widget.progress.record(_reel.id, correct: correct);
    if (correct) {
      HapticFeedback.lightImpact();
      widget.progress.solved.add(_reel.id);
      setState(() => _solved = true);
      return;
    }
    HapticFeedback.mediumImpact();
    setState(() => _wrong = true);
    _clear = Timer(const Duration(milliseconds: 700), () {
      if (!mounted) return;
      setState(() {
        _wrong = false;
        _picked.clear();
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final verb = _reel.op == '+' ? 'add up' : 'multiply';
    final color = _solved
        ? _correctColor
        : _wrong
        ? _wrongColor
        : kBrandBlue;
    return LayoutBuilder(
      builder: (context, box) {
        final compact = box.maxHeight < 520;
        return _CardShell(
          compact: compact,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ReelPills(
                kind: 'Make the target',
                subject: 'Maths',
                level: _reel.level,
              ),
              const Spacer(),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text('🎯 ', style: TextStyle(fontSize: 30)),
                  Text(
                    '${_reel.target}',
                    style: theme.textTheme.displaySmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      fontSize: compact ? 34 : 44,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Tap two numbers that $verb to ${_reel.target}.',
                style: theme.textTheme.titleMedium?.copyWith(color: muted),
              ),
              SizedBox(height: compact ? 12 : 20),
              GridView.count(
                crossAxisCount: 3,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: compact ? 1.5 : 1.25,
                children: [
                  for (var i = 0; i < _reel.numbers.length; i++)
                    _NumberTile(
                      value: '${_reel.numbers[i]}',
                      color: color,
                      selected: _picked.contains(i),
                      onTap: _solved ? null : () => _tap(i),
                    ),
                ],
              ),
              if (_solved) ...[
                SizedBox(height: compact ? 10 : 16),
                _Feedback(
                  correct: true,
                  text: '${_reel.solution} = ${_reel.target}',
                  compact: compact,
                ),
              ],
              const Spacer(),
              if (_solved)
                const _SwipeHint('Swipe up for the next one')
              else
                Text(
                  _wrong ? 'Not those two. Try again!' : 'Only one pair works.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: _wrong ? _wrongColor : muted,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// Beat the clock: quick questions one after another before time runs out.
class _BlitzCard extends StatefulWidget {
  const _BlitzCard({required this.reel, required this.progress});

  final BlitzReel reel;
  final _ReelProgress progress;

  @override
  State<_BlitzCard> createState() => _BlitzCardState();
}

enum _BlitzPhase { ready, running, done }

class _BlitzCardState extends State<_BlitzCard> {
  late final BlitzReel _reel = widget.reel;

  /// A finished round shows its score again when swiped back to.
  late _BlitzPhase _phase = widget.progress.choices.containsKey(_reel.id)
      ? _BlitzPhase.done
      : _BlitzPhase.ready;
  late int _score = widget.progress.choices[_reel.id] ?? 0;
  final _results = <bool>[];

  /// Time used, counted in timer ticks.
  int _elapsedMs = 0;
  Timer? _tick;

  int get _total => _reel.questions.length;
  double get _left => (1 - _elapsedMs / (_reel.seconds * 1000)).clamp(0.0, 1.0);

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  void _start() {
    HapticFeedback.selectionClick();
    _results.clear();
    _score = 0;
    _elapsedMs = 0;
    _tick = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!mounted) return;
      _elapsedMs += 100;
      if (_left <= 0) {
        _end();
      } else {
        setState(() {});
      }
    });
    setState(() => _phase = _BlitzPhase.running);
  }

  void _answer(int i) {
    if (_phase != _BlitzPhase.running) return;
    final q = _reel.questions[_results.length];
    final correct = i == q.answer;
    correct ? HapticFeedback.lightImpact() : HapticFeedback.mediumImpact();
    setState(() {
      _results.add(correct);
      if (correct) _score++;
    });
    if (_results.length == _total) _end();
  }

  void _end() {
    _tick?.cancel();
    widget.progress.choices[_reel.id] = _score;
    widget.progress.record(
      _reel.id,
      correct: _score >= _total - 1,
      bonus: _score == _total ? 20 : 0,
    );
    setState(() => _phase = _BlitzPhase.done);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return LayoutBuilder(
      builder: (context, box) {
        final compact = box.maxHeight < 520;
        final Widget body = switch (_phase) {
          _BlitzPhase.ready => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '⏱️ $_total questions',
                style: theme.textTheme.displaySmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  fontSize: compact ? 28 : 36,
                ),
              ),
              Text(
                'in ${_reel.seconds} seconds. Ready?',
                style: theme.textTheme.titleMedium?.copyWith(color: muted),
              ),
              SizedBox(height: compact ? 14 : 22),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _start,
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('Start'),
                ),
              ),
            ],
          ),
          _BlitzPhase.running => _running(theme, compact),
          _BlitzPhase.done => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$_score / $_total',
                style: theme.textTheme.displaySmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  fontSize: compact ? 34 : 44,
                  color: _score >= _total - 1 ? _correctColor : _wrongColor,
                ),
              ),
              const SizedBox(height: 8),
              _Feedback(
                correct: _score >= _total - 1,
                title: _score == _total
                    ? 'Perfect!'
                    : _score >= _total - 1
                    ? 'So close!'
                    : 'Out of time.',
                text: _reel.questions
                    .map((q) => '${q.prompt} = ${q.solution}')
                    .join(' · '),
                compact: compact,
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _start,
                icon: const Icon(Icons.replay_rounded, size: 18),
                label: const Text('Play again'),
              ),
            ],
          ),
        };
        return _CardShell(
          compact: compact,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ReelPills(
                kind: 'Beat the clock',
                subject: 'Maths',
                level: _reel.level,
              ),
              const Spacer(),
              body,
              const Spacer(),
              if (_phase == _BlitzPhase.done)
                const _SwipeHint('Swipe up for the next one')
              else
                Text(
                  'Answer fast. Every second counts!',
                  style: theme.textTheme.bodySmall?.copyWith(color: muted),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _running(ThemeData theme, bool compact) {
    final q = _reel.questions[math.min(_results.length, _total - 1)];
    final left = _left;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: left,
            minHeight: 10,
            color: left > 0.3 ? kBrandBlue : _wrongColor,
            backgroundColor: kBrandBlue.withValues(alpha: 0.12),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            for (var i = 0; i < _total; i++)
              Container(
                width: 12,
                height: 12,
                margin: const EdgeInsets.only(right: 6),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: i < _results.length
                      ? (_results[i] ? _correctColor : _wrongColor)
                      : kBrandBlue.withValues(alpha: 0.2),
                ),
              ),
            const Spacer(),
            Text(
              '${(left * _reel.seconds).ceil()}s',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        SizedBox(height: compact ? 14 : 22),
        Text(
          '${q.prompt} = ?',
          style: theme.textTheme.displaySmall?.copyWith(
            fontWeight: FontWeight.w800,
            fontSize: compact ? 30 : 40,
          ),
        ),
        SizedBox(height: compact ? 14 : 22),
        Row(
          children: [
            for (var i = 0; i < q.options.length; i++) ...[
              if (i > 0) const SizedBox(width: 10),
              Expanded(
                child: _OptionButton(
                  // A new key per question, so no answer colour carries over.
                  key: ValueKey('${_results.length}-$i'),
                  label: q.options[i],
                  compact: compact,
                  state: _OptionState.open,
                  onTap: () => _answer(i),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

/// Sort it: tap the numbers from smallest to largest.
class _SortCard extends StatefulWidget {
  const _SortCard({required this.reel, required this.progress});

  final SortReel reel;
  final _ReelProgress progress;

  @override
  State<_SortCard> createState() => _SortCardState();
}

class _SortCardState extends State<_SortCard> {
  late final SortReel _reel = widget.reel;
  late final List<int> _order = _reel.order;
  late bool _solved = widget.progress.solved.contains(_reel.id);

  /// How many are in place so far.
  late int _done = _solved ? _order.length : 0;
  int? _wrongTile;
  bool _missed = false;
  Timer? _clear;

  @override
  void dispose() {
    _clear?.cancel();
    super.dispose();
  }

  void _tap(int i) {
    if (_solved || _order.indexOf(i) < _done) return;
    if (_order[_done] == i) {
      HapticFeedback.selectionClick();
      setState(() => _done++);
      if (_done == _order.length) {
        HapticFeedback.lightImpact();
        widget.progress.solved.add(_reel.id);
        widget.progress.record(_reel.id, correct: !_missed);
        setState(() => _solved = true);
      }
      return;
    }
    HapticFeedback.mediumImpact();
    _missed = true;
    _clear?.cancel();
    setState(() => _wrongTile = i);
    _clear = Timer(const Duration(milliseconds: 500), () {
      if (mounted) setState(() => _wrongTile = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return LayoutBuilder(
      builder: (context, box) {
        final compact = box.maxHeight < 520;
        return _CardShell(
          compact: compact,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ReelPills(kind: 'Sort it', subject: 'Maths', level: _reel.level),
              const Spacer(),
              Text(
                'Smallest to largest',
                style: theme.textTheme.displaySmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  fontSize: compact ? 26 : 32,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Tap them in order, smallest first.',
                style: theme.textTheme.titleMedium?.copyWith(color: muted),
              ),
              SizedBox(height: compact ? 12 : 20),
              // The ordered row fills in as the learner taps.
              SizedBox(
                height: 44,
                child: Row(
                  children: [
                    for (var k = 0; k < _order.length; k++) ...[
                      if (k > 0) Text(' < ', style: TextStyle(color: muted)),
                      Expanded(
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: k < _done
                                ? _correctColor
                                : _correctColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Padding(
                              padding: const EdgeInsets.all(4),
                              child: Text(
                                k < _done ? _reel.labels[_order[k]] : '',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              SizedBox(height: compact ? 12 : 18),
              if (!_solved)
                GridView.count(
                  crossAxisCount: 3,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: compact ? 1.6 : 1.35,
                  children: [
                    for (var i = 0; i < _reel.labels.length; i++)
                      AnimatedOpacity(
                        duration: const Duration(milliseconds: 180),
                        opacity: _order.indexOf(i) < _done ? 0.25 : 1,
                        child: _NumberTile(
                          value: _reel.labels[i],
                          color: _wrongTile == i ? _wrongColor : kBrandBlue,
                          selected: _wrongTile == i,
                          onTap: () => _tap(i),
                        ),
                      ),
                  ],
                )
              else
                _Feedback(
                  correct: !_missed,
                  title: _missed ? 'Sorted!' : null,
                  text: _reel.solution,
                  compact: compact,
                ),
              const Spacer(),
              if (_solved)
                const _SwipeHint('Swipe up for the next one')
              else
                Text(
                  _wrongTile != null
                      ? 'Not that one yet!'
                      : 'Watch the minus signs.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: _wrongTile != null ? _wrongColor : muted,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// Memory flash: numbers show for a few seconds, then hide; then a question.
class _MemoryCard extends StatefulWidget {
  const _MemoryCard({required this.reel, required this.progress});

  final MemoryReel reel;
  final _ReelProgress progress;

  @override
  State<_MemoryCard> createState() => _MemoryCardState();
}

enum _MemoryPhase { ready, showing, asking }

class _MemoryCardState extends State<_MemoryCard> {
  late final MemoryReel _reel = widget.reel;
  late int? _picked = widget.progress.choices[_reel.id];
  late _MemoryPhase _phase = _picked != null
      ? _MemoryPhase.asking
      : _MemoryPhase.ready;
  int _shownMs = 0;
  Timer? _tick;

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  void _show() {
    HapticFeedback.selectionClick();
    _shownMs = 0;
    setState(() => _phase = _MemoryPhase.showing);
    _tick = Timer.periodic(const Duration(milliseconds: 100), (t) {
      if (!mounted) return;
      _shownMs += 100;
      if (_shownMs >= _reel.seconds * 1000) {
        t.cancel();
        setState(() => _phase = _MemoryPhase.asking);
      } else {
        setState(() {});
      }
    });
  }

  void _pick(int i) {
    if (_picked != null) return;
    final correct = i == _reel.answer;
    correct ? HapticFeedback.lightImpact() : HapticFeedback.mediumImpact();
    widget.progress.choices[_reel.id] = i;
    widget.progress.record(_reel.id, correct: correct);
    setState(() => _picked = i);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final picked = _picked;
    return LayoutBuilder(
      builder: (context, box) {
        final compact = box.maxHeight < 520;
        // Numbers are visible while showing, and again once answered.
        final reveal = _phase == _MemoryPhase.showing || picked != null;
        final numbers = Row(
          children: [
            for (var i = 0; i < _reel.numbers.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              Expanded(
                child: AspectRatio(
                  aspectRatio: 1,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    transitionBuilder: (child, animation) =>
                        ScaleTransition(scale: animation, child: child),
                    child: _NumberTile(
                      key: ValueKey(reveal),
                      value: reveal ? '${_reel.numbers[i]}' : '?',
                      color: reveal ? kBrandBlue : _quizColor,
                      selected: !reveal,
                      onTap: null,
                    ),
                  ),
                ),
              ),
            ],
          ],
        );
        final Widget body = switch (_phase) {
          _MemoryPhase.ready => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '🧠 Remember these',
                style: theme.textTheme.displaySmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  fontSize: compact ? 26 : 32,
                ),
              ),
              Text(
                '${_reel.numbers.length} numbers, ${_reel.seconds} seconds. '
                'Then they hide!',
                style: theme.textTheme.titleMedium?.copyWith(color: muted),
              ),
              SizedBox(height: compact ? 14 : 22),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _show,
                  icon: const Icon(Icons.visibility_rounded),
                  label: const Text('Show me'),
                ),
              ),
            ],
          ),
          _MemoryPhase.showing => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: 1 - _shownMs / (_reel.seconds * 1000),
                  minHeight: 10,
                  backgroundColor: kBrandBlue.withValues(alpha: 0.12),
                ),
              ),
              SizedBox(height: compact ? 14 : 22),
              numbers,
            ],
          ),
          _MemoryPhase.asking => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              numbers,
              SizedBox(height: compact ? 12 : 18),
              Text(
                _reel.question,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              SizedBox(height: compact ? 10 : 16),
              for (var row = 0; row < 2; row++) ...[
                if (row > 0) const SizedBox(height: 10),
                Row(
                  children: [
                    for (var i = row * 2; i < row * 2 + 2; i++) ...[
                      if (i > row * 2) const SizedBox(width: 10),
                      Expanded(
                        child: _OptionButton(
                          label: _reel.options[i],
                          compact: compact,
                          state: picked == null
                              ? _OptionState.open
                              : i == _reel.answer
                              ? _OptionState.right
                              : i == picked
                              ? _OptionState.wrong
                              : _OptionState.faded,
                          onTap: () => _pick(i),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ],
          ),
        };
        return _CardShell(
          compact: compact,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ReelPills(
                kind: 'Memory flash',
                subject: 'Maths',
                level: _reel.level,
              ),
              const Spacer(),
              body,
              if (picked != null) ...[
                SizedBox(height: compact ? 8 : 14),
                _Feedback(
                  correct: picked == _reel.answer,
                  text: 'It was ${_reel.solution}.',
                  compact: compact,
                ),
              ],
              const Spacer(),
              if (picked != null)
                const _SwipeHint('Swipe up for the next one')
              else
                Text(
                  _phase == _MemoryPhase.showing
                      ? 'Look closely…'
                      : 'A quick memory workout.',
                  style: theme.textTheme.bodySmall?.copyWith(color: muted),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// Mini Sudoku: tap an empty cell, then a number. Wrong numbers bounce off.
class _SudokuCard extends StatefulWidget {
  const _SudokuCard({required this.reel, required this.progress});

  final SudokuReel reel;
  final _ReelProgress progress;

  @override
  State<_SudokuCard> createState() => _SudokuCardState();
}

class _SudokuCardState extends State<_SudokuCard> {
  late final SudokuReel _reel = widget.reel;
  late final bool _wasSolved = widget.progress.solved.contains(_reel.id);
  late final List<int> _cells = _wasSolved
      ? [..._reel.grid]
      : [..._reel.puzzle];
  int? _selected;
  int? _wrongCell;
  int _mistakes = 0;
  Timer? _clear;

  int get _n => _reel.size;
  bool get _solved => !_cells.contains(0);

  @override
  void dispose() {
    _clear?.cancel();
    super.dispose();
  }

  void _select(int i) {
    if (_solved || _reel.puzzle[i] != 0 || _cells[i] != 0) return;
    HapticFeedback.selectionClick();
    setState(() => _selected = i);
  }

  void _enter(int v) {
    final i = _selected;
    if (i == null || _solved) return;
    if (_reel.grid[i] == v) {
      HapticFeedback.lightImpact();
      setState(() {
        _cells[i] = v;
        _selected = _nextEmpty(i);
      });
      if (_solved) {
        widget.progress.solved.add(_reel.id);
        widget.progress.record(
          _reel.id,
          correct: _mistakes == 0,
          bonus: _mistakes == 0 ? 20 : 5,
        );
        setState(() => _selected = null);
      }
      return;
    }
    HapticFeedback.mediumImpact();
    _mistakes++;
    _clear?.cancel();
    setState(() => _wrongCell = i);
    _clear = Timer(const Duration(milliseconds: 500), () {
      if (mounted) setState(() => _wrongCell = null);
    });
  }

  /// The next empty cell after [from], wrapping round, so typing flows on.
  int? _nextEmpty(int from) {
    for (var k = 1; k <= _cells.length; k++) {
      final i = (from + k) % _cells.length;
      if (_cells[i] == 0) return i;
    }
    return null;
  }

  bool _related(int a, int b) {
    final (ra, ca, rb, cb) = (a ~/ _n, a % _n, b ~/ _n, b % _n);
    return ra == rb ||
        ca == cb ||
        (ra ~/ _reel.boxRows == rb ~/ _reel.boxRows &&
            ca ~/ _reel.boxCols == cb ~/ _reel.boxCols);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final dark = theme.brightness == Brightness.dark;
    final line = theme.colorScheme.onSurface;
    return LayoutBuilder(
      builder: (context, box) {
        final compact = box.maxHeight < 520;
        final side = math.min(
          box.maxWidth - (compact ? 32 : 44),
          box.maxHeight - (compact ? 230 : 280),
        );
        final selected = _selected;
        Widget cell(int i) {
          final r = i ~/ _n, c = i % _n;
          final given = _reel.puzzle[i] != 0;
          final v = _cells[i];
          final isSel = i == selected;
          final wrong = i == _wrongCell;
          final thick = BorderSide(color: line, width: 2);
          final thin = BorderSide(color: line.withValues(alpha: 0.18));
          return Semantics(
            button: !given && v == 0,
            label: 'Row ${r + 1} column ${c + 1}, ${v == 0 ? 'empty' : '$v'}',
            excludeSemantics: true,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _select(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: wrong
                      ? _wrongColor.withValues(alpha: 0.35)
                      : isSel
                      ? kBrandBlue.withValues(alpha: 0.3)
                      : selected != null && _related(i, selected)
                      ? kBrandBlue.withValues(alpha: 0.08)
                      : (dark ? const Color(0x22FFFFFF) : Colors.white),
                  border: Border(
                    top: r % _reel.boxRows == 0 ? thick : thin,
                    left: c % _reel.boxCols == 0 ? thick : thin,
                    right: c == _n - 1 ? thick : BorderSide.none,
                    bottom: r == _n - 1 ? thick : BorderSide.none,
                  ),
                ),
                child: Text(
                  v == 0 ? '' : '$v',
                  style: TextStyle(
                    fontSize: side / _n * 0.5,
                    fontWeight: given ? FontWeight.w800 : FontWeight.w600,
                    color: given
                        ? theme.colorScheme.onSurface
                        : (_solved ? _correctColor : kBrandBlue),
                  ),
                ),
              ),
            ),
          );
        }

        return _CardShell(
          compact: compact,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ReelPills(kind: 'Sudoku', subject: 'Maths', level: _reel.level),
              const Spacer(),
              Text(
                'Fill in 1–$_n',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                'Each row, column and box has every number once.',
                style: theme.textTheme.bodyMedium?.copyWith(color: muted),
              ),
              SizedBox(height: compact ? 8 : 14),
              Center(
                child: SizedBox(
                  width: side,
                  height: side,
                  child: GridView.count(
                    crossAxisCount: _n,
                    physics: const NeverScrollableScrollPhysics(),
                    padding: EdgeInsets.zero,
                    children: [for (var i = 0; i < _n * _n; i++) cell(i)],
                  ),
                ),
              ),
              SizedBox(height: compact ? 10 : 16),
              if (_solved)
                _Feedback(
                  correct: true,
                  title: _mistakes == 0 ? 'Perfect!' : 'Solved!',
                  text: _mistakes == 0
                      ? 'No mistakes.'
                      : '$_mistakes ${_mistakes == 1 ? 'mistake' : 'mistakes'} on the way.',
                  compact: compact,
                )
              else
                Row(
                  children: [
                    for (var v = 1; v <= _n; v++) ...[
                      if (v > 1) const SizedBox(width: 6),
                      Expanded(
                        child: SizedBox(
                          height: compact ? 40 : 46,
                          child: _NumberTile(
                            value: '$v',
                            color: kBrandBlue,
                            selected: false,
                            onTap: selected == null ? null : () => _enter(v),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              const Spacer(),
              if (_solved)
                const _SwipeHint('Swipe up for the next one')
              else
                Text(
                  _wrongCell != null
                      ? 'That number is already in its row, column or box.'
                      : selected == null
                      ? 'Tap an empty square to start.'
                      : 'Now tap a number.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: _wrongCell != null ? _wrongColor : muted,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// Word search: tap a word's first letter, then its last, or drag across it.
class _WordSearchCard extends StatefulWidget {
  const _WordSearchCard({required this.reel, required this.progress});

  final WordSearchReel reel;
  final _ReelProgress progress;

  @override
  State<_WordSearchCard> createState() => _WordSearchCardState();
}

class _WordSearchCardState extends State<_WordSearchCard> {
  static const _found = [
    Color(0xFF22B573),
    Color(0xFFFF9F43),
    Color(0xFF8E5CF7),
    Color(0xFF4FC3F7),
  ];

  late final WordSearchReel _reel = widget.reel;
  late final Set<int> _done = widget.progress.solved.contains(_reel.id)
      ? {for (var i = 0; i < _reel.words.length; i++) i}
      : {};
  int? _start;
  int? _end;
  bool _missed = false;
  bool _wrong = false;
  Timer? _clear;

  int get _n => _reel.size;
  bool get _complete => _done.length == _reel.words.length;

  @override
  void dispose() {
    _clear?.cancel();
    super.dispose();
  }

  /// Cells on the straight line from [a] to [b], or null if not straight.
  List<int>? _line(int a, int b) {
    final dr = b ~/ _n - a ~/ _n, dc = b % _n - a % _n;
    if (dr != 0 && dc != 0 && dr.abs() != dc.abs()) return null;
    final steps = math.max(dr.abs(), dc.abs());
    final (sr, sc) = (dr.sign, dc.sign);
    return [
      for (var k = 0; k <= steps; k++)
        (a ~/ _n + sr * k) * _n + a % _n + sc * k,
    ];
  }

  List<int> get _selection {
    final a = _start;
    if (a == null) return const [];
    return _line(a, _end ?? a) ?? [a];
  }

  void _check() {
    final cells = _line(_start!, _end ?? _start!);
    final hit = cells == null || cells.length < 2 ? null : _reel.match(cells);
    if (hit != null && !_done.contains(hit)) {
      HapticFeedback.lightImpact();
      setState(() {
        _done.add(hit);
        _start = _end = null;
      });
      if (_complete) {
        widget.progress.solved.add(_reel.id);
        widget.progress.record(_reel.id, correct: !_missed);
      }
      return;
    }
    HapticFeedback.mediumImpact();
    _missed = true;
    _clear?.cancel();
    setState(() => _wrong = true);
    _clear = Timer(const Duration(milliseconds: 450), () {
      if (!mounted) return;
      setState(() {
        _wrong = false;
        _start = _end = null;
      });
    });
  }

  void _tap(int i) {
    if (_complete || _wrong) return;
    HapticFeedback.selectionClick();
    if (_start == null || _end != null) {
      setState(() {
        _start = i;
        _end = null;
      });
      return;
    }
    if (i == _start) {
      setState(() => _start = null);
      return;
    }
    setState(() => _end = i);
    _check();
  }

  /// One clue: its meaning, then the word once found, or its first letter
  /// and blanks for the rest.
  Widget _clue(ThemeData theme, int i) {
    final word = _reel.words[i];
    final done = _done.contains(i);
    final color = _found[i % _found.length];
    final text = word.word.toUpperCase();
    return Row(
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 22,
          height: 22,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: done ? color : kBrandBlue.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: done
              ? const Icon(Icons.check_rounded, size: 15, color: Colors.white)
              : Text(
                  '${i + 1}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: kBrandBlue,
                  ),
                ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            word.meaning,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          done
              ? (word.article == null ? text : '${word.article} $text')
              : '${text[0]}${' _' * (text.length - 1)}',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            letterSpacing: done ? 0.6 : 0,
            color: done ? color : theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  int? _cellAt(Offset p, double side) {
    final cell = side / _n;
    final r = (p.dy / cell).floor(), c = (p.dx / cell).floor();
    if (r < 0 || c < 0 || r >= _n || c >= _n) return null;
    return r * _n + c;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final dark = theme.brightness == Brightness.dark;
    final subject = kLanguageNames[_reel.lang] ?? _reel.lang.toUpperCase();
    return LayoutBuilder(
      builder: (context, box) {
        final compact = box.maxHeight < 520;
        final side = math.min(
          box.maxWidth - (compact ? 32 : 44),
          box.maxHeight - (compact ? 300 : 340),
        );
        final selection = _selection.toSet();
        final owner = <int, int>{
          for (final w in _done)
            for (final c in _reel.paths[w]) c: w,
        };
        return _CardShell(
          compact: compact,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ReelPills(
                kind: 'Word search',
                subject: subject,
                level: _reel.level,
              ),
              const Spacer(),
              Text(
                'Find the word that means…',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              for (var i = 0; i < _reel.words.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: _clue(theme, i),
                ),
              SizedBox(height: compact ? 8 : 14),
              Center(
                child: SizedBox(
                  width: side,
                  height: side,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapUp: (d) {
                      final i = _cellAt(d.localPosition, side);
                      if (i != null) _tap(i);
                    },
                    onPanStart: (d) {
                      if (_complete || _wrong) return;
                      final i = _cellAt(d.localPosition, side);
                      if (i != null) setState(() => _start = _end = i);
                    },
                    onPanUpdate: (d) {
                      if (_start == null || _wrong) return;
                      final i = _cellAt(d.localPosition, side);
                      if (i != null && i != _end && _line(_start!, i) != null) {
                        setState(() => _end = i);
                      }
                    },
                    onPanEnd: (_) {
                      if (_start != null && _end != null && _end != _start) {
                        _check();
                      } else {
                        setState(() => _start = _end = null);
                      }
                    },
                    child: GridView.count(
                      crossAxisCount: _n,
                      physics: const NeverScrollableScrollPhysics(),
                      padding: EdgeInsets.zero,
                      mainAxisSpacing: 3,
                      crossAxisSpacing: 3,
                      children: [
                        for (var i = 0; i < _n * _n; i++)
                          Semantics(
                            label:
                                'Letter ${_reel.letters[i]}, row '
                                '${i ~/ _n + 1} column ${i % _n + 1}',
                            excludeSemantics: true,
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 120),
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: selection.contains(i)
                                    ? (_wrong ? _wrongColor : kBrandBlue)
                                    : owner.containsKey(i)
                                    ? _found[owner[i]! % _found.length]
                                    : (dark
                                          ? const Color(0x22FFFFFF)
                                          : Colors.white),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                _reel.letters[i],
                                style: TextStyle(
                                  fontSize: side / _n * 0.48,
                                  fontWeight: FontWeight.w800,
                                  color:
                                      selection.contains(i) ||
                                          owner.containsKey(i)
                                      ? Colors.white
                                      : theme.colorScheme.onSurface,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              const Spacer(),
              if (_complete)
                const _SwipeHint('All found! Swipe up for the next one')
              else
                Text(
                  _wrong
                      ? 'Not a hidden word. Try again!'
                      : _start != null && _end == null
                      ? 'Now tap the last letter.'
                      : 'Tap the first letter, then the last. Or drag.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: _wrong ? _wrongColor : muted,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// Like and Save for a word search act on all its words, so they show up in
/// Saved Words; Share sends the clues.
class _WordSearchActionBar extends StatelessWidget {
  const _WordSearchActionBar({
    required this.reel,
    required this.interactions,
    required this.service,
  });

  final WordSearchReel reel;
  final WordInteractions interactions;
  final WordService service;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: interactions,
    builder: (context, _) {
      final ids = [for (final w in reel.words) w.id];
      final liked = ids.every((id) => interactions.stateOf(id).isLiked);
      final saved = ids.every((id) => interactions.stateOf(id).isSaved);
      // The puzzle is counted on its own, as well as each word in it.
      final key = 'search|${(ids.toList()..sort()).join(',')}';
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          LikeActionButton(
            liked: liked,
            countKey: key,
            onPressed: () {
              LikeCounts.instance.record(key, !liked);
              for (final id in ids) {
                interactions.setLiked(id, !liked);
              }
            },
          ),
          const SizedBox(height: 14),
          BookmarkActionButton(
            saved: saved,
            onPressed: () {
              for (final id in ids) {
                interactions.setSaved(id, !saved);
              }
            },
          ),
          const SizedBox(height: 14),
          _ShareQuestionButton(text: reel.shareText, service: service),
          const SizedBox(height: 12),
        ],
      );
    },
  );
}

/// The recogniser reading reels listen with; tests put a scripted one here.
@visibleForTesting
SpeechEngine? debugReadingEngine;

/// Read aloud, right on the reel: tap the mic, read, and each word turns
/// green as it is heard. Done scores the reading.
class _ReadingCard extends StatefulWidget {
  const _ReadingCard({required this.reel, required this.progress});

  final ReadingReel reel;
  final _ReelProgress progress;

  @override
  State<_ReadingCard> createState() => _ReadingCardState();
}

class _ReadingCardState extends State<_ReadingCard> {
  late final ReadingText _text = widget.reel.text;
  late final SpeechEngine _engine =
      debugReadingEngine ?? DeviceSpeechEngine.instance;
  late final ReadingSession _session = ReadingSession(
    Passage(
      PassageRequest(
        _text.topic,
        Difficulty.values[_text.level - 1],
        PassageLength.short,
      ),
      _text.text,
    ),
    engine: _engine,
  );

  /// The score from an earlier reading in this feed, if any.
  late final int? _last = widget.progress.choices[_text.id];

  @override
  void initState() {
    super.initState();
    _session.marks.addListener(_finishWhenAllSaid);
  }

  /// A sentence is short: once every word is heard, there's nothing to wait for.
  void _finishWhenAllSaid() {
    if (_session.phase != ReadingPhase.listening) return;
    if (_session.marks.value.every((m) => m == WordMark.matched)) _done();
  }

  @override
  void dispose() {
    // Swiping away stops the microphone.
    _session.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    HapticFeedback.selectionClick();
    final engine = _engine;
    if (engine is DeviceSpeechEngine) engine.language = _text.lang;
    await _session.start();
  }

  Future<void> _done() async {
    HapticFeedback.lightImpact();
    await _session.finish();
    final result = _session.result;
    if (!mounted || result == null) return;
    widget.progress.choices[_text.id] = result.accuracy;
    // Reading is one long stretch of real practice, measured by the session.
    ProgressStore.instance.addLearning(result.duration.inMilliseconds);
    widget.progress.record(
      _text.id,
      correct: result.accuracy >= 75,
      bonus: result.accuracy >= 90 ? 15 : 0,
    );
  }

  Future<void> _again() async {
    HapticFeedback.selectionClick();
    await _session.reset();
  }

  String _issueText(ReadingIssue issue) => switch (issue) {
    ReadingIssue.permissionDenied =>
      'Allow the microphone so I can hear you read.',
    ReadingIssue.unavailable =>
      'Speech recognition isn’t available on this phone.',
    ReadingIssue.microphone => 'The microphone is busy. Try again.',
    ReadingIssue.network => 'Check your internet connection and try again.',
    ReadingIssue.language =>
      _text.lang == 'de'
          ? 'German speech isn’t installed. Add German in your phone’s '
                'voice typing settings.'
          : 'English speech isn’t available on this phone.',
    ReadingIssue.noSpeech => 'I didn’t hear anything. Tap the mic and read.',
    ReadingIssue.failed => 'Something went wrong. Try again.',
  };

  /// Largest font from 30 down to 14 at which the sentence fits [box].
  double _fit(BoxConstraints box, TextStyle? style) {
    // Room for the meaning under it.
    final height = box.maxHeight - (_text.translation == null ? 0 : 56);
    for (var size = 30.0; size > 14; size -= 1) {
      final tp = TextPainter(
        text: TextSpan(
          text: _text.text,
          style: style?.copyWith(fontSize: size, height: 1.45),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: box.maxWidth);
      if (tp.height <= height) return size;
    }
    return 14;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final language = kLanguageNames[_text.lang] ?? _text.lang.toUpperCase();
    return LayoutBuilder(
      builder: (context, box) {
        final compact = box.maxHeight < 520;
        return _CardShell(
          compact: compact,
          child: ListenableBuilder(
            listenable: Listenable.merge([
              _session,
              _session.marks,
              _session.level,
            ]),
            builder: (context, _) {
              final phase = _session.phase;
              final result = _session.result;
              final marks = _session.marks.value;
              final words = _session.reference.words;
              final cursor = _session.cursor;
              final listening =
                  phase == ReadingPhase.listening ||
                  phase == ReadingPhase.starting;
              final issue = _session.issue;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _ReelPills(
                    kind: 'Read aloud',
                    subject: language,
                    level: _text.level,
                  ),
                  SizedBox(height: compact ? 8 : 12),
                  Text(
                    result != null
                        ? '${result.accuracy}% · ${result.headline}'
                        : listening
                        ? 'Listening… read it out loud'
                        : 'Say this',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: result == null
                          ? null
                          : result.accuracy >= 75
                          ? _correctColor
                          : _wrongColor,
                    ),
                  ),
                  SizedBox(height: compact ? 8 : 12),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, area) {
                        final base = theme.textTheme.bodyLarge;
                        final size = _fit(area, base);
                        final sentence = Text.rich(
                          TextSpan(
                            children: [
                              for (var i = 0; i < words.length; i++)
                                TextSpan(
                                  text: '${words[i].display} ',
                                  style: TextStyle(
                                    color: switch (marks[i]) {
                                      WordMark.matched => _correctColor,
                                      WordMark.missed => _wrongColor,
                                      WordMark.pending => kBrandBlue,
                                      WordMark.unread =>
                                        theme.colorScheme.onSurface,
                                    },
                                    fontWeight: listening && i == cursor
                                        ? FontWeight.w800
                                        : FontWeight.w500,
                                    decoration: marks[i] == WordMark.missed
                                        ? TextDecoration.underline
                                        : null,
                                    decorationColor: _wrongColor,
                                    backgroundColor: listening && i == cursor
                                        ? kBrandBlue.withValues(alpha: 0.15)
                                        : null,
                                  ),
                                ),
                            ],
                          ),
                          style: base?.copyWith(
                            fontSize: size,
                            height: 1.35,
                            fontWeight: FontWeight.w700,
                          ),
                        );
                        final meaning = _text.translation;
                        return Align(
                          alignment: Alignment.centerLeft,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              sentence,
                              if (meaning != null) ...[
                                const SizedBox(height: 10),
                                Text(
                                  meaning,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodyLarge?.copyWith(
                                    color: muted,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                  if (issue != null) ...[
                    Text(
                      _issueText(issue),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: _wrongColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  if (result != null) ...[
                    if (result.missedWords.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          'Practise: ${result.missedWords.take(6).join(', ')}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: muted,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    Row(
                      children: [
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(0, 44),
                          ),
                          onPressed: _again,
                          icon: const Icon(Icons.replay_rounded, size: 18),
                          label: const Text('Read again'),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(child: _SwipeHint('Swipe up')),
                      ],
                    ),
                  ] else
                    Row(
                      children: [
                        _MicButton(
                          listening: listening,
                          level: _session.level.value,
                          onPressed: listening
                              ? _session.pause
                              : (phase == ReadingPhase.finished
                                    ? null
                                    : _start),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            listening
                                ? 'Say the whole sentence.'
                                : phase == ReadingPhase.paused
                                ? 'Paused. Tap the mic to go on.'
                                : _last != null
                                ? 'Last time: $_last%. Tap the mic to read again.'
                                : 'Tap the mic and say it aloud.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: muted,
                            ),
                          ),
                        ),
                        if (_session.hasStarted)
                          FilledButton(
                            style: FilledButton.styleFrom(
                              minimumSize: const Size(84, 46),
                            ),
                            onPressed: _done,
                            child: const Text('Done'),
                          ),
                      ],
                    ),
                ],
              );
            },
          ),
        );
      },
    );
  }
}

/// Round microphone button that swells with the voice while listening.
class _MicButton extends StatelessWidget {
  const _MicButton({
    required this.listening,
    required this.level,
    required this.onPressed,
  });

  final bool listening;
  final double level;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: listening ? 'Pause reading' : 'Start reading',
    excludeSemantics: true,
    child: GestureDetector(
      onTap: onPressed,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        width: 58,
        height: 58,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: listening ? _wrongColor : kBrandBlue,
          boxShadow: [
            BoxShadow(
              color: (listening ? _wrongColor : kBrandBlue).withValues(
                alpha: 0.35,
              ),
              blurRadius: 8 + 22 * (listening ? level : 0),
              spreadRadius: 10 * (listening ? level : 0),
            ),
          ],
        ),
        child: Icon(
          listening ? Icons.pause_rounded : Icons.mic_rounded,
          color: Colors.white,
          size: 30,
        ),
      ),
    ),
  );
}

/// Like, Share and Save for a reading reel; saved paragraphs show up in
/// Saved Words.
class _ReadingActionBar extends StatelessWidget {
  const _ReadingActionBar({
    required this.reel,
    required this.interactions,
    required this.service,
  });

  final ReadingReel reel;
  final WordInteractions interactions;
  final WordService service;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: interactions,
    builder: (context, _) {
      final id = reel.id;
      final state = interactions.stateOf(id);
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          LikeActionButton(
            liked: state.isLiked,
            countKey: id,
            onPressed: () => interactions.toggleLike(id),
          ),
          const SizedBox(height: 14),
          BookmarkActionButton(
            saved: state.isSaved,
            onPressed: () => interactions.toggleSave(id),
          ),
          const SizedBox(height: 14),
          _ShareQuestionButton(
            text:
                'Can you read this aloud? 📖\n\n${reel.text.text}'
                '\n\nPractising with BiLingo',
            service: service,
          ),
          const SizedBox(height: 12),
        ],
      );
    },
  );
}

/// Level ring and rank for the current subject; "+10 XP" floats beside it
/// after each answer.
class _LevelChip extends StatelessWidget {
  const _LevelChip({required this.subject, required this.reward});

  final String subject;
  final ValueListenable<Reward?> reward;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: ProgressStore.instance,
      builder: (context, _) {
        final level = ProgressStore.instance.levelOf(subject);
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ValueListenableBuilder<Reward?>(
              valueListenable: reward,
              builder: (context, r, _) => r == null
                  ? const SizedBox.shrink()
                  : TweenAnimationBuilder<double>(
                      key: ObjectKey(r),
                      tween: Tween(begin: 0, end: 1),
                      duration: const Duration(milliseconds: 1400),
                      builder: (context, t, _) => t >= 1
                          ? const SizedBox.shrink()
                          : Opacity(
                              opacity: t < 0.7 ? 1 : (1 - t) / 0.3,
                              child: Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: Text(
                                  '+${r.xp} XP',
                                  style: TextStyle(
                                    color: _Feed.of(context).xp,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ),
                    ),
            ),
            Semantics(
              label: 'Level ${level.level}, ${level.rank}',
              excludeSemantics: true,
              child: SizedBox(
                width: 38,
                height: 38,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Positioned.fill(
                      child: CircularProgressIndicator(
                        value: level.fraction,
                        strokeWidth: 3.5,
                        strokeCap: StrokeCap.round,
                        color: _Feed.of(context).xp,
                        backgroundColor: _Feed.of(context).track,
                      ),
                    ),
                    Text(
                      '${level.level}',
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Segments along the top that fill as the learner moves through the feed.
class _StoryBar extends StatelessWidget {
  const _StoryBar({required this.current});

  final ValueListenable<int> current;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
    child: ExcludeSemantics(
      child: ValueListenableBuilder<int>(
        valueListenable: current,
        builder: (context, i, _) {
          final at = i % (_reelsPerSegment * _segments);
          return Row(
            children: [
              for (var s = 0; s < _segments; s++) ...[
                if (s > 0) const SizedBox(width: 5),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      minHeight: 3,
                      value:
                          ((at + 1 - s * _reelsPerSegment) / _reelsPerSegment)
                              .clamp(0.0, 1.0),
                      color: _Feed.of(context).xp,
                      backgroundColor: _Feed.of(context).track,
                    ),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    ),
  );
}

/// A dark panel for code, in a fixed-width font that never wraps.
class _CodeBlock extends StatelessWidget {
  const _CodeBlock(this.code, {required this.subject});

  final String code;
  final String subject;

  static const _keyword = Color(0xFFC792EA);
  static const _string = Color(0xFFF9D66B);
  static const _number = Color(0xFFF78C6C);
  static const _call = Color(0xFF7FDBFF);
  static const _plain = Color(0xFFE6EDF7);
  static const _gutter = Color(0x66FFFFFF);

  static final _tokens = RegExp(
    r'''("[^"]*"|'[^']*'|`[^`]*`)'''
    r'''|\b(const|let|var|function|return|if|else|for|while|of|in|new|class|async|await|try|catch|finally|def|elif|import|from|lambda|nonlocal|global|yield|not|and|or|is|True|False|None|true|false|null|undefined|typeof|this|self)\b'''
    r'''|\b(\d+(?:\.\d+)?)\b'''
    r'''|\b([A-Za-z_]\w*)(?=\()''',
  );

  /// Colours one line: strings, keywords, numbers and calls.
  static List<TextSpan> _spans(String line) {
    final spans = <TextSpan>[];
    var at = 0;
    for (final m in _tokens.allMatches(line)) {
      if (m.start > at) spans.add(TextSpan(text: line.substring(at, m.start)));
      final color = m[1] != null
          ? _string
          : m[2] != null
          ? _keyword
          : m[3] != null
          ? _number
          : _call;
      spans.add(
        TextSpan(
          text: m[0],
          style: TextStyle(color: color),
        ),
      );
      at = m.end;
    }
    if (at < line.length) spans.add(TextSpan(text: line.substring(at)));
    return spans;
  }

  @override
  Widget build(BuildContext context) {
    final lines = code.split('\n');
    const mono = TextStyle(
      fontFamily: 'monospace',
      fontSize: 15,
      height: 1.5,
      color: _plain,
    );
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF12141C),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _codeBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final c in const [
                  Color(0xFFFF5F57),
                  Color(0xFFFEBC2E),
                  Color(0xFF28C840),
                ])
                  Container(
                    width: 9,
                    height: 9,
                    margin: const EdgeInsets.only(right: 6),
                    decoration: BoxDecoration(color: c, shape: BoxShape.circle),
                  ),
                const SizedBox(width: 6),
                Text(
                  subject == 'python' ? 'main.py' : 'main.js',
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    color: _gutter,
                  ),
                ),
              ],
            ),
          ),
          Container(height: 1, width: 280, color: _codeBorder),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 18, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < lines.length; i++)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 24,
                        child: Text(
                          '${i + 1}',
                          style: mono.copyWith(color: _gutter),
                        ),
                      ),
                      Text.rich(
                        TextSpan(style: mono, children: _spans(lines[i])),
                        softWrap: false,
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Order the lines: tap the next line of the program; it moves up into place.
class _OrderLinesCard extends StatefulWidget {
  const _OrderLinesCard({required this.reel, required this.progress});

  final OrderLinesReel reel;
  final _ReelProgress progress;

  @override
  State<_OrderLinesCard> createState() => _OrderLinesCardState();
}

class _OrderLinesCardState extends State<_OrderLinesCard> {
  late final OrderLinesReel _reel = widget.reel;
  late bool _solved = widget.progress.solved.contains(_reel.id);
  late int _done = _solved ? _reel.lines.length : 0;
  late final List<String> _left = _solved ? [] : [..._reel.shuffled];
  int? _wrong;
  bool _missed = false;
  Timer? _clear;

  @override
  void dispose() {
    _clear?.cancel();
    super.dispose();
  }

  void _tap(int i) {
    if (_solved) return;
    // By text: two lines may read the same, such as closing braces.
    if (_left[i] == _reel.lines[_done]) {
      HapticFeedback.selectionClick();
      setState(() {
        _left.removeAt(i);
        _done++;
        _wrong = null;
      });
      if (_done == _reel.lines.length) {
        HapticFeedback.lightImpact();
        widget.progress.solved.add(_reel.id);
        widget.progress.record(_reel.id, correct: !_missed);
        setState(() => _solved = true);
      }
      return;
    }
    HapticFeedback.mediumImpact();
    _missed = true;
    _clear?.cancel();
    setState(() => _wrong = i);
    _clear = Timer(const Duration(milliseconds: 500), () {
      if (mounted) setState(() => _wrong = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return LayoutBuilder(
      builder: (context, box) {
        final compact = box.maxHeight < 520;
        return _CardShell(
          compact: compact,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ReelPills(
                kind: 'Order the lines',
                subject: _reel.languageName,
                level: _reel.level,
              ),
              const Spacer(),
              Text(
                _reel.prompt,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                constraints: const BoxConstraints(minHeight: 60),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF1B2233),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.topLeft,
                  child: Text(
                    _reel.lines.take(_done).join('\n'),
                    softWrap: false,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 15,
                      height: 1.4,
                      color: Color(0xFF7EE2A8),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              for (var i = 0; i < _left.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Semantics(
                    button: true,
                    label: 'Line ${_left[i].trim()}',
                    excludeSemantics: true,
                    child: GestureDetector(
                      onTap: () => _tap(i),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: i == _wrong
                              ? _wrongColor.withValues(alpha: 0.2)
                              : kBrandBlue.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: i == _wrong
                                ? _wrongColor
                                : kBrandBlue.withValues(alpha: 0.4),
                          ),
                        ),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            _left[i],
                            softWrap: false,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              if (_solved) ...[
                _Feedback(
                  correct: !_missed,
                  title: _missed ? 'Done!' : null,
                  text: 'The program runs in this order.',
                  compact: compact,
                ),
              ],
              const Spacer(),
              if (_solved)
                const _SwipeHint('Swipe up for the next one')
              else
                Text(
                  'Tap the next line of the program.',
                  style: theme.textTheme.bodySmall?.copyWith(color: muted),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// The chips under the header that narrow a feed to one kind of reel.
class _FilterChips extends StatelessWidget {
  const _FilterChips({
    required this.feed,
    required this.selected,
    required this.onSelect,
  });

  final String feed;
  final String selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return SizedBox(
      height: 33,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          for (final (code, label) in filtersFor(feed))
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Semantics(
                button: true,
                selected: code == selected,
                label: 'Show $label',
                excludeSemantics: true,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: code == selected ? null : () => onSelect(code),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                    decoration: BoxDecoration(
                      color: code == selected
                          ? kBrandBlue
                          : (dark ? const Color(0xFF222430) : const Color(0xFFF1F3F8)),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Center(
                      child: Text(
                        label,
                        style: TextStyle(
                          color: code == selected
                              ? Colors.white
                              : (dark ? Colors.white70 : const Color(0xFF5A5D6B)),
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Shown after the last reel when nothing new can be added.
class _EndCard extends StatelessWidget {
  const _EndCard({
    required this.filtered,
    required this.onReview,
    required this.onAll,
  });

  final bool filtered;
  final VoidCallback onReview;
  final VoidCallback onAll;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 0, 32, _navBarSpace),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Mascot(size: 130, mood: GhostMood.happy),
            const SizedBox(height: 8),
            Text(
              'You’ve done all the new ones!',
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              filtered
                  ? 'Review them to remember more, or go back to the full mix.'
                  : 'Review them to remember more.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 18),
            FilledButton(
              onPressed: onReview,
              child: const Text('Review again'),
            ),
            if (filtered) ...[
              const SizedBox(height: 8),
              OutlinedButton(onPressed: onAll, child: const Text('Show All')),
            ],
          ],
        ),
      ),
    );
  }
}
