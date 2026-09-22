import 'dart:math';

import 'markdown_utils.dart';
import 'vault_index.dart';

/// A card written in a note as `Question::Answer`
/// (same syntax as the Obsidian Spaced Repetition plugin).
class Flashcard {
  const Flashcard(this.notePath, this.question, this.answer);
  final String notePath;
  final String question;
  final String answer;

  String get id => '$notePath|$question';
}

final _cardRe = RegExp(r'^(?!\s*[-*>#|])\s*(.+?)(?<!:)::(?!:)(.+)$', multiLine: true);

List<Flashcard> parseFlashcards(Note note) => _cardRe
    .allMatches(stripCode(note.body))
    .map((m) => Flashcard(note.path, m.group(1)!.trim(), m.group(2)!.trim()))
    .where((c) => c.question.isNotEmpty && c.answer.isNotEmpty)
    .toList();

List<Flashcard> allFlashcards(VaultIndex index) => [for (final n in index.notes.values) ...parseFlashcards(n)];

/// Formats a card for writing back into a note (must stay on one line).
String formatFlashcard(String question, String answer) {
  String clean(String s) => s.replaceAll(RegExp(r'\s*\n\s*'), ' ').replaceAll('::', ':').trim();
  return '${clean(question)}::${clean(answer)}';
}

enum Grade { again, hard, good, easy }

class CardState {
  const CardState({this.ease = 2.5, this.interval = 0, this.reps = 0, this.due});

  final double ease;

  /// Days until next review.
  final int interval;
  final int reps;

  /// Null means the card is new and due now.
  final DateTime? due;

  bool isDue(DateTime now) => due == null || !due!.isAfter(now);

  Map<String, dynamic> toJson() => {
    'ease': double.parse(ease.toStringAsFixed(2)),
    'interval': interval,
    'reps': reps,
    if (due != null) 'due': due!.toIso8601String(),
  };

  factory CardState.fromJson(Map<String, dynamic> j) => CardState(
    ease: (j['ease'] as num?)?.toDouble() ?? 2.5,
    interval: (j['interval'] as num?)?.toInt() ?? 0,
    reps: (j['reps'] as num?)?.toInt() ?? 0,
    due: j['due'] == null ? null : DateTime.tryParse(j['due'] as String),
  );
}

/// SM-2 style scheduling.
CardState schedule(CardState s, Grade g, DateTime now) {
  var ease = s.ease;
  int interval;
  var reps = s.reps;
  switch (g) {
    case Grade.again:
      reps = 0;
      interval = 0;
      ease -= 0.2;
    case Grade.hard:
      reps += 1;
      interval = max(1, (max(s.interval, 1) * 1.2).round());
      ease -= 0.15;
    case Grade.good:
      reps += 1;
      interval = switch (reps) {
        1 => 1,
        2 => 3,
        _ => (max(s.interval, 1) * ease).round(),
      };
    case Grade.easy:
      reps += 1;
      interval = switch (reps) {
        1 => 3,
        2 => 6,
        _ => (max(s.interval, 1) * ease * 1.3).round(),
      };
      ease += 0.15;
  }
  ease = ease.clamp(1.3, 3.0);
  final due = interval == 0 ? now.add(const Duration(minutes: 10)) : DateTime(now.year, now.month, now.day + interval);
  return CardState(ease: ease, interval: interval, reps: reps, due: due);
}
