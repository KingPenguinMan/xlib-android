/// 微信读书的腾讯云 COS 直传。
///
/// 从 olib-mobile 的 `_uploadCos` 迁移，把原生 HMAC 换成 `crypto` 包实现，
/// 并把整块读入改成流式上传，避免大文件占内存。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'weread_client.dart';

class WereadCos {
  static const _connectTimeout = Duration(seconds: 15);
  static const _sendTimeout = Duration(minutes: 10);
  static const _receiveTimeout = Duration(minutes: 2);

  /// 把本地文件直传到微信读书的对象存储。
  ///
  /// 签名沿用腾讯云 COS 的 q-sign-algorithm=sha1 方案：
  /// signKey = HMAC-SHA1(secretKey, keyTime)，最终签名再对
  /// `sha1\n{keyTime}\n{SHA1(httpString)}\n` 做一次 HMAC-SHA1。
  static Future<void> put({
    required File file,
    required int size,
    required String bucket,
    required String objectName,
    required String secretId,
    required String secretKey,
    required String token,
    required int expiry,
    WereadCancel? cancel,
    void Function(int sent, int total)? onProgress,
  }) async {
    final host = '$bucket.cos.accelerate.myqcloud.com';
    final key = objectName.replaceFirst(RegExp(r'^/'), '');
    final path = '/${key.split('/').map(Uri.encodeComponent).join('/')}';
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final keyTime = '$now;${now + 3600 < expiry ? now + 3600 : expiry}';
    final signKey = _hmacSha1(secretKey, keyTime);
    final httpString = 'put\n$path\n\nhost=$host\n';
    final hash = _sha1(httpString);
    final signature = _hmacSha1(signKey, 'sha1\n$keyTime\n$hash\n');
    final auth =
        'q-sign-algorithm=sha1&q-ak=$secretId'
        '&q-sign-time=$keyTime&q-key-time=$keyTime'
        '&q-header-list=host&q-url-param-list=&q-signature=$signature';

    final client = HttpClient()..connectionTimeout = _connectTimeout;
    try {
      cancel?.throwIfCancelled();
      final request = await client
          .putUrl(Uri.parse('https://$host$path'))
          .timeout(_connectTimeout);
      request.headers.set('Authorization', auth);
      request.headers.set('x-cos-security-token', token);
      request.headers.contentType = ContentType('application', 'octet-stream');
      request.headers.contentLength = size;
      request.headers.chunkedTransferEncoding = false;
      var sent = 0;
      final stream = file.openRead().map((chunk) {
        cancel?.throwIfCancelled();
        sent += chunk.length;
        onProgress?.call(sent, size);
        return chunk;
      });
      await request.addStream(stream).timeout(_sendTimeout);
      final response = await request.close().timeout(_receiveTimeout);
      await response.drain<void>();
      if (response.statusCode != 200) {
        throw WereadException('上传失败（HTTP ${response.statusCode}），请稍后重试');
      }
    } on TimeoutException {
      throw const WereadException('上传超时，请检查网络后重试');
    } on SocketException {
      throw const WereadException('上传过程中网络断开，请重试');
    } finally {
      client.close(force: true);
    }
  }

  static String _sha1(String value) =>
      sha1.convert(utf8.encode(value)).toString();

  static String _hmacSha1(String key, String value) =>
      Hmac(sha1, utf8.encode(key)).convert(utf8.encode(value)).toString();
}
