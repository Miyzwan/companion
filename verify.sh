#!/bin/bash
# Canonical verification untuk companion.
# `swift test` butuh toolchain DEV snapshot (Swift Testing tidak ada di
# /usr/bin/swift stock) — script ini membungkus build + test dengan toolchain
# yang benar. Jalankan: ./verify.sh  (dari root repo)
set -euo pipefail
TOOL=~/Library/Developer/Toolchains/swift-DEVELOPMENT-SNAPSHOT-2026-07-11-a.xctoolchain/usr/bin/swift
cd "$(dirname "$0")/Packages/CompanionCore"
"$TOOL" build
"$TOOL" test
echo "VERIFY PASS"
