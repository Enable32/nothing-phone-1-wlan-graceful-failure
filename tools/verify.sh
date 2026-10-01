#!/usr/bin/env sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
ZIP="$ROOT/dist/Nothing-Phone-1-WLAN-Graceful-Failure-v0.9.zip"

for SCRIPT in \
    "$ROOT"/module/customize.sh \
    "$ROOT"/module/post-fs-data.sh \
    "$ROOT"/module/service.sh \
    "$ROOT"/module/action.sh \
    "$ROOT"/module/boot_patch.sh \
    "$ROOT"/module/boot_patch/payload/wpss_related_rescue.sh; do
    sh -n "$SCRIPT"
done

[ -f "$ZIP" ] || {
    echo "Build the ZIP first with tools/build.sh" >&2
    exit 1
}

unzip -t "$ZIP"

for REQUIRED in \
    module.prop \
    customize.sh \
    post-fs-data.sh \
    service.sh \
    action.sh \
    boot_patch.sh \
    boot_patch/payload/wpss_related_rescue.rc \
    boot_patch/payload/wpss_related_rescue.sh \
    PATCHED_SHA256.txt \
    README.md; do
    unzip -Z1 "$ZIP" | grep -Fx "$REQUIRED" >/dev/null
done

if unzip -Z1 "$ZIP" | grep -Eq '^system/vendor/.+\.ko$'; then
    echo "Unexpected proprietary kernel module in ZIP" >&2
    exit 1
fi

sha256sum "$ZIP"
echo "Verification passed"
