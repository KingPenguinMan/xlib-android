import 'package:bookisle/reading_invite.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final size in [const Size(360, 640), const Size(720, 360)]) {
    testWidgets('Invite fits $size and returns the selected action', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      InviteChoice? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await showDialog<InviteChoice>(
                    context: context,
                    builder: (_) => const ReadingInvite(),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      for (final hide in [true, false]) {
        for (final action in {'暂不加入': false, '加入 QQ 群': true}.entries) {
          await tester.tap(find.text('open'));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          final cover = tester.getRect(find.byType(Image));
          final title = tester.getRect(find.text('一起读书，一起学习'));
          if (size.width > size.height) {
            expect(cover.right, lessThanOrEqualTo(title.left));
          } else {
            expect(cover.bottom, lessThanOrEqualTo(title.top));
          }
          for (final expected in (hide ? [true] : [true, false])) {
            await tester.tap(find.text('不再弹出此邀请'));
            await tester.pumpAndSettle();
            expect(find.byType(ReadingInvite), findsOneWidget);
            expect(
              tester.widget<Checkbox>(find.byType(Checkbox)).value,
              expected,
            );
          }
          await tester.tap(find.text(action.key));
          await tester.pumpAndSettle();
          expect(result, (join: action.value, hide: hide));
          expect(find.byType(ReadingInvite), findsNothing);
        }
      }
    });
  }
}
