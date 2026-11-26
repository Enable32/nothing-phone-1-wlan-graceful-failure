#!/usr/bin/env sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
ZIP="${1:-$ROOT/dist/Nothing-Phone-1-WLAN-v1.4-UI-RECOVERY-TEST.zip}"

for SCRIPT in \
    "$ROOT"/module/customize.sh \
    "$ROOT"/module/post-fs-data.sh \
    "$ROOT"/module/service.sh \
    "$ROOT"/module/action.sh \
    "$ROOT"/module/boot_patch.sh \
    "$ROOT"/module/boot_patch/payload/wpss_related_rescue.sh \
    "$ROOT"/module/wifi_recover.sh \
    "$ROOT"/module/lib/*.sh; do
    sh -n "$SCRIPT"
done

[ -f "$ZIP" ] || {
    echo "Archive missing: $ZIP" >&2
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
    README.md \
    driver_patch.json \
    source/driver_patch.json \
    source/patch_driver.py \
    source/build_driver.py \
    source/test_driver.py \
    source/test_results.json \
    source/packaging_results.json \
    source/userspace_test_results.json \
    wifi_recover.sh \
    lib/action_menu.sh \
    lib/volume_keys.sh \
    lib/volume_filter.sh \
    lib/wifi_recovery.sh \
    lib/fresh_scans.awk; do
    unzip -Z1 "$ZIP" | grep -Fx "$REQUIRED" >/dev/null
done

if unzip -Z1 "$ZIP" | grep -Eq '\.(ko|img)$'; then
    echo "Unexpected proprietary kernel module or boot image in ZIP" >&2
    exit 1
fi

if [ "$#" -eq 0 ]; then
    (cd "$ROOT/dist" && sha256sum -c SHA256SUMS)
fi
sha256sum "$ZIP"
echo "Archive verification passed; no device or hardware test was run."
