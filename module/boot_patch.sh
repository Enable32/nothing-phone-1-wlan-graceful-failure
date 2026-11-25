#!/system/bin/sh

# Creates a complete backup of boot_a and a separately patched copy.
# This script never writes to a block device.

MODDIR=${0%/*}
EXPECTED_BUILD="2509261631"
EXPECTED_BOOT_HASH="6285978fe6650510da801b24067bf95ef067c01b6c2c5b5d61b0c7d5425d28c8"
EXPECTED_MAGISK306_BOOT_HASH="31f4ac5d32fd375f7729be35007ada9825af838de8351563f3e5ec13589de2e4"
EXPECTED_MAGISK31_BOOT_HASH="2d43dc21a2523e98e6895a3dfed2992af2a3072492d24ad17b5d0646f2be976b"
EXPECTED_KERNEL_HASH="2f2656528794dde2cb54f4abb613ebffb59b5528e034863aa4aedd7bef5d0fda"
EXPECTED_BOOT_SIZE=100663296
EXPECTED_TOP_DRIVER_HASH="291cce1505c234e8425abf3eea385fe077ae8663ba1c1337c414b6d0be6b93e9"
EXPECTED_TOP_DRIVER_SIZE=14749616
BOOT_DEVICE="/dev/block/by-name/boot_a"
DOWNLOAD="/sdcard/Download"
PUBLIC_LOGROOT="/sdcard/log"
PAYLOAD_DIR="$MODDIR/boot_patch/payload"
TOP_DRIVER="$MODDIR/system/vendor/lib/modules/qca_cld3_qca6750.ko"
MAGISKBOOT="/data/adb/magisk/magiskboot"
WORK=""

LOCALE="$(getprop persist.sys.locale)"
[ -n "$LOCALE" ] || LOCALE="$(getprop ro.product.locale)"
case "$LOCALE" in
    ru*|RU*) RU=1 ;;
    *) RU=0 ;;
esac

# Capture the complete native builder output in the agreed public log folder.
# A single child invocation runs the actual builder; its exit status survives.
if [ "${1:-}" != "--captured" ]; then
    mkdir -p "$PUBLIC_LOGROOT" || exit 1
    REPORT="$PUBLIC_LOGROOT/wpss_boot_build_$(date +%Y-%m-%d_%H-%M-%S)_$$.txt"
    [ ! -e "$REPORT" ] || REPORT="${REPORT%.txt}_retry.txt"
    [ ! -e "$REPORT" ] || { echo "Log name collision: $REPORT" >&2; exit 1; }
    if [ "$RU" = "1" ]; then
        echo "Сохраняю backup и готовлю тестовую копию boot. Дождитесь результата."
    else
        echo "Backing up boot and preparing a test copy. Wait for the result."
    fi
    sh "$0" --captured > "$REPORT" 2>&1
    BUILD_RESULT=$?
    cat "$REPORT"
    echo "Log: $REPORT"
    exit "$BUILD_RESULT"
fi

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
PATCHED_CREATED=0

cleanup() {
    [ -z "$WORK" ] || rm -rf "$WORK" 2>/dev/null
}

die2() {
    say2 "ОШИБКА: $1" "ERROR: $2" >&2
    [ -z "$BACKUP_TMP" ] || rm -f "$BACKUP_TMP" 2>/dev/null
    [ "$PATCHED_CREATED" -eq 0 ] || rm -f "$PATCHED" 2>/dev/null
    [ -z "$PATCHED_TMP" ] || rm -f "$PATCHED_TMP" 2>/dev/null
    cleanup
    exit 1
}

trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

[ "$(uname -r)" = "5.4.274-qgki-g4670d6bdb795" ] ||
    die2 "неподдерживаемое ядро" "unsupported running kernel"

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

echo "=== MAGISK / SLOT ==="
magisk -v 2>&1
echo "slot=$SLOT"

[ -r "$BOOT_DEVICE" ] ||
    die2 "не удаётся прочитать $BOOT_DEVICE" "cannot read $BOOT_DEVICE"
[ -x "$MAGISKBOOT" ] ||
    die2 "не найден $MAGISKBOOT" "$MAGISKBOOT was not found"
[ -f "$PAYLOAD_DIR/wpss_related_rescue.rc" ] ||
    die2 "не найден RC-файл патча" "patch RC file is missing"
[ -f "$PAYLOAD_DIR/wpss_related_rescue.sh" ] ||
    die2 "не найден скрипт патча" "patch script is missing"
[ -f "$TOP_DRIVER" ] ||
    die2 "не найден подготовленный WLAN-драйвер модуля" \
        "the module's prepared WLAN driver is missing"

TOP_DRIVER_SIZE="$(wc -c < "$TOP_DRIVER" 2>/dev/null)"
case "$TOP_DRIVER_SIZE" in
    ''|*[!0-9]*) TOP_DRIVER_SIZE=0 ;;
esac
[ "$TOP_DRIVER_SIZE" -eq "$EXPECTED_TOP_DRIVER_SIZE" ] ||
    die2 "неожиданный размер WLAN-драйвера: $TOP_DRIVER_SIZE" \
        "unexpected WLAN driver size: $TOP_DRIVER_SIZE"
TOP_DRIVER_HASH="$(sha256sum "$TOP_DRIVER" 2>/dev/null | awk '{print $1}')"
[ "$TOP_DRIVER_HASH" = "$EXPECTED_TOP_DRIVER_HASH" ] ||
    die2 "WLAN-драйвер не прошёл проверку SHA-256: $TOP_DRIVER_HASH" \
        "WLAN driver SHA-256 verification failed: $TOP_DRIVER_HASH"

mkdir -p "$DOWNLOAD" ||
    die2 "не удаётся открыть папку Download" "cannot access the Download folder"

FREE_KB="$(df -Pk "$DOWNLOAD" 2>/dev/null | awk 'END {print $4}')"
case "$FREE_KB" in
    ''|*[!0-9]*) FREE_KB=0 ;;
esac
[ "$FREE_KB" -ge 1048576 ] ||
    die2 "нужно не менее 1 ГиБ свободного места; доступно ${FREE_KB} КБ" \
        "at least 1 GiB of free space is required; ${FREE_KB} KiB is available"

BOOT_SIZE="$(blockdev --getsize64 "$BOOT_DEVICE" 2>/dev/null)"
case "$BOOT_SIZE" in
    ''|*[!0-9]*) BOOT_SIZE=0 ;;
esac
[ "$BOOT_SIZE" -eq "$EXPECTED_BOOT_SIZE" ] ||
    die2 "неожиданный размер boot_a: $BOOT_SIZE" "unexpected boot_a size: $BOOT_SIZE"

STAMP="$(date +%Y-%m-%d_%H-%M-%S)"
BACKUP="$DOWNLOAD/Nothing-Phone-1_boot-a_BACKUP_$STAMP.img"
PATCHED="$DOWNLOAD/Nothing-Phone-1_boot-a_QCA6750-EARLY-v1.3-TEST_$STAMP.img"
COLLISION=0
while [ -e "$BACKUP" ] || [ -e "$PATCHED" ] ||
      [ -e "$BACKUP.partial" ] || [ -e "$PATCHED.partial" ]; do
    COLLISION=$((COLLISION + 1))
    BACKUP="$DOWNLOAD/Nothing-Phone-1_boot-a_BACKUP_${STAMP}_$$_$COLLISION.img"
    PATCHED="$DOWNLOAD/Nothing-Phone-1_boot-a_QCA6750-EARLY-v1.3-TEST_${STAMP}_$$_$COLLISION.img"
done
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
[ "$(sha256sum "$BOOT_DEVICE" 2>/dev/null | awk '{print $1}')" = "$BACKUP_HASH" ] ||
    die2 "backup не совпадает с повторным чтением boot_a" "backup differs from a second boot_a read"
BACKUP_TRUST=existing-rescue
case "$BACKUP_HASH" in
    "$EXPECTED_BOOT_HASH"|"$EXPECTED_MAGISK306_BOOT_HASH"|"$EXPECTED_MAGISK31_BOOT_HASH") BACKUP_TRUST=known ;;
esac

WORK="$(mktemp -d /data/local/tmp/wpss_boot_patch_v13.XXXXXX)" ||
    die2 "не удалось создать временную папку" "could not create the work directory"
cp -f "$BACKUP" "$WORK/input.img" ||
    die2 "не удалось скопировать backup" "could not copy the backup"
cp -f "$PAYLOAD_DIR/wpss_related_rescue.rc" "$WORK/wpss_related_rescue.rc" ||
    die2 "не удалось скопировать RC-файл" "could not copy the RC file"
cp -f "$PAYLOAD_DIR/wpss_related_rescue.sh" "$WORK/wpss_related_rescue.sh" ||
    die2 "не удалось скопировать скрипт" "could not copy the script"
cp -f "$TOP_DRIVER" "$WORK/qca_cld3_qca6750.ko" ||
    die2 "не удалось скопировать WLAN-драйвер" "could not copy the WLAN driver"
chmod 0750 "$WORK/wpss_related_rescue.sh"
chmod 0644 "$WORK/qca_cld3_qca6750.ko"

cd "$WORK" ||
    die2 "не удалось открыть временную папку" "could not enter the work directory"

say2 "Распаковываю только копию boot_a." "Unpacking only the boot_a copy."
"$MAGISKBOOT" unpack input.img >/dev/null 2>&1 ||
    die2 "magiskboot не смог распаковать образ" "magiskboot could not unpack the image"
[ -f ramdisk.cpio ] ||
    die2 "в образе нет ramdisk.cpio" "ramdisk.cpio is missing from the image"
[ -s kernel ] || die2 "в образе нет ядра" "the image has no kernel"
INPUT_KERNEL_HASH="$(sha256sum kernel | awk '{print $1}')"
echo "input_kernel_sha256=$INPUT_KERNEL_HASH"
[ "$INPUT_KERNEL_HASH" = "$EXPECTED_KERNEL_HASH" ] ||
    die2 "ядро в backup не соответствует проверенной сборке; патч отменён" \
        "backup kernel is not the verified exact build; patching cancelled"


"$MAGISKBOOT" cpio ramdisk.cpio test >/dev/null 2>&1
CPIO_STATUS=$?
[ "$CPIO_STATUS" -eq 1 ] ||
    die2 "ожидался Magisk ramdisk (код 1), получен код $CPIO_STATUS" \
        "a Magisk ramdisk was expected (code 1), got code $CPIO_STATUS"

# A full boot hash changes after embedding the early driver. Unknown hashes
# are accepted ONLY with the exact known kernel, Magisk ramdisk and complete
# matching early-rescue payload. Otherwise the verified backup is retained.
if [ "$BACKUP_TRUST" = "existing-rescue" ]; then
    "$MAGISKBOOT" cpio ramdisk.cpio \
        "extract overlay.d/sbin/qca_cld3_qca6750.ko input-driver.ko" \
        "extract overlay.d/sbin/wpss_related_rescue.sh input-rescue.sh" \
        "extract overlay.d/wpss_related_rescue.rc input-rescue.rc" \
        >/dev/null 2>&1 ||
        die2 "неизвестный boot: не найден проверяемый ранний патч" \
            "unknown boot: verifiable early-rescue payload is missing"
    INPUT_PAYLOAD="$(sha256sum input-driver.ko | awk '{print $1}'):$(sha256sum input-rescue.sh | awk '{print $1}'):$(sha256sum input-rescue.rc | awk '{print $1}')"
    case "$INPUT_PAYLOAD" in
        "aaa967a88106757dc7aa9958a8206f520a6e040bf57299b7964e12ae06bb53c0:19d2dbe6af22f6039c5b1547af6c4c588d4de99c7cc29edf269eb8176fafba43:a143dcc637d959c2d85ce1356e41ee4cb65b401aaacc3fb4ae69aae23fd032f8"|\
        "291cce1505c234e8425abf3eea385fe077ae8663ba1c1337c414b6d0be6b93e9:a17a5fd2a2e78cc29f4a15f3152de6e0c16edd91a86ec7094ec5c81fb4a8bb7e:a143dcc637d959c2d85ce1356e41ee4cb65b401aaacc3fb4ae69aae23fd032f8") ;;
        *) die2 "неизвестный boot: ранние файлы не совпали с v1.2/v1.3; патч отменён" \
                "unknown boot: early files do not match v1.2/v1.3; patching cancelled" ;;
    esac
    rm -f input-driver.ko input-rescue.sh input-rescue.rc
    echo "input_verified=exact kernel + Magisk + matching v1.2/v1.3 early payload"
fi

say2 "Добавляю ранний QCA6750 и политику WPSS RELATED в копию." \
    "Adding early QCA6750 and the WPSS RELATED policy to the copy."
# Remove the obsolete v1.0 embedded driver only from the working ramdisk copy.
if "$MAGISKBOOT" cpio ramdisk.cpio "exists overlay.d/sbin/qca_cld3_wlan.ko" >/dev/null 2>&1; then
    "$MAGISKBOOT" cpio ramdisk.cpio "rm overlay.d/sbin/qca_cld3_wlan.ko" >/dev/null 2>&1 ||
        die2 "не удалось убрать старый драйвер из копии ramdisk" \
            "could not remove the old driver from the ramdisk copy"
fi
"$MAGISKBOOT" cpio ramdisk.cpio \
    "mkdir 0750 overlay.d" \
    "mkdir 0750 overlay.d/sbin" \
    "add 0644 overlay.d/wpss_related_rescue.rc wpss_related_rescue.rc" \
    "add 0750 overlay.d/sbin/wpss_related_rescue.sh wpss_related_rescue.sh" \
    "add 0644 overlay.d/sbin/qca_cld3_qca6750.ko qca_cld3_qca6750.ko" \
    >/dev/null 2>&1 ||
    die2 "не удалось добавить overlay.d" "could not add overlay.d"

rm -f verify.rc verify.sh verify.ko
"$MAGISKBOOT" cpio ramdisk.cpio \
    "extract overlay.d/wpss_related_rescue.rc verify.rc" \
    "extract overlay.d/sbin/wpss_related_rescue.sh verify.sh" \
    "extract overlay.d/sbin/qca_cld3_qca6750.ko verify.ko" \
    >/dev/null 2>&1 ||
    die2 "не удалось проверить добавленные файлы" "could not extract the added files"
cmp -s wpss_related_rescue.rc verify.rc ||
    die2 "проверка RC-файла не пройдена" "RC-file verification failed"
cmp -s wpss_related_rescue.sh verify.sh ||
    die2 "проверка скрипта не пройдена" "script verification failed"
cmp -s qca_cld3_qca6750.ko verify.ko ||
    die2 "проверка WLAN-драйвера не пройдена" "WLAN driver verification failed"
EXPECTED_RAMDISK_HASH="$(sha256sum ramdisk.cpio | awk '{print $1}')"
echo "patched_ramdisk_sha256=$EXPECTED_RAMDISK_HASH"

# Leave only boot-image components and the source image in the repack directory.
rm -f wpss_related_rescue.rc wpss_related_rescue.sh qca_cld3_qca6750.ko \
    verify.rc verify.sh verify.ko ||
    die2 "не удалось очистить staging перед repack" "could not clean staging before repack"

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

# Verify the bytes recovered from the finished image, not just the staging CPIO.
mkdir verify-image || die2 "не удалось создать папку проверки" "could not create verification directory"
(
    cd verify-image && "$MAGISKBOOT" unpack ../new-boot.img >/dev/null 2>&1
) || die2 "новый образ не распаковывается" "the new image cannot be unpacked"
[ -s verify-image/kernel ] && [ -s verify-image/ramdisk.cpio ] ||
    die2 "новый образ неполный" "the new image is incomplete"
[ "$(sha256sum verify-image/kernel | awk '{print $1}')" = "$INPUT_KERNEL_HASH" ] ||
    die2 "ядро в новом образе изменилось" "the kernel changed in the new image"
[ "$(sha256sum verify-image/ramdisk.cpio | awk '{print $1}')" = "$EXPECTED_RAMDISK_HASH" ] ||
    die2 "ramdisk в новом образе не совпадает" "the new image ramdisk does not match"
"$MAGISKBOOT" cpio verify-image/ramdisk.cpio test >/dev/null 2>&1
[ "$?" -eq 1 ] || die2 "новый образ потерял Magisk ramdisk" "the new image lost the Magisk ramdisk"
rm -rf verify-image
NEW_HASH="$(sha256sum new-boot.img | awk '{print $1}')"

cp -f new-boot.img "$PATCHED_TMP" ||
    die2 "не удалось сохранить патченый образ" "could not save the patched image"
sync
PATCHED_TMP_SIZE="$(wc -c < "$PATCHED_TMP" 2>/dev/null)"
[ "$PATCHED_TMP_SIZE" -eq "$NEW_SIZE" ] ||
    die2 "копия патченого образа имеет неверный размер: $PATCHED_TMP_SIZE" \
        "the patched image copy has the wrong size: $PATCHED_TMP_SIZE"
[ "$(sha256sum "$PATCHED_TMP" | awk '{print $1}')" = "$NEW_HASH" ] ||
    die2 "SHA-256 сохранённой копии не совпадает" "the saved copy SHA-256 does not match"
mv -f "$PATCHED_TMP" "$PATCHED" ||
    die2 "не удалось завершить сохранение патченого образа" \
        "could not finalize the patched image"
PATCHED_TMP=""
PATCHED_CREATED=1
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
say2 "В копии QCA6750 будет подмонтирован до vendor_modprobe." \
    "In this copy QCA6750 will be mounted before vendor_modprobe."
say2 "Сначала проверяйте её командой fastboot boot, не flash." \
    "Test it with fastboot boot first, not flash."
