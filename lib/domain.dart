import 'package:html/parser.dart' as html;

const knownHosts = <String>[
  'z-lib.by',
  'z-library.sk',
  'z-lib.gd',
  'z-lib.gl',
  'z-library.ec',
  'zlib.bz',
  'article.sk',
  'articles.sk',
  '1lib.sk',
  'z-lib.fm',
  'z-lib.sk',
  'zliba.ru',
];

bool trustedOrigin(Uri uri) =>
    uri.scheme == 'https' &&
    uri.userInfo.isEmpty &&
    (uri.port == 0 || uri.port == 443) &&
    (knownHosts.contains(uri.host) ||
        knownHosts.any(
          (host) =>
              host != 'z-lib.by' &&
              host != 'z-library.sk' &&
              uri.host.endsWith('.$host'),
        ));

String textValue(dynamic value) => value == null ? '' : '$value';
int intValue(dynamic value, [int fallback = 0]) =>
    int.tryParse(textValue(value)) ?? fallback;
String plainText(dynamic value) =>
    html
        .parseFragment(textValue(value).replaceAll(RegExp(r'<br\s*/?>'), '\n'))
        .text
        ?.trim() ??
    '';
String fileSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

String safeFileName(String title, String extension) {
  var name = title.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), '_').trim();
  if (name.isEmpty) name = '未命名图书';
  if (name.runes.length > 90) name = String.fromCharCodes(name.runes.take(90));
  final ext = extension.toLowerCase().replaceAll(RegExp('[^a-z0-9]'), '');
  return '$name.${ext.isEmpty ? 'bin' : ext}';
}

class Book {
  final String id,
      hash,
      title,
      author,
      cover,
      extension,
      size,
      year,
      language,
      publisher,
      isbn,
      description,
      date,
      downloadedAt;
  DateTime? get localDownloadTime {
    final raw = downloadedAt.trim();
    final timestamp = int.tryParse(raw);
    if (timestamp == null)
      return DateTime.tryParse(
        raw.replaceAll('/', '-').replaceFirst(RegExp(r'\s+'), 'T'),
      )?.toLocal();
    final millis = timestamp < 100000000000 ? timestamp * 1000 : timestamp;
    return millis.abs() > 8640000000000000
        ? null
        : DateTime.fromMillisecondsSinceEpoch(millis);
  }

  const Book({
    required this.id,
    required this.hash,
    required this.title,
    this.author = '',
    this.cover = '',
    this.extension = '',
    this.size = '',
    this.year = '',
    this.language = '',
    this.publisher = '',
    this.isbn = '',
    this.description = '',
    this.date = '',
    this.downloadedAt = '',
  });
  String get ref => '$id:$hash';
  bool get downloadable => id.isNotEmpty && hash.isNotEmpty;
  Book withCover(String value) => Book(
    id: id,
    hash: hash,
    title: title,
    author: author,
    cover: value,
    extension: extension,
    size: size,
    year: year,
    language: language,
    publisher: publisher,
    isbn: isbn,
    description: description,
    date: date,
    downloadedAt: downloadedAt,
  );
  factory Book.fromJson(Map<String, dynamic> j) => Book(
    id: textValue(j['id']),
    hash: textValue(j['hash']),
    title: plainText(j['title']).isEmpty ? '未命名图书' : plainText(j['title']),
    author: plainText(j['author']),
    cover: textValue(
      j['cover'] ??
          j['cover_url'] ??
          j['coverUrl'] ??
          j['image'] ??
          j['image_url'] ??
          j['imageUrl'],
    ),
    extension: textValue(j['extension']).toUpperCase(),
    size: textValue(j['filesizeString']).isNotEmpty
        ? textValue(j['filesizeString'])
        : fileSize(intValue(j['filesize'])),
    year: textValue(j['year']),
    language: textValue(j['language']),
    publisher: plainText(j['publisher']),
    isbn: textValue(j['identifier'] ?? j['isbn']),
    description: plainText(j['description']),
    date: textValue(j['date']),
    // The history endpoint calls the download timestamp `date` on some
    // mirrors, while newer mirrors use `downloaded_at`.
    downloadedAt: textValue(
      j['downloaded_at'] ??
          j['downloadedAt'] ??
          j['download_date'] ??
          j['date_download'] ??
          j['dateDownload'] ??
          j['date'],
    ),
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'hash': hash,
    'title': title,
    'author': author,
    'cover': cover,
    'extension': extension,
    'filesizeString': size,
    'year': year,
    'language': language,
    'publisher': publisher,
    'identifier': isbn,
    'description': description,
    'date': date,
    'downloaded_at': downloadedAt,
  };
}

class BookPage {
  final List<Book> books;
  final int page, totalPages;
  const BookPage(this.books, this.page, this.totalPages);
  factory BookPage.fromJson(Map<String, dynamic> j, int requested) {
    final p = j['pagination'] is Map ? j['pagination'] as Map : {};
    final current = intValue(
      p['current'] ?? p['current_page'] ?? p['page'],
      requested,
    );
    final total = intValue(p['total_pages'] ?? p['totalPages'] ?? p['pages']);
    return BookPage(
      (j['books'] as List? ?? [])
          .whereType<Map>()
          .map((b) => Book.fromJson(Map<String, dynamic>.from(b)))
          .toList(),
      current > 0 ? current : requested,
      total,
    );
  }
}

class Session {
  final String userId, userKey, email;
  const Session(this.userId, this.userKey, this.email);
  bool get valid => userId.isNotEmpty && userKey.isNotEmpty;
  Map<String, dynamic> toJson() => {
    'userId': userId,
    'userKey': userKey,
    'email': email,
  };
  factory Session.fromJson(Map<String, dynamic> j) => Session(
    textValue(j['userId']),
    textValue(j['userKey']),
    textValue(j['email']),
  );
}

enum RouteStatus { waiting, testing, healthy, blocked, timeout, failed }

class RouteInfo {
  final String origin;
  RouteStatus status;
  String detail;
  int milliseconds;
  String? resolvedOrigin;
  RouteInfo(
    this.origin, {
    this.status = RouteStatus.waiting,
    this.detail = '尚未检测',
    this.milliseconds = 0,
    this.resolvedOrigin,
  });
  String get host => Uri.parse(origin).host;
  bool get usable => status == RouteStatus.healthy;
  String get effectiveOrigin => resolvedOrigin ?? origin;
}

class DownloadRecord {
  final String id, title, status, uri, error, fileName;
  final int received, total, created;
  final Book book;
  const DownloadRecord({
    required this.id,
    required this.title,
    required this.status,
    required this.uri,
    required this.error,
    required this.fileName,
    required this.received,
    required this.total,
    required this.created,
    required this.book,
  });
  bool get active => status == 'running' || status == 'queued';
  bool get complete => status == 'complete';
  double? get progress =>
      total > 0 ? (received / total).clamp(0, 1).toDouble() : null;
  factory DownloadRecord.fromJson(Map<String, dynamic> j) => DownloadRecord(
    id: textValue(j['id']),
    title: textValue(j['title']),
    status: textValue(j['status']),
    uri: textValue(j['uri']),
    error: textValue(j['error']),
    fileName: textValue(j['fileName']),
    received: intValue(j['received']),
    total: intValue(j['total']),
    created: intValue(j['created']),
    book: Book.fromJson(Map<String, dynamic>.from(j['book'] as Map? ?? {})),
  );
}
