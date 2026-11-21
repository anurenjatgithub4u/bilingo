import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One checked question from the bundled coding bank or a downloaded pack.
class ContentItem {
  const ContentItem({
    required this.subject,
    required this.difficulty,
    required this.kind,
    required this.prompt,
    this.code,
    this.options = const [],
    this.answer = 0,
    this.explanation = '',
    this.lines = const [],
    this.topic,
  });

  /// 'en', 'de', 'python' or 'javascript'.
  final String subject;

  /// 1 beginner, 2 intermediate, 3 advanced.
  final int difficulty;

  /// Label over the question, such as "What does this print?". [lines] being
  /// set makes it an order-the-lines puzzle instead of a choice.
  final String kind;
  final String prompt;
  final String? code;
  final List<String> options;
  final int answer;
  final String explanation;

  /// The lines of a program in the right order, for order-the-lines.
  final List<String> lines;

  /// What it's about, such as 'travel', for matching a learner's taste.
  final String? topic;

  bool get isOrder => lines.isNotEmpty;

  /// Null for anything malformed, so a bad item can never crash the feed.
  static ContentItem? tryParse(Map<String, dynamic> j) {
    try {
      final options = ((j['options'] as List?) ?? const []).cast<String>();
      final lines = ((j['lines'] as List?) ?? const []).cast<String>();
      final answer = (j['answer'] as num?)?.toInt() ?? 0;
      final difficulty = (j['difficulty'] as num).toInt();
      final item = ContentItem(
        subject: j['subject'] as String,
        difficulty: difficulty,
        kind: j['kind'] as String,
        prompt: j['prompt'] as String,
        code: j['code'] as String?,
        options: options,
        answer: answer,
        explanation: (j['explanation'] as String?) ?? '',
        lines: lines,
        topic: j['topic'] as String?,
      );
      if (difficulty < 1 || difficulty > 3) return null;
      if (lines.isNotEmpty) return lines.length >= 3 ? item : null;
      final valid =
          options.length >= 2 &&
          options.length <= 4 &&
          options.toSet().length == options.length &&
          answer >= 0 &&
          answer < options.length;
      return valid ? item : null;
    } catch (_) {
      return null;
    }
  }

  Map<String, Object?> toJson() => {
    'subject': subject,
    'difficulty': difficulty,
    'kind': kind,
    'prompt': prompt,
    if (code != null) 'code': code,
    if (options.isNotEmpty) 'options': options,
    'answer': answer,
    'explanation': explanation,
    if (lines.isNotEmpty) 'lines': lines,
    if (topic != null) 'topic': topic,
  };
}

/// Questions beyond the fixed word list: the coding bank shipped in the app
/// plus packs generated on the server and published to Firestore
/// (`contentPacks`). Phones only ever read packs; they never call OpenAI.
class ContentPacks {
  ContentPacks._();

  static final ContentPacks instance = ContentPacks._();

  static const _itemsKey = 'content_pack_items';
  static const _syncedKey = 'content_pack_synced';

  /// Newest kept per subject, so storage stays small.
  static const _limit = 1500;

  List<ContentItem> _bank = const [];
  final _downloaded = <String, List<ContentItem>>{};
  bool _loaded = false;

  Future<void> load() async {
    _downloaded.clear();
    try {
      // Not loadString: for large files that uses a background isolate.
      final data = await rootBundle.load('assets/code_bank.json');
      final raw = utf8.decode(data.buffer.asUint8List());
      _bank = [
        for (final j in jsonDecode(raw) as List)
          ?ContentItem.tryParse((j as Map).cast<String, dynamic>()),
      ];
    } catch (e) {
      debugPrint('ContentPacks: no coding bank: $e');
      _bank = const [];
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_itemsKey);
      if (raw != null) _store(jsonDecode(raw) as List);
    } catch (_) {
      // Unreadable: they download again.
    }
    _loaded = true;
  }

  Future<void> ensureLoaded() async {
    if (!_loaded) await load();
  }

  /// Adds raw items, dropping malformed ones and the oldest over the limit.
  void _store(List<dynamic> raw) {
    for (final j in raw) {
      final item = ContentItem.tryParse((j as Map).cast<String, dynamic>());
      if (item == null) continue;
      final list = _downloaded.putIfAbsent(item.subject, () => []);
      list.add(item);
      if (list.length > _limit) list.removeAt(0);
    }
  }

  /// Everything available for [subject].
  List<ContentItem> itemsFor(String subject) => [
    ..._bank.where((i) =>
        subject == 'coding'
            ? (i.subject == 'python' || i.subject == 'javascript' || i.subject == 'coding')
            : i.subject == subject),
    ...?_downloaded[subject],
    if (subject == 'coding') ...?_downloaded['javascript'],
    if (subject == 'coding') ...?_downloaded['python'],
  ];

  /// Fetches packs published since the last sync. Quietly does nothing
  /// without Firebase or a connection; the feed never waits for this.
  Future<void> sync() async {
    if (Firebase.apps.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final since = prefs.getInt(_syncedKey) ?? 0;
      final snap = await FirebaseFirestore.instance
          .collection('contentPacks')
          .where('createdAt', isGreaterThan: since)
          .orderBy('createdAt')
          .limit(40)
          .get();
      if (snap.docs.isEmpty) return;
      var newest = since;
      for (final doc in snap.docs) {
        final data = doc.data();
        _store((data['items'] as List?) ?? const []);
        newest = (data['createdAt'] as num).toInt();
      }
      await prefs.setInt(_syncedKey, newest);
      await prefs.setString(
        _itemsKey,
        jsonEncode([
          for (final list in _downloaded.values)
            for (final item in list) item.toJson(),
        ]),
      );
    } catch (e) {
      debugPrint('ContentPacks: could not sync: $e');
    }
  }
}
