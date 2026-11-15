/// 微信读书业务接口封装。
///
/// 迁移自 olib-mobile 的 `lib/services/weread/weread_api.dart`，保留核心接入
/// 闭环所需的接口：搜索、书籍详情、目录、阅读进度、书架同步。
/// 传输层由 dio 换成 [WereadClient]。
library;

import 'dart:io';

import 'weread_client.dart';
import 'weread_cos.dart';
import 'weread_models.dart';

class WereadApi {
  final WereadClient client;

  WereadApi(this.client);

  Future<Map<String, dynamic>> _get(
    String path, {
    Map<String, dynamic>? query,
    WereadCancel? cancel,
  }) => client.call('GET', path, query: query, cancel: cancel);

  Future<Map<String, dynamic>> _post(
    String path, {
    Map<String, dynamic>? query,
    Map<String, dynamic>? body,
    WereadCancel? cancel,
  }) => client.call(
    'POST',
    path,
    query: query,
    body: body ?? const {},
    replayable: true,
    cancel: cancel,
  );

  /// `/store/search` — 在书城搜索书籍、作者、文章等。
  ///
  /// [scope] 0=全部, 10=电子书, 16=网文, 14=听书, 6=作者, 12=全文,
  /// 13=书单, 2=公众号, 4=文章。
  /// [maxIdx] 翻页偏移，用上一页最后一条的 searchIdx。
  Future<SearchResponse> search({
    required String keyword,
    int? scope,
    int? maxIdx,
    int? count,
    WereadCancel? cancel,
  }) async {
    final data = await _get(
      '/store/search',
      query: {
        'keyword': keyword,
        'scope': scope ?? 10,
        'maxIdx': maxIdx ?? 0,
        'count': ?count,
      },
      cancel: cancel,
    );
    return SearchResponse.fromJson(data);
  }

  /// `/book/info` — 书籍基本信息。
  Future<WereadBookInfo> bookInfo(String bookId, {WereadCancel? cancel}) async {
    final data = await _get(
      '/book/info',
      query: {'bookId': bookId},
      cancel: cancel,
    );
    return WereadBookInfo.fromJson(data);
  }

  /// `/book/chapterInfos` — 章节目录。
  Future<ChapterInfoResponse> chapters(
    String bookId, {
    WereadCancel? cancel,
  }) async {
    final data = await _post(
      '/book/chapterInfos',
      body: {
        'bookIds': [bookId],
        'synckeys': [0],
        'updateTimes': [0],
        'maxfreeIdx': [0],
      },
      cancel: cancel,
    );
    final entries = data['data'];
    if (entries is! List) {
      throw const WereadException('章节目录返回的数据不完整');
    }
    final entry = entries.isNotEmpty && entries.first is Map
        ? Map<String, dynamic>.from(entries.first as Map)
        : <String, dynamic>{};
    final updated = entry['updated'];
    if (updated != null && updated is! List) {
      throw const WereadException('章节目录的格式不正确');
    }
    return ChapterInfoResponse.fromJson({
      'bookId': entry['bookId'] ?? bookId,
      'synckey': entry['synckey'] ?? 0,
      'chapterUpdateTime': entry['chapterUpdateTime'],
      'chapters': updated ?? <dynamic>[],
    });
  }

  /// `/book/getProgress` — 阅读进度。
  Future<BookProgress> progress(String bookId, {WereadCancel? cancel}) async {
    final data = await _get(
      '/book/getProgress',
      query: {'bookId': bookId},
      cancel: cancel,
    );
    return BookProgress.fromJson(data);
  }

  /// `/book/bestbookmarks` — 全书热门划线（含原文与人数，固定前 20 条）。
  ///
  /// 参数对齐 olib：chapterUid=0 表示全书，count=21 取回前 20 条。
  Future<BestBookmarksResponse> bestBookmarks(
    String bookId, {
    WereadCancel? cancel,
  }) async {
    final data = await _get(
      '/book/bestbookmarks',
      query: {
        'bookId': bookId,
        'chapterUid': 0,
        'count': 21,
        'maxIdx': 0,
        'synckey': 0,
      },
      cancel: cancel,
    );
    return BestBookmarksResponse.fromJson(data);
  }

  /// 通用 GET，用于探测未文档化的路径（例如正文接口）。
  Future<Map<String, dynamic>> rawGet(
    String path,
    Map<String, dynamic> query, {
    WereadCancel? cancel,
  }) => _get(path, query: query, cancel: cancel);

  /// `/book/chaptercontent` — 章节正文。
  ///
  /// 这是非官方文档化的路径，用于验证移动端 token 能否取到正文；
  /// 取不到时由调用方降级到「在微信读书中打开」。
  Future<Map<String, dynamic>> chapterContent(
    String bookId,
    int chapterUid, {
    WereadCancel? cancel,
  }) => _get(
    '/book/chaptercontent',
    query: {'bookId': bookId, 'chapterUid': chapterUid},
    cancel: cancel,
  );

  /// `/shelf/sync` — 同步当前用户书架。
  Future<ShelfSyncResponse> shelfSync({WereadCancel? cancel}) async {
    final data = await _get('/shelf/sync', cancel: cancel);
    return ShelfSyncResponse.fromJson(data);
  }

  /// `/shelf/add` — 把书加入书架。
  ///
  /// 请求体沿用 weread-omni 的 `shelf.add` 实现：
  /// `{albumIds: [], archiveIds: [], bookIds: [bookId]}`。
  /// 重复加入同一本书不会报错，因此可以安全重放。
  Future<void> addToShelf(String bookId, {WereadCancel? cancel}) async {
    await _post(
      '/shelf/add',
      body: {
        'albumIds': <String>[],
        'archiveIds': <String>[],
        'bookIds': [bookId],
      },
      cancel: cancel,
    );
  }

  /// `/shelf/delete` — 把书移出书架，请求体与加入一致。
  Future<void> removeFromShelf(String bookId, {WereadCancel? cancel}) async {
    await _post(
      '/shelf/delete',
      body: {
        'albumIds': <String>[],
        'archiveIds': <String>[],
        'bookIds': [bookId],
      },
      cancel: cancel,
    );
  }

  /// 导入本地书籍：申请 COS 直传凭据 → 上传文件 → 通知微信读书入库。
  ///
  /// 成功后这本书就出现在微信读书账号的书架上。流程与 weread-omni 的
  /// `import.book` 一致，接口顺序：`/cos/getcredential` → COS PUT → `/cos/notify`。
  Future<String> importBook(
    File file,
    String name, {
    WereadCancel? cancel,
    void Function(int sent, int total)? onProgress,
  }) async {
    const allowed = {'epub', 'pdf', 'mobi', 'txt', 'azw3'};
    final extension = name.contains('.')
        ? name.split('.').last.toLowerCase()
        : '';
    if (!allowed.contains(extension)) {
      throw const WereadException('只支持 EPUB、PDF、MOBI、TXT、AZW3 格式');
    }
    final size = await file.length();
    if (size <= 0) throw const WereadException('这个文件是空的，换一个试试');
    if (size > 200 * 1024 * 1024) {
      throw const WereadException('文件超过 200 MB，微信读书不接受');
    }

    final baseName = name.replaceFirst(RegExp(r'\.[^.]+$'), '');
    final credential = await _get(
      '/cos/getcredential',
      query: {'name': baseName, 'from': ''},
      cancel: cancel,
    );
    final bucket = credential['bucket']?.toString() ?? '';
    final objectName = credential['ObjectName']?.toString() ?? '';
    final response = credential['Response'];
    final keys = response is Map ? response['Credentials'] : null;
    if (!RegExp(r'^[a-zA-Z0-9-]+$').hasMatch(bucket) ||
        objectName.isEmpty ||
        objectName.startsWith('//') ||
        objectName.contains('..') ||
        keys is! Map ||
        keys['TmpSecretId'] is! String ||
        keys['TmpSecretKey'] is! String ||
        keys['Token'] is! String) {
      throw const WereadException('微信读书没有返回可用的上传凭据');
    }
    final expiry = response is Map
        ? int.tryParse('${response['ExpiredTime']}') ?? 0
        : 0;
    if (expiry <= DateTime.now().millisecondsSinceEpoch ~/ 1000) {
      throw const WereadException('上传凭据已过期，请重试');
    }
    cancel?.throwIfCancelled();
    await WereadCos.put(
      file: file,
      size: size,
      bucket: bucket,
      objectName: objectName,
      secretId: keys['TmpSecretId'] as String,
      secretKey: keys['TmpSecretKey'] as String,
      token: keys['Token'] as String,
      expiry: expiry,
      cancel: cancel,
      onProgress: onProgress,
    );
    cancel?.throwIfCancelled();
    final notification = await _post(
      '/cos/notify',
      query: {'name': name, 'path': objectName, 'cancel': '0'},
      cancel: cancel,
    );
    final bookId = notification['bookId']?.toString() ?? '';
    if (notification['status'] != 1 || bookId.isEmpty) {
      throw const WereadException(
        '文件已上传，但微信读书没能确认入库。请先去书架上看看，再决定是否重试。',
      );
    }
    return bookId;
  }
}
