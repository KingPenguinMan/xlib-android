import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'controller.dart';
import 'domain.dart';
import 'native.dart';

class PreviewLoader extends StatefulWidget {
  final ReaderController controller;
  final Book book;
  const PreviewLoader({
    super.key,
    required this.controller,
    required this.book,
  });
  @override
  State<PreviewLoader> createState() => _PreviewLoaderState();
}

class _PreviewLoaderState extends State<PreviewLoader> {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  String error = '';
  double? progress;
  @override
  void initState() {
    super.initState();
    unawaited(load());
  }

  Future<void> load() async {
    File? temporary;
    try {
      final c = widget.controller;
      await c.ensureRoute();
      if (!mounted) return;
      final session = c.session;
      if (session == null) throw const FormatException('请先登录账户');
      final origin = c.activeOrigin;
      final link = await c.api.fileUrl(origin, session, widget.book);
      if (!mounted) return;
      var url = Uri.parse(link);
      HttpClientResponse? stream;
      for (var redirect = 0; redirect <= 5; redirect++) {
        if (url.scheme != 'https' ||
            url.userInfo.isNotEmpty ||
            url.host.isEmpty)
          throw const FormatException('阅读地址无效');
        final req = await client.getUrl(url);
        req.followRedirects = false;
        if (url.origin == Uri.parse(origin).origin) {
          c.api.downloadHeaders(origin, session).forEach(req.headers.set);
        }
        req.headers.set('Accept-Encoding', 'identity');
        final res = await req.close().timeout(const Duration(seconds: 20));
        if (!res.isRedirect) {
          stream = res;
          break;
        }
        final location = res.headers.value('location');
        if (location == null) throw const FormatException('阅读地址跳转失败');
        url = url.resolve(location);
        await res.drain<void>().timeout(const Duration(seconds: 10));
      }
      if (stream == null || stream.statusCode != 200)
        throw const FormatException('未能获取完整书籍，请稍后重试');
      const limit = 128 * 1024 * 1024;
      if (stream.contentLength > limit)
        throw const FormatException('试读支持 128 MB 以内的文件');
      final dir = await NativeBridge.channel.invokeMethod<String>(
        'readerCache',
      );
      if (dir == null || !mounted) return;
      final file = temporary = File(
        '$dir/${DateTime.now().microsecondsSinceEpoch}.book',
      );
      final out = await file.open(mode: FileMode.write);
      var received = 0;
      final clock = Stopwatch()..start();
      try {
        await for (final bytes in stream.timeout(const Duration(seconds: 30))) {
          if (!mounted) return;
          received += bytes.length;
          if (received > limit) throw const FormatException('文件超出试读大小上限');
          await out.writeFrom(bytes);
          if (mounted &&
              clock.elapsedMilliseconds > 200 &&
              stream.contentLength > 0) {
            setState(() => progress = received / stream!.contentLength);
            clock.reset();
          }
        }
      } finally {
        await out.close();
      }
      if (!mounted) return;
      if (received == 0 ||
          (stream.contentLength >= 0 && received != stream.contentLength))
        throw const FormatException('书籍传输不完整');
      await NativeBridge.channel.invokeMethod<void>('openPreview', {
        'path': file.path,
        'title': widget.book.title,
        'format': widget.book.extension,
      });
      temporary = null;
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted)
        setState(
          () => error = e is FormatException
              ? e.message
              : '无法载入书籍，请检查网络或切换线路后重试。',
        );
    } finally {
      client.close(force: true);
      if (temporary != null && await temporary.exists())
        await temporary.delete();
    }
  }

  @override
  void dispose() {
    client.close(force: true);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.book.title)),
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (error.isEmpty) LinearProgressIndicator(value: progress),
            const SizedBox(height: 12),
            Text(error.isEmpty ? '正在载入书籍…' : error),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(error.isEmpty ? '取消' : '返回'),
            ),
          ],
        ),
      ),
    ),
  );
}
