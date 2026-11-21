/// 微信读书移动端客户端：扫码连接 + 受信 API 调用。
///
/// 迁移自 olib-mobile（https://github.com/GGbone520/olib-mobile）的
/// `lib/services/weread/weread_mobile_client.dart`，网络层由 dio 改写为
/// `dart:io` HttpClient，与本项目「不引入第三方网络库」的约定保持一致；
/// 接口协议、请求头、登录与刷新流程均未改动。
///
/// 会话令牌用平台密钥库加密后保存，明文不落盘、不进日志。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'weread_store.dart';

class WereadException implements Exception {
  final String message;

  /// 写操作已发出但结果未知（例如刷新令牌后重放写请求会有重复提交风险）。
  final bool outcomeUnknown;

  /// 需要重新扫码连接。
  final bool needsConnect;

  const WereadException(
    this.message, {
    this.outcomeUnknown = false,
    this.needsConnect = false,
  });

  @override
  String toString() => message;
}

/// 取消标记。dio 的 CancelToken 在迁移时以此替代。
class WereadCancel {
  bool _cancelled = false;
  bool get isCancelled => _cancelled;
  void cancel() => _cancelled = true;
  void throwIfCancelled() {
    if (_cancelled) throw const WereadException('操作已取消');
  }
}

class WereadQr {
  final String uuid;
  final String confirmUrl;

  /// 微信接口直接返回的官方二维码图片。
  /// 自己拿 confirmUrl 重新生成的二维码并不等价于官方二维码，
  /// 在微信里打开那个链接只会要求「请在微信客户端打开 / 扫一扫」。
  final Uint8List? imageBytes;
  const WereadQr(this.uuid, this.confirmUrl, [this.imageBytes]);
}

/// 会话令牌的持久化抽象，默认走平台密钥库。
class _Session {
  final String vid;
  final String accessToken;
  final String refreshToken;
  final String deviceId;

  const _Session(this.vid, this.accessToken, this.refreshToken, this.deviceId);

  factory _Session.fromJson(Map<String, dynamic> json) => _Session(
    json['vid'] as String,
    json['accessToken'] as String,
    json['refreshToken'] as String,
    json['deviceId'] as String,
  );

  String encode() => jsonEncode({
    'vid': vid,
    'accessToken': accessToken,
    'refreshToken': refreshToken,
    'deviceId': deviceId,
  });
}

/// 一次 HTTP 往返的原始结果。
class _Res {
  final int status;
  final String body;
  const _Res(this.status, this.body);
}

class WereadClient {
  WereadClient({WereadSessionStore? store, HttpClient? http})
    : _store = store ?? NativeWereadSessionStore(),
      _client = http ?? (HttpClient()..connectionTimeout = const Duration(seconds: 15));

  static const baseUrl = 'https://i.weread.qq.com';
  static const _userAgent =
      'WeRead/2.1.2 WRBrand/Onyx wr_eink Dalvik/2.1.0 (Linux; U; Android 11; BOOX Build/onyx)';
  static const _versionHeaders = <String, String>{
    'baseapi': '30',
    'appver': '2.1.2.10245900',
    'basever': '2.1.2.10245900',
    'osver': '11',
    'channelId': '900',
    'User-Agent': _userAgent,
  };

  final HttpClient _client;
  final WereadSessionStore _store;
  final Random _random = Random.secure();
  _Session? _session;
  bool _loaded = false;
  Future<void>? _refreshing;

  void close() => _client.close(force: true);

  Future<bool> get isConnected async {
    await _load();
    return _session != null;
  }

  String? get connectedVid => _session?.vid;

  Future<void> _load() async {
    if (_loaded) return;
    String? raw;
    try {
      raw = await _store.read();
    } catch (_) {
      // 密钥不可用（例如换机恢复）时按未连接处理，不阻断启动。
      raw = null;
    }
    if (raw != null && raw.isNotEmpty) {
      try {
        _session = _Session.fromJson(
          Map<String, dynamic>.from(jsonDecode(raw) as Map),
        );
      } catch (_) {
        await _store.delete().catchError((_) {});
        throw const WereadException('本机保存的微信读书连接已损坏，请重新扫码');
      }
    }
    _loaded = true;
  }

  Future<void> disconnect() async {
    try {
      await _store.delete();
    } catch (_) {
      // 删除失败也要把内存会话清掉，避免继续用旧令牌。
    }
    _session = null;
    _loaded = true;
  }

  // ─────────────────── 连接信息导出 / 导入 ───────────────────

  /// 导出当前连接信息（JSON 文本），用于换机或重装后免扫码恢复。
  Future<String?> exportSession() async {
    await _load();
    return _session?.encode();
  }

  /// 导入连接信息。先用 `/shelf/sync` 验证令牌可用，再写入密钥库，
  /// 避免导入一份过期凭据后界面却显示「已连接」。
  Future<void> importSession(String raw) async {
    Map<String, dynamic> map;
    try {
      final decoded = jsonDecode(raw.trim());
      if (decoded is! Map) throw const FormatException('not a map');
      map = Map<String, dynamic>.from(decoded);
    } catch (_) {
      throw const WereadException('连接信息不是有效的 JSON，请检查是否复制完整');
    }
    String field(String key) => '${map[key] ?? ''}'.trim();
    final vid = field('vid');
    final access = field('accessToken');
    final refresh = field('refreshToken');
    final deviceId = field('deviceId');
    if (vid.isEmpty || access.isEmpty || refresh.isEmpty) {
      throw const WereadException(
        '连接信息缺少 vid / accessToken / refreshToken',
      );
    }
    final candidate = _Session(vid, access, refresh, deviceId);
    final previous = _session;
    _session = candidate;
    _loaded = true;
    try {
      // 导出的 accessToken 是短期令牌，往往一导出就过期了；
      // 先用它验证，过期就拿 refreshToken 换一张新的再验证。
      if (!await _verifySession(candidate)) {
        final renewed = await _renewSession(candidate);
        _session = renewed;
        if (!await _verifySession(renewed)) {
          throw const WereadException('refreshToken 已失效，请重新扫码');
        }
      }
    } on WereadException catch (error) {
      _session = previous;
      throw WereadException('连接信息校验失败：${error.message}');
    } catch (_) {
      _session = previous;
      rethrow;
    }
    await _store.write((_session ?? candidate).encode());
  }

  /// 用 vid + accessToken 试一次书架，判断这组令牌还能不能用。
  Future<bool> _verifySession(_Session session) async {
    try {
      final response = await _send(
        'GET',
        Uri.parse('$baseUrl/shelf/sync'),
        headers: {
          ..._versionHeaders,
          'vid': session.vid,
          'accessToken': session.accessToken,
        },
        timeout: const Duration(seconds: 15),
        receive: const Duration(seconds: 20),
      );
      if (response.status == 401) return false;
      final data = _decode(response, '验证连接信息');
      final code = data['errCode'] ?? data['errcode'];
      return code != -2012;
    } catch (_) {
      return false;
    }
  }

  /// 用 refreshToken 换一张新的 accessToken，不清本地会话。
  Future<_Session> _renewSession(_Session session) async {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final random = _random.nextInt(1000) + 1;
    final signature = _sha256('$timestamp${session.deviceId}$random');
    final response = await _send(
      'POST',
      Uri.parse('$baseUrl/login'),
      json: {
        'deviceId': session.deviceId,
        'deviceName': 'BOOX',
        'inBackground': 0,
        'kickType': 1,
        'random': random,
        'refCgi': '',
        'refreshToken': session.refreshToken,
        'signature': signature,
        'timestamp': timestamp,
        'trackId': '',
        'deviceType': 3,
      },
      headers: _versionHeaders,
      timeout: const Duration(seconds: 30),
    );
    final json = _decode(response, '刷新登录状态');
    final access = json['accessToken'];
    if (access is! String || access.isEmpty) {
      throw const WereadException('这份连接信息已失效，请重新扫码');
    }
    final refresh = json['refreshToken'];
    return _Session(
      json['vid']?.toString() ?? session.vid,
      access,
      refresh is String && refresh.isNotEmpty ? refresh : session.refreshToken,
      session.deviceId,
    );
  }

  // ───────────────────────────── HTTP ─────────────────────────────

  Future<_Res> _send(
    String method,
    Uri uri, {
    Map<String, String>? headers,
    Object? json,
    Duration timeout = const Duration(seconds: 30),
    Duration receive = const Duration(seconds: 30),
  }) async {
    final deadline = DateTime.now().add(timeout + receive);
    try {
      final request = await _client.openUrl(method, uri).timeout(timeout);
      request.followRedirects = false;
      headers?.forEach(request.headers.set);
      if (json != null) {
        final raw = utf8.encode(jsonEncode(json));
        request.headers.contentType = ContentType(
          'application',
          'json',
          charset: 'utf-8',
        );
        request.contentLength = raw.length;
        request.add(raw);
      }
      final response = await request.close().timeout(receive);
      final bytes = <int>[];
      await for (final part in response.timeout(
        deadline.difference(DateTime.now()),
      )) {
        bytes.addAll(part);
        if (bytes.length > 4 * 1024 * 1024) {
          throw const WereadException('微信读书返回的数据过大');
        }
      }
      return _Res(
        response.statusCode,
        utf8.decode(bytes, allowMalformed: true),
      );
    } on TimeoutException {
      throw const WereadException('连接微信读书超时，请检查网络后重试');
    } on SocketException {
      throw const WereadException('无法连接微信读书，请检查网络');
    } on HandshakeException {
      throw const WereadException('微信读书的证书校验失败，请检查系统日期');
    } on HttpException {
      throw const WereadException('连接微信读书被中断，请重试');
    }
  }

  Map<String, dynamic> _decode(
    _Res res,
    String operation, {
    bool allowHttpError = false,
  }) {
    if (res.body.length > 1024 * 1024) {
      throw WereadException('$operation 返回的数据过大（HTTP ${res.status}）');
    }
    Object? decoded;
    try {
      decoded = jsonDecode(res.body);
    } on FormatException {
      throw WereadException('$operation 返回的不是 JSON（HTTP ${res.status}）');
    }
    if (decoded is! Map) {
      throw WereadException('$operation 返回的格式异常（HTTP ${res.status}）');
    }
    final data = Map<String, dynamic>.from(decoded);
    if (!allowHttpError && (res.status >= 400 || res.status == 0)) {
      final code = data['errcode'] ?? data['errCode'];
      final suffix = code == null ? '' : '，代码 $code';
      throw WereadException('$operation 失败（HTTP ${res.status}$suffix）');
    }
    return data;
  }

  String _digits(int count) =>
      List.generate(count, (_) => _random.nextInt(10)).join();

  // ─────────────────────────── 扫码登录 ───────────────────────────

  Future<WereadQr> requestQr({WereadCancel? cancel}) async {
    cancel?.throwIfCancelled();
    final ticketRes = await _send(
      'GET',
      Uri.parse('$baseUrl/wxticket?nonceStr=weread'),
      headers: _versionHeaders,
    );
    final ticket = _decode(ticketRes, '获取扫码凭证');
    final signature = ticket['signature'];
    final timestamp = ticket['timeStamp'];
    if (signature is! String || timestamp == null) {
      throw const WereadException('扫码凭证不完整，请重试');
    }
    final uri = Uri.https('open.weixin.qq.com', '/connect/sdk/qrconnect', {
      'appid': 'wxab9b71ad2b90ff34',
      'noncestr': 'weread',
      'timestamp': '$timestamp',
      'scope': 'snsapi_userinfo,snsapi_timeline,snsapi_friend',
      'signature': signature,
    });
    cancel?.throwIfCancelled();
    final response = await _send(
      'GET',
      uri,
      headers: {'User-Agent': _userAgent},
    );
    final json = _decode(response, '获取微信二维码');
    final uuid = json['uuid'];
    final code = int.tryParse('${json['errcode']}');
    if (code != null && code != 0) {
      throw WereadException('微信拒绝了二维码请求（代码 $code）');
    }
    if (uuid is! String || uuid.isEmpty) {
      throw const WereadException('微信没有返回二维码标识，请重试');
    }
    Uint8List? imageBytes;
    final qrcode = json['qrcode'];
    if (qrcode is Map) {
      final encoded = qrcode['qrcodebase64'];
      if (encoded is String && encoded.isNotEmpty) {
        try {
          imageBytes = base64Decode(encoded);
        } catch (_) {
          // 图片解析失败不影响长轮询，界面会回退到本地生成的二维码。
        }
      }
    }
    return WereadQr(
      uuid,
      Uri.https('open.weixin.qq.com', '/connect/confirm', {
        'uuid': uuid,
      }).toString(),
      imageBytes,
    );
  }

  /// 长轮询等待扫码结果。[onStatus] 会收到 waiting / scanned / confirmed。
  Future<void> waitForQr(
    WereadQr qr, {
    WereadCancel? cancel,
    void Function(String status)? onStatus,
  }) async {
    final deadline = DateTime.now().add(const Duration(minutes: 5));
    int? last;
    WereadException? dropped;
    while (DateTime.now().isBefore(deadline)) {
      cancel?.throwIfCancelled();
      _Res response;
      try {
        response = await _send(
          'GET',
          Uri.https('long.open.weixin.qq.com', '/connect/l/qrconnect', {
            'f': 'json',
            'uuid': qr.uuid,
            if (last != null) 'last': '$last',
          }),
          headers: {'User-Agent': 'Mozilla/5.0'},
          timeout: const Duration(seconds: 20),
          receive: const Duration(seconds: 70),
        );
      } on WereadException catch (error) {
        // 切到微信扫码时应用会退到后台，长轮询常被中断。轮询是幂等的，
        // 退避后继续即可。
        dropped = error;
        await Future<void>.delayed(const Duration(seconds: 2));
        continue;
      }
      dropped = null;
      final data = _decode(response, '扫码状态');
      final status = int.tryParse('${data['wx_errcode']}');
      if (status == 405) {
        final code = data['wx_code'];
        if (code is! String || code.isEmpty) {
          throw const WereadException('扫码确认没有返回授权码，请重新扫码');
        }
        onStatus?.call('confirmed');
        await _exchange(code, cancel: cancel);
        return;
      }
      if (status == 404) onStatus?.call('scanned');
      if (status == 402) {
        throw const WereadException('二维码已过期，请点击刷新');
      }
      if (status == 403) {
        throw const WereadException('已取消扫码，请重新扫码');
      }
      if (status != 404 && status != 408) {
        throw WereadException('扫码返回了未知状态（$status），请重试');
      }
      last = status;
      if (status == 408) {
        await Future<void>.delayed(const Duration(seconds: 1));
      }
    }
    if (dropped != null) throw dropped;
    throw const WereadException('扫码登录超时，请重新生成二维码');
  }

  Future<void> _exchange(String code, {WereadCancel? cancel}) async {
    final deviceId = 'eink334691225${_digits(19)}';
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final random = _random.nextInt(1000);
    final signature = _sha256('$timestamp$deviceId$random');
    final installId = 'eink31${_digits(26)}';
    _Res? response;
    var attempt = 0;
    while (true) {
      cancel?.throwIfCancelled();
      try {
        response = await _send(
          'POST',
          Uri.parse('$baseUrl/login'),
          json: {
            'appFirstInstall': 1,
            'code': code,
            'deviceId': deviceId,
            'deviceName': 'BOOX',
            'installId': installId,
            'isAutoLogout': 0,
            'isFromQrcode': 1,
            'random': random,
            'signature': signature,
            'timestamp': timestamp,
            'trackId': '',
            'deviceType': 3,
          },
          headers: _versionHeaders,
          timeout: const Duration(seconds: 30),
        );
        break;
      } on WereadException {
        // 授权码只能消费一次，重试过多会让用户白扫一遍。
        if (++attempt > 2) rethrow;
        await Future<void>.delayed(const Duration(seconds: 2));
      }
    }
    final json = _decode(response, '扫码登录');
    final access = json['accessToken'];
    final refresh = json['refreshToken'];
    final vid = json['vid']?.toString();
    if (access is! String ||
        access.isEmpty ||
        refresh is! String ||
        refresh.isEmpty ||
        vid == null ||
        vid.isEmpty) {
      final code = int.tryParse('${json['errCode']}');
      throw WereadException(
        '扫码登录没有拿到完整凭据${code == null ? '' : '（代码 $code）'}，请重新扫码',
      );
    }
    final session = _Session(vid, access, refresh, deviceId);
    await _store.write(session.encode());
    _session = session;
    _loaded = true;
  }

  Future<void> _refresh() async {
    final pending = _refreshing;
    if (pending != null) return pending;
    final started = _refreshOnce();
    _refreshing = started;
    try {
      await started;
    } finally {
      _refreshing = null;
    }
  }

  Future<void> _refreshOnce() async {
    final current = _session;
    if (current == null) {
      throw const WereadException('请先连接微信读书', needsConnect: true);
    }
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final random = _random.nextInt(1000) + 1;
    final signature = _sha256('$timestamp${current.deviceId}$random');
    final response = await _send(
      'POST',
      Uri.parse('$baseUrl/login'),
      json: {
        'deviceId': current.deviceId,
        'deviceName': 'BOOX',
        'inBackground': 0,
        'kickType': 1,
        'random': random,
        'refCgi': '',
        'refreshToken': current.refreshToken,
        'signature': signature,
        'timestamp': timestamp,
        'trackId': '',
        'deviceType': 3,
      },
      headers: _versionHeaders,
      timeout: const Duration(seconds: 30),
    );
    final json = _decode(response, '刷新登录状态');
    final vid = json['vid']?.toString() ?? current.vid;
    final access = json['accessToken'];
    final refresh = json['refreshToken'] ?? current.refreshToken;
    if (vid != current.vid ||
        access is! String ||
        access.isEmpty ||
        refresh is! String ||
        refresh.isEmpty) {
      await disconnect();
      throw const WereadException(
        '微信读书登录已失效，请重新扫码',
        needsConnect: true,
      );
    }
    final updated = _Session(vid, access, refresh, current.deviceId);
    await _store.write(updated.encode());
    _session = updated;
  }

  // ─────────────────────────── API 调用 ───────────────────────────

  Future<Map<String, dynamic>> call(
    String method,
    String path, {
    Map<String, dynamic>? query,
    Map<String, dynamic>? body,
    bool replayable = false,
    WereadCancel? cancel,
  }) async {
    await _load();
    if (_session == null) {
      throw const WereadException('请先连接微信读书', needsConnect: true);
    }
    if (!path.startsWith('/') || path.startsWith('//')) {
      throw ArgumentError.value(path, 'path');
    }
    final uri = Uri.parse('$baseUrl$path').replace(
      queryParameters: query?.map((k, v) => MapEntry(k, '$v')),
    );
    for (var attempt = 0; attempt < 2; attempt++) {
      cancel?.throwIfCancelled();
      final token = _session!;
      _Res response;
      try {
        response = await _send(
          method,
          uri,
          json: body,
          headers: {
            ..._versionHeaders,
            'vid': token.vid,
            'accessToken': token.accessToken,
          },
          timeout: const Duration(seconds: 20),
          receive: const Duration(seconds: 45),
        );
      } on WereadException catch (error) {
        throw WereadException(
          error.message,
          outcomeUnknown: method == 'POST' && !replayable,
        );
      }
      final expired =
          response.status == 401 ||
          _decodedErrorCode(response) == -2012;
      if (expired && attempt == 0) {
        try {
          await _refresh();
        } on WereadException catch (error) {
          if (error.needsConnect) rethrow;
          throw WereadException('微信读书登录状态刷新失败：${error.message}');
        }
        if (method == 'GET' || replayable) continue;
        throw const WereadException(
          '登录状态已刷新，但这次提交的结果未知，请回到列表确认',
          outcomeUnknown: true,
        );
      }
      final data = _decode(response, path, allowHttpError: true);
      final rawError = data.containsKey('errCode')
          ? data['errCode']
          : data['errcode'];
      final errorCode = rawError == null ? null : int.tryParse('$rawError');
      if (rawError != null && errorCode == null) {
        throw WereadException('$path 返回了无效的错误码');
      }
      if (response.status >= 400 || (errorCode != null && errorCode != 0)) {
        if (response.status == 401 || errorCode == -2012) {
          throw const WereadException(
            '微信读书登录已失效，请重新扫码',
            needsConnect: true,
          );
        }
        throw WereadException(
          '$path 调用失败（HTTP ${response.status}，代码 ${errorCode ?? '未知'}）',
          outcomeUnknown:
              method == 'POST' &&
              !replayable &&
              response.status >= 500,
        );
      }
      return data;
    }
    throw WereadException('$path 重试次数已用尽');
  }

  /// 只解析错误码，用于 401/令牌过期判定，不抛错。
  int? _decodedErrorCode(_Res res) {
    try {
      final decoded = jsonDecode(res.body);
      if (decoded is! Map) return null;
      final raw = decoded.containsKey('errCode')
          ? decoded['errCode']
          : decoded['errcode'];
      return raw == null ? null : int.tryParse('$raw');
    } catch (_) {
      return null;
    }
  }

  String _sha256(String value) =>
      sha256.convert(utf8.encode(value)).toString();
}
