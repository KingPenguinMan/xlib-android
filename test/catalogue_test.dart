import 'package:xlib/controller.dart';
import 'package:xlib/domain.dart';
import 'package:xlib/main.dart';
import 'package:xlib/screens.dart';
import 'package:xlib/weread/weread_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final size in [const Size(320, 640), const Size(760, 360)]) {
    testWidgets('Catalogue layouts fit $size and group local dates', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final books = List.generate(
        7,
        (i) => Book(
          id: '$i',
          hash: 'hash',
          title: '山茶文具店与读书笔记第$i册',
          author: '作者',
          extension: 'EPUB',
          downloadedAt: '2026-11-10 10:12',
        ),
      );
      final c = ReaderController()
        ..session = const Session('1', 'test', 'reader@example.com')
        ..historyPage = BookPage(books, 1, 1)
        ..recommendationBooks = books
        ..recommendationHasMore = false;
      addTearDown(c.dispose);
      final weread = WereadController();
      addTearDown(weread.dispose);
      for (final screen in [
        SearchScreen(controller: c, weread: weread),
        HistoryScreen(controller: c),
        ProfileScreen(controller: c),
      ]) {
        await tester.pumpWidget(
          MaterialApp(
            theme: readerTheme(Brightness.light),
            home: Scaffold(body: screen),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        if (screen is HistoryScreen)
          expect(find.text('2026年11月10日'), findsOneWidget);
      }
    });
  }
}
