import 'package:xlib/update.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('isNewerVersion 正确比较三段式版本号', () {
    expect(isNewerVersion('0.1.3', '0.1.2'), isTrue);
    expect(isNewerVersion('0.2.0', '0.1.9'), isTrue);
    expect(isNewerVersion('1.0.0', '0.10.0'), isTrue);
    expect(isNewerVersion('0.1.2', '0.1.3'), isFalse);
    expect(isNewerVersion('0.1.2', '0.1.2'), isFalse);
    expect(isNewerVersion('0.10.0', '1.0.0'), isFalse);
    expect(isNewerVersion('abc', '0.1.2'), isFalse);
  });

  test('AppRelease.fromJson 解析版本号与 GitHub 锚点链接', () {
    final release = AppRelease.fromJson({
      'tag_name': 'v0.1.2',
      'name': 'xlib Android 0.1.2 稳定版',
      'body': '# 标题\n- 改动一\n- 改动二',
      'created_at': '2026-11-11T06:56:57+08:00',
      'published_at': '2026-11-21T12:00:00Z',
      'assets': [{'name': 'xlib-android-v0.1.2-arm64-v8a.apk', 'browser_download_url': 'https://github.com/KingPenguinMan/xlib-android/releases/download/v0.1.2/xlib-android-v0.1.2-arm64-v8a.apk'}],
    });
    expect(release.version, '0.1.2');
    expect(release.tag, 'v0.1.2');
    expect(release.publishedAt, '2026-11-21T12:00:00Z');
    expect(release.abiFor(['armeabi-v7a', 'arm64-v8a']), 'arm64-v8a');
    expect(release.apkFor(['arm64-v8a']), contains('/releases/download/v0.1.2/'));
    expect(release.apkFor(['x86_64']), isNull);
    expect(
      release.releaseUrl,
      'https://github.com/KingPenguinMan/xlib-android/releases/tag/v0.1.2',
    );
  });

  test('markdownToPlain 去掉标题、链接、强调并保留列表符号', () {
    final text = markdownToPlain(
      '# 版本标题\n- [链接](https://x) 与 x86_64\n- **加粗**文本',
    );
    expect(text, '• 链接 与 x86_64\n• 加粗文本');
  });
}
