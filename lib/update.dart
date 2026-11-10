import 'dart:convert';
import 'dart:io';

const updateBase = 'https://128374.xyz/zlib-updates';

typedef AppUpdate = ({String version, String url});

AppUpdate? selectUpdate(Map release, String installed, List<String> abis) {
  final pattern = RegExp(r'^v?(\d+)\.(\d+)\.(\d+)$');
  final current = pattern.firstMatch(installed);
  final tag = release['tag_name'];
  if (release['draft'] == true ||
      release['prerelease'] == true ||
      tag is! String)
    return null;
  final next = pattern.firstMatch(tag);
  if (current == null || next == null) return null;
  for (var i = 1; i <= 3; i++) {
    final comparison = int.parse(next[i]!).compareTo(int.parse(current[i]!));
    if (comparison < 0 || (comparison == 0 && i == 3)) return null;
    if (comparison > 0) break;
  }
  final version = tag.replaceFirst(RegExp('^v'), '');
  for (final abi in abis) {
    final name = 'z-lib-android-v$version-$abi.apk';
    for (final asset in (release['assets'] as List? ?? []).whereType<Map>()) {
      final url = asset['browser_download_url'];
      if (asset['name'] == name &&
          url is String &&
          url == '$updateBase/$name') {
        return (version: version, url: url);
      }
    }
  }
  return null;
}

Future<AppUpdate?> checkForUpdate(String installed, List<String> abis) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 4);
  Future<AppUpdate?> fetch() async {
    final req = await client.getUrl(Uri.parse('$updateBase/latest.json'));
    req.followRedirects = false;
    req.headers.set(HttpHeaders.userAgentHeader, 'z-lib-android/$installed');
    final response = await req.close();
    if (response.statusCode != 200) return null;
    final release = jsonDecode(await utf8.decoder.bind(response).join());
    return release is Map ? selectUpdate(release, installed, abis) : null;
  }

  try {
    return await fetch().timeout(const Duration(seconds: 7));
  } catch (_) {
    return null;
  } finally {
    client.close(force: true);
  }
}
