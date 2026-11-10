import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'api.dart';
import 'domain.dart';
import 'native.dart';

class ReaderController extends ChangeNotifier {
  final LibraryApi api;
  final NativeBridge native;
  ReaderController({LibraryApi? api, NativeBridge? native})
    : api = api ?? LibraryApi(),
      native = native ?? NativeBridge();
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
  List<DownloadRecord> downloads = [];
  final Set<String> selectedDownloadIds = {};
  BookPage? searchPage, historyPage;
  List<Book> recommendationBooks = [];
  bool recommendationsLoading = false;
  int recommendationPage = 0, recommendationTotalPages = 1;
  bool recommendationHasMore = true;
  Map<String, dynamic> _historyCache = {};
  Map<String, dynamic>? profileData;
  Timer? _timer;
  Future<void>? _probeFuture;
  bool _disposed = false, _refreshingDownloads = false;
  final Set<String> resolvingDownloads = {};
  bool get loggedIn => session?.valid ?? false;
  String get host =>
      activeOrigin.isEmpty ? '尚未选择线路' : Uri.parse(activeOrigin).host;
  int get healthyCount => routes.where((r) => r.usable).length;
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
      directory = await native.directoryLabel();
      session = await native.loadSession();
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
    await probeRoutes();
    if (loggedIn && healthyCount > 0) unawaited(loadProfile());
    if (loggedIn && healthyCount > 0) unawaited(loadRecommendations());
    if (loggedIn && historyPage != null && healthyCount > 0) {
      unawaited(_hydrateHistoryCovers());
    }
  }

  Future<void> persist() => native.saveSettings({
    'automatic': automatic,
    'origin': activeOrigin,
    'theme': theme.name,
    'recent': recent,
    'bookmarks': bookmarks.map((b) => b.toJson()).toList(),
    'historyCache': _historyCache,
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

  Future<void> toggleBookmark(Book book) async {
    if (bookmarked(book)) {
      bookmarks.removeWhere((b) => b.ref == book.ref);
    } else {
      bookmarks.insert(0, book);
    }
    changed();
    await persist();
  }

  bool bookmarked(Book book) => bookmarks.any((b) => b.ref == book.ref);
  Future<void> clearRecent() async {
    recent.clear();
    changed();
    await persist();
  }

  Future<void> probeRoutes() =>
      _probeFuture ??= _probeAll().whenComplete(() => _probeFuture = null);
  Future<void> _probeAll() async {
    probing = true;
    routes = knownHosts.map((h) => RouteInfo('https://$h')).toList();
    changed();
    var cursor = 0;
    Future<void> worker() async {
      while (cursor < routes.length) {
        final index = cursor++;
        routes[index].status = RouteStatus.testing;
        routes[index].detail = '正在检测';
        changed();
        routes[index] = await api.probe(routes[index].origin);
        if (automatic && activeOrigin.isEmpty && routes[index].usable)
          activeOrigin = routes[index].effectiveOrigin;
        changed();
      }
    }

    try {
      await Future.wait(List.generate(4, (_) => worker()));
      final usable = routes.where((r) => r.usable).toList()
        ..sort((a, b) => a.milliseconds.compareTo(b.milliseconds));
      if (automatic && usable.isNotEmpty)
        activeOrigin = usable.first.effectiveOrigin;
      if (usable.isEmpty) say('暂未发现可用线路。请检查网络后重新检测，也可稍后重试');
      await persist();
    } catch (_) {
      say('线路检测未完成，请重新检测');
    } finally {
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
    if (activeOrigin.isEmpty && probing) await _probeFuture;
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

  Future<void> search(
    String value, {
    int page = 1,
    String? fileFormat,
    String? lang,
  }) async {
    final input = value.trim();
    if (input.isEmpty) return;
    query = input;
    format = fileFormat ?? format;
    language = lang ?? language;
    final generation = ++_searchGeneration;
    searching = true;
    searchError = '';
    selectedTab = 0;
    changed();
    try {
      final result = await read(
        (o, s) => api.search(o, s, input, page, format, language),
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
    if (!loggedIn || recommendationsLoading) return;
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
      final result = await read(
        (o, s) => api.search(o, s, '热门', requestedPage, '', ''),
      );
      final previousCount = recommendationBooks.length;
      final seen = <String>{};
      seen.addAll(recommendationBooks.map(_historyIdentity));
      recommendationBooks = [
        ...recommendationBooks,
        ...result.books.where((book) => seen.add(_historyIdentity(book))),
      ];
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

  Future<void> loadHistory({int page = 1}) async {
    if (historyLoading || !loggedIn) return;
    historyLoading = true;
    historyError = '';
    changed();
    try {
      final result = await read((o, s) => api.history(o, s, page));
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

  Future<void> startDownload(Book book) async {
    if (resolvingDownloads.contains(book.ref) ||
        downloads.any((d) => d.active && d.book.ref == book.ref)) {
      say('这本书已经在下载队列中');
      return;
    }
    if (!loggedIn) throw const ApiException('请先登录账户', needsLogin: true);
    resolvingDownloads.add(book.ref);
    changed();
    try {
      await ensureRoute();
      final s = session!;
      final origin = activeOrigin;
      final link = await api.fileUrl(origin, s, book);
      await native.download(book, link, api.downloadHeaders(origin, s), origin);
      await refreshDownloads();
      say('已加入下载队列，可在「下载」查看进度');
    } finally {
      resolvingDownloads.remove(book.ref);
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
    for (final item in detailed) {
      final (i, book) = item;
      if (book.cover.isNotEmpty) {
        books[i] = book;
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
