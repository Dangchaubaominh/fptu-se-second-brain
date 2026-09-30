import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:watcher/watcher.dart';

import '../core/ai_assistant.dart';
import '../core/claude_client.dart';
import '../core/flashcards.dart';
import '../core/openai_client.dart';
import '../core/rename.dart';
import '../core/review_stats.dart';
import '../core/vault_index.dart';
import '../core/vault_repository.dart';

final prefsProvider = Provider<SharedPreferences>((ref) => throw UnimplementedError('override in main'));

/// Version from pubspec.yaml, read from the built executable.
final appVersionProvider = FutureProvider<String>((ref) async => (await PackageInfo.fromPlatform()).version);

/// Whether to look for a new GitHub release on startup (disabled in tests).
final autoUpdateCheckProvider = Provider<bool>((ref) => true);

/// Which service the AI features talk to.
enum AiProvider { claude, openAiCompatible }

class AppSettings {
  const AppSettings({
    this.vaultPath,
    this.apiKey = '',
    this.themeMode = ThemeMode.system,
    this.provider = AiProvider.claude,
    this.altApiKey = '',
    this.altBaseUrl = '',
    this.altModel = '',
    this.altProviderName = '',
  });

  final String? vaultPath;

  /// Anthropic key.
  final String apiKey;
  final ThemeMode themeMode;

  final AiProvider provider;

  /// Key, endpoint and model for the OpenAI-compatible provider.
  final String altApiKey;
  final String altBaseUrl;
  final String altModel;
  final String altProviderName;

  /// Falls back to the ANTHROPIC_API_KEY environment variable.
  String get effectiveApiKey => apiKey.isNotEmpty ? apiKey : (Platform.environment['ANTHROPIC_API_KEY'] ?? '');

  /// True when the AI features have everything they need to run.
  bool get aiConfigured =>
      provider == AiProvider.claude ? effectiveApiKey.isNotEmpty : altBaseUrl.isNotEmpty && altModel.isNotEmpty;

  AppSettings copyWith({
    String? vaultPath,
    bool clearVault = false,
    String? apiKey,
    ThemeMode? themeMode,
    AiProvider? provider,
    String? altApiKey,
    String? altBaseUrl,
    String? altModel,
    String? altProviderName,
  }) => AppSettings(
    vaultPath: clearVault ? null : (vaultPath ?? this.vaultPath),
    apiKey: apiKey ?? this.apiKey,
    themeMode: themeMode ?? this.themeMode,
    provider: provider ?? this.provider,
    altApiKey: altApiKey ?? this.altApiKey,
    altBaseUrl: altBaseUrl ?? this.altBaseUrl,
    altModel: altModel ?? this.altModel,
    altProviderName: altProviderName ?? this.altProviderName,
  );
}

class SettingsNotifier extends Notifier<AppSettings> {
  SharedPreferences get _prefs => ref.read(prefsProvider);

  @override
  AppSettings build() => AppSettings(
    vaultPath: _prefs.getString('vaultPath'),
    apiKey: _prefs.getString('apiKey') ?? '',
    themeMode: ThemeMode.values.byName(_prefs.getString('themeMode') ?? 'system'),
    provider: AiProvider.values.byName(_prefs.getString('ai.provider') ?? 'claude'),
    altApiKey: _prefs.getString('ai.altApiKey') ?? '',
    altBaseUrl: _prefs.getString('ai.altBaseUrl') ?? '',
    altModel: _prefs.getString('ai.altModel') ?? '',
    altProviderName: _prefs.getString('ai.altProviderName') ?? '',
  );

  Future<void> setVaultPath(String? path) async {
    path == null ? await _prefs.remove('vaultPath') : await _prefs.setString('vaultPath', path);
    state = state.copyWith(vaultPath: path, clearVault: path == null);
  }

  Future<void> setApiKey(String key) async {
    await _prefs.setString('apiKey', key.trim());
    state = state.copyWith(apiKey: key.trim());
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    await _prefs.setString('themeMode', mode.name);
    state = state.copyWith(themeMode: mode);
  }

  Future<void> setProvider(AiProvider provider) async {
    await _prefs.setString('ai.provider', provider.name);
    state = state.copyWith(provider: provider);
  }

  /// Saves the OpenAI-compatible provider; empty arguments keep the old value.
  Future<void> setAltProvider({String? name, String? baseUrl, String? model, String? apiKey}) async {
    if (name != null) await _prefs.setString('ai.altProviderName', name);
    if (baseUrl != null) await _prefs.setString('ai.altBaseUrl', baseUrl.trim());
    if (model != null) await _prefs.setString('ai.altModel', model.trim());
    if (apiKey != null) await _prefs.setString('ai.altApiKey', apiKey.trim());
    state = state.copyWith(
      altProviderName: name,
      altBaseUrl: baseUrl?.trim(),
      altModel: model?.trim(),
      altApiKey: apiKey?.trim(),
    );
  }
}

final settingsProvider = NotifierProvider<SettingsNotifier, AppSettings>(SettingsNotifier.new);

final repoProvider = Provider<VaultRepository?>((ref) {
  final path = ref.watch(settingsProvider.select((s) => s.vaultPath));
  return path == null ? null : VaultRepository(path);
});

/// The vault index. Reloads incrementally when files change on disk
/// (e.g. the user edits the same vault in Obsidian at the same time).
class VaultNotifier extends AsyncNotifier<VaultIndex?> {
  VaultRepository? get _repo => ref.read(repoProvider);

  @override
  Future<VaultIndex?> build() async {
    final repo = ref.watch(repoProvider);
    if (repo == null) return null;
    final sub = repo.watch().listen(_onFsEvent, onError: (_) {});
    ref.onDispose(sub.cancel);
    return repo.loadIndex();
  }

  Future<void> _onFsEvent(WatchEvent e) async {
    final repo = _repo;
    final index = state.value;
    if (repo == null || index == null) return;
    final rel = repo.rel(e.path);
    if (VaultRepository.isAttachmentPath(rel)) {
      final known = index.attachments.containsKey(rel.toLowerCase());
      if (e.type == ChangeType.REMOVE && known) {
        state = AsyncData(index.withAttachments(index.attachments.values.where((a) => a != rel)));
      } else if (e.type != ChangeType.REMOVE && !known) {
        state = AsyncData(index.withAttachments([...index.attachments.values, rel]));
      }
      return;
    }
    if (!VaultRepository.isNotePath(rel)) return;
    if (e.type == ChangeType.REMOVE) {
      // Atomic saves briefly move the old file aside before replacing it. Only
      // remove the note from the index when the final path is truly gone.
      if (!await File(repo.abs(rel)).exists()) {
        if (index.notes.containsKey(rel)) state = AsyncData(index.without(rel));
        return;
      }
    }
    final note = await repo.readNote(rel);
    final current = state.value;
    if (note == null || current == null) return;
    if (current.notes[rel]?.content == note.content) return; // our own write
    state = AsyncData(current.withNote(note));
  }

  Future<void> reload() async {
    ref.invalidateSelf();
    await future;
  }

  Future<Note> save(String path, String content, {String? expectedContent}) async {
    final note = await _repo!.writeNote(path, content, expectedContent: expectedContent);
    final index = state.value;
    if (index != null) state = AsyncData(index.withNote(note));
    return note;
  }

  Future<Note> create(String folder, String title, {String content = ''}) async {
    final note = await _repo!.createNote(folder, title, content: content);
    final index = state.value;
    if (index != null) state = AsyncData(index.withNote(note));
    return note;
  }

  Future<void> trash(String path) async {
    await _repo!.trashNote(path);
    final index = state.value;
    if (index != null) state = AsyncData(index.without(path));
    ref.invalidate(trashProvider);
  }

  Future<Note> restoreTrash(TrashedNote entry) async {
    final note = await _repo!.restoreTrash(entry);
    final index = state.value;
    if (index != null) state = AsyncData(index.withNote(note));
    ref.invalidate(trashProvider);
    return note;
  }

  /// Renames a note in place and rewrites every `[[link]]` pointing to it.
  /// Returns the new path and how many notes had links updated.
  Future<({String path, int linkedNotes})> rename(String oldPath, String newTitle) async {
    final index = state.value!;
    final title = newTitle.trim();
    if (title.isEmpty || invalidNameChars.hasMatch(title)) {
      throw const FormatException('Tên không hợp lệ (không dùng các ký tự \\ / : * ? " < > | # ^ [ ])');
    }
    final plan = planRename(index, oldPath, title);
    if (plan.newPath == oldPath) return (path: oldPath, linkedNotes: 0);
    final repo = _repo!;
    await repo.renameFile(oldPath, plan.newPath);

    final moved = index.notes[oldPath]!;
    final notes = {
      for (final n in index.notes.values)
        if (n.path != oldPath) n.path: n,
      plan.newPath: Note.parse(plan.newPath, moved.content, DateTime.now()),
    };
    for (final e in plan.updates.entries) {
      notes[e.key] = await repo.writeNote(e.key, e.value);
    }
    state = AsyncData(VaultIndex(index.root, notes.values, attachments: index.attachments.values));
    await ref.read(srsProvider.notifier).moveNote(oldPath, plan.newPath);
    return (path: plan.newPath, linkedNotes: plan.linkedNotes);
  }

  /// Copies an image into the vault and returns the path to embed.
  Future<String> importAttachment(String sourcePath) async {
    final rel = await _repo!.importAttachment(sourcePath);
    final index = state.value;
    if (index != null) {
      state = AsyncData(index.withAttachments([...index.attachments.values, rel]));
    }
    return rel;
  }

  Future<void> appendToNote(String path, String text, {String? underHeading}) async {
    final note = state.value?.notes[path];
    if (note == null) return;
    var content = note.content.trimRight();
    if (underHeading != null &&
        !RegExp('^## ${RegExp.escape(underHeading)}\\s*\$', multiLine: true).hasMatch(content)) {
      content += '\n\n## $underHeading';
    }
    await save(path, '$content\n$text\n');
  }
}

final vaultProvider = AsyncNotifierProvider<VaultNotifier, VaultIndex?>(VaultNotifier.new);

final trashProvider = FutureProvider<List<TrashedNote>>((ref) async {
  final repo = ref.watch(repoProvider);
  return repo == null ? const [] : repo.listTrash();
});

/// Simple settable value.
class ValueCell<T> extends Notifier<T> {
  ValueCell(this._initial);
  final T _initial;
  @override
  T build() => _initial;
  void set(T value) => state = value;
}

enum AppPage { dashboard, courses, notes, search, graph, review, ask, settings }

final pageProvider = NotifierProvider<ValueCell<AppPage>, AppPage>(() => ValueCell(AppPage.dashboard));

/// Widths and visibility of the side columns on the notes page, remembered
/// between sessions.
class NotesLayout {
  const NotesLayout({this.treeWidth = 260, this.sideWidth = 360, this.showTree = true, this.showSide = true});

  static const minTreeWidth = 180.0;
  static const maxTreeWidth = 460.0;
  static const minSideWidth = 260.0;
  static const maxSideWidth = 560.0;

  final double treeWidth;
  final double sideWidth;
  final bool showTree;
  final bool showSide;

  NotesLayout copyWith({double? treeWidth, double? sideWidth, bool? showTree, bool? showSide}) => NotesLayout(
    treeWidth: (treeWidth ?? this.treeWidth).clamp(minTreeWidth, maxTreeWidth),
    sideWidth: (sideWidth ?? this.sideWidth).clamp(minSideWidth, maxSideWidth),
    showTree: showTree ?? this.showTree,
    showSide: showSide ?? this.showSide,
  );
}

class NotesLayoutNotifier extends Notifier<NotesLayout> {
  SharedPreferences get _prefs => ref.read(prefsProvider);

  @override
  NotesLayout build() => const NotesLayout().copyWith(
    treeWidth: _prefs.getDouble('notes.treeWidth'),
    sideWidth: _prefs.getDouble('notes.sideWidth'),
    showTree: _prefs.getBool('notes.showTree'),
    showSide: _prefs.getBool('notes.showSide'),
  );

  void toggleTree() {
    state = state.copyWith(showTree: !state.showTree);
    save();
  }

  void toggleSide() {
    state = state.copyWith(showSide: !state.showSide);
    save();
  }

  /// Called while dragging a divider; [save] persists once the drag ends.
  void resize({double? treeWidth, double? sideWidth}) =>
      state = state.copyWith(treeWidth: treeWidth, sideWidth: sideWidth);

  Future<void> save() async {
    await _prefs.setDouble('notes.treeWidth', state.treeWidth);
    await _prefs.setDouble('notes.sideWidth', state.sideWidth);
    await _prefs.setBool('notes.showTree', state.showTree);
    await _prefs.setBool('notes.showSide', state.showSide);
  }
}

final notesLayoutProvider = NotifierProvider<NotesLayoutNotifier, NotesLayout>(NotesLayoutNotifier.new);

final selectedNoteProvider = NotifierProvider<ValueCell<String?>, String?>(() => ValueCell(null));
final searchQueryProvider = NotifierProvider<ValueCell<String>, String>(() => ValueCell(''));

void openNote(WidgetRef ref, String path) {
  ref.read(selectedNoteProvider.notifier).set(path);
  ref.read(pageProvider.notifier).set(AppPage.notes);
}

void openSearch(WidgetRef ref, String query) {
  ref.read(searchQueryProvider.notifier).set(query);
  ref.read(pageProvider.notifier).set(AppPage.search);
}

final flashcardsProvider = Provider<List<Flashcard>>((ref) {
  final index = ref.watch(vaultProvider).value;
  return index == null ? const [] : allFlashcards(index);
});

/// Review state for every card, persisted to `.fptu/srs.json` in the vault.
class SrsNotifier extends AsyncNotifier<Map<String, CardState>> {
  @override
  Future<Map<String, CardState>> build() async {
    final repo = ref.watch(repoProvider);
    return repo == null ? {} : repo.loadSrs();
  }

  Future<void> grade(Flashcard card, Grade g) async {
    final states = {...?state.value};
    final before = states[card.id] ?? const CardState();
    final now = DateTime.now();
    states[card.id] = schedule(before, g, now);
    state = AsyncData(states);
    await ref.read(repoProvider)?.saveSrs(states);
    await ref.read(reviewLogProvider.notifier).add(ReviewEntry(now, card.id, g, before.interval));
  }

  /// Card ids contain the note path; keep review history when a note is renamed.
  Future<void> moveNote(String oldPath, String newPath) async {
    final states = await future;
    final prefix = '$oldPath|';
    if (!states.keys.any((k) => k.startsWith(prefix))) return;
    final moved = {
      for (final e in states.entries)
        (e.key.startsWith(prefix) ? '$newPath|${e.key.substring(prefix.length)}' : e.key): e.value,
    };
    state = AsyncData(moved);
    await ref.read(repoProvider)?.saveSrs(moved);
  }
}

final srsProvider = AsyncNotifierProvider<SrsNotifier, Map<String, CardState>>(SrsNotifier.new);

/// Every graded review, persisted to `.fptu/review_log.json` for statistics.
class ReviewLogNotifier extends AsyncNotifier<List<ReviewEntry>> {
  @override
  Future<List<ReviewEntry>> build() async {
    final repo = ref.watch(repoProvider);
    return repo == null ? [] : repo.loadReviewLog();
  }

  Future<void> add(ReviewEntry e) async {
    final log = [...await future, e];
    state = AsyncData(log);
    await ref.read(repoProvider)?.saveReviewLog(log);
  }
}

final reviewLogProvider = AsyncNotifierProvider<ReviewLogNotifier, List<ReviewEntry>>(ReviewLogNotifier.new);

final reviewStatsProvider = Provider<ReviewStats>(
  (ref) => ReviewStats.compute(
    ref.watch(flashcardsProvider),
    ref.watch(srsProvider).value ?? const {},
    ref.watch(reviewLogProvider).value ?? const [],
  ),
);

final dueCardsProvider = Provider<List<Flashcard>>((ref) {
  final cards = ref.watch(flashcardsProvider);
  final states = ref.watch(srsProvider).value ?? const {};
  final now = DateTime.now();
  return cards.where((c) => (states[c.id] ?? const CardState()).isDue(now)).toList();
});

/// Builds the client for the configured provider, or null when it isn't set up.
AiClient? buildAiClient(AppSettings s) {
  if (!s.aiConfigured) return null;
  return s.provider == AiProvider.claude
      ? ClaudeClient(s.effectiveApiKey)
      : OpenAiCompatibleClient(
          apiKey: s.altApiKey,
          baseUrl: s.altBaseUrl,
          model: s.altModel,
          providerName: s.altProviderName.isEmpty ? 'Model' : s.altProviderName,
        );
}

final aiProvider = Provider<AiAssistant?>((ref) {
  final settings = ref.watch(settingsProvider);
  final client = buildAiClient(settings);
  if (client == null) return null;
  ref.onDispose(client.close);
  return AiAssistant(client);
});
