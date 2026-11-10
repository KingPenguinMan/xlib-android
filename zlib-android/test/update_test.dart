import 'package:bookisle/update.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final release = {
    'tag_name': 'v0.10.0',
    'assets': [
      for (final abi in ['arm64-v8a', 'armeabi-v7a'])
        {
          'name': 'z-lib-android-v0.10.0-$abi.apk',
          'browser_download_url': '$updateBase/z-lib-android-v0.10.0-$abi.apk',
        },
    ],
  };
  test('32-bit reader receives the compatible stable upgrade', () {
    final next = selectUpdate(release, '0.2.0', ['armeabi-v7a']);
    expect(next?.url, endsWith('armeabi-v7a.apk'));
  });
  test('equal, older, prerelease and incompatible updates stay hidden', () {
    for (final version in ['0.10.0', '1.0.0']) {
      expect(selectUpdate(release, version, ['arm64-v8a']), isNull);
    }
    expect(
      selectUpdate({...release, 'prerelease': true}, '0.2.0', ['arm64-v8a']),
      isNull,
    );
    expect(selectUpdate(release, '0.2.0', ['x86']), isNull);
  });
}
