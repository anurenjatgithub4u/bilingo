import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'premium_store.dart';

/// Shows an interstitial once when the app is opened, then once every
/// [swipesPerAd] words swiped in WordFlow. Nothing shows on resume, tab
/// switches or after sharing, and never to Premium learners. The next ad
/// is preloaded so it is ready.
class AdService {
  AdService._();
  static final AdService instance = AdService._();

  static const swipesPerAd = 5;

  /// A slow app-open ad is dropped (kept for later) rather than popping up
  /// over the learner after they have started.
  static const _openAdTimeout = Duration(seconds: 6);

  // Real unit in release builds only; debug/profile use Google's test unit so
  // tapping ads while developing can't flag the AdMob account.
  static const _interstitialUnitId = kReleaseMode
      ? 'ca-app-pub-1651818088795080/6116909602'
      : 'ca-app-pub-3940256099942544/1033173712';

  InterstitialAd? _ad;
  bool _ready = false;
  bool _loading = false;
  bool _showing = false;
  bool _openAdPending = false;
  int _swipes = 0;

  static bool get _premium => PremiumStore.instance.isPremium;

  Future<void> init() async {
    if (_premium) return;
    await MobileAds.instance.initialize();
    _ready = true;
    _openAdPending = true;
    Future.delayed(_openAdTimeout, () => _openAdPending = false);
    _load();
  }

  /// Call when the learner swipes to another word.
  void onReelSwiped() {
    if (_premium) return;
    _swipes++;
    if (_swipes < swipesPerAd) return;
    if (_ad == null) {
      // Not loaded yet: try on the next swipe instead of skipping a round.
      _load();
      return;
    }
    _swipes = 0;
    _show();
  }

  void _load() {
    if (!_ready || _loading || _ad != null) return;
    _loading = true;
    InterstitialAd.load(
      adUnitId: _interstitialUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _loading = false;
          _ad = ad;
          if (_openAdPending) {
            _openAdPending = false;
            _show();
          }
        },
        onAdFailedToLoad: (_) => _loading = false,
      ),
    );
  }

  void _show() {
    final ad = _ad;
    if (ad == null || _showing || _premium) return;
    _ad = null;
    _showing = true;
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        _showing = false;
        ad.dispose();
        _load();
      },
      onAdFailedToShowFullScreenContent: (ad, _) {
        _showing = false;
        ad.dispose();
        _load();
      },
    );
    ad.show();
  }
}
