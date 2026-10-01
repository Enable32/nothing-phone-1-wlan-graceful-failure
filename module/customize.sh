#!/system/bin/sh

EXPECTED_BUILD="2509261631"

TOP_TARGET="${TOP_TARGET_OVERRIDE:-/vendor/lib/modules/qca_cld3_wlan.ko}"
GKI_TARGET="${GKI_TARGET_OVERRIDE:-/vendor/lib/modules/5.4-gki/qca_cld3_wlan.ko}"
TOP_PATCHED="$MODPATH/system/vendor/lib/modules/qca_cld3_wlan.ko"
GKI_PATCHED="$MODPATH/system/vendor/lib/modules/5.4-gki/qca_cld3_wlan.ko"

TOP_ORIGINAL_HASH="92542a7dccb8ead32046519fbdc03e024f258e5fe7cf13e51318c389df18f27f"
TOP_V02_HASH="1dc0c6a4826557535496e095eb83b0db09868fe4017e1ac9fa29c70df6be6810"
TOP_V03_HASH="9127891857ca5d21ceacffa8a28c881235c7138496ab7ec85317b2af24057419"
TOP_V04_HASH="7babd9e6b6e5627e521871609409e08d55ba50d0255cc7ae77c712c0a6314718"
TOP_V07_HASH="6ace945e9c86b38357c837e767daed577723bcf051cea31bfd60455ffa71eb35"
TOP_FINAL_HASH="27a2bc077b38299f495377b1b13ed9143bfc53e48904d89af080834a1801d47c"
GKI_ORIGINAL_HASH="e1736447482c2a4d6b02d7645071f15306c1654b1550fafa539894bb91a06bef"
GKI_V04_HASH="f95560690ea959d3fd87501f878e6a798b20c798b710492bea8ba0a231e3cf0c"
GKI_V07_HASH="f711d9c2dc98482d10cc9047cc06993eac00e257ee1d7017df215374d01e9976"
GKI_FINAL_HASH="8d76c32c557648c7633b8d6090dcc8a0afb4d6dcb15b027338e244d1f7156166"

LOCALE="$(getprop persist.sys.locale)"
[ -n "$LOCALE" ] || LOCALE="$(getprop ro.product.locale)"
case "$LOCALE" in
    ru*|RU*) RU=1 ;;
    *) RU=0 ;;
esac

say() {
    if [ "$RU" = "1" ]; then
        ui_print "$1"
    else
        ui_print "$2"
    fi
}

fail() {
    if [ "$RU" = "1" ]; then
        abort "! $1"
    else
        abort "! $2"
    fi
}

write_patch() {
    PAYLOAD="$1"
    OFFSET="$2"
    printf '%s' "$PAYLOAD" | base64 -d 2>/dev/null |
        dd of="$PATCH_FILE" bs=1 seek="$OFFSET" conv=notrunc 2>/dev/null
}

# Stock/v0.2 top-level driver -> v0.3. These are the same exact-build edits
# that were used by the original public installer.
top_add_v03_guard() {
    write_patch "AAEANwAAAJTAACA3EgAAFA==" 2025828
    write_patch "GwEAAMF6AAAAAAAAAAAAAA==" 8958184
    write_patch "AAAAAAAAAAAAAAAAAAAAAA==" 8958208
    write_patch "AAAAAAAAAAAAAAAAAAAAAA==" 8958232
}

top_add_v02_return() {
    write_patch "4AMfKg==" 2026296
}

# v0.3 -> final v0.8/v0.9 driver bytes.
top_v03_to_final() {
    write_patch "ggM=" 2024728
    write_patch "CAA=" 2025828
    write_patch "FAg=" 2025831
    write_patch "kAgBQDmo" 2025835
    write_patch "NRE=" 2025843
    write_patch "FA==" 2025847
    write_patch "Ew==" 8958184
    write_patch "Lwc=" 8958188
    write_patch "KAE=" 8958192
    write_patch "FgE=" 8958208
    write_patch "Lwc=" 8958212
    write_patch "KAE=" 8958216
    write_patch "AAA=" 8958256
    write_patch "AAA=" 8958260
    write_patch "AAAA" 8958264
}

top_v04_to_final() {
    write_patch "ggM=" 2024728
    write_patch "CAA=" 2025828
    write_patch "FA==" 2025831
}

top_v07_to_final() {
    write_patch "ggM=" 2024728
}

gki_stock_to_final() {
    write_patch "ggM=" 2006064
    write_patch "CAA=" 2007164
    write_patch "FAg=" 2007167
    write_patch "CAFAOag=" 2007172
    write_patch "NRE=" 2007179
    write_patch "FA==" 2007183
    write_patch "Hw==" 2007678
    write_patch "Dw==" 8825292
    write_patch "KAEA" 8825296
    write_patch "Fg==" 8825312
    write_patch "Dw==" 8825316
    write_patch "KAEA" 8825320
    write_patch "AAA=" 8825336
    write_patch "AAA=" 8825340
    write_patch "AAAA" 8825344
    write_patch "AAA=" 8825360
    write_patch "AAA=" 8825364
    write_patch "AAAA" 8825368
}

gki_v04_to_final() {
    write_patch "ggM=" 2006064
    write_patch "CAA=" 2007164
    write_patch "FA==" 2007167
}

gki_v07_to_final() {
    write_patch "ggM=" 2006064
}

patch_top() {
    SOURCE_HASH="$1"
    PATCH_FILE="$TOP_PATCHED"
    case "$SOURCE_HASH" in
        "$TOP_ORIGINAL_HASH")
            top_add_v03_guard
            top_add_v02_return
            top_v03_to_final
            ;;
        "$TOP_V02_HASH")
            top_add_v03_guard
            top_v03_to_final
            ;;
        "$TOP_V03_HASH") top_v03_to_final ;;
        "$TOP_V04_HASH") top_v04_to_final ;;
        "$TOP_V07_HASH") top_v07_to_final ;;
        "$TOP_FINAL_HASH") ;;
        *) return 1 ;;
    esac
}

patch_gki() {
    SOURCE_HASH="$1"
    PATCH_FILE="$GKI_PATCHED"
    case "$SOURCE_HASH" in
        "$GKI_ORIGINAL_HASH") gki_stock_to_final ;;
        "$GKI_V04_HASH") gki_v04_to_final ;;
        "$GKI_V07_HASH") gki_v07_to_final ;;
        "$GKI_FINAL_HASH") ;;
        *) return 1 ;;
    esac
}

say "- Проверяю точную сборку Nothing Phone (1)" \
    "- Checking the exact Nothing Phone (1) build"

BUILD="$(getprop ro.build.version.incremental)"
if [ "$BUILD" != "$EXPECTED_BUILD" ]; then
    fail "Неподдерживаемая сборка: $BUILD" "Unsupported build: $BUILD"
fi

DEVICE="$(getprop ro.product.device):$(getprop ro.product.vendor.device)"
case "$DEVICE" in
    *Spacewar*|*spacewar*) ;;
    *) fail "Неподдерживаемое устройство: $DEVICE" "Unsupported device: $DEVICE" ;;
esac

[ -f "$TOP_TARGET" ] ||
    fail "Не найден драйвер: $TOP_TARGET" "Driver not found: $TOP_TARGET"
[ -f "$GKI_TARGET" ] ||
    fail "Не найден драйвер: $GKI_TARGET" "Driver not found: $GKI_TARGET"

TOP_CURRENT="$(sha256sum "$TOP_TARGET" 2>/dev/null | awk '{print $1}')"
GKI_CURRENT="$(sha256sum "$GKI_TARGET" 2>/dev/null | awk '{print $1}')"

mkdir -p "${TOP_PATCHED%/*}" "${GKI_PATCHED%/*}" ||
    fail "Не удалось создать каталоги модуля" "Could not create module directories"
cp -f "$TOP_TARGET" "$TOP_PATCHED" ||
    fail "Не удалось скопировать верхний драйвер" "Could not copy the top-level driver"
cp -f "$GKI_TARGET" "$GKI_PATCHED" ||
    fail "Не удалось скопировать драйвер 5.4-gki" "Could not copy the 5.4-gki driver"

patch_top "$TOP_CURRENT" ||
    fail "Хеш верхнего WLAN-драйвера не поддерживается: $TOP_CURRENT" \
        "Unsupported top-level WLAN driver hash: $TOP_CURRENT"
patch_gki "$GKI_CURRENT" ||
    fail "Хеш WLAN-драйвера 5.4-gki не поддерживается: $GKI_CURRENT" \
        "Unsupported 5.4-gki WLAN driver hash: $GKI_CURRENT"

TOP_RESULT="$(sha256sum "$TOP_PATCHED" 2>/dev/null | awk '{print $1}')"
GKI_RESULT="$(sha256sum "$GKI_PATCHED" 2>/dev/null | awk '{print $1}')"
[ "$TOP_RESULT" = "$TOP_FINAL_HASH" ] ||
    fail "Проверка верхнего драйвера не пройдена: $TOP_RESULT" \
        "Top-level driver verification failed: $TOP_RESULT"
[ "$GKI_RESULT" = "$GKI_FINAL_HASH" ] ||
    fail "Проверка драйвера 5.4-gki не пройдена: $GKI_RESULT" \
        "5.4-gki driver verification failed: $GKI_RESULT"

set_perm "$TOP_PATCHED" 0 0 0644 u:object_r:vendor_file:s0
set_perm "$GKI_PATCHED" 0 0 0644 u:object_r:vendor_file:s0
set_perm "$MODPATH/service.sh" 0 0 0755
set_perm "$MODPATH/post-fs-data.sh" 0 0 0755
set_perm "$MODPATH/action.sh" 0 0 0755
set_perm "$MODPATH/boot_patch.sh" 0 0 0755
set_perm "$MODPATH/boot_patch/payload/wpss_related_rescue.sh" 0 0 0750
set_perm "$MODPATH/boot_patch/payload/wpss_related_rescue.rc" 0 0 0644

say "- Обе копии WLAN-драйвера созданы на телефоне и проверены" \
    "- Both WLAN driver copies were built on-device and verified"
say "- Автоматический reinit Wi-Fi после сбоя WPSS заблокирован" \
    "- Automatic Wi-Fi reinit after a WPSS crash is blocked"
say "- Kernel BUG после трёх неудачных запусков направлен в очистку" \
    "- The kernel BUG after three failed WLAN probes enters cleanup"
say "- post-fs-data установит политику WPSS RELATED как дополнительную защиту" \
    "- post-fs-data will set WPSS RELATED as an additional guard"
say "- Action умеет показать uptime, создать дамп и подготовить boot-образ" \
    "- Action can show uptime, create a dump, and prepare a boot image"
say "- Action никогда не прошивает boot-раздел автоматически" \
    "- Action never flashes the boot partition automatically"
say "- Если загрузка не удастся, отключите модуль через OrangeFox" \
    "- If boot fails, disable the module from OrangeFox"
