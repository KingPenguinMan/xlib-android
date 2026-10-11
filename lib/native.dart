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
  Future<void> openUrl(String url) => channel.invokeMethod('openUrl', url);
}
