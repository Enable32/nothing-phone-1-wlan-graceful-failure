#!/usr/bin/env sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
MODULE="$ROOT/module"
DIST="$ROOT/dist"
OUTPUT="$DIST/Nothing-Phone-1-WLAN-Graceful-Failure-v0.4.zip"

mkdir -p "$DIST"
rm -f "$OUTPUT"

(
    cd "$MODULE"
    zip -0 -X "$OUTPUT" \
        module.prop customize.sh service.sh action.sh PATCHED_SHA256.txt README.md
)

unzip -t "$OUTPUT"
sha256sum "$OUTPUT"

