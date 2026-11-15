/// 微信读书连接与数据状态。
///
/// 对应 olib-mobile 的 `lib/providers/weread_provider.dart`，把 riverpod 的
/// StateNotifier 改成项目统一使用的 [ChangeNotifier]。
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../native.dart';
import 'weread_api.dart';
import 'weread_client.dart';
import 'weread_models.dart';

/// 扫码流程的当前阶段。
enum QrPhase { idle, loading, waiting, scanned, error }

class WereadController extends ChangeNotifier {
  WereadController({WereadClient? client})
    : client = client ?? WereadClient();

  final WereadClient client;

  bool _disposed = false;
  WereadApi? _api;
  WereadApi get api => _api ??= WereadApi(client);

  // ── 连接状态 ──
  bool checking = true;
  bool connected = false;
  String connectionError = '';

  // ── 扫码状态 ──
  QrPhase qrPhase = QrPhase.idle;
  WereadQr? qr;
  String qrMessage = '';
  WereadCancel? _qrCancel;

  // ── 搜索 ──
  String searchKeyword = '';
  List<SearchResultBook> searchBooks = [];
  bool searching = false;
  bool searchMore = false;
  String searchError = '';
  bool searchHasMore = false;
  int _searchIdx = 0;
  WereadCancel? _searchCancel;

  // ── 书架 ──
  List<ShelfBook> shelfBooks = [];
  bool shelfLoading = false;
  String shelfError = '';
  bool shelfLoaded = false;

  /// 正在提交「加入书架」的书，用于按钮置灰。
  final Set<String> addingBooks = {};

  /// 正在提交「移出书架」的书。
  final Set<String> removingBooks = {};

  /// 已在书架里的书号，用来把按钮显示成「已在书架」。
  Set<String> get shelfIds => shelfBooks.map((b) => b.bookId).toSet();

  // ── 本地导入 ──
  bool importing = false;
  double importProgress = 0;
  String importName = '';
  String importError = '';
  final NativeBridge native = NativeBridge();
  WereadCancel? _importCancel;

  void dismissImportError() {
    importError = '';
    _notify();
  }

  bool get busy => searching || shelfLoading;

  bool _started = false;

  /// 首次进入微信读书页时才初始化，避免拖慢应用启动。
  Future<void> ensureStarted() async {
    if (_started) return;
    _started = true;
    await init();
  }

  @override
  void dispose() {
    _disposed = true;
    _qrCancel?.cancel();
    _searchCancel?.cancel();
    client.close();
    super.dispose();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// 启动时检查本机是否已保存过连接。
  Future<void> init() async {
    checking = true;
    _notify();
    try {
      connected = await client.isConnected;
      connectionError = '';
    } catch (error) {
      connected = false;
      connectionError = '$error';
    }
    checking = false;
    _notify();
    if (connected) unawaited(loadShelf());
  }

  // ─────────────────────────── 扫码连接 ───────────────────────────

  Future<void> startQr() async {
    _qrCancel?.cancel();
    final cancel = WereadCancel();
    _qrCancel = cancel;
    qr = null;
    qrPhase = QrPhase.loading;
    qrMessage = '正在向微信申请二维码…';
    _notify();
    try {
      final ticket = await client.requestQr(cancel: cancel);
      if (cancel.isCancelled) return;
      qr = ticket;
      qrPhase = QrPhase.waiting;
      qrMessage = '请用微信扫一扫，并在手机上确认';
      _notify();
      unawaited(_poll(ticket, cancel));
    } catch (error) {
      if (cancel.isCancelled) return;
      qrPhase = QrPhase.error;
      qrMessage = _message(error);
      _notify();
    }
  }

  Future<void> _poll(WereadQr ticket, WereadCancel cancel) async {
    try {
      await client.waitForQr(
        ticket,
        cancel: cancel,
        onStatus: (status) {
          if (cancel.isCancelled) return;
          if (status == 'scanned') {
            qrPhase = QrPhase.scanned;
            qrMessage = '已扫码，请在微信上点击确认';
          } else if (status == 'confirmed') {
            qrPhase = QrPhase.scanned;
            qrMessage = '已确认，正在完成连接…';
          }
          _notify();
        },
      );
      if (cancel.isCancelled) return;
      connected = true;
      connectionError = '';
      qr = null;
      qrPhase = QrPhase.idle;
      qrMessage = '';
      _notify();
      await loadShelf();
    } catch (error) {
      if (cancel.isCancelled) return;
      qrPhase = QrPhase.error;
      qrMessage = _message(error);
      _notify();
    }
  }

  void cancelQr() {
    _qrCancel?.cancel();
    _qrCancel = null;
    qr = null;
    qrPhase = QrPhase.idle;
    qrMessage = '';
    _notify();
  }

  Future<void> disconnect() async {
    _qrCancel?.cancel();
    await client.disconnect();
    connected = false;
    qr = null;
    qrPhase = QrPhase.idle;
    shelfBooks = [];
    shelfLoaded = false;
    searchBooks = [];
    searchHasMore = false;
    _notify();
  }

  /// 导出当前连接信息，供换机 / 重装后免扫码恢复。
  Future<String?> exportConnection() => client.exportSession();

  /// 从连接信息恢复登录。成功会直接进书架，失败把错误抛给界面。
  Future<void> importConnection(String raw) async {
    await client.importSession(raw);
    _qrCancel?.cancel();
    _qrCancel = null;
    connected = true;
    connectionError = '';
    qr = null;
    qrPhase = QrPhase.idle;
    qrMessage = '';
    _notify();
    unawaited(loadShelf());
  }

  // ─────────────────────────── 搜索 ───────────────────────────

  Future<void> search(String keyword) async {
    final text = keyword.trim();
    if (text.isEmpty) return;
    _searchCancel?.cancel();
    final cancel = WereadCancel();
    _searchCancel = cancel;
    searchKeyword = text;
    searchBooks = [];
    searchHasMore = false;
    searchError = '';
    searching = true;
    _searchIdx = 0;
    _notify();
    try {
      final page = await api.search(keyword: text, cancel: cancel);
      if (cancel.isCancelled) return;
      final books = page.results.expand((group) => group.books).toList();
      searchBooks = books;
      searchHasMore = page.hasMoreResults;
      _searchIdx = books.isEmpty ? 0 : books.last.searchIdx;
    } catch (error) {
      if (cancel.isCancelled) return;
      searchError = _message(error);
      if (_needsConnect(error)) await _markDisconnected();
    }
    searching = false;
    _notify();
  }

  Future<void> loadMoreSearch() async {
    if (searching || searchMore || !searchHasMore) return;
    final cancel = WereadCancel();
    _searchCancel = cancel;
    searchMore = true;
    _notify();
    try {
      final page = await api.search(
        keyword: searchKeyword,
        maxIdx: _searchIdx,
        cancel: cancel,
      );
      if (cancel.isCancelled) return;
      final books = page.results.expand((group) => group.books).toList();
      final known = searchBooks.map((b) => b.bookInfo.bookId).toSet();
      final fresh = books
          .where((b) => !known.contains(b.bookInfo.bookId))
          .toList();
      searchBooks = [...searchBooks, ...fresh];
      searchHasMore = page.hasMoreResults && fresh.isNotEmpty;
      if (fresh.isNotEmpty) _searchIdx = fresh.last.searchIdx;
    } catch (error) {
      if (cancel.isCancelled) return;
      searchError = _message(error);
    }
    searchMore = false;
    _notify();
  }

  // ─────────────────────────── 书架 ───────────────────────────

  Future<void> loadShelf() async {
    if (shelfLoading) return;
    shelfLoading = true;
    shelfError = '';
    _notify();
    try {
      final shelf = await api.shelfSync();
      shelfBooks = shelf.books;
      shelfLoaded = true;
    } catch (error) {
      shelfError = _message(error);
      if (_needsConnect(error)) await _markDisconnected();
    }
    shelfLoading = false;
    _notify();
  }

  /// 把书加入微信读书书架，成功后重新同步书架。
  Future<void> addToShelf(String bookId) async {
    if (addingBooks.contains(bookId)) return;
    addingBooks.add(bookId);
    _notify();
    try {
      await api.addToShelf(bookId);
      await loadShelf();
    } finally {
      addingBooks.remove(bookId);
      _notify();
    }
  }

  /// 把书移出微信读书书架。先本地移除再同步，避免等待期间列表不动。
  Future<void> removeFromShelf(String bookId) async {
    if (removingBooks.contains(bookId)) return;
    removingBooks.add(bookId);
    _notify();
    try {
      await api.removeFromShelf(bookId);
      shelfBooks = shelfBooks.where((b) => b.bookId != bookId).toList();
      _notify();
      await loadShelf();
    } finally {
      removingBooks.remove(bookId);
      _notify();
    }
  }

  void cancelImport() {
    _importCancel?.cancel();
  }

  /// 选本地文件并上传到微信读书书架。
  ///
  /// 返回导入成功后的书号；用户取消选择时返回 null。
  Future<String?> pickAndImport() async {
    if (importing) return null;
    final picked = await native.pickBookFile();
    if (picked == null) return null;
    final file = File(picked.path);
    final cancel = WereadCancel();
    _importCancel = cancel;
    importing = true;
    importProgress = 0;
    importName = picked.name;
    importError = '';
    _notify();
    var lastNotified = 0.0;
    try {
      final bookId = await api.importBook(
        file,
        picked.name,
        cancel: cancel,
        onProgress: (sent, total) {
          if (total <= 0) return;
          final value = sent / total;
          // 大文件每块都重建界面会卡，2% 刷一次足够。
          if (value - lastNotified < 0.02 && value < 1) return;
          lastNotified = value;
          importProgress = value;
          _notify();
        },
      );
      await loadShelf();
      return bookId;
    } catch (error) {
      importError = _message(error);
      rethrow;
    } finally {
      importing = false;
      importProgress = 0;
      _importCancel = null;
      _notify();
      // 缓存里的临时副本用完就删。
      unawaited(() async {
        try {
          await file.delete();
        } catch (_) {}
      }());
    }
  }

  Future<void> _markDisconnected() async {
    connected = false;
    await client.disconnect().catchError((_) {});
  }

  bool _needsConnect(Object error) =>
      error is WereadException && error.needsConnect;

  String _message(Object error) =>
      error is WereadException ? error.message : '$error';
}
