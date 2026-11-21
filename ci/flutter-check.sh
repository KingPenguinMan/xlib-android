#!/usr/bin/env bash
set -euo pipefail
sdk="$(mktemp -d)"
trap 'rm -rf "$sdk"' EXIT
git clone --quiet --depth 1 --branch 3.47.9 https://github.com/flutter/flutter.git "$sdk/flutter"
export PATH="$sdk/flutter/bin:$PATH"
cd "$(dirname "$0")/.."
flutter pub get --enforce-lockfile
flutter test --no-pub
