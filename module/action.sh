#!/system/bin/sh

MODDIR=${0%/*}
LOGROOT="/data/adb/wlan_graceful_fail_logs"
PUBLIC_LOGROOT="/sdcard/log"

LOCALE="$(getprop persist.sys.locale)"
[ -n "$LOCALE" ] || LOCALE="$(getprop ro.product.locale)"
case "$LOCALE" in
    ru*|RU*) RU=1 ;;
    *) RU=0 ;;
esac

mkdir -p "$LOGROOT" "$PUBLIC_LOGROOT" 2>/dev/null

read_uptime() {
    read -r UP_RAW _REST < /proc/uptime 2>/dev/null
    UP_SECONDS=${UP_RAW%%.*}
    case "$UP_SECONDS" in
        ''|*[!0-9]*) UP_SECONDS=0 ;;
    esac
    UP_DAYS=$((UP_SECONDS / 86400))
    UP_HOURS=$(((UP_SECONDS % 86400) / 3600))
    UP_MINUTES=$(((UP_SECONDS % 3600) / 60))
}

show_uptime() {
    read_uptime
    echo
    if [ "$RU" = "1" ]; then
        echo "Время работы: $UP_DAYS дн. $UP_HOURS ч. $UP_MINUTES мин."
        echo "Всего секунд: $UP_SECONDS"
    else
        echo "Uptime: $UP_DAYS d $UP_HOURS h $UP_MINUTES min"
        echo "Total seconds: $UP_SECONDS"
    fi
}

write_status() {
    read_uptime
    echo "=== TIME ==="
    date
    echo "=== UPTIME ==="
    echo "seconds=$UP_SECONDS"
    echo "days=$UP_DAYS hours=$UP_HOURS minutes=$UP_MINUTES"
    echo "=== BOOT ID ==="
    cat /proc/sys/kernel/random/boot_id 2>&1
    echo "=== MODULE ==="
    cat "$MODDIR/module.prop" 2>&1
    echo "=== BUILD ==="
    getprop ro.product.device
    getprop ro.build.version.incremental
    uname -a
    echo "=== BOOT REASON ==="
    getprop ro.boot.bootreason
    getprop sys.boot.reason
    echo "=== MAGISK/SLOT ==="
    magisk -v 2>&1
    getprop ro.boot.slot_suffix
    echo "=== SSR PARAMETERS ==="
    for PARAM in /sys/module/subsystem_restart/parameters/*; do
        [ -f "$PARAM" ] || continue
        echo "--- $PARAM"
        cat "$PARAM" 2>&1
    done
    echo "=== HUNG TASK SETTINGS ==="
    for PARAM in hung_task_panic hung_task_timeout_secs panic_on_warn; do
        echo "--- $PARAM"
        cat "/proc/sys/kernel/$PARAM" 2>&1
    done
    echo "=== WPSS POLICY ==="
    for NODE in /sys/bus/msm_subsys/devices/*; do
        [ -f "$NODE/name" ] || continue
        [ "$(cat "$NODE/name" 2>/dev/null)" = "wpss" ] || continue
        echo "node=$NODE"
        echo "restart_level=$(cat "$NODE/restart_level" 2>/dev/null)"
        for FIELD in state crash_count crash_reason crash_timestamp system_debug; do
            echo "$FIELD=$(cat "$NODE/$FIELD" 2>/dev/null)"
        done
    done
    echo "=== ACTIVE WLAN FILES ==="
    sha256sum /vendor/lib/modules/qca_cld3_wlan.ko 2>&1
    sha256sum /vendor/lib/modules/5.4-gki/qca_cld3_wlan.ko 2>&1
    sha256sum /vendor/lib/modules/qca_cld3_qca6750.ko 2>&1
    echo "=== LOADED MODULE ==="
    grep '^wlan ' /proc/modules 2>&1
    echo "=== LOADED WLAN BUILD ID ==="
    /system/bin/toybox od -An -tx1 -j16 -N8 \
        /sys/module/wlan/notes/.note.gnu.build-id 2>&1
    echo "expected_v13=e2388611edd9fe47"
    echo "=== WIFI INTERFACE ==="
    ip link show wlan0 2>&1
    echo "wifi_hal=$(getprop init.svc.vendor.wifi_hal_legacy)"
    echo "=== WLAN MOUNTS ==="
    grep -E 'qca_cld3_(wlan|qca6750)\.ko' /proc/mounts 2>&1
    echo "=== EARLY RESCUE MARKERS ==="
    dmesg 2>&1 | grep -a 'WPSS_RESCUE:' | tail -n 30
}

create_dump() {
    STAMP="$(date +%Y-%m-%d_%H-%M-%S)"
    DUMP_NAME="wlan_dump_$STAMP"
    [ ! -e "$PUBLIC_LOGROOT/$DUMP_NAME.tar.gz" ] || DUMP_NAME="${DUMP_NAME}_$$"
    DUMP_DIR="$LOGROOT/$DUMP_NAME"
    ARCHIVE="$PUBLIC_LOGROOT/$DUMP_NAME.tar.gz"
    ARCHIVE_TMP="$ARCHIVE.partial"

    mkdir -p "$DUMP_DIR/pstore" "$DUMP_DIR/module_logs" "$DUMP_DIR/loader" || return 1
    write_status > "$DUMP_DIR/status.txt"

    cp -f /sys/fs/pstore/* "$DUMP_DIR/pstore/" 2>/dev/null
    cp -f "$LOGROOT"/console-ramoops-*.txt "$DUMP_DIR/module_logs/" 2>/dev/null
    cp -f "$LOGROOT"/pmsg-ramoops-*.txt "$DUMP_DIR/module_logs/" 2>/dev/null
    cp -f "$LOGROOT"/events.log* "$DUMP_DIR/module_logs/" 2>/dev/null
    cp -f "$LOGROOT"/kernel.log* "$DUMP_DIR/module_logs/" 2>/dev/null
    cp -f /data/adb/wpss_related_rescue.log "$DUMP_DIR/module_logs/" 2>/dev/null
    cp -f /sys/module/wlan/notes/.note.gnu.build-id \
        "$DUMP_DIR/loaded-wlan-build-id.bin" 2>/dev/null
    cp -f /vendor/bin/vendor_modprobe.sh "$DUMP_DIR/loader/" 2>/dev/null
    for FILE in modules.load modules.blocklist modules.dep modules.alias modules.softdep; do
        cp -f "/vendor/lib/modules/$FILE" "$DUMP_DIR/loader/" 2>/dev/null
    done

    dmesg 2>&1 | tail -c 2097152 > "$DUMP_DIR/dmesg_tail.txt"
    /system/bin/logcat -b kernel -d -v threadtime 2>&1 |
        tail -c 2097152 > "$DUMP_DIR/kernel_current.txt"

    TAR_BIN="$(command -v tar 2>/dev/null)"
    if [ -n "$TAR_BIN" ]; then
        "$TAR_BIN" -czf "$ARCHIVE_TMP" -C "$LOGROOT" "$DUMP_NAME"
        TAR_RESULT=$?
    elif [ -x /data/adb/magisk/busybox ]; then
        /data/adb/magisk/busybox tar -czf "$ARCHIVE_TMP" \
            -C "$LOGROOT" "$DUMP_NAME"
        TAR_RESULT=$?
    else
        TAR_RESULT=127
    fi

    if [ "$TAR_RESULT" = "0" ] && [ -s "$ARCHIVE_TMP" ] && mv -f "$ARCHIVE_TMP" "$ARCHIVE"; then
        rm -rf "$DUMP_DIR"
        chmod 0644 "$ARCHIVE" 2>/dev/null
        echo
        if [ "$RU" = "1" ]; then
            echo "Готов один архив с диагностикой:"
        else
            echo "One diagnostic archive was created:"
        fi
        echo "$ARCHIVE"
    else
        rm -f "$ARCHIVE_TMP"
        echo
        if [ "$RU" = "1" ]; then
            echo "Не удалось создать архив. Файлы оставлены в папке:"
        else
            echo "Could not create the archive. Files were kept in:"
        fi
        echo "$DUMP_DIR"
        return 1
    fi
}

wait_volume_key() {
    GETEVENT_BIN="$(command -v getevent 2>/dev/null)"
    [ -n "$GETEVENT_BIN" ] || return 2

    FAILURES=0
    while true; do
        KEY_EVENT="$("$GETEVENT_BIN" -qlc 1 2>/dev/null)"
        KEY_RESULT=$?
        if [ "$KEY_RESULT" != "0" ]; then
            FAILURES=$((FAILURES + 1))
            [ "$FAILURES" -ge 3 ] && return 2
            sleep 1
            continue
        fi
        case "$KEY_EVENT" in
            *KEY_VOLUMEUP*DOWN*|*"0001 0073 00000001"*) return 0 ;;
            *KEY_VOLUMEDOWN*DOWN*|*"0001 0072 00000001"*) return 1 ;;
        esac
    done
}

echo
if [ "$RU" = "1" ]; then
    echo "Выберите действие физической кнопкой:"
    echo "  Громкость +  — показать время работы"
    echo "  Громкость -  — открыть дополнительные действия"
else
    echo "Choose an action with a physical key:"
    echo "  Volume Up    — show uptime"
    echo "  Volume Down  — more actions"
fi
echo

wait_volume_key
FIRST_CHOICE=$?
case "$FIRST_CHOICE" in
    0)
        show_uptime
        exit $?
        ;;
    1) ;;
    *)
        if [ "$RU" = "1" ]; then
            echo "Не удалось прочитать кнопки громкости. Создаю только безопасный дамп."
        else
            echo "Could not read the volume keys. Creating only the safe dump."
        fi
        create_dump
        exit $?
        ;;
esac

echo
if [ "$RU" = "1" ]; then
    echo "Дополнительные действия:"
    echo "  Громкость +  — создать один архив с диагностикой"
    echo "  Громкость -  — сделать backup и тестовый boot с ранним QCA6750"
    echo "Патченая копия НЕ будет прошита автоматически."
else
    echo "More actions:"
    echo "  Volume Up    — create one diagnostic archive"
    echo "  Volume Down  — back up boot_a and build an early-QCA6750 test boot"
    echo "The patched copy will NOT be flashed automatically."
fi
echo

wait_volume_key
SECOND_CHOICE=$?
case "$SECOND_CHOICE" in
    0) create_dump ;;
    1) "$MODDIR/boot_patch.sh" ;;
    *)
        if [ "$RU" = "1" ]; then
            echo "Кнопки не прочитаны. Изменение boot отменено; создаю дамп."
        else
            echo "Keys could not be read. Boot-image creation was cancelled; creating a dump."
        fi
        create_dump
        ;;
esac
