import 'markdown_utils.dart';
import 'vault_index.dart';

/// The notes sent to Claude for a vault-wide question or quiz.
class VaultContext {
  const VaultContext({required this.label, required this.text, required this.included, required this.omitted});

  /// e.g. "Toàn bộ vault" or "PRO192 — Object-Oriented Programming".
  final String label;
  final String text;
  final List<String> included;

  /// Notes left out because the scope exceeded [buildVaultContext]'s budget.
  final List<String> omitted;
}

/// Collects the notes for a scope: the whole vault, or one course (the course
/// note plus everything it links to and everything linking to it).
///
/// Everything fits in one request for typical student vaults. When it doesn't,
/// the notes most relevant to [question] are kept and the rest are reported
/// in [VaultContext.omitted] rather than silently dropped.
VaultContext buildVaultContext(VaultIndex index, {String? coursePath, String question = '', int maxChars = 600000}) {
  final course = coursePath == null ? null : index.notes[coursePath];
  final paths = course == null
      ? (index.notes.keys.toList()..sort())
      : [
          course.path,
          ...{...?index.outgoing[course.path], ...?index.backlinks[course.path]}.toList()..sort(),
        ];
  final label = course == null
      ? 'Toàn bộ vault "${index.name}"'
      : '${course.courseCode}${course.courseName.isEmpty ? '' : ' — ${course.courseName}'}';

  var ordered = paths;
  final total = paths.fold<int>(0, (s, p) => s + index.notes[p]!.content.length);
  if (total > maxChars) {
    final terms = foldVietnamese(question).split(RegExp(r'[^a-z0-9]+')).where((t) => t.length > 2).toSet();
    int score(String p) {
      final n = index.notes[p]!;
      final title = foldVietnamese(n.title);
      final body = foldVietnamese(n.content);
      return terms.fold(0, (s, t) => s + (title.contains(t) ? 20 : 0) + t.allMatches(body).length) +
          (p == coursePath ? 1000 : 0);
    }

    ordered = [...paths]..sort((a, b) => score(b).compareTo(score(a)));
  }

  final included = <String>[];
  final omitted = <String>[];
  final sb = StringBuffer();
  for (final p in ordered) {
    final n = index.notes[p]!;
    final chunk = '<note path="${n.path}" title="${n.title}">\n${n.content.trim()}\n</note>\n\n';
    if (sb.length + chunk.length > maxChars && included.isNotEmpty) {
      omitted.add(p);
      continue;
    }
    sb.write(chunk);
    included.add(p);
  }
  return VaultContext(label: label, text: sb.toString(), included: included, omitted: omitted);
}

class QuizQuestion {
  const QuizQuestion({
    required this.question,
    required this.options,
    required this.answerIndex,
    required this.explanation,
    this.source,
  });

  final String question;
  final List<String> options;
  final int answerIndex;
  final String explanation;

  /// Title of the note the question came from, if the model named one.
  final String? source;

  /// Parses model output, dropping malformed questions instead of failing the whole quiz.
  static List<QuizQuestion> listFromJson(Map<String, dynamic> json) => [
    for (final q in (json['questions'] as List? ?? const []).whereType<Map<String, dynamic>>())
      if (q['question'] is String &&
          q['options'] is List &&
          (q['options'] as List).length >= 2 &&
          q['answer_index'] is int &&
          (q['answer_index'] as int) >= 0 &&
          (q['answer_index'] as int) < (q['options'] as List).length)
        QuizQuestion(
          question: (q['question'] as String).trim(),
          options: [for (final o in q['options'] as List) o.toString().trim()],
          answerIndex: q['answer_index'] as int,
          explanation: (q['explanation'] as String? ?? '').trim(),
          source: (q['source'] as String?)?.trim().isEmpty ?? true ? null : (q['source'] as String).trim(),
        ),
  ];
}

const _letters = 'ABCDEFGH';

/// Saves a quiz as an Obsidian note: answers are hidden in folded callouts.
String quizToMarkdown(String scopeLabel, List<QuizQuestion> questions, {DateTime? at, List<int?>? answers}) {
  final t = at ?? DateTime.now();
  final date =
      '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')} '
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  final correct = answers == null
      ? null
      : [for (var i = 0; i < questions.length; i++) answers[i] == questions[i].answerIndex].where((x) => x).length;
  final sb = StringBuffer()
    ..writeln('---')
    ..writeln('type: quiz')
    ..writeln('scope: "${scopeLabel.replaceAll('"', "'")}"')
    ..writeln('created: $date')
    ..writeln(correct == null ? 'score: ' : 'score: $correct/${questions.length}')
    ..writeln('tags: [quiz]')
    ..writeln('---')
    ..writeln('# Đề trắc nghiệm — $scopeLabel')
    ..writeln();
  for (var i = 0; i < questions.length; i++) {
    final q = questions[i];
    sb.writeln('## Câu ${i + 1}. ${q.question}');
    for (var j = 0; j < q.options.length; j++) {
      sb.writeln('- ${_letters[j]}. ${q.options[j]}');
    }
    sb
      ..writeln()
      ..writeln('> [!success]- Đáp án: ${_letters[q.answerIndex]}')
      ..writeln('> ${q.explanation.replaceAll('\n', '\n> ')}');
    if (q.source != null) sb.writeln('> Nguồn: [[${q.source}]]');
    sb.writeln();
  }
  return sb.toString();
}
