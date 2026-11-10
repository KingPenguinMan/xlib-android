import 'package:bookisle/controller.dart';
import 'package:bookisle/domain.dart';
import 'package:bookisle/screens.dart';
import 'package:bookisle/preview_loader.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'search_download_test.dart' show MemoryBridge;

class LocalController extends ReaderController {
  LocalController() : super(native: MemoryBridge());

  @override
  Future<Book> details(Book book) async => book;

  @override
  Future<void> ensureRoute() async {}
}

void main() {
  for (final size in [const Size(360, 740), const Size(740, 360)]) {
    testWidgets('收藏详情和长标题在 ${size.width} 宽度下可操作', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final c = LocalController();
      final book = Book(
        id: '42',
        hash: 'abc',
        extension: 'EPUB',
        title: '残雪作品最全集30册' * 14,
      );
      await c.toggleBookmark(book);
      await tester.pumpWidget(MaterialApp(home: BookmarksPage(controller: c)));
      await tester.tap(find.text(book.title).first);
      await tester.pumpAndSettle();
      final detail = find.descendant(
        of: find.byType(BookDetailsSheet),
        matching: find.byWidgetPredicate(
          (w) => w is Text && w.data == book.title && w.style?.fontSize == 20,
        ),
      );
      expect(tester.widget<Text>(detail).maxLines, 2);
      await tester.tap(find.text('展开完整书名'));
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(detail).maxLines, isNull);
      await tester.ensureVisible(find.text('收起书名'));
      await tester.tap(find.text('收起书名'));
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(detail).maxLines, 2);
      await tester.ensureVisible(find.text('在线预览'));
      await tester.tap(find.text('在线预览'));
      await tester.pumpAndSettle();
      expect(find.byType(PreviewLoader), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
      await tester.pageBack();
      await tester.pumpAndSettle();
      Navigator.of(tester.element(detail)).pop();
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('取消收藏'));
      await tester.pumpAndSettle();
      expect(find.textContaining('还没有收藏'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
