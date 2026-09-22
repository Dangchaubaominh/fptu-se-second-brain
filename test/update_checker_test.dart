import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:fptu_brain/core/update_checker.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('compares versions numerically', () {
    expect(isNewerVersion('v1.1.0', '1.0.0'), isTrue);
    expect(isNewerVersion('1.10.0', '1.9.3'), isTrue);
    expect(isNewerVersion('2.0', '1.9.9'), isTrue);
    expect(isNewerVersion('v1.0.0', '1.0.0'), isFalse);
    expect(isNewerVersion('1.0.0+5', '1.0.0'), isFalse);
    expect(isNewerVersion('0.9.0', '1.0.0'), isFalse);
    expect(isNewerVersion('latest', '1.0.0'), isFalse);
  });

  test('reads the latest release and picks the zip asset', () async {
    final client = MockClient((req) async {
      expect(req.url.path, '/repos/$githubRepo/releases/latest');
      return http.Response.bytes(
        utf8.encode(
          jsonEncode({
            'tag_name': 'v1.1.0',
            'body': '- Gợi ý khi gõ [[',
            'html_url': 'https://github.com/$githubRepo/releases/tag/v1.1.0',
            'assets': [
              {'name': 'notes.txt', 'browser_download_url': 'https://x/notes.txt'},
              {'name': 'fptu-brain-windows-v1.1.0.zip', 'browser_download_url': 'https://x/app.zip'},
            ],
          }),
        ),
        200,
      );
    });
    final r = (await fetchLatestRelease(client: client))!;
    expect(r.version, '1.1.0');
    expect(r.notes, '- Gợi ý khi gõ [[');
    expect(r.downloadUrl, 'https://x/app.zip');
  });

  test('returns null when GitHub has no readable release (e.g. private repo)', () async {
    final client = MockClient((_) async => http.Response('{"message":"Not Found"}', 404));
    expect(await fetchLatestRelease(client: client), isNull);
    final broken = MockClient((_) async => throw http.ClientException('offline'));
    expect(await fetchLatestRelease(client: broken), isNull);
  });
}
