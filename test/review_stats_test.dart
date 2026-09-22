import 'package:flutter_test/flutter_test.dart';
import 'package:fptu_brain/core/deck_io.dart';
import 'package:fptu_brain/core/flashcards.dart';
import 'package:fptu_brain/core/review_stats.dart';
import 'package:fptu_brain/core/vault_index.dart';

void main() {
  final now = DateTime(2026, 9, 22, 20);
  DateTime daysAgo(int d, [int h = 9]) => DateTime(2026, 9, 22 - d, h);
  const cards = [
    Flashcard('a.md', 'Q1', 'A1'),
    Flashcard('a.md', 'Q2', 'A2'),
    Flashcard('a.md', 'Q3', 'A3'),
    Flashcard('b.md', 'Q4', 'A4'),
  ];

  group('ReviewStats', () {
    final states = {
      'a.md|Q1': CardState(interval: 30, reps: 5, due: DateTime(2026, 9, 24)), // mature, due in 2 days
      'a.md|Q2': CardState(interval: 3, reps: 2, due: DateTime(2026, 9, 20)), // learning, overdue
      'a.md|Q3': CardState(interval: 1, reps: 1, due: DateTime(2026, 10, 30)), // learning, beyond 7 days
    };
    final log = [
      ReviewEntry(daysAgo(0), 'a.md|Q1', Grade.good, 12),
      ReviewEntry(daysAgo(0, 10), 'a.md|Q2', Grade.again, 3),
      ReviewEntry(daysAgo(1), 'a.md|Q2', Grade.good, 0),
      ReviewEntry(daysAgo(2), 'a.md|Q3', Grade.easy, 5),
      ReviewEntry(daysAgo(4), 'a.md|Q3', Grade.hard, 2), // gap on day 3 breaks the streak
      ReviewEntry(daysAgo(40), 'a.md|Q1', Grade.again, 8), // outside the 30-day window
    ];
    final s = ReviewStats.compute(cards, states, log, now: now);

    test('per-day counts, streak and today', () {
      expect(s.perDay[DateTime(2026, 9, 22)], 2);
      expect(s.reviewsToday, 2);
      expect(s.streak, 3);
    });

    test('retention counts only reviews of learned cards in the last 30 days', () {
      // Reviews with prevInterval > 0 in window: good, again, easy, hard -> 3/4 remembered.
      expect(s.retention30, 0.75);
      expect(ReviewStats.compute(cards, {}, const [], now: now).retention30, isNull);
    });

    test('card buckets and 7-day forecast (overdue + new count today)', () {
      expect((s.newCards, s.learningCards, s.matureCards), (1, 2, 1));
      expect(s.forecast, [2, 0, 1, 0, 0, 0, 0]);
    });

    test('streak still counts when today has no reviews yet', () {
      final y = ReviewStats.compute(cards, {}, [ReviewEntry(daysAgo(1), 'x', Grade.good, 0)], now: now);
      expect(y.streak, 1);
      expect(y.reviewsToday, 0);
    });

    test('log entries round-trip through JSON and bad rows are dropped', () {
      final e = ReviewEntry(daysAgo(0), 'a.md|Q1', Grade.hard, 6);
      final back = ReviewEntry.fromJson(e.toJson())!;
      expect((back.cardId, back.grade, back.prevInterval, back.time), (e.cardId, e.grade, 6, e.time));
      expect(ReviewEntry.fromJson({'t': 'x', 'id': 'a', 'g': 'good'}), isNull);
    });
  });

  group('deck import/export', () {
    test('Anki TSV export round-trips through parseDeck', () {
      final tsv = exportDeckTsv(const [Flashcard('a.md', 'Big-O của\tbinary search?', 'O(log n)\nluôn')]);
      expect(tsv, startsWith('#separator:tab\n#html:false\n'));
      expect(parseDeck(tsv), [(question: 'Big-O của binary search?', answer: 'O(log n) luôn')]);
    });

    test('CSV with quotes, commas, header row and blank lines', () {
      const csv =
          'question,answer\n"OOP có mấy tính chất?","4: đóng gói, kế thừa, đa hình, trừu tượng"\n\n'
          '"Nói ""xin chào""",Hello\nchỉ một cột\n';
      expect(parseDeck(csv), [
        (question: 'OOP có mấy tính chất?', answer: '4: đóng gói, kế thừa, đa hình, trừu tượng'),
        (question: 'Nói "xin chào"', answer: 'Hello'),
      ]);
    });

    test('semicolon CSV from Excel (Vietnamese locale)', () {
      expect(parseDeck('Câu hỏi;Trả lời\nTCP ở tầng nào?;Transport'), [
        (question: 'TCP ở tầng nào?', answer: 'Transport'),
      ]);
    });

    test('imported deck note is parsed back as flashcards', () {
      final md = deckNote('Mạng', const [(question: 'Router ở tầng nào?', answer: 'Network (3)')], source: 'm.csv');
      final cards = parseFlashcards(Note.parse('Flashcards/Mạng.md', md, DateTime(2026)));
      expect(cards.single.question, 'Router ở tầng nào?');
      expect(cards.single.answer, 'Network (3)');
    });
  });
}
