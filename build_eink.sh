#!/usr/bin/env bash
# 构建墨水屏版 APK：
#   1) 临时在 Manifest 关闭 Impeller（回退 Skia，兼容弱 GPU）
#   2) 用 --dart-define=EINK=true 打开黑白主题与零动画
#   3) 构建完还原 Manifest，保证普通版仍是默认配置
set -e

cd "$(dirname "$0")"

MANIFEST=android/app/src/main/AndroidManifest.xml
cp "$MANIFEST" "$MANIFEST.bak"
trap 'mv -f "$MANIFEST.bak" "$MANIFEST"' EXIT

python - <<'PY'
p = 'android/app/src/main/AndroidManifest.xml'
s = open(p, encoding='utf-8').read()
anchor = '        android:icon="@drawable/xlib_logo">'
add = (anchor + '\n'
       '        <meta-data\n'
       '            android:name="io.flutter.embedding.android.EnableImpeller"\n'
       '            android:value="false" />')
if 'EnableImpeller' not in s:
    s = s.replace(anchor, add, 1)
    open(p, 'w', encoding='utf-8').write(s)
    print('Impeller 已临时关闭')
PY

flutter build apk --release --target-platform android-arm64 --dart-define=EINK=true
cp build/app/outputs/flutter-apk/app-release.apk ../dist/xlib-kindle-v0.3.0-arm64-v8a.apk

flutter build apk --release --target-platform android-arm --dart-define=EINK=true
cp build/app/outputs/flutter-apk/app-release.apk ../dist/xlib-kindle-v0.3.0-armeabi-v7a.apk

echo "墨水屏版构建完成，Manifest 将自动还原"
