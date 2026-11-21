import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Google Play subscription ids. Create subscriptions with exactly these
/// ids in Play Console → Monetize → Subscriptions.
const kPremiumMonthly = 'bilingo_premium_monthly';
const kPremiumYearly = 'bilingo_premium_yearly';
const kPremiumProducts = {kPremiumMonthly, kPremiumYearly};

/// What the free version allows.
const kFreeTrackedApps = 3;
const kFreeHardPerDay = 5;

/// BiLingo Premium: whether the learner has it, the plans on sale, buying
/// and restoring them through Google Play.
///
/// Google Play is the source of truth: on start the app asks Play which
/// subscriptions are active, so a cancelled or expired one switches Premium
/// off. The last answer is kept on the phone for offline starts.
class PremiumStore extends ChangeNotifier {
  PremiumStore._();

  static final PremiumStore instance = PremiumStore._();

  static const _activeKey = 'premium_active';
  static const _productKey = 'premium_product';
  static const _testKey = 'premium_test';

  /// How long to wait for Play to report restored purchases.
  static const _restoreWait = Duration(seconds: 6);

  SharedPreferences? _prefs;
  bool _active = false;
  String? _product;
  bool _test = false;

  InAppPurchase? _iap;
  StreamSubscription<List<PurchaseDetails>>? _sub;
  bool _storeAvailable = false;
  List<ProductDetails> _plans = const [];
  bool _busy = false;
  String? _error;

  /// Purchases seen during the current restore.
  bool _restoring = false;
  bool _seenActive = false;

  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    _active = _prefs!.getBool(_activeKey) ?? false;
    _product = _prefs!.getString(_productKey);
    _test = !kReleaseMode && (_prefs!.getBool(_testKey) ?? false);
    notifyListeners();
  }

  /// Has Premium, from Google Play or (in debug and profile builds only)
  /// the developer switch on the Premium screen.
  bool get isPremium => _active || _test;

  /// The subscription that gives Premium, when bought.
  String? get product => _product;

  /// Google Play billing works on this phone.
  bool get storeAvailable => _storeAvailable;

  /// The plans Play offers, monthly first; empty until Play Console has them.
  List<ProductDetails> get plans => _plans;

  bool get busy => _busy;

  /// The last billing problem to show, if any.
  String? get error => _error;

  /// Developer switch, for trying Premium before Play is set up.
  bool get testPremium => _test;

  Future<void> setTestPremium(bool value) async {
    if (kReleaseMode) return;
    _test = value;
    await _prefs?.setBool(_testKey, value);
    notifyListeners();
  }

  /// Connects to Google Play, loads the plans and checks what is owned.
  Future<void> start() async {
    if (_iap != null) return;
    try {
      _iap = InAppPurchase.instance;
      _storeAvailable = await _iap!.isAvailable();
      if (!_storeAvailable) {
        notifyListeners();
        return;
      }
      _sub = _iap!.purchaseStream.listen(
        _onPurchases,
        onError: (Object e) {
          _error = 'Google Play: $e';
          notifyListeners();
        },
      );
      await loadPlans();
      await restore(silent: true);
    } catch (e) {
      // No Play Store (tests, some emulators): the free version runs.
      debugPrint('PremiumStore: $e');
      _storeAvailable = false;
      notifyListeners();
    }
  }

  Future<void> loadPlans() async {
    final iap = _iap;
    if (iap == null || !_storeAvailable) return;
    final response = await iap.queryProductDetails(kPremiumProducts);
    // A subscription can come back once per offer; one card per plan.
    final byId = <String, ProductDetails>{};
    for (final p in response.productDetails) {
      byId.putIfAbsent(p.id, () => p);
    }
    _plans = [
      for (final id in [kPremiumMonthly, kPremiumYearly]) ?byId[id],
    ];
    notifyListeners();
  }

  /// Opens Google Play's checkout for [plan].
  Future<void> buy(ProductDetails plan) async {
    final iap = _iap;
    if (iap == null || _busy) return;
    _error = null;
    _busy = true;
    notifyListeners();
    try {
      // Subscriptions are bought as non-consumables on Google Play.
      await iap.buyNonConsumable(
        purchaseParam: PurchaseParam(productDetails: plan),
      );
    } catch (e) {
      _busy = false;
      _error = 'Couldn’t start the purchase. Please try again.';
      notifyListeners();
    }
  }

  /// Asks Play which subscriptions are active. Without one, Premium ends.
  /// [silent] keeps quiet about problems (the check on every start).
  Future<void> restore({bool silent = false}) async {
    final iap = _iap;
    if (iap == null || !_storeAvailable) return;
    _restoring = true;
    _seenActive = false;
    if (!silent) {
      _busy = true;
      _error = null;
      notifyListeners();
    }
    try {
      await iap.restorePurchases();
      await Future<void>.delayed(_restoreWait);
      if (_restoring && !_seenActive) await _setActive(false, null);
    } catch (e) {
      // Offline or Play busy: keep the last known state.
      if (!silent) _error = 'Couldn’t reach Google Play. Please try again.';
    } finally {
      _restoring = false;
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> _onPurchases(List<PurchaseDetails> purchases) async {
    for (final p in purchases) {
      if (!kPremiumProducts.contains(p.productID)) continue;
      switch (p.status) {
        case PurchaseStatus.purchased || PurchaseStatus.restored:
          _seenActive = true;
          await _setActive(true, p.productID);
          _busy = false;
        case PurchaseStatus.pending:
          _busy = true;
        case PurchaseStatus.error:
          _busy = false;
          _error = p.error?.message ?? 'The purchase didn’t go through.';
        case PurchaseStatus.canceled:
          _busy = false;
      }
      // Play refunds purchases that are never acknowledged.
      if (p.pendingCompletePurchase) await _iap?.completePurchase(p);
    }
    notifyListeners();
  }

  Future<void> _setActive(bool active, String? product) async {
    if (_active == active && _product == product) return;
    _active = active;
    _product = product;
    await _prefs?.setBool(_activeKey, active);
    if (product == null) {
      await _prefs?.remove(_productKey);
    } else {
      await _prefs?.setString(_productKey, product);
    }
    notifyListeners();
  }

  /// Kept with the learner's profile, for support and counting subscribers.
  Map<String, Object?> toCloud() => {'active': _active, 'product': _product};

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @visibleForTesting
  void resetForTest({bool premium = false}) {
    _active = premium;
    _product = null;
    _test = false;
    _plans = const [];
    _storeAvailable = false;
    _error = null;
    _busy = false;
    notifyListeners();
  }
}
