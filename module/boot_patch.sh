#!/system/bin/sh

# Creates a complete backup of boot_a and a separately patched copy.
# This script never writes to a block device.

MODDIR=${0%/*}
EXPECTED_BUILD="2509261631"
EXPECTED_BOOT_HASH="6285978fe6650510da801b24067bf95ef067c01b6c2c5b5d61b0c7d5425d28c8"
EXPECTED_BOOT_SIZE=100663296
BOOT_DEVICE="/dev/block/by-name/boot_a"
DOWNLOAD="/sdcard/Download"
PAYLOAD_DIR="$MODDIR/boot_patch/payload"
MAGISKBOOT="/data/adb/magisk/magiskboot"
WORK="/data/local/tmp/wpss_boot_patch_$$"

LOCALE="$(getprop persist.sys.locale)"
[ -n "$LOCALE" ] || LOCALE="$(getprop ro.product.locale)"
case "$LOCALE" in
    ru*|RU*) RU=1 ;;
    *) RU=0 ;;
esac

say2() {
    if [ "$RU" = "1" ]; then
        echo "$1"
    else
        echo "$2"
    fi
}

BACKUP=""
BACKUP_TMP=""
PATCHED=""
PATCHED_TMP=""

cleanup() {
    rm -rf "$WORK" 2>/dev/null
}

die2() {
    say2 "ОШИБКА: $1" "ERROR: $2" >&2
    [ -z "$BACKUP_TMP" ] || rm -f "$BACKUP_TMP" 2>/dev/null
    [ -z "$PATCHED" ] || rm -f "$PATCHED" 2>/dev/null
    [ -z "$PATCHED_TMP" ] || rm -f "$PATCHED_TMP" 2>/dev/null
    cleanup
    exit 1
}

trap cleanup EXIT INT TERM

[ "$(getprop ro.build.version.incremental)" = "$EXPECTED_BUILD" ] ||
    die2 "неподдерживаемая сборка Android" "unsupported Android build"

DEVICE="$(getprop ro.product.device):$(getprop ro.product.vendor.device)"
case "$DEVICE" in
    *Spacewar*|*spacewar*) ;;
    *) die2 "это не Nothing Phone (1) Spacewar" "this is not Nothing Phone (1) Spacewar" ;;
esac

SLOT="$(getprop ro.boot.slot_suffix)"
[ -n "$SLOT" ] || SLOT="_$(getprop ro.boot.slot)"
[ "$SLOT" = "_a" ] ||
    die2 "текущий слот $SLOT; разрешён только слот _a" \
        "current slot is $SLOT; only slot _a is allowed"

[ -r "$BOOT_DEVICE" ] ||
    die2 "не удаётся прочитать $BOOT_DEVICE" "cannot read $BOOT_DEVICE"
[ -x "$MAGISKBOOT" ] ||
    die2 "не найден $MAGISKBOOT" "$MAGISKBOOT was not found"
[ -f "$PAYLOAD_DIR/wpss_related_rescue.rc" ] ||
    die2 "не найден RC-файл патча" "patch RC file is missing"
[ -f "$PAYLOAD_DIR/wpss_related_rescue.sh" ] ||
    die2 "не найден скрипт патча" "patch script is missing"

mkdir -p "$DOWNLOAD" ||
    die2 "не удаётся открыть папку Download" "cannot access the Download folder"

FREE_KB="$(df -Pk "$DOWNLOAD" 2>/dev/null | awk 'END {print $4}')"
case "$FREE_KB" in
    ''|*[!0-9]*) FREE_KB=0 ;;
esac
[ "$FREE_KB" -ge 716800 ] ||
    die2 "нужно не менее 700 МБ свободного места; доступно ${FREE_KB} КБ" \
        "at least 700 MiB of free space is required; ${FREE_KB} KiB is available"

BOOT_SIZE="$(blockdev --getsize64 "$BOOT_DEVICE" 2>/dev/null)"
case "$BOOT_SIZE" in
    ''|*[!0-9]*) BOOT_SIZE=0 ;;
esac
[ "$BOOT_SIZE" -eq "$EXPECTED_BOOT_SIZE" ] ||
    die2 "неожиданный размер boot_a: $BOOT_SIZE" "unexpected boot_a size: $BOOT_SIZE"

STAMP="$(date +%Y-%m-%d_%H-%M-%S)"
BACKUP="$DOWNLOAD/Nothing-Phone-1_boot-a_BACKUP_$STAMP.img"
PATCHED="$DOWNLOAD/Nothing-Phone-1_boot-a_WPSS-RELATED_PATCHED_$STAMP.img"
[ ! -e "$BACKUP" ] && [ ! -e "$PATCHED" ] || {
    BACKUP="$DOWNLOAD/Nothing-Phone-1_boot-a_BACKUP_${STAMP}_$$.img"
    PATCHED="$DOWNLOAD/Nothing-Phone-1_boot-a_WPSS-RELATED_PATCHED_${STAMP}_$$.img"
}
BACKUP_TMP="$BACKUP.partial"
PATCHED_TMP="$PATCHED.partial"

say2 "Снимаю полный backup boot_a. Не закрывайте Magisk." \
    "Creating a complete boot_a backup. Keep Magisk open."
dd if="$BOOT_DEVICE" of="$BACKUP_TMP" bs=4194304 2>/dev/null ||
    die2 "не удалось прочитать boot_a" "could not read boot_a"
sync

BACKUP_SIZE="$(wc -c < "$BACKUP_TMP" 2>/dev/null)"
[ "$BACKUP_SIZE" -eq "$BOOT_SIZE" ] ||
    die2 "backup имеет неверный размер: $BACKUP_SIZE" \
        "backup has the wrong size: $BACKUP_SIZE"
mv -f "$BACKUP_TMP" "$BACKUP" ||
    die2 "не удалось завершить сохранение backup" "could not finalize the backup"
BACKUP_TMP=""
chmod 0644 "$BACKUP" 2>/dev/null

BACKUP_HASH="$(sha256sum "$BACKUP" 2>/dev/null | awk '{print $1}')"
[ "$BACKUP_HASH" = "$EXPECTED_BOOT_HASH" ] ||
    die2 "backup сохранён, но SHA-256 boot_a неизвестен: $BACKUP_HASH; патч отменён" \
        "backup was saved, but boot_a SHA-256 is unknown: $BACKUP_HASH; patching cancelled"

rm -rf "$WORK"
mkdir -p "$WORK" ||
    die2 "не удалось создать временную папку" "could not create the work directory"
cp -f "$BACKUP" "$WORK/input.img" ||
    die2 "не удалось скопировать backup" "could not copy the backup"
cp -f "$PAYLOAD_DIR/wpss_related_rescue.rc" "$WORK/wpss_related_rescue.rc" ||
    die2 "не удалось скопировать RC-файл" "could not copy the RC file"
cp -f "$PAYLOAD_DIR/wpss_related_rescue.sh" "$WORK/wpss_related_rescue.sh" ||
    die2 "не удалось скопировать скрипт" "could not copy the script"
chmod 0750 "$WORK/wpss_related_rescue.sh"

cd "$WORK" ||
    die2 "не удалось открыть временную папку" "could not enter the work directory"

say2 "Распаковываю только копию boot_a." "Unpacking only the boot_a copy."
"$MAGISKBOOT" unpack input.img >/dev/null 2>&1 ||
    die2 "magiskboot не смог распаковать образ" "magiskboot could not unpack the image"
[ -f ramdisk.cpio ] ||
    die2 "в образе нет ramdisk.cpio" "ramdisk.cpio is missing from the image"

"$MAGISKBOOT" cpio ramdisk.cpio test >/dev/null 2>&1
CPIO_STATUS=$?
[ "$CPIO_STATUS" -eq 1 ] ||
    die2 "ожидался Magisk ramdisk (код 1), получен код $CPIO_STATUS" \
        "a Magisk ramdisk was expected (code 1), got code $CPIO_STATUS"

say2 "Добавляю раннюю политику WPSS RELATED в копию." \
    "Adding the early WPSS RELATED policy to the copy."
"$MAGISKBOOT" cpio ramdisk.cpio \
    "mkdir 0750 overlay.d" \
    "mkdir 0750 overlay.d/sbin" \
    "add 0644 overlay.d/wpss_related_rescue.rc wpss_related_rescue.rc" \
    "add 0750 overlay.d/sbin/wpss_related_rescue.sh wpss_related_rescue.sh" \
    >/dev/null 2>&1 ||
    die2 "не удалось добавить overlay.d" "could not add overlay.d"

rm -f verify.rc verify.sh
"$MAGISKBOOT" cpio ramdisk.cpio \
    "extract overlay.d/wpss_related_rescue.rc verify.rc" \
    "extract overlay.d/sbin/wpss_related_rescue.sh verify.sh" \
    >/dev/null 2>&1 ||
    die2 "не удалось проверить добавленные файлы" "could not extract the added files"
cmp -s wpss_related_rescue.rc verify.rc ||
    die2 "проверка RC-файла не пройдена" "RC-file verification failed"
cmp -s wpss_related_rescue.sh verify.sh ||
    die2 "проверка скрипта не пройдена" "script verification failed"

"$MAGISKBOOT" repack input.img >/dev/null 2>&1 ||
    die2 "magiskboot не смог собрать новый образ" "magiskboot could not repack the image"
[ -f new-boot.img ] ||
    die2 "new-boot.img не создан" "new-boot.img was not created"

NEW_SIZE="$(wc -c < new-boot.img 2>/dev/null)"
case "$NEW_SIZE" in
    ''|*[!0-9]*) NEW_SIZE=0 ;;
esac
[ "$NEW_SIZE" -gt 41943040 ] && [ "$NEW_SIZE" -le "$BOOT_SIZE" ] ||
    die2 "неожиданный размер нового образа: $NEW_SIZE" \
        "unexpected new image size: $NEW_SIZE"

cp -f new-boot.img "$PATCHED_TMP" ||
    die2 "не удалось сохранить патченый образ" "could not save the patched image"
sync
PATCHED_TMP_SIZE="$(wc -c < "$PATCHED_TMP" 2>/dev/null)"
[ "$PATCHED_TMP_SIZE" -eq "$NEW_SIZE" ] ||
    die2 "копия патченого образа имеет неверный размер: $PATCHED_TMP_SIZE" \
        "the patched image copy has the wrong size: $PATCHED_TMP_SIZE"
mv -f "$PATCHED_TMP" "$PATCHED" ||
    die2 "не удалось завершить сохранение патченого образа" \
        "could not finalize the patched image"
PATCHED_TMP=""
chmod 0644 "$PATCHED" 2>/dev/null
PATCHED_HASH="$(sha256sum "$PATCHED" 2>/dev/null | awk '{print $1}')"

echo
say2 "Готово. Реальный boot_a НЕ изменялся." \
    "Done. The real boot_a was NOT changed."
say2 "Полный backup:" "Complete backup:"
echo "$BACKUP"
echo "SHA-256: $BACKUP_HASH"
say2 "Патченая копия:" "Patched copy:"
echo "$PATCHED"
echo "SHA-256: $PATCHED_HASH"
say2 "Сначала проверяйте её командой fastboot boot, не flash." \
    "Test it with fastboot boot first, not flash."
