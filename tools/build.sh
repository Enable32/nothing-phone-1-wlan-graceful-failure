#!/usr/bin/env sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
DIST="$ROOT/dist"
OUTPUT="$DIST/Nothing-Phone-1-WLAN-v1.3-RECOVERY-TEST-repacked.zip"

mkdir -p "$DIST"
[ ! -e "$OUTPUT" ] || unlink "$OUTPUT"
(
    cd "$ROOT/module"
    zip -0 -X -r "$OUTPUT" .
)

sh "$ROOT/tools/verify.sh" "$OUTPUT"
