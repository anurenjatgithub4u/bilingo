import 'package:flutter/material.dart';

import '../services/taste_store.dart';
import 'app_theme.dart';
import 'mascot.dart';

/// "What are you into?": optional chips that give a feed its first taste.
/// Returns true if the choice was saved; closing it counts as skipping.
Future<bool> showInterestsSheet(BuildContext context) async {
  final saved = await showModalBottomSheet<bool>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => const _InterestsSheet(),
  );
  await TasteStore.instance.markAsked();
  return saved ?? false;
}

class _InterestsSheet extends StatefulWidget {
  const _InterestsSheet();

  @override
  State<_InterestsSheet> createState() => _InterestsSheetState();
}

class _InterestsSheetState extends State<_InterestsSheet> {
  late final Set<String> _picked = TasteStore.instance.picked;

  Future<void> _save() async {
    await TasteStore.instance.setPicked(_picked);
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Center(child: Mascot(size: 90, mood: GhostMood.happy)),
            Text(
              'What are you into?',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'I’ll show more of what you pick. Your choices stay on your '
              'phone, and I keep learning from what you like.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final e in kInterestTopics.entries)
                  FilterChip(
                    label: Text(e.value),
                    selected: _picked.contains(e.key),
                    selectedColor: kBrandBlue.withValues(alpha: 0.25),
                    onSelected: (on) => setState(() {
                      on ? _picked.add(e.key) : _picked.remove(e.key);
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 18),
            FilledButton(onPressed: _save, child: const Text('Save')),
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Skip for now'),
            ),
          ],
        ),
      ),
    );
  }
}
