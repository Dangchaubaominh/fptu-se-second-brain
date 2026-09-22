import 'dart:convert';

import 'package:http/http.dart' as http;

/// Where releases are published (see .github/workflows/release.yml).
const githubRepo = 'Dangchaubaominh/fptu-se-second-brain';

class ReleaseInfo {
  const ReleaseInfo({required this.version, required this.notes, required this.pageUrl, this.downloadUrl});

  /// e.g. `1.1.0` (without the leading `v`).
  final String version;
  final String notes;
  final String pageUrl;

  /// Direct link to the Windows zip, when the release has one.
  final String? downloadUrl;
}

/// Parses `v1.2.3`, `1.2`, `1.2.3+4` into comparable parts; null if not a version.
List<int>? parseVersion(String v) {
  final m = RegExp(r'^v?(\d+)(?:\.(\d+))?(?:\.(\d+))?').firstMatch(v.trim());
  if (m == null) return null;
  return [for (var i = 1; i <= 3; i++) int.parse(m.group(i) ?? '0')];
}

bool isNewerVersion(String candidate, String current) {
  final a = parseVersion(candidate);
  final b = parseVersion(current);
  if (a == null || b == null) return false;
  for (var i = 0; i < 3; i++) {
    if (a[i] != b[i]) return a[i] > b[i];
  }
  return false;
}

/// Asks GitHub for the latest published release. Returns null when there is
/// none or it can't be read (offline, rate-limited, or the repo is private).
Future<ReleaseInfo?> fetchLatestRelease({http.Client? client}) async {
  final c = client ?? http.Client();
  try {
    final res = await c
        .get(
          Uri.parse('https://api.github.com/repos/$githubRepo/releases/latest'),
          headers: {'Accept': 'application/vnd.github+json', 'User-Agent': 'fptu-brain'},
        )
        .timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) return null;
    final j = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    final tag = j['tag_name'] as String?;
    if (tag == null || parseVersion(tag) == null) return null;
    final assets = (j['assets'] as List? ?? const []).cast<Map<String, dynamic>>();
    final zip = assets.where((a) => (a['name'] as String? ?? '').toLowerCase().endsWith('.zip')).firstOrNull;
    return ReleaseInfo(
      version: tag.replaceFirst(RegExp('^v'), ''),
      notes: (j['body'] as String? ?? '').trim(),
      pageUrl: j['html_url'] as String? ?? 'https://github.com/$githubRepo/releases',
      downloadUrl: zip?['browser_download_url'] as String?,
    );
  } catch (_) {
    return null;
  } finally {
    if (client == null) c.close();
  }
}
