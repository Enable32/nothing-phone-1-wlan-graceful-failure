#!/usr/bin/env sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
MODULE="$ROOT/module"
DIST="$ROOT/dist"
OUTPUT="$DIST/Nothing-Phone-1-WLAN-Graceful-Failure-v0.9.zip"

mkdir -p "$DIST"
[ ! -e "$OUTPUT" ] || unlink "$OUTPUT"

(
    cd "$MODULE"
    zip -0 -X "$OUTPUT" \
        module.prop \
        customize.sh \
        post-fs-data.sh \
        service.sh \
        action.sh \
        boot_patch.sh \
        boot_patch/payload/wpss_related_rescue.rc \
        boot_patch/payload/wpss_related_rescue.sh \
        PATCHED_SHA256.txt \
        README.md
)

unzip -t "$OUTPUT"
sha256sum "$OUTPUT"
