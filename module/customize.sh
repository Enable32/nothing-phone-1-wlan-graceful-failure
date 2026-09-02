#!/system/bin/sh

ORIGINAL_HASH="92542a7dccb8ead32046519fbdc03e024f258e5fe7cf13e51318c389df18f27f"
V02_HASH="1dc0c6a4826557535496e095eb83b0db09868fe4017e1ac9fa29c70df6be6810"
PATCHED_HASH="9127891857ca5d21ceacffa8a28c881235c7138496ab7ec85317b2af24057419"
EXPECTED_BUILD="2509261631"
TARGET="${WLAN_TARGET_OVERRIDE:-/vendor/lib/modules/qca_cld3_wlan.ko}"
PATCHED="$MODPATH/system/vendor/lib/modules/qca_cld3_wlan.ko"

detect_language() {
    DEVICE_LOCALE="$(getprop persist.sys.locale)"
    [ -n "$DEVICE_LOCALE" ] || DEVICE_LOCALE="$(getprop ro.product.locale)"
    case "$DEVICE_LOCALE" in
        ru*|RU*|*_RU*|*-RU*) UI_LANG=ru ;;
        *) UI_LANG=en ;;
    esac
}

msg() {
    KEY="$1"
    if [ "$UI_LANG" = "ru" ]; then
        case "$KEY" in
            language) ui_print "- Язык установщика: Русский" ;;
            checking) ui_print "- Проверка Nothing Phone (1) и версии прошивки" ;;
            unsupported_firmware) abort "! Неподдерживаемая прошивка: $BUILD" ;;
            missing_driver) abort "! Драйвер WLAN не найден: $TARGET" ;;
            unsafe_hash) abort "! SHA-256 активного драйвера не поддерживается: $SOURCE_HASH" ;;
            copying) ui_print "- Копирование штатного драйвера с телефона" ;;
            patching_original) ui_print "- Применение исправлений v0.2 и v0.3" ;;
            patching_v02) ui_print "- Обновление исправления v0.2 до v0.4" ;;
            already_patched) ui_print "- Исправление драйвера уже применено" ;;
            patch_failed) abort "! Проверка изменённого драйвера не пройдена: $RESULT_HASH" ;;
            verified) ui_print "- Изменённый драйвер успешно проверен" ;;
            wifi_kept) ui_print "- Переключатель Wi-Fi не будет выключаться модулем" ;;
            guard) ui_print "- Опасная повторная инициализация WLAN будет пропущена" ;;
            logs) ui_print "- Уведомления и ограниченные журналы включены" ;;
            reboot) ui_print "- Перезагрузите телефон для применения модуля" ;;
        esac
    else
        case "$KEY" in
            language) ui_print "- Installer language: English" ;;
            checking) ui_print "- Checking Nothing Phone (1) and firmware build" ;;
            unsupported_firmware) abort "! Unsupported firmware: $BUILD" ;;
            missing_driver) abort "! WLAN driver was not found: $TARGET" ;;
            unsafe_hash) abort "! Active driver SHA-256 is not supported: $SOURCE_HASH" ;;
            copying) ui_print "- Copying the stock driver from this device" ;;
            patching_original) ui_print "- Applying the v0.2 and v0.3 fixes" ;;
            patching_v02) ui_print "- Updating the v0.2 fix to v0.4" ;;
            already_patched) ui_print "- The driver fix is already applied" ;;
            patch_failed) abort "! Patched driver verification failed: $RESULT_HASH" ;;
            verified) ui_print "- Patched driver verified successfully" ;;
            wifi_kept) ui_print "- The module will not turn off the Android Wi-Fi switch" ;;
            guard) ui_print "- A dangerous duplicate WLAN reinitialization will be skipped" ;;
            logs) ui_print "- Notifications and size-limited logs are enabled" ;;
            reboot) ui_print "- Reboot the phone to activate the module" ;;
        esac
    fi
}

write_patch() {
    PAYLOAD="$1"
    OFFSET="$2"
    printf '%s' "$PAYLOAD" | base64 -d 2>/dev/null |
        dd of="$PATCHED" bs=1 seek="$OFFSET" conv=notrunc 2>/dev/null
}

apply_v03_guard() {
    write_patch "AAEANwAAAJTAACA3EgAAFA==" 2025828
    write_patch "GwEAAMF6AAAAAAAAAAAAAA==" 8958184
    write_patch "AAAAAAAAAAAAAAAAAAAAAA==" 8958208
    write_patch "AAAAAAAAAAAAAAAAAAAAAA==" 8958232
}

apply_v02_return() {
    write_patch "4AMfKg==" 2026296
}

detect_language
msg language
msg checking

BUILD="$(getprop ro.build.fingerprint)"
case "$BUILD" in
    *"/$EXPECTED_BUILD:user/release-keys") ;;
    *) msg unsupported_firmware ;;
esac

[ -f "$TARGET" ] || msg missing_driver
SOURCE_HASH="$(sha256sum "$TARGET" 2>/dev/null | awk '{print $1}')"

case "$SOURCE_HASH" in
    "$ORIGINAL_HASH"|"$V02_HASH"|"$PATCHED_HASH") ;;
    *) msg unsafe_hash ;;
esac

msg copying
mkdir -p "${PATCHED%/*}" || abort "! mkdir failed: ${PATCHED%/*}"
cp -f "$TARGET" "$PATCHED" || abort "! copy failed: $TARGET"

case "$SOURCE_HASH" in
    "$ORIGINAL_HASH")
        msg patching_original
        apply_v03_guard
        apply_v02_return
        ;;
    "$V02_HASH")
        msg patching_v02
        apply_v03_guard
        ;;
    "$PATCHED_HASH")
        msg already_patched
        ;;
esac

RESULT_HASH="$(sha256sum "$PATCHED" 2>/dev/null | awk '{print $1}')"
[ "$RESULT_HASH" = "$PATCHED_HASH" ] || msg patch_failed

set_perm "$PATCHED" 0 0 0644 u:object_r:vendor_file:s0
set_perm "$MODPATH/service.sh" 0 0 0755
set_perm "$MODPATH/action.sh" 0 0 0755

msg verified
msg wifi_kept
msg guard
msg logs
msg reboot

