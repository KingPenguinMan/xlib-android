import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import 'domain.dart';

class ApiException implements Exception {
  final String message;
  final bool retryable, needsLogin;
  const ApiException(
    this.message, {
    this.retryable = false,
    this.needsLogin = false,
  });
  @override
  String toString() => message;
}

String solveProof(String token) {
  if (!RegExp(r'^[0-9a-fA-F]{40}$').hasMatch(token)) return '';
  final index = int.parse(token[0], radix: 16);
  for (var i = 0; i < 1000000; i++) {
    final candidate = '$token$i';
    final bytes = sha1.convert(utf8.encode(candidate)).bytes;
    if (bytes[index] == 0xb0 && bytes[index + 1] == 0x0b) return candidate;
  }
  return '';
}

class NetResponse {
  final int status;
  final String body;
  final Uri uri;
  const NetResponse(this.status, this.body, this.uri);
}

abstract class ApiTransport {
  Future<NetResponse> request(
    String origin,
    String path, {
    String method = 'GET',
    Map<String, String>? form,
    Session? session,
    Duration timeout = const Duration(seconds: 14),
  });
  Map<String, String> cookies(String origin);
  void close();
}

class HttpTransport implements ApiTransport {
  final HttpClient _client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 7);
  final Map<String, Map<String, String>> _cookies = {};
  static const userAgent =
      'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36';
  @override
  Map<String, String> cookies(String origin) => Map.of(_cookies[origin] ?? {});
  @override
  void close() => _client.close(force: true);

  @override
  Future<NetResponse> request(
    String origin,
    String path, {
    String method = 'GET',
    Map<String, String>? form,
    Session? session,
    Duration timeout = const Duration(seconds: 14),
  }) async {
    var uri = Uri.parse(origin).resolve(path);
    if (!trustedOrigin(uri)) throw const ApiException('线路地址不受支持，请选择列表中的线路');
    var verb = method;
    var payload = form;
    var challengeCount = 0;
    var redirects = 0;
    final deadline = DateTime.now().add(timeout);
    try {
      while (true) {
        final left = deadline.difference(DateTime.now());
        if (left.isNegative) throw TimeoutException('request deadline');
        final req = await _client.openUrl(verb, uri).timeout(left);
        req.followRedirects = false;
        req.headers.set(HttpHeaders.userAgentHeader, userAgent);
        req.headers.set(
          HttpHeaders.acceptHeader,
          'application/json, text/html;q=0.9',
        );
        final cookieMap = cookies(uri.origin);
        if (session != null && session.valid) {
          req.headers.set('remix-userid', session.userId);
          req.headers.set('remix-userkey', session.userKey);
          cookieMap.addAll({
            'remix_userid': session.userId,
            'remix_userkey': session.userKey,
          });
        }
        for (final entry in cookieMap.entries) {
          if (!entry.key.contains(RegExp(r'[\r\n;]')) &&
              !entry.value.contains(RegExp(r'[\r\n;]'))) {
            req.cookies.add(Cookie(entry.key, entry.value));
          }
        }
        if (verb == 'POST') {
          req.headers.contentType = ContentType(
            'application',
            'x-www-form-urlencoded',
            charset: 'utf-8',
          );
          req.write(Uri(queryParameters: payload ?? {}).query);
        }
        final response = await req.close().timeout(
          deadline.difference(DateTime.now()),
        );
        final jar = _cookies.putIfAbsent(uri.origin, () => {});
        for (final cookie in response.cookies) {
          if (cookie.maxAge == 0 ||
              (cookie.expires?.isBefore(DateTime.now()) ?? false)) {
            jar.remove(cookie.name);
          } else {
            jar[cookie.name] = cookie.value;
          }
        }
        final bytes = <int>[];
        await for (final part in response.timeout(
          deadline.difference(DateTime.now()),
        )) {
          bytes.addAll(part);
          if (bytes.length > 8 * 1024 * 1024) {
            throw const ApiException('服务器返回的数据过大，请缩小搜索范围');
          }
        }
        final body = utf8.decode(bytes, allowMalformed: true);
        final challenge = RegExp("'([0-9A-Fa-f]{40})','c_token=")
            .firstMatch(body);
        if (challenge != null && challengeCount++ < 4) {
          final proof = await compute(
            solveProof,
            challenge.group(1)!,
          ).timeout(deadline.difference(DateTime.now()));
          if (proof.isEmpty)
            throw const ApiException('线路验证暂未通过，请换一条线路', retryable: true);
          jar['c_token'] = proof;
          await Future<void>.delayed(
            Duration(milliseconds: 300 * challengeCount),
          );
          continue;
        }
        if (response.isRedirect ||
            [301, 302, 303, 307, 308].contains(response.statusCode)) {
          final location = response.headers.value(HttpHeaders.locationHeader);
          if (location == null || redirects++ >= 4) {
            throw const ApiException('线路反复跳转，请换一条线路', retryable: true);
          }
          final next = uri.resolve(location);
          if (!trustedOrigin(next))
            throw const ApiException('线路跳转到未知地址，已停止连接', retryable: true);
          if (verb == 'POST' && next.origin != uri.origin) {
            throw const ApiException('登录线路发生变化，请重新检测线路后再登录', retryable: true);
          }
          if ([301, 302, 303].contains(response.statusCode)) {
            verb = 'GET';
            payload = null;
          }
          uri = next;
          continue;
        }
        final isJson = body.trimLeft().startsWith('{');
        if (!isJson &&
            (response.statusCode == 517 ||
                body.toLowerCase().contains('diamwall') ||
                challenge != null)) {
          throw const ApiException('此线路被防护页面拦截，请切换线路', retryable: true);
        }
        if (!isJson && response.statusCode >= 400) {
          throw ApiException(
            '线路暂不可用（HTTP ${response.statusCode}）',
            retryable: true,
          );
        }
        return NetResponse(response.statusCode, body, uri);
      }
    } on TimeoutException {
      throw const ApiException('连接超时，请检测线路或检查网络', retryable: true);
    } on SocketException {
      throw const ApiException('无法连接服务器，请检查网络或切换线路', retryable: true);
    } on HandshakeException catch (error) {
      final certificateError = error.toString().toUpperCase().contains(
        'CERTIFICATE_VERIFY_FAILED',
      );
      throw ApiException(
        certificateError ? '线路证书校验失败，请检查系统日期或更换线路' : 'TLS 握手未完成，请更换线路或网络后重新检测',
        retryable: true,
      );
    } on HttpException {
      throw const ApiException('连接被中断，请重试或切换线路', retryable: true);
    }
  }
}

class LibraryApi {
  final ApiTransport transport;
  LibraryApi({ApiTransport? transport})
    : transport = transport ?? HttpTransport();
  void close() => transport.close();

  BookPage _resolveCovers(BookPage page, String origin) {
    final base = Uri.parse(origin);
    final books = page.books.map((book) {
      if (book.cover.isEmpty) return book;
      try {
        var uri = base.resolve(book.cover);
        if (uri.scheme == 'http') uri = uri.replace(scheme: 'https');
        // The history endpoint omits the collection segment. Search/detail
        // responses use `collections/userbooks/<hash>`, which is the valid
        // CDN path for the same cover.
        if (uri.path.contains('/collections//')) {
          uri = uri.replace(
            path: uri.path.replaceFirst(
              '/collections//',
              '/collections/userbooks/',
            ),
          );
        }
        return book.withCover(uri.toString());
      } catch (_) {
        return book;
      }
    }).toList();
    return BookPage(books, page.page, page.totalPages);
  }

  static Map<String, dynamic> decode(
    NetResponse response, {
    bool requireSuccess = true,
  }) {
    dynamic body;
    try {
      body = jsonDecode(response.body);
    } catch (_) {
      throw const ApiException('线路返回了网页而不是图书数据，请切换线路', retryable: true);
    }
    if (body is! Map)
      throw const ApiException('服务器数据格式异常，请稍后重试', retryable: true);
    final data = Map<String, dynamic>.from(body);
    if (requireSuccess && intValue(data['success']) != 1) {
      var message = plainText(data['error'] ?? data['message']);
      if (message.isEmpty) message = '服务器未完成请求，请稍后重试';
      final low = message.toLowerCase();
      if (low.contains('password') || low.contains('incorrect email')) {
        throw const ApiException('邮箱或密码不正确，请检查后重试');
      }
      final auth =
          low.contains('not authorized') ||
          low.contains('not logged') ||
          low.contains('unauthorized') ||
          low.contains('session expired');
      if (auth) throw const ApiException('登录已过期，请重新登录', needsLogin: true);
      if (low.contains('limit') || low.contains('quota')) {
        throw const ApiException('账户下载额度不足，请在「我的」查看今日额度');
      }
      throw ApiException(
        message.length > 180 ? '${message.substring(0, 180)}…' : message,
      );
    }
    return data;
  }

  Future<RouteInfo> probe(String origin) async {
    final result = RouteInfo(origin, status: RouteStatus.testing);
    final watch = Stopwatch()..start();
    try {
      final response = await transport.request(
        origin,
        '/eapi/info/domains',
        timeout: const Duration(seconds: 8),
      );
      final data = decode(response, requireSuccess: false);
      if (data['domains'] == null && data['data'] == null) {
        throw const ApiException('健康检测返回数据不完整');
      }
      result.status = RouteStatus.healthy;
      result.detail = '可连接';
      result.resolvedOrigin = response.uri.origin;
    } catch (e) {
      final message = '$e';
      result.status = message.contains('超时')
          ? RouteStatus.timeout
          : message.contains('拦截')
          ? RouteStatus.blocked
          : RouteStatus.failed;
      result.detail = message;
    } finally {
      watch.stop();
      result.milliseconds = watch.elapsedMilliseconds;
    }
    return result;
  }

  Future<Session> login(String origin, String email, String password) async {
    final result = await transport.request(
      origin,
      '/eapi/user/login',
      method: 'POST',
      form: {'email': email, 'password': password},
      timeout: const Duration(seconds: 45),
    );
    final data = decode(result, requireSuccess: false);
    final user = data['user'] is Map ? data['user'] as Map : {};
    if (intValue(data['success']) == 1) {
      final session = Session(
        textValue(user['id']),
        textValue(user['remix_userkey'] ?? user['remix_user_key']),
        email,
      );
      if (session.valid) return session;
    }
    if (textValue(data['error']).toLowerCase().contains('incorrect'))
      decode(result);
    final fallback = await transport.request(
      origin,
      '/rpc.php',
      method: 'POST',
      form: {
        'email': email,
        'password': password,
        'action': 'login',
        'isModal': 'true',
        'site_mode': 'books',
        'isSingleLogin': '1',
        'redirectUrl': '',
        'gg_json_mode': '1',
      },
      timeout: const Duration(seconds: 45),
    );
    final formResult = decode(fallback, requireSuccess: false);
    final errors = formResult['response'] is Map
        ? (formResult['response'] as Map)['validationError']
        : null;
    if (errors != null && '$errors'.isNotEmpty)
      throw ApiException(plainText(errors));
    final cookies = transport.cookies(fallback.uri.origin);
    final session = Session(
      cookies['remix_userid'] ?? '',
      cookies['remix_userkey'] ?? '',
      email,
    );
    if (!session.valid) throw const ApiException('当前线路暂时无法完成登录，请换线后重试');
    return session;
  }

  Future<BookPage> search(
    String origin,
    Session session,
    String query,
    int page,
    String format,
    String language, {
    int? yearFrom,
  }) async {
    final form = {'message': query, 'page': '$page', 'limit': '30'};
    if (format.isNotEmpty) form['extensions[]'] = format.toLowerCase();
    if (language.isNotEmpty) form['languages[]'] = language;
    // 线路支持按出版年下限过滤，用来做「新书上架」这类板块。
    if (yearFrom != null) form['yearFrom'] = '$yearFrom';
    final r = await transport.request(
      origin,
      '/eapi/book/search',
      method: 'POST',
      form: form,
      session: session,
    );
    return _resolveCovers(BookPage.fromJson(decode(r), page), origin);
  }

  Future<Book> details(String origin, Session session, Book book) async {
    if (!book.downloadable) throw const ApiException('此记录缺少图书标识，请重新搜索书名');
    try {
      return await _fetchDetails(origin, session, book);
    } catch (error) {
      // 官方分类页是 HTML，里面只有 id / termshash，缺 EAPI 需要的短 hash。
      // 这里用书名回查一次，按 id 匹配补回正确 hash 再重试。
      if (error is ApiException && _isInvalidHash(error)) {
        final fixed = await _resolveBook(origin, session, book);
        if (fixed != null) return _fetchDetails(origin, session, fixed);
      }
      rethrow;
    }
  }

  Future<Book> _fetchDetails(String origin, Session session, Book book) async {
    final r = await transport.request(
      origin,
      '/eapi/book/${Uri.encodeComponent(book.id)}/${Uri.encodeComponent(book.hash)}',
      session: session,
    );
    final data = decode(r);
    final raw = Map<String, dynamic>.from(data['book'] as Map? ?? {});
    raw.putIfAbsent('id', () => book.id);
    raw.putIfAbsent('hash', () => book.hash);
    final detailed = Book.fromJson({...book.toJson(), ...raw});
    return _resolveCovers(BookPage([detailed], 1, 1), origin).books.first;
  }

  bool _isInvalidHash(ApiException error) =>
      error.message.toLowerCase().contains('invalid hash');

  /// 用书名搜索，按 id 优先匹配回一本带正确 hash 的书。
  Future<Book?> _resolveBook(String origin, Session session, Book book) async {
    try {
      final page = await search(origin, session, book.title, 1, '', '');
      for (final candidate in page.books) {
        if (candidate.id == book.id &&
            candidate.hash.isNotEmpty &&
            candidate.hash != book.hash) {
          return candidate;
        }
      }
      for (final candidate in page.books) {
        if (candidate.title == book.title &&
            candidate.hash.isNotEmpty &&
            (book.author.isEmpty || candidate.author == book.author)) {
          return candidate;
        }
      }
    } catch (_) {
      // 回查失败就让原始错误抛出去。
    }
    return null;
  }

  Future<BookPage> history(String origin, Session session, int page) async {
    final r = await transport.request(
      origin,
      '/eapi/user/book/downloaded?page=$page&limit=30',
      session: session,
    );
    return _resolveCovers(BookPage.fromJson(decode(r), page), origin);
  }

  /// `/eapi/user/book/saved` — 云端收藏列表（跨设备可见）。
  Future<BookPage> savedBooks(String origin, Session session, int page) async {
    final r = await transport.request(
      origin,
      '/eapi/user/book/saved?page=$page&limit=30',
      session: session,
    );
    return _resolveCovers(BookPage.fromJson(decode(r), page), origin);
  }

  /// `/eapi/user/book/{id}/save` — 收藏一本书。
  Future<void> saveBook(String origin, Session session, String bookId) async {
    final r = await transport.request(
      origin,
      '/eapi/user/book/${Uri.encodeComponent(bookId)}/save',
      session: session,
    );
    decode(r);
  }

  /// `/eapi/user/book/{id}/unsave` — 取消收藏。
  Future<void> unsaveBook(String origin, Session session, String bookId) async {
    final r = await transport.request(
      origin,
      '/eapi/user/book/${Uri.encodeComponent(bookId)}/unsave',
      session: session,
    );
    decode(r);
  }

  Future<Map<String, dynamic>> profile(String origin, Session session) async {
    final r = await transport.request(
      origin,
      '/eapi/user/profile',
      session: session,
    );
    return Map<String, dynamic>.from(decode(r)['user'] as Map? ?? {});
  }

  Future<String> fileUrl(String origin, Session session, Book book) async {
    if (!book.downloadable) throw const ApiException('此记录缺少下载标识，请重新搜索');
    try {
      return await _fetchFileUrl(origin, session, book);
    } catch (error) {
      // 和详情一样：分类页的书缺短 hash，先用书名回查补全再重试。
      if (error is ApiException && _isInvalidHash(error)) {
        final fixed = await _resolveBook(origin, session, book);
        if (fixed != null) return _fetchFileUrl(origin, session, fixed);
      }
      rethrow;
    }
  }

  Future<String> _fetchFileUrl(
    String origin,
    Session session,
    Book book,
  ) async {
    final r = await transport.request(
      origin,
      '/eapi/book/${Uri.encodeComponent(book.id)}/${Uri.encodeComponent(book.hash)}/file',
      session: session,
    );
    final data = decode(r);
    final file = data['file'] is Map ? data['file'] as Map : {};
    final raw = textValue(
      file['downloadLink'] ??
          data['downloadLink'] ??
          data['url'] ??
          data['link'],
    );
    if (raw.isEmpty) throw const ApiException('服务器没有返回下载地址，请稍后重试');
    final uri = Uri.parse(origin).resolve(raw);
    if (uri.scheme != 'https' || uri.host.isEmpty || uri.userInfo.isNotEmpty) {
      throw const ApiException('下载地址不是有效的安全链接');
    }
    return uri.toString();
  }

  /// `/eapi/user/book/{id}/delete` — 从账户的下载历史中移除一条记录。
  /// 只删云端的下载历史，不影响已经下载到本地的文件。
  Future<void> deleteDownloaded(
    String origin,
    Session session,
    String bookId,
  ) async {
    final r = await transport.request(
      origin,
      '/eapi/user/book/${Uri.encodeComponent(bookId)}/delete',
      session: session,
    );
    if (r.body.trim().isEmpty) return;
    final data = decode(r, requireSuccess: false);
    if (intValue(data['success']) == 1) return;
    final error = textValue(data['error'] ?? data['message']);
    if (error.isEmpty) return;
    final low = error.toLowerCase();
    if (low.contains('not authorized') ||
        low.contains('not logged') ||
        low.contains('unauthorized')) {
      throw const ApiException('登录已过期，请重新登录', needsLogin: true);
    }
    throw ApiException(
      error.length > 180 ? '${error.substring(0, 180)}…' : error,
    );
  }

  Map<String, String> downloadHeaders(String origin, Session session) => {
    'User-Agent': HttpTransport.userAgent,
    'Cookie': {
      ...transport.cookies(origin),
      'remix_userid': session.userId,
      'remix_userkey': session.userKey,
    }.entries.map((e) => '${e.key}=${e.value}').join('; '),
    'remix-userid': session.userId,
    'remix-userkey': session.userKey,
  };

  static String? _attr(String attrs, String name) =>
      RegExp('$name="([^"]*)"').firstMatch(attrs)?.group(1);

  static String _slot(String inner, String name) {
    final raw =
        RegExp(
          '<div slot="$name"[^>]*>(.*?)</div>',
          dotAll: true,
        ).firstMatch(inner)?.group(1) ??
        '';
    return plainText(raw);
  }

  /// `/category/{id}?page=N` — 官方分类书单。
  ///
  /// 分类页是服务端渲染的 HTML，书卡是 `<z-bookcard>` 自定义元素，
  /// 属性与插槽里带着完整元数据，所以能解析出和搜索接口一样的 Book。
  /// 线路没提供按分类过滤的接口（`categories[]` 实测无效）。
  Future<BookPage> categoryBooks(
    String origin,
    int categoryId,
    int page,
  ) async {
    final response = await transport.request(
      origin,
      '/category/$categoryId?page=$page',
      timeout: const Duration(seconds: 24),
    );
    final books = <Book>[];
    for (final card in RegExp(
      r'<z-bookcard([^>]*)>(.*?)</z-bookcard>',
      dotAll: true,
    ).allMatches(response.body)) {
      final attrs = card.group(1) ?? '';
      final inner = card.group(2) ?? '';
      final href = _attr(attrs, 'href') ?? '';
      final hash = RegExp(r'^/book/([^/]+)/').firstMatch(href)?.group(1) ?? '';
      final id = _attr(attrs, 'id') ?? '';
      if (hash.isEmpty || id.isEmpty) continue;
      var cover =
          RegExp(r'data-src="([^"]+)"').firstMatch(inner)?.group(1) ?? '';
      if (cover.startsWith('http://')) {
        cover = cover.replaceFirst('http://', 'https://');
      }
      books.add(
        Book.fromJson({
          'id': id,
          'hash': hash,
          'title': _slot(inner, 'title'),
          'author': _slot(inner, 'author'),
          'cover': cover,
          'extension': _attr(attrs, 'extension') ?? '',
          'filesizeString': _attr(attrs, 'filesize') ?? '',
          'year': _attr(attrs, 'year') ?? '',
          'language': _attr(attrs, 'language') ?? '',
          'publisher': _attr(attrs, 'publisher') ?? '',
          'isbn': _attr(attrs, 'isbn') ?? '',
        }),
      );
    }
    if (books.isEmpty) {
      throw const ApiException('这个分类暂时读不出书单，请稍后重试', retryable: true);
    }
    // 页面上只要出现比当前更大的页码链接，就说明还有下一页。
    // 不用数总页数，线路的分页控件经常只列相邻几页。
    var hasNext = false;
    for (final match in RegExp(
      r'/category/\d+\?page=(\d+)',
    ).allMatches(response.body)) {
      final value = int.tryParse(match.group(1) ?? '') ?? 0;
      if (value > page) {
        hasNext = true;
        break;
      }
    }
    return BookPage(books, page, hasNext ? page + 1 : page);
  }

  /// `/categories` — 官方分类清单。
  Future<List<ZlibCategory>> categories(String origin) async {
    final response = await transport.request(
      origin,
      '/categories',
      timeout: const Duration(seconds: 24),
    );
    final result = <ZlibCategory>[];
    final seen = <int>{};
    for (final match in RegExp(
      r'href="/category/(\d+)/([^"]+)"',
    ).allMatches(response.body)) {
      final id = int.tryParse(match.group(1) ?? '') ?? 0;
      if (id == 0 || !seen.add(id)) continue;
      result.add(ZlibCategory(id, Uri.decodeComponent(match.group(2) ?? '')));
    }
    if (result.isEmpty) {
      throw const ApiException('分类清单暂时读取不到，请稍后重试', retryable: true);
    }
    return result;
  }
}
