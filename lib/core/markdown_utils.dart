import 'package:yaml/yaml.dart';

/// A parsed Obsidian wikilink: `[[target#heading|alias]]` or `![[embed]]`.
class WikiLink {
  const WikiLink(this.target, {this.heading, this.alias, this.embed = false});

  final String target;
  final String? heading;
  final String? alias;
  final bool embed;

  String get label => alias ?? (heading != null ? '$target > $heading' : target);
}

final _wikiRe = RegExp(r'(!?)\[\[([^\[\]\n]+?)\]\]');
final _fenceRe = RegExp(r'```[\s\S]*?(```|$)');
final _inlineCodeRe = RegExp(r'`[^`\n]*`');
final _tagRe = RegExp(r'(?<=^|[\s(,])#([\p{L}\p{N}_/-]*[\p{L}_/-][\p{L}\p{N}_/-]*)', unicode: true);

/// Removes fenced and inline code so links/tags inside code are ignored.
String stripCode(String text) =>
    text.replaceAll(_fenceRe, '').replaceAll(_inlineCodeRe, '');

WikiLink _toLink(Match m) {
  var inner = m.group(2)!.trim();
  String? alias;
  String? heading;
  final pipe = inner.indexOf('|');
  if (pipe >= 0) {
    alias = inner.substring(pipe + 1).trim();
    inner = inner.substring(0, pipe).trim();
  }
  final hash = inner.indexOf('#');
  if (hash >= 0) {
    heading = inner.substring(hash + 1).trim();
    inner = inner.substring(0, hash).trim();
  }
  return WikiLink(inner, heading: heading, alias: alias, embed: m.group(1) == '!');
}

List<WikiLink> parseWikiLinks(String body) =>
    _wikiRe.allMatches(stripCode(body)).map(_toLink).where((l) => l.target.isNotEmpty).toList();

Set<String> parseInlineTags(String body) =>
    _tagRe.allMatches(stripCode(body)).map((m) => m.group(1)!.toLowerCase()).toSet();

/// Splits YAML frontmatter (`---` block at the very top) from the body.
({Map<String, dynamic> data, String body}) splitFrontmatter(String content) {
  final text = content.replaceFirst('﻿', '');
  final range = _frontmatterRange(text);
  if (range == null) return (data: const {}, body: text);
  final yamlText = text.substring(range.$1, range.$2);
  final body = text.substring(range.$3);
  try {
    final parsed = loadYaml(yamlText);
    if (parsed is YamlMap) {
      return (data: _plain(parsed) as Map<String, dynamic>, body: body);
    }
  } catch (_) {
    // Malformed YAML: Obsidian still shows the note, so do we.
  }
  return (data: const {}, body: body);
}

/// Returns (yamlStart, yamlEnd, bodyStart) or null when there is no frontmatter.
(int, int, int)? _frontmatterRange(String text) {
  final open = RegExp(r'^---[ \t]*\r?\n').firstMatch(text);
  if (open == null) return null;
  final close = RegExp(r'^---[ \t]*(\r?\n|$)', multiLine: true).firstMatch(text.substring(open.end));
  if (close == null) return null;
  return (open.end, open.end + close.start, open.end + close.end);
}

Object? _plain(Object? v) {
  if (v is YamlMap) return {for (final e in v.entries) e.key.toString(): _plain(e.value)};
  if (v is YamlList) return v.map(_plain).toList();
  return v;
}

/// Sets `key: value` inside the frontmatter, creating the block if needed.
/// Only touches that one line so the rest of the user's YAML is preserved.
String setFrontmatterField(String content, String key, String value) {
  final line = '$key: $value';
  final range = _frontmatterRange(content);
  if (range == null) return '---\n$line\n---\n$content';
  final yamlText = content.substring(range.$1, range.$2);
  final keyRe = RegExp('^${RegExp.escape(key)}:.*\$', multiLine: true);
  final newYaml = keyRe.hasMatch(yamlText)
      ? yamlText.replaceFirst(keyRe, line)
      : '${yamlText.trimRight()}\n$line\n';
  return content.replaceRange(range.$1, range.$2, newYaml.endsWith('\n') ? newYaml : '$newYaml\n');
}

List<String> asStringList(Object? v) {
  if (v == null) return const [];
  if (v is List) return v.map((e) => e.toString()).toList();
  return v.toString().split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
}

const _calloutIcons = {
  'info': 'ℹ️', 'note': '📝', 'tip': '💡', 'hint': '💡', 'important': '❗',
  'warning': '⚠️', 'caution': '⚠️', 'danger': '⛔', 'example': '🧪',
  'question': '❓', 'faq': '❓', 'success': '✅', 'abstract': '📌', 'summary': '📌', 'quote': '💬',
};

/// Converts Obsidian-only syntax into plain Markdown for the preview:
/// `[[x|y]]` -> `[y](wikilink:x)`, callouts -> bold blockquote title.
/// Code blocks are left untouched.
String obsidianToMarkdown(String body) {
  final parts = body.split('```');
  for (var i = 0; i < parts.length; i += 2) {
    parts[i] = parts[i]
        .replaceAllMapped(_wikiRe, (m) {
          final l = _toLink(m);
          final href = Uri.encodeComponent(l.heading == null ? l.target : '${l.target}#${l.heading}');
          return '[${l.label}](wikilink:$href)';
        })
        .replaceAllMapped(RegExp(r'^(\s*>\s*)\[!(\w+)\][+-]?\s*(.*)$', multiLine: true), (m) {
          final type = m.group(2)!.toLowerCase();
          final title = m.group(3)!.isEmpty ? type[0].toUpperCase() + type.substring(1) : m.group(3)!;
          return '${m.group(1)}**${_calloutIcons[type] ?? '📌'} $title**\n${m.group(1)}';
        });
  }
  return parts.join('```');
}

const _vnFrom = 'àáạảãâầấậẩẫăằắặẳẵèéẹẻẽêềếệểễìíịỉĩòóọỏõôồốộổỗơờớợởỡùúụủũưừứựửữỳýỵỷỹđ';
const _vnTo = 'aaaaaaaaaaaaaaaaaeeeeeeeeeeeiiiiiooooooooooooooooouuuuuuuuuuuyyyyyd';
final _vnMap = {for (var i = 0; i < _vnFrom.length; i++) _vnFrom[i]: _vnTo[i]};

/// Lower-cases and strips Vietnamese diacritics, keeping string length
/// identical so match offsets map back onto the original text.
String foldVietnamese(String s) {
  final lower = s.toLowerCase();
  final sb = StringBuffer();
  for (var i = 0; i < lower.length; i++) {
    final c = lower[i];
    sb.write(_vnMap[c] ?? c);
  }
  return sb.toString();
}
