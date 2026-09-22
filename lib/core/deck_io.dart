import 'flashcards.dart';

/// Exports cards as tab-separated text that Anki imports directly
/// (File → Import; the `#` header lines configure the importer).
String exportDeckTsv(List<Flashcard> cards) {
  String clean(String s) => s.replaceAll(RegExp(r'[\t\r\n]+'), ' ').trim();
  final sb = StringBuffer()
    ..writeln('#separator:tab')
    ..writeln('#html:false')
    ..writeln('#columns:Front\tBack\tSource');
  for (final c in cards) {
    sb.writeln('${clean(c.question)}\t${clean(c.answer)}\t${clean(c.notePath)}');
  }
  return sb.toString();
}

const _headerWords = {'front', 'back', 'question', 'answer', 'câu hỏi', 'trả lời', 'term', 'definition'};

/// Parses question/answer pairs from TSV (Anki/Quizlet export) or CSV
/// (quoted fields allowed). Comment lines, a header row and rows with fewer
/// than two non-empty columns are skipped.
List<({String question, String answer})> parseDeck(String text) {
  final lines = text.replaceAll('\r\n', '\n').split('\n');
  final tabbed = lines.any((l) => l.startsWith('#separator:tab')) || lines.any((l) => l.contains('\t'));
  final rows = tabbed
      ? [
          for (final l in lines)
            if (!l.startsWith('#')) l.split('\t'),
        ]
      : _parseCsv(lines.where((l) => !l.startsWith('#')).join('\n'));

  final out = <({String question, String answer})>[];
  for (final (i, r) in rows.indexed) {
    if (r.length < 2) continue;
    final q = r[0].trim(), a = r[1].trim();
    if (q.isEmpty || a.isEmpty) continue;
    if (i == 0 && _headerWords.contains(q.toLowerCase()) && _headerWords.contains(a.toLowerCase())) continue;
    out.add((question: q, answer: a));
  }
  return out;
}

List<List<String>> _parseCsv(String text) {
  // Excel in Vietnamese locale writes `;`-separated CSV; otherwise use `,`.
  final first = text.split('\n').first;
  final sep = first.contains(';') && !first.contains(',') ? ';' : ',';
  final rows = <List<String>>[];
  var row = <String>[];
  final field = StringBuffer();
  var quoted = false;
  for (var i = 0; i < text.length; i++) {
    final c = text[i];
    if (quoted) {
      if (c == '"') {
        if (i + 1 < text.length && text[i + 1] == '"') {
          field.write('"');
          i++;
        } else {
          quoted = false;
        }
      } else {
        field.write(c);
      }
    } else if (c == '"') {
      quoted = true;
    } else if (c == sep) {
      row.add(field.toString());
      field.clear();
    } else if (c == '\n') {
      row.add(field.toString());
      field.clear();
      rows.add(row);
      row = <String>[];
    } else {
      field.write(c);
    }
  }
  if (field.isNotEmpty || row.isNotEmpty) {
    row.add(field.toString());
    rows.add(row);
  }
  return rows;
}

/// Builds a deck note of `Q::A` lines for the imported cards.
String deckNote(String title, List<({String question, String answer})> cards, {String? source}) {
  final sb = StringBuffer()
    ..writeln('---')
    ..writeln('type: deck')
    ..writeln('tags: [flashcards]')
    ..writeln('---')
    ..writeln('# $title')
    ..writeln();
  if (source != null) {
    sb
      ..writeln('Nhập từ `$source`.')
      ..writeln();
  }
  sb.writeln('## Flashcards');
  for (final c in cards) {
    sb.writeln(formatFlashcard(c.question, c.answer));
  }
  return sb.toString();
}
