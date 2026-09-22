import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fptu_brain/core/sample_vault.dart';
import 'package:fptu_brain/main.dart';
import 'package:fptu_brain/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Builds the full app on a freshly generated sample vault.
Future<ProviderContainer> pumpApp(WidgetTester tester, {Size size = const Size(1600, 1000)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final dir = await tester.runAsync(() async {
    final d = await Directory.systemTemp.createTemp('fptu_ui');
    await SampleVault.create(d.path);
    return d;
  });
  addTearDown(() async {
    await tester.runAsync(() async {
      try {
        await dir!.delete(recursive: true);
      } on FileSystemException {
        // The directory watcher may still hold a handle on Windows; temp dir is cleaned by the OS.
      }
    });
  });
  SharedPreferences.setMockInitialValues({'vaultPath': dir!.path});
  final prefs = await tester.runAsync(SharedPreferences.getInstance);

  final container = ProviderContainer(
    overrides: [
      prefsProvider.overrideWithValue(prefs!),
      autoUpdateCheckProvider.overrideWithValue(false),
      appVersionProvider.overrideWith((_) async => '1.0.0'),
    ],
  );
  addTearDown(container.dispose);
  // Load real file I/O outside the fake-async zone before building widgets.
  await tester.runAsync(() async {
    final sub = container.listen(vaultProvider, (_, _) {});
    final srsSub = container.listen(srsProvider, (_, _) {});
    addTearDown(sub.close);
    addTearDown(srsSub.close);
    await container.read(vaultProvider.future);
    await container.read(srsProvider.future);
  });
  await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const FptuBrainApp()));
  await tester.pump();
  return container;
}

/// The quick switcher's search box (not the note editor behind it).
final switcherField = find.byWidgetPredicate(
  (w) => w is TextField && (w.decoration?.hintText ?? '').startsWith('Tìm hoặc tạo note'),
);

Future<void> pressCtrl(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(key);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pump();
}

void main() {
  for (final size in const [Size(1600, 1000), Size(1100, 700)]) {
    testWidgets('every page renders on the sample vault at $size', (tester) async {
      final container = await pumpApp(tester, size: size);
      expect(find.text('Xin chào 👋'), findsOneWidget);

      for (final page in AppPage.values) {
        container.read(pageProvider.notifier).set(page);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(tester.takeException(), isNull, reason: 'page $page');
      }

      // Open a note with links, flashcards and a code block.
      final index = container.read(vaultProvider).value!;
      final path = index.resolve('Đệ quy (Recursion)')!;
      container.read(selectedNoteProvider.notifier).set(path);
      container.read(pageProvider.notifier).set(AppPage.notes);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
      expect(find.text('Backlinks (3)'), findsOneWidget);
    }, timeout: const Timeout(Duration(seconds: 60)));
  }

  testWidgets('Ctrl+O quick switcher finds a note without accents and opens it', (tester) async {
    final container = await pumpApp(tester);

    await pressCtrl(tester, LogicalKeyboardKey.keyO);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('Note sửa gần đây'), findsOneWidget);

    await tester.enterText(switcherField, 'de quy');
    await tester.pump();
    expect(find.text('Đệ quy (Recursion)'), findsOneWidget);
    expect(find.text('Tạo note mới "de quy"'), findsOneWidget); // name isn't an exact match

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(container.read(selectedNoteProvider), 'Concepts/Đệ quy (Recursion).md');
    expect(container.read(pageProvider), AppPage.notes);
    expect(find.textContaining('Note sửa gần đây'), findsNothing);

    // Esc closes without changing the open note.
    await pressCtrl(tester, LogicalKeyboardKey.keyO);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.enterText(switcherField, 'prf');
    await tester.pump();
    expect(find.text('PRF192'), findsWidgets);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump(); // starts the close animation
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('Enter mở'), findsNothing);
    expect(container.read(selectedNoteProvider), 'Concepts/Đệ quy (Recursion).md');
  }, timeout: const Timeout(Duration(seconds: 60)));
}
