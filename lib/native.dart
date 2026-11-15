import 'dart:convert';

import 'package:flutter/services.dart';

import 'domain.dart';

class NativeBridge {
  static const channel = MethodChannel('dev.bookisle/native');
  Future<Map<String, dynamic>> loadSettings() async =>
      Map<String, dynamic>.from(
        jsonDecode(await channel.invokeMethod<String>('loadSettings') ?? '{}')
            as Map,
      );
  Future<void> saveSettings(Map<String, dynamic> data) =>
      channel.invokeMethod('saveSettings', jsonEncode(data));
  Future<Session?> loadSession() async {
    final raw = await channel.invokeMethod<String>('loadSession');
    if (raw == null || raw.isEmpty) return null;
    final s = Session.fromJson(
      Map<String, dynamic>.from(jsonDecode(raw) as Map),
    );
    return s.valid ? s : null;
  }

  Future<void> saveSession(Session? s) => channel.invokeMethod(
    'saveSession',
    s == null ? null : jsonEncode(s.toJson()),
  );
  Future<Map<String, dynamic>?> chooseDirectory() async {
    final result = await channel.invokeMapMethod<String, dynamic>(
      'chooseDirectory',
    );
    return result;
  }

  Future<void> resetDirectory() => channel.invokeMethod('resetDirectory');
  Future<String> directoryLabel() async =>
      await channel.invokeMethod<String>('directoryLabel') ?? 'Download/Books';
  Future<List<DownloadRecord>> downloads() async {
    final raw = await channel.invokeMethod<String>('listDownloads') ?? '[]';
    return (jsonDecode(raw) as List)
        .map(
          (x) => DownloadRecord.fromJson(Map<String, dynamic>.from(x as Map)),
        )
        .toList();
  }

  Future<void> download(
    Book book,
    String url,
    Map<String, String> headers,
    String origin,
  ) => channel.invokeMethod('download', {
    'url': url,
    'headers': headers,
    'origin': origin,
    'title': book.title,
    'fileName': safeFileName(book.title, book.extension),
    'book': jsonEncode(book.toJson()),
  });
  Future<void> cancelDownload(String id) =>
      channel.invokeMethod('cancelDownload', id);
  Future<void> pauseDownload(String id) =>
      channel.invokeMethod('pauseDownload', id);
  Future<void> resumeDownload(String id) =>
      channel.invokeMethod('resumeDownload', id);
  Future<bool> fileAvailable(String uri) async =>
      await channel.invokeMethod<bool>('fileAvailable', uri) ?? false;
  Future<void> openFile(DownloadRecord item) => channel.invokeMethod(
    'openFile',
    {'uri': item.uri, 'fileName': item.fileName},
  );
  Future<void> shareFile(DownloadRecord item) => channel.invokeMethod(
    'shareFile',
    {'uri': item.uri, 'fileName': item.fileName},
  );
  Future<void> removeRecord(String id, {bool deleteFile = false}) => channel
      .invokeMethod('removeRecord', {'id': id, 'deleteFile': deleteFile});
  Future<String> appVersion() async =>
      await channel.invokeMethod<String>('appVersion') ?? '';
  Future<List<String>> supportedAbis() async =>
      await channel.invokeListMethod<String>('supportedAbis') ?? [];
  Future<void> openUrl(String url) => channel.invokeMethod('openUrl', url);

  /// 尝试打开链接，返回是否成功。用于深链（例如 weread://），
  /// 没装对应 App 时原生会报 NO_APP，这里转成 false。
  Future<bool> tryOpenUrl(String url) async {
    try {
      await channel.invokeMethod('openUrl', url);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 直接用微信读书 App 打开深链，绕开系统选择器和浏览器。
  /// 返回是否成功（没装微信读书返回 false）。
  Future<bool> openWeread(String url) async {
    try {
      return await channel.invokeMethod<bool>('openWeread', url) ?? false;
    } catch (_) {
      return false;
    }
  }

  /// 让用户挑一个本地书籍文件，原生侧会先复制到缓存目录再返回路径。
  Future<BookFile?> pickBookFile() async {
    final result = await channel.invokeMapMethod<String, dynamic>('pickBookFile');
    if (result == null) return null;
    final path = result['path'] as String? ?? '';
    if (path.isEmpty) return null;
    return BookFile(
      path: path,
      name: result['name'] as String? ?? 'book.bin',
      size: (result['size'] as num?)?.toInt() ?? 0,
    );
  }
}

/// 选中的本地书籍文件。
class BookFile {
  final String path, name;
  final int size;
  const BookFile({
    required this.path,
    required this.name,
    required this.size,
  });
}
