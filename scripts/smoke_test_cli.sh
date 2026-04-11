#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

swift build -c release --product myarchive-cli
BIN="$ROOT_DIR/.build/release/myarchive-cli"
TEST_DIR="$ROOT_DIR/.tmp-smoke"
rm -rf "$TEST_DIR"
mkdir -p "$TEST_DIR/input/sub"

printf 'hello from myarchive\n' > "$TEST_DIR/input/hello.txt"
head -c 65536 /dev/urandom > "$TEST_DIR/input/sub/random.bin"

"$BIN" pack "$TEST_DIR/input" -o "$TEST_DIR/test.myarc" -p secret -l normal
mkdir -p "$TEST_DIR/out"
"$BIN" unpack "$TEST_DIR/test.myarc" -d "$TEST_DIR/out" -p secret

diff -rq "$TEST_DIR/input" "$TEST_DIR/out/input"

echo "CLI smoke test passed."
