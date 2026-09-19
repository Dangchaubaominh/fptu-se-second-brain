import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:watcher/watcher.dart';

import '../core/ai_assistant.dart';
import '../core/claude_client.dart';
import '../core/flashcards.dart';
import '../core/vault_index.dart';
import '../core/vault_repository.dart';

final prefsProvider = Provider<SharedPreferences>((ref) => throw UnimplementedError('override in main'));

class AppSettings {
  const AppSettings({this.vaultPath, this.apiKey = '', this.themeMode = ThemeMode.system});
  final String? vaultPath;
  final String apiKey;
  final ThemeMode themeMode;

  /// Falls back to the ANTHROPIC_API_KEY environment variable.
  String get effectiveApiKey => apiKey.isNotEmpty ? apiKey : (Platform.environment['ANTHROPIC_API_KEY'] ?? '');
}

class SettingsNotifier extends Notifier<AppSettings> {
  SharedPreferences get _prefs => ref.read(prefsProvider);

  @override
  AppSettings build() => AppSettings(
        vaultPath: _prefs.getString('vaultPath'),
        apiKey: _prefs.getString('apiKey') ?? '',
        themeMode: ThemeMode.values.byName(_prefs.getString('themeMode') ?? 'system'),
      );

  Future<void> setVaultPath(String? path) async {
    path == null ? await _prefs.remove('vaultPath') : await _prefs.setString('vaultPath', path);
    state = AppSettings(vaultPath: path, apiKey: state.apiKey, themeMode: state.themeMode);
  }

  Future<void> setApiKey(String key) async {
    await _prefs.setString('apiKey', key.trim());
    state = AppSettings(vaultPath: state.vaultPath, apiKey: key.trim(), themeMode: state.themeMode);
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    await _prefs.setString('themeMode', mode.name);
    state = AppSettings(vaultPath: state.vaultPath, apiKey: state.apiKey, themeMode: mode);
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
    return VaultIndex(repo.root, await repo.loadAll());
  }

  Future<void> _onFsEvent(WatchEvent e) async {
    final repo = _repo;
    final index = state.value;
    if (repo == null || index == null) return;
    final rel = repo.rel(e.path);
    if (!VaultRepository.isNotePath(rel)) return;
    if (e.type == ChangeType.REMOVE) {
      if (index.notes.containsKey(rel)) state = AsyncData(index.without(rel));
      return;
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

  Future<Note> save(String path, String content) async {
    final note = await _repo!.writeNote(path, content);
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
  }

  Future<void> appendToNote(String path, String text, {String? underHeading}) async {
    final note = state.value?.notes[path];
    if (note == null) return;
    var content = note.content.trimRight();
    if (underHeading != null && !RegExp('^## ${RegExp.escape(underHeading)}\\s*\$', multiLine: true).hasMatch(content)) {
      content += '\n\n## $underHeading';
    }
    await save(path, '$content\n$text\n');
  }
}

final vaultProvider = AsyncNotifierProvider<VaultNotifier, VaultIndex?>(VaultNotifier.new);

/// Simple settable value.
class ValueCell<T> extends Notifier<T> {
  ValueCell(this._initial);
  final T _initial;
  @override
  T build() => _initial;
  void set(T value) => state = value;
}

enum AppPage { dashboard, courses, notes, search, graph, review, settings }

final pageProvider = NotifierProvider<ValueCell<AppPage>, AppPage>(() => ValueCell(AppPage.dashboard));
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
    states[card.id] = schedule(states[card.id] ?? const CardState(), g, DateTime.now());
    state = AsyncData(states);
    await ref.read(repoProvider)?.saveSrs(states);
  }
}

final srsProvider = AsyncNotifierProvider<SrsNotifier, Map<String, CardState>>(SrsNotifier.new);

final dueCardsProvider = Provider<List<Flashcard>>((ref) {
  final cards = ref.watch(flashcardsProvider);
  final states = ref.watch(srsProvider).value ?? const {};
  final now = DateTime.now();
  return cards.where((c) => (states[c.id] ?? const CardState()).isDue(now)).toList();
});

final aiProvider = Provider<AiAssistant?>((ref) {
  final key = ref.watch(settingsProvider.select((s) => s.effectiveApiKey));
  if (key.isEmpty) return null;
  final client = ClaudeClient(key);
  ref.onDispose(client.close);
  return AiAssistant(client);
});
