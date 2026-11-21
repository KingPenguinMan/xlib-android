import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'api.dart';
import 'domain.dart';
import 'native.dart';
import 'update.dart';

/// 首页的一个分区。
///
/// 三种来源：
/// - [categoryId] 有值：走线路的官方分类页
/// - [yearFrom] 有值：按出版年过滤的检索
/// - 否则：按 [query] 关键词检索
class HomeSection {
  final String id;
  final String title;
  final String query;
  final int? yearFrom;
  final int? categoryId;

  /// 内置分区不能被删除（热门推荐、新书上架）。
  final bool builtin;

  const HomeSection(
    this.id,
    this.title,
    this.query, {
    this.yearFrom,
    this.categoryId,
    this.builtin = false,
  });

  bool get isCategory => categoryId != null;

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'query': query,
    if (yearFrom != null) 'yearFrom': yearFrom,
    if (categoryId != null) 'categoryId': categoryId,
    if (builtin) 'builtin': true,
  };

  factory HomeSection.fromJson(Map<String, dynamic> json) {
    int? asInt(Object? value) => value is int
        ? value
        : (value is num ? value.toInt() : int.tryParse('$value'));
    return HomeSection(
      textValue(json['id']),
      textValue(json['title']),
      textValue(json['query']),
      yearFrom: asInt(json['yearFrom']),
      categoryId: asInt(json['categoryId']),
      builtin: json['builtin'] == true,
    );
  }
}

class ReaderController extends ChangeNotifier {
  final LibraryApi api;
  final NativeBridge native;
  ReaderController({LibraryApi? api, NativeBridge? native})
    : api = api ?? LibraryApi(),
      native = native ?? NativeBridge();
  String version = '';
  bool hideGroupInvite = false;
  bool hideUpdatePrompt = false;
  List<AppRelease> releases = [];
  bool releasesLoading = false;
  bool updateDownloading = false;
  double updateProgress = 0;
  bool ready = false, probing = false, automatic = true, searching = false;
  bool historyLoading = false, profileLoading = false;
  ThemeMode theme = ThemeMode.system;
  Session? session;
  String activeOrigin = '',
      directory = 'Download/Books',
      query = '',
      format = '',
      language = '';
  String searchError = '', historyError = '', profileError = '';
  String notice = '';
  int noticeId = 0, _searchGeneration = 0;
  int selectedTab = 0;
  List<RouteInfo> routes = knownHosts
      .map((h) => RouteInfo('https://$h'))
      .toList();
  List<String> recent = [];
  List<Book> bookmarks = [];
  bool bookmarksLoading = false;
  String bookmarksError = '';
  List<DownloadRecord> downloads = [];
  final Map<String, String> _downloadLinkCache = {};
  final Set<String> selectedDownloadIds = {};
  BookPage? searchPage, historyPage;
  List<Book> recommendationBooks = [];
  bool recommendationsLoading = false;
  int recommendationPage = 0, recommendationTotalPages = 1;
  bool recommendationHasMore = true;

  /// 首页分类板块：按板块 id 存书单、错误和加载状态。
  final Map<String, List<Book>> sectionBooks = {};
  final Map<String, String> sectionErrors = {};
  final Set<String> sectionLoading = {};

  /// 每个分区当前加载到第几页，以及是否还有下一页。
  final Map<String, int> sectionPages = {};
  final Map<String, bool> sectionHasMore = {};

  /// 刷新代次：刷新会 +1，正在飞的「加载更多」回来后发现代次变了就丢弃结果，
  /// 避免它把刷新后的第一页又覆盖掉。
  final Map<String, int> sectionEpoch = {};
  final _hiddenHistory = <String, Set<String>>{};
  BookPage? get visibleHistoryPage {
    final page = historyPage;
    final hidden = _hiddenHistory[session?.userId];
    if (page == null || hidden == null || hidden.isEmpty) return page;
    return BookPage(
      page.books
          .where(
            (b) =>
                !hidden.contains(b.downloadable ? b.ref : _historyIdentity(b)),
          )
          .toList(),
      page.page,
      page.totalPages,
    );
  }

  Future<void> hideHistory(Book book) async {
    final user = session?.userId;
    if (user == null) return;
    final hidden = _hiddenHistory.putIfAbsent(user, () => <String>{});
    final key = book.downloadable ? book.ref : _historyIdentity(book);
    if (!hidden.add(key)) return;
    changed();
    try {
      await persist();
    } catch (_) {
      hidden.remove(key);
      changed();
      rethrow;
    }
  }

  /// 云端删除一条下载历史，并同步在本机隐藏。
  /// 只删记录，不删已经下载到本地的文件。
  Future<void> deleteHistoryRemote(Book book) async {
    await read((o, s) => api.deleteDownloaded(o, s, book.id));
    await hideHistory(book);
  }

  /// 批量删除历史记录：[cloud] 为 true 时同时从账户里删掉。
  Future<void> deleteHistoryBatch(
    List<Book> books, {
    required bool cloud,
  }) async {
    if (cloud) {
      for (final book in books) {
        await read((o, s) => api.deleteDownloaded(o, s, book.id));
      }
    }
    for (final book in books) {
      await hideHistory(book);
    }
  }

  Map<String, dynamic> _historyCache = {};
  Map<String, dynamic>? profileData;
  Timer? _timer;
  Future<void>? _probeFuture;
  Completer<void>? _firstRoute;
  bool _disposed = false, _refreshingDownloads = false;
  final Set<String> resolvingDownloads = {};
  bool get loggedIn => session?.valid ?? false;
  String get host =>
      activeOrigin.isEmpty ? '尚未选择线路' : Uri.parse(activeOrigin).host;
  int get healthyCount => routes
      .where((r) => r.usable)
      .map((r) => r.effectiveOrigin)
      .toSet()
      .length;
  int get activeDownloads => downloads.where((d) => d.active).length;
  bool get selectingDownloads => selectedDownloadIds.isNotEmpty;
  void changed() {
    if (!_disposed) notifyListeners();
  }

  void say(String message) {
    notice = message;
    noticeId++;
    changed();
  }

  Future<void> init() async {
    try {
      final settings = await native.loadSettings();
      hideGroupInvite = settings['hideGroupInvite'] == true;
      hideUpdatePrompt = settings['hideUpdatePrompt'] == true;
      version = await native.appVersion();
      automatic = settings['automatic'] != false;
      final savedOrigin = textValue(settings['origin']);
      if (savedOrigin.isNotEmpty && trustedOrigin(Uri.parse(savedOrigin)))
        activeOrigin = savedOrigin;
      theme = ThemeMode.values.firstWhere(
        (t) => t.name == settings['theme'],
        orElse: () => ThemeMode.system,
      );
      recent = (settings['recent'] as List? ?? [])
          .map(textValue)
          .take(10)
          .toList();
      bookmarks = (settings['bookmarks'] as List? ?? [])
          .whereType<Map>()
          .map((b) => Book.fromJson(Map<String, dynamic>.from(b)))
          .toList();
      final savedSections = settings['sections'];
      sections.clear();
      if (savedSections is List) {
        sections.addAll(
          savedSections
              .whereType<Map>()
              .map((s) => HomeSection.fromJson(Map<String, dynamic>.from(s)))
              .where((s) => s.id.isNotEmpty),
        );
      }
      if (sections.isEmpty) sections.addAll(defaultSections());
      downloadedApkPath = textValue(settings['downloadedApkPath']);
      downloadedApkVersion = textValue(settings['downloadedApkVersion']);
      directory = await native.directoryLabel();
      session = await native.loadSession();
      final hidden = settings['hiddenHistory'];
      if (hidden is Map) {
        for (final entry in hidden.entries) {
          if (entry.key is String && entry.value is List)
            _hiddenHistory[entry.key as String] = (entry.value as List)
                .whereType<String>()
                .toSet();
        }
      }
      final cached = settings['historyCache'];
      if (cached is Map) {
        _historyCache = Map<String, dynamic>.from(cached);
        _restoreHistoryCache();
      }
      await refreshDownloads();
    } catch (_) {
      say('部分本地信息无法恢复，请重新登录或选择下载目录');
    }
    ready = true;
    changed();
    _timer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (activeDownloads > 0) unawaited(refreshDownloads());
    });
    final scan = probeRoutes();
    await (_firstRoute?.future ?? scan);
    if (loggedIn && healthyCount > 0) unawaited(loadProfile());
    if (loggedIn && healthyCount > 0) unawaited(loadRecommendations());
    if (loggedIn && healthyCount > 0) unawaited(loadBookmarks());
    if (loggedIn && historyPage != null && healthyCount > 0) {
      unawaited(_hydrateHistoryCovers());
    }
  }

  Future<void> persist() => native.saveSettings({
    'hideGroupInvite': hideGroupInvite,
    'hideUpdatePrompt': hideUpdatePrompt,
    'automatic': automatic,
    'origin': activeOrigin,
    'theme': theme.name,
    'recent': recent,
    'bookmarks': bookmarks.map((b) => b.toJson()).toList(),
    'hiddenHistory': _hiddenHistory.map((k, v) => MapEntry(k, v.toList())),
    'historyCache': _historyCache,
    'sections': sections.map((s) => s.toJson()).toList(),
    'downloadedApkPath': downloadedApkPath,
    'downloadedApkVersion': downloadedApkVersion,
  });
  Future<void> setTheme(ThemeMode value) async {
    theme = value;
    changed();
    await persist();
  }

  void setTab(int tab) {
    selectedTab = tab;
    changed();
    if (tab == 1 && loggedIn && historyPage == null) unawaited(loadHistory());
  }

  Future<void> cancelDownload(String id) async {
    await native.cancelDownload(id);
    await refreshDownloads();
  }

  Future<void> pauseDownload(String id) async {
    await native.pauseDownload(id);
    await refreshDownloads();
  }

  Future<void> resumeDownload(String id) async {
    await native.resumeDownload(id);
    await refreshDownloads();
  }

  void toggleDownloadSelection(String id) {
    if (!selectedDownloadIds.add(id)) selectedDownloadIds.remove(id);
    changed();
  }

  void selectAllDownloads() {
    selectedDownloadIds
      ..clear()
      ..addAll(downloads.map((d) => d.id));
    changed();
  }

  void clearDownloadSelection() {
    selectedDownloadIds.clear();
    changed();
  }

  Future<void> deleteSelectedDownloads({bool deleteFiles = false}) async {
    final ids = [...selectedDownloadIds];
    selectedDownloadIds.clear();
    for (final id in ids) {
      await native.removeRecord(id, deleteFile: deleteFiles);
    }
    await refreshDownloads();
  }

  /// 收藏 / 取消收藏。先乐观更新本地，再同步到 zlib 云端收藏，
  /// 这样同一账号在其他设备登录也能看到。云端失败会回滚本地并抛错。
  Future<void> toggleBookmark(Book book) async {
    final wasBookmarked = bookmarked(book);
    if (wasBookmarked) {
      bookmarks.removeWhere((b) => b.ref == book.ref);
    } else {
      bookmarks.insert(0, book);
    }
    changed();
    await persist();
    if (!loggedIn) return;
    try {
      await read(
        (o, s) => wasBookmarked
            ? api.unsaveBook(o, s, book.id)
            : api.saveBook(o, s, book.id),
      );
    } catch (_) {
      // 云端没同步成，回滚本地，避免本地和云端不一致。
      if (wasBookmarked) {
        bookmarks.insert(0, book);
      } else {
        bookmarks.removeWhere((b) => b.ref == book.ref);
      }
      changed();
      await persist();
      rethrow;
    }
  }

  /// 拉取 zlib 云端收藏，覆盖本地缓存（离线时仍可看上次同步的结果）。
  Future<void> loadBookmarks() async {
    if (bookmarksLoading || !loggedIn) return;
    bookmarksLoading = true;
    bookmarksError = '';
    changed();
    try {
      final all = <Book>[];
      var page = 1;
      while (true) {
        final result = await read((o, s) => api.savedBooks(o, s, page));
        all.addAll(result.books);
        if (result.books.isEmpty || result.page >= result.totalPages) break;
        page++;
      }
      bookmarks = all;
      await persist();
    } catch (e) {
      bookmarksError = '$e';
    } finally {
      bookmarksLoading = false;
      changed();
    }
  }

  bool bookmarked(Book book) => bookmarks.any((b) => b.ref == book.ref);

  /// 拉取 GitHub 上的版本历史（供「版本历史」页和更新检查用）。
  Future<void> loadReleases() async {
    if (releasesLoading) return;
    releasesLoading = true;
    changed();
    try {
      releases = await fetchReleases();
    } finally {
      releasesLoading = false;
      changed();
    }
  }

  /// 找出比当前安装版本更新的最新 release，找不到返回 null。
  AppRelease? latestUpdate() {
    for (final release in releases) {
      if (release.draft || release.prerelease) continue;
      if (isNewerVersion(release.version, version)) return release;
    }
    return null;
  }

  /// 后台下载并安装更新：进度通过 [updateProgress] 上报，可暂停 / 取消。
  StreamSubscription<List<int>>? _updateSub;
  bool updatePaused = false;
  String? downloadedApkPath;
  String? downloadedApkVersion;

  Future<void> startUpdateDownload(String url, {String? version}) async {
    if (updateDownloading) {
      say('正在下载更新，请看下方的进度条');
      return;
    }
    // 已经下载过这个版本，直接安装，不重复下载。
    if (version != null &&
        downloadedApkVersion == version &&
        downloadedApkPath != null &&
        File(downloadedApkPath!).existsSync()) {
      say('安装包已就绪，正在打开安装界面');
      final ok = await native.installApk(downloadedApkPath!);
      if (!ok) say('请在系统设置里允许本应用安装，然后重新点「立即安装」（无需重新下载）');
      return;
    }
    downloadedApkPath = null;
    downloadedApkVersion = null;
    updateDownloading = true;
    updatePaused = false;
    updateProgress = 0;
    changed();
    try {
      final dir = await native.updateDir();
      if (dir.isEmpty) throw Exception('无法获取下载目录');
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 15);
      final request = await client.getUrl(Uri.parse(url));
      request.headers.set(HttpHeaders.userAgentHeader, 'xlib-android');
      final response = await request.close();
      if (response.statusCode != 200) {
        client.close(force: true);
        throw Exception('下载失败（HTTP ${response.statusCode}）');
      }
      final total = response.contentLength;
      final file = File('${dir.replaceAll('\\', '/')}/update.apk');
      final sink = file.openWrite();
      var received = 0;
      _updateSub = response.listen(
        (chunk) {
          sink.add(chunk);
          received += chunk.length;
          if (total > 0) {
            updateProgress = (received / total).clamp(0.0, 1.0);
            changed();
          }
        },
        onDone: () async {
          await sink.close();
          client.close(force: true);
          _updateSub = null;
          updateDownloading = false;
          updatePaused = false;
          updateProgress = 1;
          changed();
          downloadedApkPath = file.path;
          if (version != null) downloadedApkVersion = version;
          unawaited(persist());
          say('安装包已下载完成，正在打开安装界面');
          final ok = await native.installApk(file.path);
          if (!ok) {
            say('请在系统设置里允许本应用安装，然后重新点「立即安装」（无需重新下载）');
          }
        },
        onError: (Object error) async {
          await sink.close();
          client.close(force: true);
          _updateSub = null;
          updateDownloading = false;
          updatePaused = false;
          changed();
          say('更新下载失败：$error');
        },
        cancelOnError: true,
      );
    } catch (error) {
      updateDownloading = false;
      updatePaused = false;
      changed();
      say('更新下载失败：$error');
    }
  }

  /// 暂停当前更新下载。
  void pauseUpdate() {
    if (!updateDownloading || updatePaused) return;
    _updateSub?.pause();
    updatePaused = true;
    changed();
  }

  /// 继续被暂停的更新下载。
  void resumeUpdate() {
    if (!updateDownloading || !updatePaused) return;
    _updateSub?.resume();
    updatePaused = false;
    changed();
  }

  /// 取消当前更新下载。
  void cancelUpdate() {
    if (!updateDownloading) return;
    _updateSub?.cancel();
    _updateSub = null;
    updateDownloading = false;
    updatePaused = false;
    updateProgress = 0;
    changed();
  }

  Future<void> removeRecent(String keyword) async {
    recent.remove(keyword);
    changed();
    await persist();
  }

  Future<void> clearRecent() async {
    recent.clear();
    changed();
    await persist();
  }

  Future<void> probeRoutes() =>
      _probeFuture ??= _probeAll().whenComplete(() => _probeFuture = null);
  Future<void> _probeAll() async {
    probing = true;
    final first = _firstRoute = Completer<void>();
    final previous = activeOrigin;
    final hosts = [...knownHosts];
    final preferred = Uri.tryParse(previous)?.host;
    if (preferred != null && hosts.remove(preferred))
      hosts.insert(0, preferred);
    routes = hosts.map((h) => RouteInfo('https://$h')).toList();
    changed();
    var cursor = 0;
    Future<void> worker() async {
      while (cursor < routes.length) {
        final index = cursor++;
        routes[index].status = RouteStatus.testing;
        routes[index].detail = '正在检测';
        changed();
        routes[index] = await api.probe(routes[index].origin);
        if (!first.isCompleted &&
            routes[index].usable &&
            (automatic ||
                routes[index].effectiveOrigin == activeOrigin ||
                routes[index].origin == activeOrigin)) {
          if (automatic) activeOrigin = routes[index].effectiveOrigin;
          first.complete();
        }
        changed();
      }
    }

    try {
      await Future.wait(List.generate(4, (_) => worker()));
      final usable = routes.where((r) => r.usable).toList()
        ..sort((a, b) => a.milliseconds.compareTo(b.milliseconds));
      if (automatic && usable.isNotEmpty)
        activeOrigin = usable.first.effectiveOrigin;
      if (!automatic) {
        for (final route in usable) {
          if (route.origin == activeOrigin)
            activeOrigin = route.effectiveOrigin;
        }
      }
      final destinations = <String>{};
      // Keep the fastest working entry for each final HTTPS origin.
      routes = [
        for (final route in usable)
          if (destinations.add(route.effectiveOrigin)) route,
        ...routes.where((route) => !route.usable),
      ];
      if (usable.isEmpty) say('暂未发现可用线路。请检查网络后重新检测，也可稍后重试');
      await persist();
    } catch (_) {
      say('线路检测未完成，请重新检测');
    } finally {
      if (!first.isCompleted) first.complete();
      probing = false;
      changed();
    }
  }

  Future<void> setAutomatic(bool enabled) async {
    automatic = enabled;
    if (enabled) {
      final good = routes.where((r) => r.usable).toList()
        ..sort((a, b) => a.milliseconds.compareTo(b.milliseconds));
      if (good.isNotEmpty) activeOrigin = good.first.effectiveOrigin;
    }
    changed();
    await persist();
  }

  Future<void> selectRoute(RouteInfo route) async {
    automatic = false;
    activeOrigin = route.effectiveOrigin;
    changed();
    await persist();
  }

  Future<void> ensureRoute() async {
    if (probing && automatic && !(_firstRoute?.isCompleted ?? true))
      await _firstRoute?.future;
    if (activeOrigin.isEmpty) throw const ApiException('请先检测并选择一条可用线路');
  }

  Future<T> read<T>(
    Future<T> Function(String origin, Session session) request,
  ) async {
    final savedSession = session;
    if (savedSession == null)
      throw const ApiException('请先登录账户', needsLogin: true);
    await ensureRoute();
    final alternatives = routes.where((r) => r.usable).toList()
      ..sort((a, b) => a.milliseconds.compareTo(b.milliseconds));
    final candidates = <String>{
      activeOrigin,
      if (automatic) ...alternatives.map((r) => r.effectiveOrigin),
    }.take(3);
    ApiException? last;
    for (final origin in candidates) {
      try {
        final value = await request(origin, savedSession);
        if (origin != activeOrigin) {
          activeOrigin = origin;
          await persist();
          say('已自动切换到 ${Uri.parse(origin).host}');
        }
        return value;
      } on ApiException catch (e) {
        if (e.needsLogin) {
          session = null;
          profileData = null;
          historyPage = null;
          await native.saveSession(null);
          changed();
          rethrow;
        }
        if (!e.retryable || !automatic) rethrow;
        last = e;
      }
    }
    throw last ?? const ApiException('没有可用线路，请重新检测', retryable: true);
  }

  /// 不需要登录态的请求：未登录也能搜索、浏览官方分类。
  Future<T> readAnon<T>(Future<T> Function(String origin) request) async {
    await ensureRoute();
    final alternatives = routes.where((r) => r.usable).toList()
      ..sort((a, b) => a.milliseconds.compareTo(b.milliseconds));
    final candidates = <String>{
      activeOrigin,
      if (automatic) ...alternatives.map((r) => r.effectiveOrigin),
    }.take(3);
    ApiException? last;
    for (final origin in candidates) {
      try {
        final value = await request(origin);
        if (origin != activeOrigin) {
          activeOrigin = origin;
          await persist();
          say('已自动切换到 ${Uri.parse(origin).host}');
        }
        return value;
      } on ApiException catch (e) {
        if (!e.retryable || !automatic) rethrow;
        last = e;
      }
    }
    throw last ?? const ApiException('没有可用线路，请重新检测', retryable: true);
  }

  Future<void> login(String email, String password) async {
    await ensureRoute();
    final s = await api.login(activeOrigin, email.trim(), password);
    await native.saveSession(s);
    session = s;
    historyPage = null;
    historyError = '';
    _restoreHistoryCache();
    changed();
    unawaited(loadProfile());
    unawaited(loadRecommendations());
  }

  Future<void> logout() async {
    await native.saveSession(null);
    session = null;
    profileData = null;
    historyPage = null;
    historyError = '';
    searchPage = null;
    changed();
  }

  void returnToRecommendations() {
    ++_searchGeneration;
    query = '';
    searchPage = null;
    searchError = '';
    searching = false;
    changed();
  }

  Future<void> search(
    String value, {
    int page = 1,
    String? fileFormat,
    String? lang,
  }) async {
    final input = value.trim();
    if (input.isEmpty) return;
    if (query != input) searchPage = null;
    query = input;
    format = fileFormat ?? format;
    language = lang ?? language;
    final generation = ++_searchGeneration;
    searching = true;
    searchError = '';
    selectedTab = 0;
    changed();
    try {
      // 未登录也能搜索：zlib 的搜索接口不需要账号。
      final result = loggedIn
          ? await read(
              (o, s) => api.search(o, s, input, page, format, language),
            )
          : await readAnon(
              (o) => api.search(o, null, input, page, format, language),
            );
      if (generation != _searchGeneration) return;
      searchPage = result;
      recent.remove(input);
      recent.insert(0, input);
      recent = recent.take(10).toList();
      await persist();
    } catch (e) {
      if (generation == _searchGeneration) searchError = '$e';
    } finally {
      if (generation == _searchGeneration) {
        searching = false;
        changed();
      }
    }
  }

  Future<Book> details(Book book) => read((o, s) => api.details(o, s, book));

  Future<void> loadRecommendations({bool refresh = false}) async {
    // 未登录也能看「热门」：走匿名搜索，首页不再是空的。
    if (recommendationsLoading) return;
    if (refresh) {
      recommendationPage = 0;
      recommendationTotalPages = 1;
      recommendationHasMore = true;
      recommendationBooks = [];
    }
    if (!recommendationHasMore) return;
    recommendationsLoading = true;
    changed();
    try {
      final requestedPage = recommendationPage + 1;
      final result = loggedIn
          ? await read((o, s) => api.search(o, s, '热门', requestedPage, '', ''))
          : await readAnon(
              (o) => api.search(o, null, '热门', requestedPage, '', ''),
            );
      final previousCount = recommendationBooks.length;
      final seen = <String>{};
      seen.addAll(recommendationBooks.map(_historyIdentity));
      recommendationBooks = [
        ...recommendationBooks,
        ...result.books.where((book) => seen.add(_historyIdentity(book))),
      ];
      // 下拉刷新时打乱第一页，刷新完能看到新顺序。
      if (refresh) {
        recommendationBooks = [...recommendationBooks]..shuffle();
      }
      recommendationPage = result.page > recommendationPage
          ? result.page
          : requestedPage;
      recommendationTotalPages = result.totalPages > 0
          ? result.totalPages
          : recommendationPage + (result.books.length >= 30 ? 1 : 0);
      recommendationHasMore =
          recommendationPage < recommendationTotalPages &&
          result.books.isNotEmpty &&
          recommendationBooks.length > previousCount;
    } catch (_) {
      // Keep the home screen usable when recommendation search is unavailable.
      recommendationHasMore = false;
    } finally {
      recommendationsLoading = false;
      changed();
    }
  }

  /// 首页分区列表，用户可增删和拖动排序，保存在设置里。
  /// 给默认初值，保证连 init() 都还没跑时页面也有内容可渲染。
  final List<HomeSection> sections = defaultSections();

  /// 线路官方分类缓存，第一次打开「添加分区」时才拉。
  List<ZlibCategory> zlibCategories = [];
  bool categoriesLoading = false;
  String categoriesError = '';

  static List<HomeSection> defaultSections() => [
    const HomeSection('popular', '热门推荐', '热门', builtin: true),
    HomeSection(
      'new',
      '新书上架',
      '',
      yearFrom: DateTime.now().year - 1,
      builtin: true,
    ),
  ];

  /// 增加一个分区（追加到末尾）。
  void addSection(HomeSection section) {
    if (sections.any((s) => s.id == section.id)) return;
    sections.add(section);
    changed();
    unawaited(persist());
    unawaited(loadSection(section));
  }

  /// 恢复首次安装时的分区顺序：热门推荐第一、新书上架第二。
  void resetSections() {
    sections
      ..clear()
      ..addAll(defaultSections());
    changed();
    unawaited(persist());
  }

  /// 删除一个分区，内置的不能删。
  void removeSection(String id) {
    final index = sections.indexWhere((s) => s.id == id);
    if (index < 0 || sections[index].builtin) return;
    sections.removeAt(index);
    sectionBooks.remove(id);
    sectionErrors.remove(id);
    sectionPages.remove(id);
    sectionHasMore.remove(id);
    sectionEpoch.remove(id);
    changed();
    unawaited(persist());
  }

  /// 拖动排序。
  void reorderSections(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= sections.length) return;
    var target = newIndex;
    if (target > oldIndex) target -= 1;
    if (target < 0 || target >= sections.length) return;
    final item = sections.removeAt(oldIndex);
    sections.insert(target, item);
    changed();
    unawaited(persist());
  }

  /// 拉取线路官方分类清单。
  Future<void> loadCategories() async {
    if (categoriesLoading || zlibCategories.isNotEmpty) return;
    categoriesLoading = true;
    categoriesError = '';
    changed();
    try {
      zlibCategories = await readAnon((o) => api.categories(o));
    } catch (error) {
      categoriesError = '$error';
    } finally {
      categoriesLoading = false;
      changed();
    }
  }

  /// 顺序加载各板块，避免一次打太多请求触发线路限流。
  /// 下拉刷新时重新拉取已经打开过的分类。
  ///
  /// 没打开过的分类不预先请求：线路对短时间内的连续检索比较敏感，
  /// 一次打五个很容易握手失败。
  Future<void> refreshLoadedSections() async {
    if (healthyCount == 0) return;
    for (final spec in sections) {
      if (!sectionBooks.containsKey(spec.id)) continue;
      await loadSection(spec);
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
  }

  /// 打乱热门推荐当前书单，纯本地、立即生效。
  void shuffleRecommendations() {
    if (recommendationBooks.length < 2) return;
    recommendationBooks = [...recommendationBooks]..shuffle();
    changed();
  }

  /// 加载（或下拉刷新）分区的第一页，会替换现有列表。
  /// 刷新可以抢占正在进行的「加载更多」，不会被加载状态挡住。
  Future<void> loadSection(HomeSection spec) {
    final epoch = (sectionEpoch[spec.id] ?? 0) + 1;
    sectionEpoch[spec.id] = epoch;
    return _loadSectionPage(spec, 1, append: false, epoch: epoch, force: true);
  }

  /// 往下滑到底时追加下一页，书单可以一直往下延伸。
  Future<void> loadMoreSection(HomeSection spec) async {
    if (sectionLoading.contains(spec.id)) return;
    if (sectionHasMore[spec.id] != true) return;
    final epoch = sectionEpoch[spec.id] ?? 0;
    final next = (sectionPages[spec.id] ?? 1) + 1;
    await _loadSectionPage(spec, next, append: true, epoch: epoch);
  }

  /// 打乱某个分区当前已加载图书的顺序。
  ///
  /// 这是纯本地操作，不走网络、不受正在进行的加载影响，
  /// 所以在任何滚动位置点「换一批」都能立刻看到变化。
  void shuffleSection(HomeSection spec) {
    final books = sectionBooks[spec.id];
    if (books == null || books.length < 2) return;
    sectionBooks[spec.id] = [...books]..shuffle();
    changed();
  }

  bool _epochStillValid(String id, int epoch) =>
      (sectionEpoch[id] ?? 0) == epoch;

  Future<void> _loadSectionPage(
    HomeSection spec,
    int page, {
    required bool append,
    required int epoch,
    bool force = false,
  }) async {
    if (!force && sectionLoading.contains(spec.id)) return;
    sectionLoading.add(spec.id);
    if (force) sectionErrors.remove(spec.id);
    changed();
    try {
      // 分区浏览不需要登录：官方分类页和搜索接口都可以匿名访问。
      Future<BookPage> load(String origin, Session? session) {
        if (spec.isCategory) {
          return api.categoryBooks(origin, spec.categoryId!, page);
        }
        return api.search(
          origin,
          session,
          spec.query,
          page,
          '',
          'chinese',
          yearFrom: spec.yearFrom,
        );
      }

      final result = loggedIn
          ? await read((o, s) => load(o, s))
          : await readAnon((o) => load(o, null));
      // 期间发生过刷新，这次「加载更多」的结果直接作废。
      if (!_epochStillValid(spec.id, epoch)) return;
      final existing = append
          ? (sectionBooks[spec.id] ?? const <Book>[])
          : const <Book>[];
      final seen = existing.map(_historyIdentity).toSet();
      final merged = <Book>[
        ...existing,
        ...result.books.where((book) => seen.add(_historyIdentity(book))),
      ];
      // 下拉刷新（重新拉第一页）时打乱顺序，保证刷新有肉眼可见的变化。
      sectionBooks[spec.id] = append ? merged : (merged..shuffle());
      sectionPages[spec.id] = result.page;
      // 分类页会明确给出「还有下一页」；搜索接口偶尔不给总页数，
      // 这时按是否返回了满页来兜底，避免只能看一页。
      final total = result.totalPages > 0
          ? result.totalPages
          : result.page + (result.books.length >= 20 ? 1 : 0);
      sectionHasMore[spec.id] = result.page < total && result.books.isNotEmpty;
    } catch (error) {
      if (!_epochStillValid(spec.id, epoch)) return;
      sectionErrors[spec.id] = '$error';
    } finally {
      // 只有当前代次能清加载状态，避免并发请求互相把状态踩掉。
      if (_epochStillValid(spec.id, epoch)) {
        sectionLoading.remove(spec.id);
        changed();
      }
    }
  }

  Future<void> loadHistory({int page = 1}) async {
    if (historyLoading || !loggedIn) return;
    final historyUser = session?.userId;
    historyLoading = true;
    historyError = '';
    changed();
    try {
      final result = await read((o, s) => api.history(o, s, page));
      if (session?.userId != historyUser) return;
      final previous = page > 1
          ? (historyPage?.books ?? const <Book>[])
          : const <Book>[];
      final byId = <String, Book>{};
      for (final book in previous) {
        byId[_historyIdentity(book)] = book;
      }
      var newBooks = 0;
      for (final book in result.books) {
        final key = _historyIdentity(book);
        final existing = byId[key];
        if (existing == null) {
          byId[key] = book;
          newBooks++;
        } else {
          // Keep the original download timestamp stable across overlapping
          // pages; later pages often repeat an item with incomplete metadata.
          byId[key] = _mergeHistoryBook(existing, book);
        }
      }
      final ordered = byId.values.toList().asMap().entries.toList()
        ..sort((a, b) {
          final timeA = _historyTime(a.value);
          final timeB = _historyTime(b.value);
          if (timeA != timeB) return timeB.compareTo(timeA);
          return a.key.compareTo(b.key);
        });
      final books = ordered.map((entry) => entry.value).toList();
      final currentPage = page > result.page ? page : result.page;
      final noNewPage = page > 1 && newBooks == 0;
      final totalPages = noNewPage
          ? currentPage
          : result.totalPages > currentPage
          ? result.totalPages
          : (result.books.length >= 30 ? currentPage + 1 : currentPage);
      historyPage = BookPage(books, currentPage, totalPages);
      _saveHistoryCache();
      unawaited(_hydrateHistoryCovers());
    } catch (e) {
      historyError = '$e';
    } finally {
      historyLoading = false;
      changed();
    }
  }

  Book _mergeHistoryBook(Book existing, Book incoming) => Book(
    id: existing.id.isNotEmpty ? existing.id : incoming.id,
    hash: existing.hash.isNotEmpty ? existing.hash : incoming.hash,
    title: existing.title.isNotEmpty ? existing.title : incoming.title,
    author: existing.author.isNotEmpty ? existing.author : incoming.author,
    cover: existing.cover.isNotEmpty ? existing.cover : incoming.cover,
    extension: existing.extension.isNotEmpty
        ? existing.extension
        : incoming.extension,
    size: existing.size.isNotEmpty ? existing.size : incoming.size,
    year: existing.year.isNotEmpty ? existing.year : incoming.year,
    language: existing.language.isNotEmpty
        ? existing.language
        : incoming.language,
    publisher: existing.publisher.isNotEmpty
        ? existing.publisher
        : incoming.publisher,
    isbn: existing.isbn.isNotEmpty ? existing.isbn : incoming.isbn,
    description: existing.description.isNotEmpty
        ? existing.description
        : incoming.description,
    date: existing.date.isNotEmpty ? existing.date : incoming.date,
    downloadedAt: existing.downloadedAt.isNotEmpty
        ? existing.downloadedAt
        : incoming.downloadedAt,
  );

  int _historyTime(Book book) {
    final raw = book.downloadedAt.trim();
    final numeric = int.tryParse(raw);
    if (numeric != null)
      return numeric < 100000000000 ? numeric * 1000 : numeric;
    final normalized = raw
        .replaceAll('/', '-')
        .replaceFirst(RegExp(r'\s+'), 'T');
    return DateTime.tryParse(normalized)?.millisecondsSinceEpoch ?? 0;
  }

  String _historyIdentity(Book book) {
    final normalizedTitle = book.title
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r'[·:：,，;；.!?！？()（）\[\]【】]'), '')
        .trim();
    if (normalizedTitle.isNotEmpty) return 'title:$normalizedTitle';
    return book.id.isNotEmpty ? 'id:${book.id}' : 'ref:${book.ref}';
  }

  Future<void> loadProfile() async {
    if (profileLoading || !loggedIn) return;
    profileLoading = true;
    profileError = '';
    changed();
    try {
      profileData = await read((o, s) => api.profile(o, s));
    } catch (e) {
      profileError = '$e';
    } finally {
      profileLoading = false;
      changed();
    }
  }

  Future<void> chooseDirectory() async {
    final result = await native.chooseDirectory();
    if (result != null) {
      directory = textValue(result['label']);
      changed();
    }
  }

  Future<void> resetDirectory() async {
    await native.resetDirectory();
    directory = await native.directoryLabel();
    changed();
  }

  Future<bool> startDownload(
    Book book, {
    required Future<void> Function(DownloadRecord) onExistingFile,
    bool refreshLink = false,
  }) async {
    if (resolvingDownloads.contains(book.id) ||
        downloads.any((d) => d.active && d.book.id == book.id)) {
      say('这本书已经在下载队列中');
      return false;
    }
    if (!loggedIn) throw const ApiException('请先登录账户', needsLogin: true);
    resolvingDownloads.add(book.id);
    changed();
    try {
      final records = await native.downloads();
      for (final item in records.where((d) => d.book.id == book.id)) {
        if (item.active || item.status == 'paused') {
          say('已有下载任务，可从侧边栏查看或继续');
          return false;
        }
      }
      for (final item in records.reversed.where(
        (d) => d.book.id == book.id && d.complete,
      )) {
        if (await native.fileAvailable(item.uri)) {
          await onExistingFile(item);
          return false;
        }
      }
      await ensureRoute();
      final s = session!;
      final origin = activeOrigin;
      // 复用本次会话内拿到的链接，避免「失败重试」重复消耗下载额度；
      // 只有明确要求刷新（refreshLink）才重新向服务器要链接。
      final cached = refreshLink ? null : _downloadLinkCache[book.ref];
      final link = cached ?? await api.fileUrl(origin, s, book);
      _downloadLinkCache[book.ref] = link;
      await native.download(book, link, api.downloadHeaders(origin, s), origin);
      await refreshDownloads();
      say('已加入下载队列，可在侧边栏「下载任务」查看');
      return true;
    } finally {
      resolvingDownloads.remove(book.id);
      changed();
    }
  }

  Future<void> refreshDownloads() async {
    if (_refreshingDownloads) return;
    _refreshingDownloads = true;
    try {
      downloads = await native.downloads();
      downloads.sort((a, b) => b.created.compareTo(a.created));
      selectedDownloadIds.removeWhere(
        (id) => !downloads.any((d) => d.id == id),
      );
      changed();
    } catch (_) {
      /* transient channel unavailability is retried on resume */
    } finally {
      _refreshingDownloads = false;
    }
  }

  void _restoreHistoryCache() {
    final key = session?.userId;
    final raw = key == null ? null : _historyCache[key];
    if (raw is! Map) return;
    try {
      // Older caches used the wrong order and treated distinct hashes as
      // separate entries. Fetch a clean first page once after upgrade.
      if (intValue(raw['sortVersion']) < 9) {
        if (key != null) {
          _historyCache.remove(key);
          unawaited(persist());
        }
        historyPage = null;
        return;
      }
      final books = (raw['books'] as List? ?? [])
          .whereType<Map>()
          .map((b) => Book.fromJson(Map<String, dynamic>.from(b)))
          .toList();
      historyPage = BookPage(
        books,
        intValue(raw['page'], 1),
        intValue(raw['totalPages'], 1),
      );
    } catch (_) {
      historyPage = null;
    }
  }

  void _saveHistoryCache() {
    final key = session?.userId;
    final page = historyPage;
    if (key == null || page == null) return;
    _historyCache[key] = {
      'sortVersion': 9,
      'page': page.page,
      'totalPages': page.totalPages,
      'books': page.books.take(100).map((b) => b.toJson()).toList(),
    };
    unawaited(persist());
  }

  Future<void> _hydrateHistoryCovers() async {
    final page = historyPage;
    if (!loggedIn || page == null) return;
    final books = [...page.books];
    var changedAny = false;
    final indexes = [
      for (var i = 0; i < books.length && i < 50; i++)
        if (books[i].cover.isEmpty && books[i].downloadable) i,
    ];
    final detailed = await Future.wait(
      indexes.map((i) async {
        try {
          return (i, await details(books[i]));
        } catch (_) {
          return (i, books[i]);
        }
      }),
    );
    if (!identical(historyPage, page)) return;
    for (final item in detailed) {
      final (i, book) = item;
      if (book.cover.isNotEmpty) {
        books[i] = books[i].withCover(book.cover);
        changedAny = true;
      }
    }
    if (changedAny) {
      historyPage = BookPage(books, page.page, page.totalPages);
      changed();
    }
    if (changedAny) _saveHistoryCache();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    api.close();
    super.dispose();
  }
}
