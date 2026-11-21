import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'services/ad_service.dart';
import 'services/arrest_store.dart';
import 'services/cloud_sync.dart';
import 'services/content_packs.dart';
import 'services/like_counts.dart';
import 'services/premium_store.dart';
import 'services/profile_store.dart';
import 'services/progress_store.dart';
import 'services/rating_service.dart';
import 'services/seen_content.dart';
import 'services/taste_store.dart';
import 'services/word_interactions.dart';
import 'services/word_service.dart';
import 'ui/app_theme.dart';
import 'ui/splash_screen.dart';
import 'ui/word_links.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Draw behind the system bars so the gradient fills them (Android 15+
  // does this by default; older versions show a grey status bar otherwise).
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  await Firebase.initializeApp();
  await ProfileStore.instance.load();
  await WordInteractions.instance.load();
  await SeenContent.instance.load();
  await ProgressStore.instance.load();
  await ContentPacks.instance.load();
  await TasteStore.instance.load();
  await ArrestStore.instance.load();
  // Before ads start, so Premium learners never see one.
  await PremiumStore.instance.load();
  await RatingService.instance.load();
  themeModeNotifier.value = ProfileStore.instance.darkTheme
      ? ThemeMode.dark
      : ThemeMode.light;
  WordLinks.instance.init();
  // The background tracker needs to know whether to arrest or just nudge.
  unawaited(
    const WordService()
        .update(mascot: ProfileStore.instance.mascot.name)
        .then((_) {}, onError: (_) {}),
  );
  runApp(const BiLingoApp(service: WordService()));
  AdService.instance.init();
  // Asks Google Play what is owned; a lapsed subscription ends Premium.
  unawaited(PremiumStore.instance.start());
  CloudSync.instance.start();
  LikeCounts.instance.start(earlierLikes: WordInteractions.instance.likedIds);
  // In the background; the feed uses what it has until this finishes.
  ContentPacks.instance.sync();
}

class BiLingoApp extends StatelessWidget {
  const BiLingoApp({super.key, required this.service});

  final WordService service;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeModeNotifier,
      builder: (context, mode, _) => MaterialApp(
        title: 'BiLingo',
        navigatorKey: navigatorKey,
        debugShowCheckedModeBanner: false,
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
        themeMode: mode,
        builder: (context, child) {
          final dark = Theme.of(context).brightness == Brightness.dark;
          return AnnotatedRegion<SystemUiOverlayStyle>(
            value: (dark
                    ? SystemUiOverlayStyle.light
                    : SystemUiOverlayStyle.dark)
                .copyWith(
                  statusBarColor: Colors.transparent,
                  systemNavigationBarColor: Colors.transparent,
                  systemNavigationBarContrastEnforced: false,
                ),
            child: child!,
          );
        },
        home: const SplashScreen(),
      ),
    );
  }
}
