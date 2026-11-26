#!/system/bin/sh

EXPECTED_BUILD="2509261631"

TOP_TARGET="${TOP_TARGET_OVERRIDE:-/vendor/lib/modules/qca_cld3_wlan.ko}"
GKI_TARGET="${GKI_TARGET_OVERRIDE:-/vendor/lib/modules/5.4-gki/qca_cld3_wlan.ko}"
QCA6750_TARGET="${QCA6750_TARGET_OVERRIDE:-/vendor/lib/modules/qca_cld3_qca6750.ko}"
TOP_PATCHED="$MODPATH/system/vendor/lib/modules/qca_cld3_wlan.ko"
GKI_PATCHED="$MODPATH/system/vendor/lib/modules/5.4-gki/qca_cld3_wlan.ko"
QCA6750_PATCHED="$MODPATH/system/vendor/lib/modules/qca_cld3_qca6750.ko"
QCA6750_ORIGINAL_HASH="d205f2480c621b0eef866b61c684f9c9669136e932d4a0ee3914fccaf0c60139"
QCA6750_V12_HASH="aaa967a88106757dc7aa9958a8206f520a6e040bf57299b7964e12ae06bb53c0"
QCA6750_FINAL_HASH="291cce1505c234e8425abf3eea385fe077ae8663ba1c1337c414b6d0be6b93e9"

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

# v0.3 -> final v0.8+ driver bytes.
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

patch_qca6750() {
    PATCH_FILE="$QCA6750_PATCHED"
    case "$1" in
        "$QCA6750_ORIGINAL_HASH"|"$QCA6750_V12_HASH")
            # Exact stock/v1.2 -> v1.3 instructions AND loader relocation edits.
            write_patch "ggM=" 2015696
            write_patch "4AEANwAAAJSgARg2BgAAFB8gA9UfIAPVHyAD1Q==" 2016404
            write_patch "6ANA+cgAALQABUD5HyAD1R8gA9UfIAPV" 2016464
            write_patch "YP0f" 2016548
            write_patch "IgM=" 2016764
            write_patch "/wMA+QAAAJSgAgA2AgAAkAMAAJBCAACRYwAAkWAGgFKBAIBSAAAAlPQDHypmAAAUAAAAlKD/HzYCAACQQgAAkeEDAJHgAxOqAAAAlKAAADR5AAAUtAKAElsAABT1//8X4ANA+QAAAJQBAAAU" 2016780
            write_patch "AQAAFA==" 2017152
            write_patch "BAAAFB8gA9UfIAPVHyAD1Q==" 2017188
            write_patch "FA==" 2017224
            write_patch "4///Fx8gA9UfIAPVHyAD1R8gA9UfIAPVHyAD1R8gA9UfIAPVHyAD1R8gA9UfIAPVHyAD1R8gA9UfIAPVHyAD1Q==" 2017348
            write_patch "gAQAtAcAABQ=" 2279244
            write_patch "AQAAFA==" 2279348
            write_patch "4jiGEe3Z/kc=" 6330576
            write_patch "GwEAAPR4AAAAAAAAAAAAAFSWAwAAAAAAGwEAAD+BAAAAAAA=" 8870096
            write_patch "AAAAAAAAAAAAAAA=" 8870144
            write_patch "AAAAAAAAAAAAAAA=" 8870168
            write_patch "P4E=" 8870268
            write_patch "AAAAAAAAAAAAAAA=" 8870288
            write_patch "AAAAAAAAAAAAAAA=" 8870312
            write_patch "AAAAAAAAAAAAAAA=" 8870336
            write_patch "AAAAAAAAAAAAAAA=" 8870360
            write_patch "UoY=" 8870388
            write_patch "IAcAAMT7Bw==" 8871156
            write_patch "IAcAAKYMDw==" 8871180
            write_patch "FQEAACAHAADE+wc=" 8871200
            write_patch "IAcAAKYMDw==" 8871228
            write_patch "bg==" 8871252
            write_patch "GwEAAPR4AAAAAAA=" 8871272
            write_patch "AAAAAAAAAAAAAAA=" 8871296
            write_patch "EwEAACAHAACmDA8=" 8871320
            write_patch "pgwP" 8871352
            write_patch "AAAAAAAA" 8871368
            write_patch "/3w=" 8871396
            write_patch "AAAAAAAA" 8872424
            write_patch "AAAAAAAA" 8872448
            write_patch "AAAAAAAA" 8872472
            write_patch "AAAAAAAA" 8872496
            write_patch "AAAAAAAAAAAAAAA=" 8872904
            write_patch "AAAAAAAAAAAAAAA=" 8872928
            write_patch "AAAAAAAAAAAAAAA=" 8872952
            write_patch "AAAAAAAAAAAAAAA=" 8872976
            write_patch "AAAAAAAA" 8873000
            write_patch "AAAAAAAA" 8873024
            write_patch "AAAAAAAAAAAAAAA=" 8873048
            write_patch "AAAAAAAAAAAAAAA=" 8873072
            write_patch "AAAAAAAAAAAAAAA=" 8873096
            write_patch "AAAAAAAAAAAAAAA=" 8873120
            write_patch "AAAAAAAA" 8873144
            write_patch "AAAAAAAA" 8873168
            write_patch "AAAAAAAAAAAAAAA=" 9279488
            ;;
        "$QCA6750_FINAL_HASH") ;;
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

[ "$(uname -r)" = "5.4.274-qgki-g4670d6bdb795" ] ||
    fail "Неподдерживаемое ядро: $(uname -r)" "Unsupported kernel: $(uname -r)"

[ -f "$TOP_TARGET" ] ||
    fail "Не найден драйвер: $TOP_TARGET" "Driver not found: $TOP_TARGET"
[ -f "$GKI_TARGET" ] ||
    fail "Не найден драйвер: $GKI_TARGET" "Driver not found: $GKI_TARGET"
[ -f "$QCA6750_TARGET" ] ||
    fail "Не найден QCA6750: $QCA6750_TARGET" "QCA6750 not found: $QCA6750_TARGET"

TOP_CURRENT="$(sha256sum "$TOP_TARGET" 2>/dev/null | awk '{print $1}')"
GKI_CURRENT="$(sha256sum "$GKI_TARGET" 2>/dev/null | awk '{print $1}')"
QCA6750_CURRENT="$(sha256sum "$QCA6750_TARGET" 2>/dev/null | awk '{print $1}')"

mkdir -p "${TOP_PATCHED%/*}" "${GKI_PATCHED%/*}" ||
    fail "Не удалось создать каталоги модуля" "Could not create module directories"
cp -f "$TOP_TARGET" "$TOP_PATCHED" ||
    fail "Не удалось скопировать верхний драйвер" "Could not copy the top-level driver"
cp -f "$GKI_TARGET" "$GKI_PATCHED" ||
    fail "Не удалось скопировать драйвер 5.4-gki" "Could not copy the 5.4-gki driver"
cp -f "$QCA6750_TARGET" "$QCA6750_PATCHED" ||
    fail "Не удалось скопировать QCA6750" "Could not copy QCA6750"

patch_top "$TOP_CURRENT" ||
    fail "Хеш верхнего WLAN-драйвера не поддерживается: $TOP_CURRENT" \
        "Unsupported top-level WLAN driver hash: $TOP_CURRENT"
patch_gki "$GKI_CURRENT" ||
    fail "Хеш WLAN-драйвера 5.4-gki не поддерживается: $GKI_CURRENT" \
        "Unsupported 5.4-gki WLAN driver hash: $GKI_CURRENT"
patch_qca6750 "$QCA6750_CURRENT" ||
    fail "Хеш QCA6750 не поддерживается: $QCA6750_CURRENT" \
        "Unsupported QCA6750 hash: $QCA6750_CURRENT"

TOP_RESULT="$(sha256sum "$TOP_PATCHED" 2>/dev/null | awk '{print $1}')"
GKI_RESULT="$(sha256sum "$GKI_PATCHED" 2>/dev/null | awk '{print $1}')"
QCA6750_RESULT="$(sha256sum "$QCA6750_PATCHED" 2>/dev/null | awk '{print $1}')"
[ "$TOP_RESULT" = "$TOP_FINAL_HASH" ] ||
    fail "Проверка верхнего драйвера не пройдена: $TOP_RESULT" \
        "Top-level driver verification failed: $TOP_RESULT"
[ "$GKI_RESULT" = "$GKI_FINAL_HASH" ] ||
    fail "Проверка драйвера 5.4-gki не пройдена: $GKI_RESULT" \
        "5.4-gki driver verification failed: $GKI_RESULT"
[ "$QCA6750_RESULT" = "$QCA6750_FINAL_HASH" ] ||
    fail "Проверка QCA6750 не пройдена: $QCA6750_RESULT" \
        "QCA6750 verification failed: $QCA6750_RESULT"

set_perm "$TOP_PATCHED" 0 0 0644 u:object_r:vendor_file:s0
set_perm "$GKI_PATCHED" 0 0 0644 u:object_r:vendor_file:s0
set_perm "$QCA6750_PATCHED" 0 0 0644 u:object_r:vendor_file:s0
set_perm "$MODPATH/service.sh" 0 0 0755
set_perm "$MODPATH/post-fs-data.sh" 0 0 0755
set_perm "$MODPATH/action.sh" 0 0 0755
set_perm "$MODPATH/boot_patch.sh" 0 0 0755
set_perm "$MODPATH/wifi_recover.sh" 0 0 0755
for HELPER in volume_keys.sh volume_filter.sh action_menu.sh wifi_recovery.sh; do
    set_perm "$MODPATH/lib/$HELPER" 0 0 0644
done
for FILTER in fresh_scans.awk; do
    set_perm "$MODPATH/lib/$FILTER" 0 0 0644
done
set_perm "$MODPATH/boot_patch/payload/wpss_related_rescue.sh" 0 0 0750
set_perm "$MODPATH/boot_patch/payload/wpss_related_rescue.rc" 0 0 0644

say "- Две ранее изменённые копии WLAN сохранены и проверены" \
    "- The two previously patched WLAN variants were preserved and verified"
say "- Фактически используемый QCA6750 создан и проверен; build ID: e2388611edd9fe47" \
    "- The active QCA6750 variant was patched and verified; build ID: e2388611edd9fe47"
say "- Reinit снова запускает Wi-Fi; каждый обработчик освобождает только свою транзакцию" \
    "- Reinit runs real Wi-Fi recovery; each callback releases only its own transaction"
say "- Kernel BUG после трёх неудачных запусков направлен в очистку" \
    "- The kernel BUG after three failed WLAN probes enters cleanup"
say "- post-fs-data установит политику WPSS RELATED как дополнительную защиту" \
    "- post-fs-data will set WPSS RELATED as an additional guard"
say "- Обычная Magisk-подмена слишком поздняя для раннего vendor_modprobe" \
    "- A normal Magisk overlay is too late for the early vendor_modprobe"
say "- Action подготовит тестовый boot с QCA6750 в раннем ramdisk" \
    "- Action will prepare a test boot with QCA6750 in the early ramdisk"
say "- Нужен ранний boot v1.3: уже проверенный образ можно оставить" \
    "- Early v1.3 boot is required: keep an already verified image"
say "- Action никогда не прошивает boot-раздел автоматически" \
    "- Action never flashes the boot partition automatically"
say "- Для отката раннего драйвера восстановите полный backup boot A через OrangeFox" \
    "- Restore the full boot A backup in OrangeFox to roll back the early driver"

say "- Action: Громкость + меняет номер; Громкость - запускает пункт" \
    "- Action: Volume Up changes the number; Volume Down runs the selection"
say "- Пункт 3: до трёх ручных попыток Wi-Fi; Громкость - отменяет повторы" \
    "- Option 3: up to three manual Wi-Fi recovery attempts; Volume Down cancels"
say "- Для уже проверенного раннего boot v1.3 новый boot не требуется" \
    "- An already verified early v1.3 boot needs no new boot image"
