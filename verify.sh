#!/bin/bash
# Canonical verification untuk SELURUH workspace companion.
#   * paket CompanionCore : build + test (butuh toolchain DEV snapshot —
#     Swift Testing tidak ada di /usr/bin/swift stock)
#   * app target           : build via xcodebuild -scheme companion
#     (target-only -target tidak resolve paket SPM → wajib scheme)
# Jalankan dari root repo: ./verify.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
TOOL=~/Library/Developer/Toolchains/swift-DEVELOPMENT-SNAPSHOT-2026-07-11-a.xctoolchain/usr/bin/swift

echo "== paket: build + test =="
cd "$ROOT/Packages/CompanionCore"
"$TOOL" build
"$TOOL" test

echo "== app: build =="
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
cd "$ROOT"
xcodebuild -project Companion.xcodeproj -scheme companion -configuration Debug build

echo "VERIFY PASS"