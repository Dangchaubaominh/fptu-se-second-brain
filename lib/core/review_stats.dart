import 'flashcards.dart';

/// One graded review, appended to `.fptu/review_log.json`.
class ReviewEntry {
  const ReviewEntry(this.time, this.cardId, this.grade, this.prevInterval);

  final DateTime time;
  final String cardId;
  final Grade grade;

  /// Interval (days) before this review; 0 means the card was new or relearning.
  final int prevInterval;

  Map<String, dynamic> toJson() => {'t': time.toIso8601String(), 'id': cardId, 'g': grade.name, 'p': prevInterval};

  static ReviewEntry? fromJson(Object? j) {
    if (j is! Map) return null;
    final t = DateTime.tryParse('${j['t']}');
    final g = Grade.values.where((x) => x.name == j['g']).firstOrNull;
    if (t == null || g == null || j['id'] is! String) return null;
    return ReviewEntry(t, j['id'] as String, g, (j['p'] as num?)?.toInt() ?? 0);
  }
}

DateTime dayOf(DateTime t) => DateTime(t.year, t.month, t.day);

class ReviewStats {
  ReviewStats._({
    required this.perDay,
    required this.streak,
    required this.reviewsToday,
    required this.retention30,
    required this.newCards,
    required this.learningCards,
    required this.matureCards,
    required this.forecast,
  });

  /// Reviews per calendar day.
  final Map<DateTime, int> perDay;

  /// Consecutive days with reviews, ending today (or yesterday if today has none yet).
  final int streak;
  final int reviewsToday;

  /// Share of reviews of already-learned cards in the last 30 days that were
  /// remembered (not "Quên"). Null when there is nothing to measure yet.
  final double? retention30;

  final int newCards;

  /// Seen but interval < 21 days.
  final int learningCards;

  /// Interval ≥ 21 days (Anki's definition of mature).
  final int matureCards;

  /// Cards due on each of the next 7 days; overdue cards count toward today.
  final List<int> forecast;

  static ReviewStats compute(
    List<Flashcard> cards,
    Map<String, CardState> states,
    List<ReviewEntry> log, {
    DateTime? now,
  }) {
    final today = dayOf(now ?? DateTime.now());
    final perDay = <DateTime, int>{};
    for (final e in log) {
      final d = dayOf(e.time);
      perDay[d] = (perDay[d] ?? 0) + 1;
    }

    var streak = 0;
    var d = (perDay[today] ?? 0) > 0 ? today : DateTime(today.year, today.month, today.day - 1);
    while ((perDay[d] ?? 0) > 0) {
      streak++;
      d = DateTime(d.year, d.month, d.day - 1);
    }

    final since = DateTime(today.year, today.month, today.day - 30);
    final mature = log.where((e) => e.prevInterval > 0 && !e.time.isBefore(since)).toList();
    final retention = mature.isEmpty ? null : mature.where((e) => e.grade != Grade.again).length / mature.length;

    var fresh = 0, learning = 0, grown = 0;
    final forecast = List.filled(7, 0);
    for (final c in cards) {
      final s = states[c.id];
      if (s == null || s.reps == 0 && s.due == null) {
        fresh++;
        forecast[0]++;
        continue;
      }
      s.interval >= 21 ? grown++ : learning++;
      final due = s.due == null ? today : dayOf(s.due!);
      final offset = due.difference(today).inDays;
      if (offset < 7) forecast[offset < 0 ? 0 : offset]++;
    }

    return ReviewStats._(
      perDay: perDay,
      streak: streak,
      reviewsToday: perDay[today] ?? 0,
      retention30: retention,
      newCards: fresh,
      learningCards: learning,
      matureCards: grown,
      forecast: forecast,
    );
  }
}
