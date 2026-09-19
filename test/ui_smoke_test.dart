import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fptu_brain/core/sample_vault.dart';
import 'package:fptu_brain/main.dart';
import 'package:fptu_brain/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  for (final size in const [Size(1600, 1000), Size(1100, 700)]) {
    testWidgets('every page renders on the sample vault at $size', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final dir = await tester.runAsync(() async {
        final d = await Directory.systemTemp.createTemp('fptu_ui');
        await SampleVault.create(d.path);
        return d;
      });
      SharedPreferences.setMockInitialValues({'vaultPath': dir!.path});
      final prefs = await tester.runAsync(SharedPreferences.getInstance);

      final container = ProviderContainer(overrides: [prefsProvider.overrideWithValue(prefs!)]);
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

      await tester.runAsync(() async {
        try {
          await dir.delete(recursive: true);
        } on FileSystemException {
          // The directory watcher may still hold a handle on Windows; temp dir is cleaned by the OS.
        }
      });
    }, timeout: const Timeout(Duration(seconds: 60)));
  }
}
