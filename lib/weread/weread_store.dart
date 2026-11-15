import 'package:flutter/services.dart';

/// 微信读书会话令牌的持久化抽象。
abstract class WereadSessionStore {
  Future<String?> read();
  Future<void> write(String value);
  Future<void> delete();
}

/// 走平台密钥库（AndroidKeyStore）加密后保存，明文不落盘、不进日志。
class NativeWereadSessionStore implements WereadSessionStore {
  static const _channel = MethodChannel('dev.bookisle/native');

  @override
  Future<String?> read() async =>
      _channel.invokeMethod<String>('readWereadSession');

  @override
  Future<void> write(String value) =>
      _channel.invokeMethod('writeWereadSession', value);

  @override
  Future<void> delete() => _channel.invokeMethod('deleteWereadSession');
}
