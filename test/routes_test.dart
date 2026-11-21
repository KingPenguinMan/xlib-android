import 'package:xlib/api.dart';
import 'package:xlib/controller.dart';
import 'package:xlib/domain.dart';
import 'package:xlib/native.dart';
import 'package:flutter_test/flutter_test.dart';

class ProbeApi extends LibraryApi {
  @override
  Future<RouteInfo> probe(String origin) async {
    final route = RouteInfo(origin, status: RouteStatus.failed);
    if ([
      'https://zliba.ru',
      'https://z-lib.by',
      'https://z-library.ec',
    ].contains(origin)) {
      route.status = RouteStatus.healthy;
      route.resolvedOrigin = origin.endsWith('.ru')
          ? 'https://z-lib.by'
          : origin;
      route.milliseconds = origin.endsWith('.ru') ? 200 : 50;
    }
    return route;
  }
}

class Settings extends NativeBridge {
  @override
  Future<void> saveSettings(Map<String, dynamic> data) async {}
}

void main() {
  test('verified HTTPS destination has exact hostname trust', () {
    expect(
      trustedOrigin(Uri.parse('https://z-lib.by/eapi/info/domains')),
      isTrue,
    );
    for (final url in [
      'http://z-lib.by',
      'https://x.z-lib.by',
      'https://z-lib.by.example.org',
      'https://z-lib.by:8443',
    ]) {
      expect(trustedOrigin(Uri.parse(url)), isFalse);
    }
  });
  test(
    'redirect alias counts once and a pinned route follows its destination',
    () async {
      final c = ReaderController(api: ProbeApi(), native: Settings())
        ..automatic = false
        ..activeOrigin = 'https://zliba.ru';
      await c.probeRoutes();
      expect(c.healthyCount, 2);
      expect(c.routes.where((r) => r.usable), hasLength(2));
      expect(c.activeOrigin, 'https://z-lib.by');
      expect(c.automatic, isFalse);
      c.dispose();
    },
  );
}
