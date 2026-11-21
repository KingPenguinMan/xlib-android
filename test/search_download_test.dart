import 'package:xlib/controller.dart';
import 'package:xlib/domain.dart';
import 'package:xlib/native.dart';
import 'package:xlib/screens.dart';
import 'package:xlib/weread/weread_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const book = Book(id: '1', hash: 'abc', title: '试读');

class MemoryBridge extends NativeBridge {
  List<DownloadRecord> records = [];
  Map<String, dynamic> settings = {};
  @override
  Future<void> saveSettings(Map<String, dynamic> data) async {
    settings = data;
  }

  @override
  Future<List<DownloadRecord>> downloads() async => records;
  @override
  Future<bool> fileAvailable(String uri) async => true;
}

void main() {
  testWidgets('search history appears only inside dedicated route', (
    tester,
  ) async {
    final c = ReaderController(native: MemoryBridge())..recent = ['测试关键词'];
    final weread = WereadController();
    addTearDown(weread.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: SearchScreen(controller: c, weread: weread)),
      ),
    );
    expect(find.text('测试关键词'), findsNothing);
    await tester.tap(find.text('搜书名、作者或关键词'));
    await tester.pumpAndSettle();
    expect(find.text('搜索历史'), findsOneWidget);
    expect(find.text('测试关键词'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('测试关键词'), findsNothing);
    c.dispose();
  });
  test(
    'history removal is account-local and survives page replacement',
    () async {
      final native = MemoryBridge();
      final c = ReaderController(native: native)
        ..session = const Session('a', 'k', '')
        ..historyPage = const BookPage([book], 1, 2);
      await c.hideHistory(book);
      c.historyPage = const BookPage([book], 2, 2);
      expect(c.visibleHistoryPage!.books, isEmpty);
      expect(native.settings['hiddenHistory']['a'], contains(book.ref));
      c.session = const Session('b', 'k', '');
      expect(c.visibleHistoryPage!.books, [book]);
      c.dispose();
    },
  );
  test('completed file prompts before resolving a URL and paused task blocks duplicates', () async {
    final bridge = MemoryBridge();
    final c = ReaderController(native: bridge)
      ..session = const Session('a', 'k', '');
    for (final status in ['complete', 'paused']) {
      bridge.records = [
        DownloadRecord(
          id: 'd',
          title: '试读',
          status: status,
          uri: 'content://file',
          error: '',
          fileName: 'book.pdf',
          received: 1,
          total: 1,
          created: 1,
          book: book,
        ),
      ];
      var prompts = 0;
      expect(
        await c.startDownload(
          const Book(id: '1', hash: 'different-route-hash', title: '试读'),
          onExistingFile: (_) async {
            prompts++;
          },
        ),
        isFalse,
      );
      expect(prompts, status == 'complete' ? 1 : 0);
    }
    c.dispose();
  });
}
