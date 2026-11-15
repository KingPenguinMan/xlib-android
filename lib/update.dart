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

  const AppRelease({
    required this.version,
    required this.tag,
    required this.name,
    required this.body,
    required this.publishedAt,
    required this.prerelease,
    required this.draft,
  });

  factory AppRelease.fromJson(Map<String, dynamic> json) {
    final tag = '${json['tag_name'] ?? ''}';
    return AppRelease(
      version: tag.replaceFirst(RegExp('^v'), ''),
      tag: tag,
      name: '${json['name'] ?? ''}',
      body: '${json['body'] ?? ''}',
      publishedAt: '${json['created_at'] ?? ''}',
      prerelease: json['prerelease'] == true,
      draft: json['draft'] == true,
    );
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
    req.headers.set(HttpHeaders.userAgentHeader, 'z-lib-android');
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
