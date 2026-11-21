import 'dart:convert';
import 'dart:io';

/// Gitee 仓库信息（仓库已公开，可匿名访问）。
const giteeRepo = 'Gjbone/zlib-android';
const giteeReleasesUrl = 'https://gitee.com/api/v5/repos/$giteeRepo/releases';
const giteeReleasesPage = 'https://gitee.com/$giteeRepo/releases';

/// 蓝奏云网盘下载入口（固定地址 + 密码）。
const netdiskUrl = 'https://wward.lanzouw.com/b01i60kfsf';
const netdiskPassword = 'zlib';

/// 一个应用版本，对应 Gitee 上的一个 release（发行版）。
class AppRelease {
  final String version; // 去掉 v 前缀，如 0.1.2
  final String tag; // 原始 tag，如 v0.1.2
  final String name; // 发行版标题
  final String body; // 更新说明（Markdown）
  final String publishedAt; // 发布时间，ISO 8601
  final bool prerelease;
  final bool draft;
  final Map<String, String> apks; // 架构 -> 附件下载链接

  const AppRelease({
    required this.version,
    required this.tag,
    required this.name,
    required this.body,
    required this.publishedAt,
    required this.prerelease,
    required this.draft,
    required this.apks,
  });

  factory AppRelease.fromJson(Map<String, dynamic> json) {
    final tag = '${json['tag_name'] ?? ''}';
    // 从发行版附件里找各架构的 APK（文件名形如 xxx-arm64-v8a.apk）。
    final apks = <String, String>{};
    for (final asset in (json['assets'] as List? ?? []).whereType<Map>()) {
      final name = '${asset['name'] ?? ''}';
      final url = '${asset['browser_download_url'] ?? ''}';
      final match = RegExp(r'-(arm64-v8a|armeabi-v7a|x86_64)\.apk$')
          .firstMatch(name);
      if (match != null && url.isNotEmpty) apks[match.group(1)!] = url;
    }
    return AppRelease(
      version: tag.replaceFirst(RegExp('^v'), ''),
      tag: tag,
      name: '${json['name'] ?? ''}',
      body: '${json['body'] ?? ''}',
      publishedAt: '${json['created_at'] ?? ''}',
      prerelease: json['prerelease'] == true,
      draft: json['draft'] == true,
      apks: apks,
    );
  }

  /// 在给定架构列表里挑一个可用的 APK 下载链接（按优先级）。
  String? apkFor(List<String> abis) {
    for (final abi in abis) {
      final url = apks[abi];
      if (url != null && url.isNotEmpty) return url;
    }
    return null;
  }

  /// 与 [apkFor] 对应的架构名，用于界面提示「适配 arm64-v8a」。
  String? abiFor(List<String> abis) {
    for (final abi in abis) {
      if (apks.containsKey(abi)) return abi;
    }
    return null;
  }

  /// Gitee releases 页面上精准跳到这个版本的锚点链接。
  /// 每次发新版 tag 会变，链接也会跟着变（#release-v{tag}）。
  String get giteeUrl => '$giteeReleasesPage#release-$tag';
}

/// 三段式版本号比较：candidate 是否严格比 installed 新。
bool isNewerVersion(String candidate, String installed) {
  final pattern = RegExp(r'^(\d+)\.(\d+)\.(\d+)$');
  final a = pattern.firstMatch(candidate);
  final b = pattern.firstMatch(installed);
  if (a == null || b == null) return false;
  for (var i = 1; i <= 3; i++) {
    final diff = int.parse(a[i]!).compareTo(int.parse(b[i]!));
    if (diff != 0) return diff > 0;
  }
  return false;
}

/// 拉取 Gitee 上全部 release，最新在前。
Future<List<AppRelease>> fetchReleases() async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 6);
  try {
    final req = await client.getUrl(
      Uri.parse('$giteeReleasesUrl?per_page=100&direction=desc'),
    );
    req.headers.set(HttpHeaders.userAgentHeader, 'xlib-android');
    final response = await req.close();
    if (response.statusCode != 200) return const [];
    final decoded = jsonDecode(await utf8.decoder.bind(response).join());
    if (decoded is! List) return const [];
    return decoded
        .whereType<Map>()
        .map((e) => AppRelease.fromJson(Map<String, dynamic>.from(e)))
        .where((r) => r.tag.isNotEmpty)
        .toList();
  } catch (_) {
    return const [];
  } finally {
    client.close(force: true);
  }
}

/// 把 Markdown 更新说明转成可读的纯文本（去掉链接、强调、标题、列表符号）。
/// 取更新说明里「## 下载」之前的内容，避免在弹窗/卡片里显示 APK 文件名。
String releaseNotes(String body) {
  final idx = body.indexOf('## 下载');
  return markdownToPlain(idx >= 0 ? body.substring(0, idx) : body);
}

String markdownToPlain(String markdown) {
  final out = <String>[];
  final lines = markdown.split('\n');
  for (var i = 0; i < lines.length; i++) {
    var text = lines[i].trimRight();
    // 首行通常是「# 版本标题」，与卡片标题重复，跳过。
    if (i == 0 && RegExp(r'^#{1,6}\s').hasMatch(text)) continue;
    // [text](url) -> text（Dart 的 replaceAll 不支持 $1 捕获组，用 Mapped）。
    text = text.replaceAllMapped(
      RegExp(r'\[([^\]]*)\]\([^)]*\)'),
      (m) => m.group(1) ?? '',
    );
    // 去掉加粗/行内代码标记，保留下划线（x86_64 这类名字里有下划线）。
    text = text.replaceAll(RegExp(r'[*`]'), '');
    text = text.replaceAll(RegExp(r'^#{1,6}\s*'), '');
    if (text.startsWith('- ')) text = '• ${text.substring(2)}';
    out.add(text);
  }
  return out.join('\n').trim();
}
