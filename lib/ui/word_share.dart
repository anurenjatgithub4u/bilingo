import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../services/vocab.dart';
import '../services/word_service.dart';
import 'app_theme.dart';
import 'mascot.dart';

/// Shares [word] as a branded picture card through the system share sheet,
/// so it can go to WhatsApp, Instagram, Telegram or any other app. Falls back
/// to plain text if the picture cannot be made. Returns false when sharing
/// could not be opened at all.
Future<bool> shareWordCard(
  BuildContext context,
  VocabWord word, {
  WordService service = const WordService(),
}) async {
  Uint8List? png;
  try {
    png = await _renderCard(context, word);
  } catch (e) {
    debugPrint('shareWordCard: could not draw the card: $e');
  }
  try {
    if (png != null) {
      await service.shareImage(png, word.shareText);
    } else {
      await service.shareText(word.shareText);
    }
    return true;
  } catch (e) {
    debugPrint('shareWordCard: $e');
    try {
      await service.shareText(word.shareText);
      return true;
    } catch (_) {
      return false;
    }
  }
}

/// Lays the card out off screen for a frame and captures it as a PNG
/// (1080 × 1350, the 4:5 portrait size Instagram and WhatsApp show in full).
Future<Uint8List?> _renderCard(BuildContext context, VocabWord word) async {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return null;
  final key = GlobalKey();
  final theme = Theme.of(context);
  final entry = OverlayEntry(
    builder: (_) => Positioned(
      // Far outside the screen: painted, never seen.
      left: -ShareCard.width * 4,
      top: 0,
      child: RepaintBoundary(
        key: key,
        child: Theme(
          data: theme,
          child: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.noScaling),
            child: ShareCard(word: word),
          ),
        ),
      ),
    ),
  );
  overlay.insert(entry);
  try {
    await WidgetsBinding.instance.endOfFrame;
    await WidgetsBinding.instance.endOfFrame;
    final boundary =
        key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return null;
    final image = await boundary.toImage(pixelRatio: 1080 / ShareCard.width);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return data?.buffer.asUint8List();
  } finally {
    entry.remove();
  }
}

/// The picture that gets shared: BiLingo branding, the word, its meaning,
/// an example sentence and the language.
class ShareCard extends StatelessWidget {
  const ShareCard({super.key, required this.word});

  static const width = 360.0;
  static const height = 450.0;

  final VocabWord word;

  @override
  Widget build(BuildContext context) {
    final gender = word.gender;
    final accent = gender?.color ?? kBrandBlue;
    return SizedBox(
      width: width,
      height: height,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF2F80FF), Color(0xFF7A5CFA)],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
          child: DefaultTextStyle(
            style: const TextStyle(
              color: Color(0xFF16213A),
              fontFamily: 'Roboto',
              decoration: TextDecoration.none,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const SizedBox(
                      width: 34,
                      height: 34,
                      child: FittedBox(child: Mascot(size: 80, still: true)),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'BiLingo',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.3,
                      ),
                    ),
                    const Spacer(),
                    _Tag(word.languageName, Colors.white, kBrandBlue),
                  ],
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (gender != null) ...[
                          _Tag(
                            '${gender.article} · ${gender.label}',
                            accent.withValues(alpha: 0.14),
                            accent,
                          ),
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
                                    style: TextStyle(color: accent),
                                  ),
                                TextSpan(text: word.word),
                              ],
                            ),
                            style: const TextStyle(
                              fontSize: 34,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        if (word.pluralLine case final plural?)
                          Text(
                            plural,
                            style: const TextStyle(
                              fontSize: 15,
                              color: Color(0xFF5B6B8C),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        if (word.romanised != null)
                          Text(
                            word.romanised!,
                            style: const TextStyle(
                              fontSize: 15,
                              color: Color(0xFF5B6B8C),
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        const SizedBox(height: 10),
                        Text(
                          word.meaning,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 17, height: 1.35),
                        ),
                        const Spacer(),
                        if (word.example != null)
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF1F6FF),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '“${word.example}”',
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    height: 1.35,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                if (word.translation != null) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    word.translation!,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      color: Color(0xFF5B6B8C),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Learn a new word every unlock · BiLingo',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.text, this.background, this.color);

  final String text;
  final Color background;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      text,
      style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700),
    ),
  );
}
